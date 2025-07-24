//=============================================================================
// Copyright © 2025 RVGPU Team
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//   
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//=============================================================================

`ifndef RVGPU_SM_FETCH_STAGE_SV
`define RVGPU_SM_FETCH_STAGE_SV

`include "rvgpu_typedef.svh"

// SM取指阶段
// 负责从L0 ICache获取指令
module rvgpu_sm_fetch_stage #(
    parameter int WARP_COUNT = 32,      // 支持的warp数量
    parameter int THREAD_COUNT = 32     // 每个warp的线程数
) (
    input  logic clk,
    input  logic rst_n,
    
    // Warp调度器接口
    input  logic                                warp_schedule_valid,
    input  logic [$clog2(WARP_COUNT)-1:0]      scheduled_warp_id,
    output logic                                fetch_ready,
    
    // Warp状态输入
    input  logic [63:0]                         warp_pc[WARP_COUNT],
    input  logic [THREAD_COUNT-1:0]             warp_active_mask[WARP_COUNT],
    input  logic [WARP_COUNT-1:0]               warp_valid,
    
    // L0 ICache接口
    output logic                                icache_req_valid,
    output logic [63:0]                         icache_req_vaddr,
    input  logic                                icache_req_ready,
    input  logic                                icache_resp_valid,
    input  logic [31:0]                         icache_resp_inst,
    output logic                                icache_resp_ready,
    
    // 到解码阶段的输出
    output logic                                fetch_decode_valid,
    output logic [31:0]                         fetch_decode_inst,
    output logic [63:0]                         fetch_decode_pc,
    output logic [$clog2(WARP_COUNT)-1:0]      fetch_decode_warp_id,
    output logic [THREAD_COUNT-1:0]             fetch_decode_active_mask,
    input  logic                                fetch_decode_ready,
    
    // PC更新接口
    input  logic                                pc_update_valid,
    input  logic [$clog2(WARP_COUNT)-1:0]      pc_update_warp_id,
    input  logic [63:0]                         pc_update_pc,
    
    // 分支预测接口
    output logic                                branch_pred_req_valid,
    output logic [63:0]                         branch_pred_pc,
    input  logic                                branch_pred_taken,
    input  logic [63:0]                         branch_pred_target,
    
    // 流水线控制
    input  logic                                pipeline_stall,
    input  logic                                pipeline_flush
);

    // 取指状态机
    typedef enum logic [2:0] {
        IDLE,
        SEND_REQ,
        WAIT_RESP,
        BRANCH_PRED,
        FORWARD
    } fetch_state_t;
    
    // 内部状态
    fetch_state_t state;
    logic [$clog2(WARP_COUNT)-1:0] current_warp_id;
    logic [63:0] current_pc;
    logic [THREAD_COUNT-1:0] current_active_mask;
    logic [31:0] fetched_inst;
    
    // PC存储器
    logic [63:0] pc_storage[WARP_COUNT];
    
    // 分支预测相关
    logic predicted_taken;
    logic [63:0] predicted_target;
    logic use_prediction;
    
    // 流水线寄存器
    logic                               fd_valid_reg;
    logic [31:0]                        fd_inst_reg;
    logic [63:0]                        fd_pc_reg;
    logic [$clog2(WARP_COUNT)-1:0]     fd_warp_id_reg;
    logic [THREAD_COUNT-1:0]            fd_active_mask_reg;
    
    // PC初始化和更新
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < WARP_COUNT; i++) begin
                pc_storage[i] <= '0;
            end
        end else begin
            // PC更新
            if (pc_update_valid) begin
                pc_storage[pc_update_warp_id] <= pc_update_pc;
            end else if (state == FORWARD && fetch_decode_ready) begin
                // 正常PC递增
                pc_storage[current_warp_id] <= current_pc + 4;
            end
        end
    end
    
    // 分支预测逻辑
    always_comb begin
        // 简单的分支预测：检查指令是否为分支指令
        use_prediction = (fetched_inst[6:0] == 7'b1100011); // B-type指令
        
        if (use_prediction) begin
            // 简单的静态预测：向后分支预测为跳转，向前分支预测为不跳转
            logic [12:0] imm;
            imm = {fetched_inst[31], fetched_inst[7], fetched_inst[30:25], fetched_inst[11:8], 1'b0};
            predicted_target = current_pc + {{19{imm[12]}}, imm};
            predicted_taken = imm[12]; // 负偏移（向后分支）预测为跳转
        end else begin
            predicted_target = current_pc + 4;
            predicted_taken = 1'b0;
        end
    end
    
    // 主状态机
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            current_warp_id <= '0;
            current_pc <= '0;
            current_active_mask <= '0;
            fetched_inst <= '0;
        end else if (pipeline_flush) begin
            state <= IDLE;
        end else if (!pipeline_stall) begin
            case (state)
                IDLE: begin
                    if (warp_schedule_valid && warp_valid[scheduled_warp_id]) begin
                        current_warp_id <= scheduled_warp_id;
                        current_pc <= pc_storage[scheduled_warp_id];
                        current_active_mask <= warp_active_mask[scheduled_warp_id];
                        state <= SEND_REQ;
                    end
                end
                
                SEND_REQ: begin
                    if (icache_req_ready) begin
                        state <= WAIT_RESP;
                    end
                end
                
                WAIT_RESP: begin
                    if (icache_resp_valid) begin
                        fetched_inst <= icache_resp_inst;
                        state <= BRANCH_PRED;
                    end
                end
                
                BRANCH_PRED: begin
                    // 分支预测阶段
                    state <= FORWARD;
                end
                
                FORWARD: begin
                    if (fetch_decode_ready) begin
                        state <= IDLE;
                    end
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
    
    // ICache请求信号
    assign icache_req_valid = (state == SEND_REQ);
    assign icache_req_vaddr = current_pc;
    assign icache_resp_ready = (state == WAIT_RESP);
    
    // 分支预测请求
    assign branch_pred_req_valid = (state == BRANCH_PRED) && use_prediction;
    assign branch_pred_pc = current_pc;
    
    // 流水线寄存器更新
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fd_valid_reg <= 1'b0;
            fd_inst_reg <= '0;
            fd_pc_reg <= '0;
            fd_warp_id_reg <= '0;
            fd_active_mask_reg <= '0;
        end else if (pipeline_flush) begin
            fd_valid_reg <= 1'b0;
        end else if (!pipeline_stall) begin
            if (state == FORWARD && fetch_decode_ready) begin
                fd_valid_reg <= 1'b1;
                fd_inst_reg <= fetched_inst;
                fd_pc_reg <= current_pc;
                fd_warp_id_reg <= current_warp_id;
                fd_active_mask_reg <= current_active_mask;
            end else if (fetch_decode_ready) begin
                fd_valid_reg <= 1'b0;
            end
        end
    end
    
    // 输出信号
    assign fetch_decode_valid = fd_valid_reg;
    assign fetch_decode_inst = fd_inst_reg;
    assign fetch_decode_pc = fd_pc_reg;
    assign fetch_decode_warp_id = fd_warp_id_reg;
    assign fetch_decode_active_mask = fd_active_mask_reg;
    
    // 取指准备信号
    assign fetch_ready = (state == IDLE);

endmodule : rvgpu_sm_fetch_stage

`endif // RVGPU_SM_FETCH_STAGE_SV