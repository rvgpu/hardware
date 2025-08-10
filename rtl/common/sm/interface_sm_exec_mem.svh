//=============================================================================
// Copyright © 2025 RVGPU Team
// Licensed under the Apache License, Version 2.0 (the "License");
// You may not use this file except in compliance with the License.
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

`ifndef RVGPU_INTERFACE_SM_EXEC_MEM_SVH
`define RVGPU_INTERFACE_SM_EXEC_MEM_SVH

`include "rvgpu_typedef.svh"

// SM Execute->Memory 接口
interface interface_sm_exec_mem #(
    parameter int WARP_COUNT = 32,
    parameter int THREAD_COUNT = 32
);
    // 有效/就绪
    logic                                valid;
    logic                                ready;

    // 基本上下文
    logic [31:0]                         inst;
    logic [63:0]                         pc;
    logic [$clog2(WARP_COUNT)-1:0]       warp_id;
    logic [THREAD_COUNT-1:0]             active_mask;
    logic [4:0]                          rd;

    // 结果/访存控制
    logic [31:0]                         result[THREAD_COUNT];
    logic                                is_load;
    logic                                is_store;
    logic                                is_branch;
    logic                                reg_write;
    logic [31:0]                         branch_target;
    logic [THREAD_COUNT-1:0]             branch_mask;

    // exec方（生产者）
    modport exec_source (
        output valid, inst, pc, warp_id, active_mask, rd,
        output result, is_load, is_store, is_branch, reg_write, branch_target, branch_mask,
        input  ready
    );

    // mem方（消费者）
    modport mem_sink (
        input  valid, inst, pc, warp_id, active_mask, rd,
        input  result, is_load, is_store, is_branch, reg_write, branch_target, branch_mask,
        output ready
    );

endinterface : interface_sm_exec_mem

`endif // RVGPU_INTERFACE_SM_EXEC_MEM_SVH


