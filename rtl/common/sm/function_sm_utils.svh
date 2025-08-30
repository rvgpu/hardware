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

`ifndef FUNCTION_SM_UTILS_SVH
`define FUNCTION_SM_UTILS_SVH

`include "rvgpu_typedef.svh"
`include "rvgpu_config.svh"
`include "types_sm_warp.svh"

// 计算Block中的Warp数量
function automatic int f_calc_warp_count(int thread_count);
    return (thread_count + `CONFIG_WARP_THREAD_NUMBER - 1) / `CONFIG_WARP_THREAD_NUMBER;
endfunction

// 计算Warp中的活跃线程掩码
function automatic logic [`CONFIG_WARP_THREAD_NUMBER-1:0] f_calc_active_mask(int thread_count, int warp_idx);
    int threads_in_warp;
    logic [`CONFIG_WARP_THREAD_NUMBER-1:0] mask;
    
    // 计算当前warp中的线程数
    if (warp_idx == f_calc_warp_count(thread_count) - 1 && 
        thread_count % `CONFIG_WARP_THREAD_NUMBER != 0) begin
        // 最后一个warp可能不满
        threads_in_warp = thread_count % `CONFIG_WARP_THREAD_NUMBER;
    end else begin
        // 完整warp
        threads_in_warp = `CONFIG_WARP_THREAD_NUMBER;
    end
    
    // 生成掩码
    mask = (1 << threads_in_warp) - 1;
    return mask;
endfunction

// 从指令中提取寄存器地址
function automatic void f_extract_reg_addrs(
    input logic [31:0] inst,
    output logic [4:0] rs1,
    output logic [4:0] rs2,
    output logic [4:0] rs3,
    output logic [4:0] rd
);
    // RISC-V指令格式
    rs1 = inst[19:15];
    rs2 = inst[24:20];
    rs3 = inst[31:27]; // 假设格式
    rd = inst[11:7];
endfunction

// 从指令中提取立即数 (I-type)
function automatic logic [31:0] f_extract_imm_i(logic [31:0] inst);
    return {{20{inst[31]}}, inst[31:20]};
endfunction

// 从指令中提取立即数 (S-type)
function automatic logic [31:0] f_extract_imm_s(logic [31:0] inst);
    return {{20{inst[31]}}, inst[31:25], inst[11:7]};
endfunction

// 从指令中提取立即数 (B-type)
function automatic logic [31:0] f_extract_imm_b(logic [31:0] inst);
    return {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
endfunction

// 从指令中提取立即数 (U-type)
function automatic logic [31:0] f_extract_imm_u(logic [31:0] inst);
    return {inst[31:12], 12'b0};
endfunction

// 从指令中提取立即数 (J-type)
function automatic logic [31:0] f_extract_imm_j(logic [31:0] inst);
    return {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
endfunction

// 检查指令类型
function automatic logic f_is_alu_inst(logic [31:0] inst);
    return (inst[6:0] == 7'b0110011) || (inst[6:0] == 7'b0010011);
endfunction

function automatic logic f_is_fpu_inst(logic [31:0] inst);
    return (inst[6:0] == 7'b1010011);
endfunction

function automatic logic f_is_branch_inst(logic [31:0] inst);
    return (inst[6:0] == 7'b1100011);
endfunction

function automatic logic f_is_load_inst(logic [31:0] inst);
    return (inst[6:0] == 7'b0000011);
endfunction

function automatic logic f_is_store_inst(logic [31:0] inst);
    return (inst[6:0] == 7'b0100011);
endfunction

`endif // FUNCTION_SM_UTILS_SVH
