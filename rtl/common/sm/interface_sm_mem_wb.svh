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

`ifndef RVGPU_INTERFACE_SM_MEM_WB_SVH
`define RVGPU_INTERFACE_SM_MEM_WB_SVH

`include "rvgpu_typedef.svh"

// SM Memory->Writeback 接口
interface interface_sm_mem_wb #(
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
    logic [31:0]                         result[THREAD_COUNT];
    logic                                reg_write;
    logic                                is_branch;
    logic [31:0]                         branch_target;
    logic [THREAD_COUNT-1:0]             branch_mask;

    // mem方（生产者）
    modport mem_source (
        output valid, inst, pc, warp_id, active_mask, rd, result, reg_write,
        output is_branch, branch_target, branch_mask,
        input  ready
    );

    // wb方（消费者）
    modport wb_sink (
        input  valid, inst, pc, warp_id, active_mask, rd, result, reg_write,
        input  is_branch, branch_target, branch_mask,
        output ready
    );

endinterface : interface_sm_mem_wb

`endif // RVGPU_INTERFACE_SM_MEM_WB_SVH


