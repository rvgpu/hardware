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

`ifndef RVGPU_SM_WRITEBACK_STAGE_SV
`define RVGPU_SM_WRITEBACK_STAGE_SV

`include "rvgpu_typedef.svh"

// SM写回阶段
// 处理寄存器写回、分支处理和PC更新
module rvgpu_sm_writeback_stage #(
    parameter int WARP_COUNT = 32,      // 支持的warp数量
    parameter int THREAD_COUNT = 32     // 每个warp的线程数
) (
    input  logic clk,
    input  logic rst_n,
    
    // 从访存阶段的输入
    input  logic                                mem_wb_valid,
    input  logic [31:0]                         mem_wb_inst,
    input  logic [63:0]                         mem_wb_pc,
    input  logic [$clog2(WARP_COUNT)-1:0]      mem_wb_warp_id,
    input  logic [THREAD_COUNT-1:0]             mem_wb_active_mask,
    input  logic [4:0]                          mem_wb_rd,
    input  logic [31:0]                         mem_wb_result[THREAD_COUNT],
    input  logic                                mem_wb_reg_write,
    input  logic                                mem_wb_is_branch,
    input  logic [31:0]                         mem_wb_branch_target,
    input  logic [THREAD_COUNT-1:0]             mem_wb_branch_mask,
    output logic                                mem_wb_ready,
    
    // 寄存器文件写接口
    output logic                                reg_write_enable,
    output logic [$clog2(WARP_COUNT)-1:0]      reg_write_warp_id,
    output logic [4:0]                          reg_write_addr,
    output logic [31:0]                         reg_write_data[THREAD_COUNT],
    output logic [THREAD_COUNT-1:0]             reg_write_mask,
    
    // PC更新接口
    output logic                                pc_update_valid,
    output logic [$clog2(WARP_COUNT)-1:0]      pc_update_warp_id,
    output logic [63:0]                         pc_update_pc,
    
    // 分支预测反馈
    output logic                                branch_feedback_valid,
    output logic [63:0]                         branch_feedback_pc,
    output logic                                branch_feedback_taken,
    output logic [63:0]                         branch_feedback_target,
    
    // Warp完成信号
    output logic                                warp_complete,
    output logic [$clog2(WARP_COUNT)-1:0]      warp_complete_id,
    
    // 流水线控制
    input  logic                                pipeline_stall,
    input  logic                                pipeline_flush,
    output logic                                pipeline_flush_req
);

    // 分支决策
    logic branch_taken;
    logic [63:0] next_pc;
    logic [THREAD_COUNT-1:0] divergent_mask;
    logic has_divergence;
    
    // 计算分支决策
    always_comb begin
        // 简化分支决策：如果任何线程需要分支则分支
        branch_taken = |mem_wb_branch_mask;
        
        // 检测分支发散
        divergent_mask = mem_wb_branch_mask ^ {THREAD_COUNT{branch_taken}};
        has_divergence = |divergent_mask;
        
        // 计算下一个PC
        if (mem_wb_is_branch && branch_taken) begin
            next_pc = mem_wb_branch_target;
        end else begin
            next_pc = mem_wb_pc + 4; // 正常递增
        end
    end
    
    // 寄存器写回控制
    always_comb begin
        reg_write_enable = mem_wb_valid && mem_wb_reg_write;
        reg_write_warp_id = mem_wb_warp_id;
        reg_write_addr = mem_wb_rd;
        reg_write_data = mem_wb_result;
        reg_write_mask = mem_wb_active_mask;
    end
    
    // PC更新控制
    always_comb begin
        pc_update_valid = mem_wb_valid && 
                         (mem_wb_is_branch || 
                          (mem_wb_inst[6:0] == 7'b1101111) || // JAL
                          (mem_wb_inst[6:0] == 7'b1100111));  // JALR
        pc_update_warp_id = mem_wb_warp_id;
        pc_update_pc = next_pc;
    end
    
    // 分支预测反馈
    always_comb begin
        branch_feedback_valid = mem_wb_valid && mem_wb_is_branch;
        branch_feedback_pc = mem_wb_pc;
        branch_feedback_taken = branch_taken;
        branch_feedback_target = mem_wb_branch_target;
    end
    
    // Warp完成检测
    always_comb begin
        // 简化实现：检测特殊指令或条件来确定warp完成
        warp_complete = mem_wb_valid && 
                       (mem_wb_inst == 32'h00000073 || // ECALL
                        mem_wb_active_mask == '0);      // 所有线程都不活跃
        warp_complete_id = mem_wb_warp_id;
    end
    
    // 流水线刷新请求
    always_comb begin
        // 当发生分支或跳转时请求刷新流水线
        pipeline_flush_req = mem_wb_valid && 
                            (mem_wb_is_branch && branch_taken && has_divergence);
    end
    
    // 总是准备好接收
    assign mem_wb_ready = !pipeline_stall;

endmodule : rvgpu_sm_writeback_stage

`endif // RVGPU_SM_WRITEBACK_STAGE_SV 