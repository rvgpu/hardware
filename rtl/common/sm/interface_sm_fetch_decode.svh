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

`ifndef RVGPU_INTERFACE_SM_FETCH_DECODE_SVH
`define RVGPU_INTERFACE_SM_FETCH_DECODE_SVH

`include "rvgpu_typedef.svh"

// SM Fetch->Decode 接口
interface interface_sm_fetch_decode #(
    parameter int WARP_COUNT = 32,
    parameter int THREAD_COUNT = 32
);
    // 有效/就绪握手
    logic                                valid;
    logic                                ready;

    // 负载
    logic [31:0]                         inst;
    logic [63:0]                         pc;
    logic [$clog2(WARP_COUNT)-1:0]       warp_id;
    logic [THREAD_COUNT-1:0]             active_mask;

    // fetch方（生产者）视角
    modport fetch_source (
        output valid, inst, pc, warp_id, active_mask,
        input  ready
    );

    // decode方（消费者）视角
    modport decode_sink (
        input  valid, inst, pc, warp_id, active_mask,
        output ready
    );

endinterface : interface_sm_fetch_decode

`endif // RVGPU_INTERFACE_SM_FETCH_DECODE_SVH


