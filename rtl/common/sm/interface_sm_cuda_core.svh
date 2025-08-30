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

`ifndef INTERFACE_SM_CUDA_CORE_SVH
`define INTERFACE_SM_CUDA_CORE_SVH

`include "rvgpu_typedef.svh"
`include "rvgpu_config.svh"

// CUDA Core接口
// 用于SM与CUDA Core之间的通信
interface interface_sm_cuda_core #(
    parameter int THREAD_COUNT = `CONFIG_WARP_THREAD_NUMBER
);
    // 时钟和复位
    logic clk;
    logic rst_n;
    
    // 指令输入
    logic inst_valid;
    logic [31:0] inst;
    logic [31:0] pc;
    logic [31:0] warp_id;
    logic [31:0] active_mask;
    
    // 操作数输入
    logic [THREAD_COUNT-1:0][31:0] src1_data;
    logic [THREAD_COUNT-1:0][31:0] src2_data;
    logic [THREAD_COUNT-1:0][31:0] src3_data;
    logic [31:0] imm_data;
    
    // 控制信号
    logic stall;
    logic ready;
    
    // 执行结果输出
    logic result_valid;
    logic [THREAD_COUNT-1:0][31:0] result_data;
    logic [4:0] result_rd;
    logic [31:0] result_pc;
    logic [31:0] result_warp_id;
    logic [31:0] result_active_mask;
    
    // 分支结果
    logic result_is_branch;
    logic [31:0] result_branch_target;
    logic [31:0] result_branch_mask;
    
    // Core端口
    modport core (
        input  clk, rst_n,
        input  inst_valid, inst, pc, warp_id, active_mask,
        input  src1_data, src2_data, src3_data, imm_data, stall,
        output ready, result_valid, result_data, result_rd, result_pc, result_warp_id, result_active_mask,
        output result_is_branch, result_branch_target, result_branch_mask
    );
    
    // SM端口
    modport sm (
        output clk, rst_n,
        output inst_valid, inst, pc, warp_id, active_mask,
        output src1_data, src2_data, src3_data, imm_data, stall,
        input  ready, result_valid, result_data, result_rd, result_pc, result_warp_id, result_active_mask,
        input  result_is_branch, result_branch_target, result_branch_mask
    );
endinterface

`endif // INTERFACE_SM_CUDA_CORE_SVH