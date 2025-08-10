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

`ifndef RVGPU_SM_MEMORY_STAGE_SV
`define RVGPU_SM_MEMORY_STAGE_SV

`include "rvgpu_typedef.svh"
`include "interface_sm_exec_mem.svh"
`include "interface_sm_mem_wb.svh"
`include "interface_sm_ldst.svh"

// SM访存阶段
// 处理load/store指令和与LDST单元的通信
module rvgpu_sm_memory_stage #(
    parameter int WARP_COUNT = 32,      // 支持的warp数量
    parameter int THREAD_COUNT = 32     // 每个warp的线程数
) (
    input  logic clk,
    input  logic rst_n,
    
    // 从执行阶段的输入（接口）
    interface_sm_exec_mem.mem_sink              em_if,
    
    // LDST单元接口（统一接口）
    interface_sm_ldst.sm                        ldst_if,
    
    // 到写回阶段的输出（接口）
    interface_sm_mem_wb.mem_source              mw_if,
    
    // 流水线控制
    input  logic                                pipeline_stall,
    input  logic                                pipeline_flush
);

    // 访存状态机
    typedef enum logic [2:0] {
        IDLE,
        SEND_REQ,
        WAIT_RESP,
        FORWARD
    } mem_state_t;
    
    // 内部状态
    mem_state_t state;
    logic [$clog2(WARP_COUNT)-1:0] current_warp_id;
    logic [THREAD_COUNT-1:0] current_active_mask;
    logic [4:0] current_rd;
    logic [31:0] current_result[THREAD_COUNT];
    logic current_reg_write;
    logic current_is_branch;
    logic [31:0] current_branch_target;
    logic [THREAD_COUNT-1:0] current_branch_mask;
    logic [31:0] current_inst;
    logic [63:0] current_pc;
    
    // Load/Store地址计算
    logic [63:0] mem_addr[THREAD_COUNT];
    logic [31:0] store_data[THREAD_COUNT];
    logic [2:0] mem_size;
    
    // 流水线寄存器
    logic                               mw_valid_reg;
    logic [31:0]                        mw_inst_reg;
    logic [63:0]                        mw_pc_reg;
    logic [$clog2(WARP_COUNT)-1:0]     mw_warp_id_reg;
    logic [THREAD_COUNT-1:0]            mw_active_mask_reg;
    logic [4:0]                         mw_rd_reg;
    logic [31:0]                        mw_result_reg[THREAD_COUNT];
    logic                               mw_reg_write_reg;
    logic                               mw_is_branch_reg;
    logic [31:0]                        mw_branch_target_reg;
    logic [THREAD_COUNT-1:0]            mw_branch_mask_reg;
    
    // 地址计算
    always_comb begin
        for (int t = 0; t < THREAD_COUNT; t++) begin
            // 简化地址计算：基地址 + 偏移
            mem_addr[t] = em_if.result[t]; // 执行阶段已计算好地址
            store_data[t] = em_if.result[t]; // 简化：使用结果作为存储数据
        end
        
        // 根据指令确定访存大小
        case (em_if.inst[14:12])
            3'b000: mem_size = 3'b000; // LB/SB - 8位
            3'b001: mem_size = 3'b001; // LH/SH - 16位
            3'b010: mem_size = 3'b010; // LW/SW - 32位
            3'b011: mem_size = 3'b011; // LD/SD - 64位
            3'b100: mem_size = 3'b000; // LBU - 8位无符号
            3'b101: mem_size = 3'b001; // LHU - 16位无符号
            3'b110: mem_size = 3'b010; // LWU - 32位无符号
            default: mem_size = 3'b010; // 默认32位
        endcase
    end
    
    // 主状态机
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            current_warp_id <= '0;
            current_active_mask <= '0;
            current_rd <= '0;
            current_reg_write <= 1'b0;
            current_is_branch <= 1'b0;
            current_branch_target <= '0;
            current_branch_mask <= '0;
            current_inst <= '0;
            current_pc <= '0;
            
            for (int t = 0; t < THREAD_COUNT; t++) begin
                current_result[t] <= '0;
            end
        end else if (pipeline_flush) begin
            state <= IDLE;
        end else if (!pipeline_stall) begin
            case (state)
                IDLE: begin
            if (em_if.valid) begin
                current_warp_id <= em_if.warp_id;
                current_active_mask <= em_if.active_mask;
                current_rd <= em_if.rd;
                current_reg_write <= em_if.reg_write;
                current_is_branch <= em_if.is_branch;
                current_branch_target <= em_if.branch_target;
                current_branch_mask <= em_if.branch_mask;
                current_inst <= em_if.inst;
                current_pc <= em_if.pc;
                        
                        for (int t = 0; t < THREAD_COUNT; t++) begin
                    current_result[t] <= em_if.result[t];
                        end
                        
                if (em_if.is_load || em_if.is_store) begin
                            state <= SEND_REQ;
                        end else begin
                            state <= FORWARD;
                        end
                    end
                end
                
                SEND_REQ: begin
                    if (ldst_if.req_ready) begin
                        state <= WAIT_RESP;
                    end
                end
                
                WAIT_RESP: begin
                    if (ldst_if.resp_valid && ldst_if.resp_warp_id == current_warp_id) begin
                        // 更新Load结果
                        if (!em_if.is_store) begin
                            for (int t = 0; t < THREAD_COUNT; t++) begin
                                if (ldst_if.resp_mask[t]) begin
                                    current_result[t] <= ldst_if.resp_data[t];
                                end
                            end
                        end
                        state <= FORWARD;
                    end
                end
                
                FORWARD: begin
                    if (mw_if.ready) begin
                        state <= IDLE;
                    end
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
    
    // LDST请求信号 - 通过内部if_ldst接口
    assign ldst_if.req_valid   = (state == SEND_REQ);
    assign ldst_if.req_warp_id = current_warp_id;
    assign ldst_if.req_mask    = current_active_mask;
    assign ldst_if.req_addr    = mem_addr;
    assign ldst_if.req_data    = store_data;
    assign ldst_if.req_size    = mem_size;
    assign ldst_if.req_is_load = em_if.is_load;
    
    // LDST响应准备信号 - 通过内部if_ldst接口
    assign ldst_if.resp_ready = (state == WAIT_RESP);
    
    // 流水线寄存器更新
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mw_valid_reg <= 1'b0;
            mw_inst_reg <= '0;
            mw_pc_reg <= '0;
            mw_warp_id_reg <= '0;
            mw_active_mask_reg <= '0;
            mw_rd_reg <= '0;
            mw_reg_write_reg <= 1'b0;
            mw_is_branch_reg <= 1'b0;
            mw_branch_target_reg <= '0;
            mw_branch_mask_reg <= '0;
            
            for (int t = 0; t < THREAD_COUNT; t++) begin
                mw_result_reg[t] <= '0;
            end
        end else if (pipeline_flush) begin
            mw_valid_reg <= 1'b0;
        end else if (!pipeline_stall) begin
            if (state == FORWARD && mw_if.ready) begin
                mw_valid_reg <= 1'b1;
                mw_inst_reg <= current_inst;
                mw_pc_reg <= current_pc;
                mw_warp_id_reg <= current_warp_id;
                mw_active_mask_reg <= current_active_mask;
                mw_rd_reg <= current_rd;
                mw_reg_write_reg <= current_reg_write;
                mw_is_branch_reg <= current_is_branch;
                mw_branch_target_reg <= current_branch_target;
                mw_branch_mask_reg <= current_branch_mask;
                
                for (int t = 0; t < THREAD_COUNT; t++) begin
                    mw_result_reg[t] <= current_result[t];
                end
            end else if (mw_if.ready) begin
                mw_valid_reg <= 1'b0;
            end
        end
    end
    
    // 输出信号
    assign mw_if.valid         = mw_valid_reg;
    assign mw_if.inst          = mw_inst_reg;
    assign mw_if.pc            = mw_pc_reg;
    assign mw_if.warp_id       = mw_warp_id_reg;
    assign mw_if.active_mask   = mw_active_mask_reg;
    assign mw_if.rd            = mw_rd_reg;
    assign mw_if.result        = mw_result_reg;
    assign mw_if.reg_write     = mw_reg_write_reg;
    assign mw_if.is_branch     = mw_is_branch_reg;
    assign mw_if.branch_target = mw_branch_target_reg;
    assign mw_if.branch_mask   = mw_branch_mask_reg;
    
    // 准备信号
    assign em_if.ready = (state == IDLE) || (state == FORWARD && mw_if.ready);

endmodule : rvgpu_sm_memory_stage

`endif // RVGPU_SM_MEMORY_STAGE_SV 