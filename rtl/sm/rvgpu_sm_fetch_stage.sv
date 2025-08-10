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
`include "interface_sm_fetch_decode.svh"
`include "interface_sm_icache_fetch.svh"
`include "interface_sm_warp_schedule.svh"
`include "interface_sm_pc_update.svh"
`include "interface_sm_warp_state.svh"

// SM取指阶段
// 负责从L0 ICache获取指令
module rvgpu_sm_fetch_stage #(
    parameter int WARP_COUNT = 32,      // 支持的warp数量
    parameter int THREAD_COUNT = 32     // 每个warp的线程数
) (
    input  logic clk,
    input  logic rst_n,
    
    // Warp调度器接口（接口化）
    interface_sm_warp_schedule.fetch_sink       sched_if,
    
    // Warp状态输入（接口化）
    interface_sm_warp_state.fetch_view          warp_state_if,
    
    // L0 ICache接口（接口化）
    interface_sm_icache_fetch.fetch             ic_if,
    
    // 到解码阶段的输出（接口）
    interface_sm_fetch_decode.fetch_source      fd_if,
    
    // PC更新接口（接口化）
    interface_sm_pc_update.sink                 pc_update_if,
    
    // 分支预测：不使用
    
    // 流水线控制
    input  logic                                pipeline_stall,
    input  logic                                pipeline_flush
);

    // 取指状态机
    typedef enum logic [2:0] {
        IDLE,
        SEND_REQ,
        WAIT_RESP,
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
    
    // 分支预测相关（未使用）
    
    // 流水线寄存器
    logic                               fd_valid_reg;
    logic [31:0]                        fd_inst_reg;
    logic [63:0]                        fd_pc_reg;
    logic [$clog2(WARP_COUNT)-1:0]     fd_warp_id_reg;
    logic [THREAD_COUNT-1:0]            fd_active_mask_reg;
    
    // PC初始化和更新
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < WARP_COUNT; i++) begin
                pc_storage[i] <= '0;
            end
        end else begin
            // PC更新
            if (pc_update_if.valid) begin
                pc_storage[pc_update_if.warp_id] <= pc_update_if.pc;
            end else if (state == FORWARD && fd_if.ready) begin
                // 正常PC递增
                pc_storage[current_warp_id] <= current_pc + 4;
            end
        end
    end
    
    // 分支预测逻辑（移除）
    
    // 主状态机
    always_ff @(posedge clk) begin
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
                    if (sched_if.valid && warp_state_if.warp_valid[sched_if.scheduled_warp_id]) begin
                        current_warp_id <= sched_if.scheduled_warp_id;
                        current_pc <= pc_storage[sched_if.scheduled_warp_id];
                        current_active_mask <= warp_state_if.warp_active_mask[sched_if.scheduled_warp_id];
                        state <= SEND_REQ;
                    end
                end
                
                SEND_REQ: begin
                    if (ic_if.req_ready) begin
                        state <= WAIT_RESP;
                    end
                end
                
                WAIT_RESP: begin
                    if (ic_if.resp_valid) begin
                        fetched_inst <= ic_if.resp_inst;
                        state <= FORWARD;
                    end
                end
                
                FORWARD: begin
                    if (fd_if.ready) begin
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
    assign ic_if.req_valid = (state == SEND_REQ);
    assign ic_if.req_vaddr = current_pc;
    // ic_if.req_ready 由L0 ICache端驱动
    
    // 分支预测请求（不使用）
    
    // 流水线寄存器更新
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            fd_valid_reg <= 1'b0;
            fd_inst_reg <= '0;
            fd_pc_reg <= '0;
            fd_warp_id_reg <= '0;
            fd_active_mask_reg <= '0;
        end else if (pipeline_flush) begin
            fd_valid_reg <= 1'b0;
        end else if (!pipeline_stall) begin
            if (state == FORWARD && fd_if.ready) begin
                fd_valid_reg <= 1'b1;
                fd_inst_reg <= fetched_inst;
                fd_pc_reg <= current_pc;
                fd_warp_id_reg <= current_warp_id;
                fd_active_mask_reg <= current_active_mask;
            end else if (fd_if.ready) begin
                fd_valid_reg <= 1'b0;
            end
        end
    end
    
    // 输出信号
    assign fd_if.valid = fd_valid_reg;
    assign fd_if.inst = fd_inst_reg;
    assign fd_if.pc = fd_pc_reg;
    assign fd_if.warp_id = fd_warp_id_reg;
    assign fd_if.active_mask = fd_active_mask_reg;
    
    // 取指准备信号
    assign sched_if.ready = (state == IDLE);

endmodule : rvgpu_sm_fetch_stage

`endif // RVGPU_SM_FETCH_STAGE_SV