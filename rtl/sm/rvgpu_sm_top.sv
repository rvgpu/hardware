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

`ifndef RVGPU_SM_TOP_SV
`define RVGPU_SM_TOP_SV

`include "rvgpu_typedef.svh"
`include "rvgpu_config.svh"
`include "types_gpc_router_message.svh"
`include "interface_gpc_router.svh"
`include "interface_sm_warp_dispatch.svh"
`include "interface_sm_l1cache.svh"

module rvgpu_sm_top #(
    parameter int SM_ID = 0
) (
    input  logic clk,
    input  logic rst_n,
    
    interface_gpc_router.left_port router_if
);

    localparam int CUDA_CORE_COUNT = `CONFIG_SM_CUDA_CORE_COUNT;
    
    // Warp分发接口 - Frontend <-> CUDA Core
    interface_sm_warp_dispatch warp_dispatch_if[CUDA_CORE_COUNT]();    
    // L1 Cache接口 - CUDA Core <-> L1 Cache
    interface_sm_l1cache l1_cache_if[CUDA_CORE_COUNT]();
    
    rvgpu_sm_frontend #(
        .SM_ID(SM_ID)
    ) u_sm_frontend (
        .clk(clk),
        .rst_n(rst_n),
        .router_if(router_if),
        .warp_dispatch_if(warp_dispatch_if),
        .l1_cache_if(l1_cache_if)
    );

    genvar i;
    generate
        for (i = 0; i < CUDA_CORE_COUNT; i = i + 1) begin : cuda_core_gen
            rvgpu_cudacore_top #(
                .CORE_ID(i),
                .SM_ID(SM_ID)
            ) u_cuda_core (
                .clk(clk),
                .rst_n(rst_n),
                .warp_dispatch_if(warp_dispatch_if[i]),
                .l1_cache_if(l1_cache_if[i])
            );
        end
    endgenerate

endmodule : rvgpu_sm_top

`endif // RVGPU_SM_TOP_SV