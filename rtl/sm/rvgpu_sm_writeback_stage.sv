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
`include "interface_sm_mem_wb.svh"
`include "interface_sm_regfile_access.svh"
`include "interface_sm_pc_update.svh"

// SM写回阶段
// 处理寄存器写回、分支处理和PC更新
module rvgpu_sm_writeback_stage #(
    parameter int WARP_COUNT = 32,      // 支持的warp数量
    parameter int THREAD_COUNT = 32     // 每个warp的线程数
) (
    input  logic clk,
    input  logic rst_n,
    
    // 从访存阶段的输入（接口）
    interface_sm_mem_wb.wb_sink                 mw_if,
    
    // 寄存器文件写接口（接口化）
    interface_sm_regfile_access.core            rf_if,
    
    // PC更新接口（接口化）
    interface_sm_pc_update.source               pc_update_if,
    
    // 分支预测反馈
    output logic                                branch_feedback_valid,
    output logic [63:0]                         branch_feedback_pc,
    output logic                                branch_feedback_taken,
    output logic [63:0]                         branch_feedback_target,
    
    // Warp完成信号
    output logic                                warp_complete,
    output logic [$clog2(WARP_COUNT)-1:0]       warp_complete_id,
    
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
        branch_taken = |mw_if.branch_mask;
        
        // 检测分支发散
        divergent_mask = mw_if.branch_mask ^ {THREAD_COUNT{branch_taken}};
        has_divergence = |divergent_mask;
        
        // 计算下一个PC
        if (mw_if.is_branch && branch_taken) begin
            next_pc = mw_if.branch_target;
        end else begin
            next_pc = mw_if.pc + 4; // 正常递增
        end
    end
    
    // 寄存器写回控制
    always_comb begin
        rf_if.write_enable  = mw_if.valid && mw_if.reg_write;
        rf_if.write_warp_id = mw_if.warp_id;
        rf_if.write_reg_addr= mw_if.rd;
        rf_if.write_data    = mw_if.result;
        rf_if.write_mask    = mw_if.active_mask;
    end
    
    // PC更新控制
    always_comb begin
        pc_update_if.valid  = mw_if.valid && 
                              (mw_if.is_branch || 
                               (mw_if.inst[6:0] == 7'b1101111) || // JAL
                               (mw_if.inst[6:0] == 7'b1100111));  // JALR
        pc_update_if.warp_id = mw_if.warp_id;
        pc_update_if.pc      = next_pc;
    end
    
    // 分支预测反馈
    always_comb begin
        branch_feedback_valid = mw_if.valid && mw_if.is_branch;
        branch_feedback_pc = mw_if.pc;
        branch_feedback_taken = branch_taken;
        branch_feedback_target = mw_if.branch_target;
    end
    
    // Warp完成检测
    always_comb begin
        // 简化实现：检测特殊指令或条件来确定warp完成
        warp_complete = mw_if.valid && 
                       (mw_if.inst == 32'h00000073 || // ECALL
                        mw_if.active_mask == '0);      // 所有线程都不活跃
        warp_complete_id = mw_if.warp_id;
    end
    
    // 流水线刷新请求
    always_comb begin
        // 当发生分支或跳转时请求刷新流水线
        pipeline_flush_req = mw_if.valid && 
                            (mw_if.is_branch && branch_taken && has_divergence);
    end
    
    // 总是准备好接收
    assign mw_if.ready = !pipeline_stall;

endmodule : rvgpu_sm_writeback_stage

`endif // RVGPU_SM_WRITEBACK_STAGE_SV 