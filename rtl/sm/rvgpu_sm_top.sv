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
    parameter int SM_ID = 0                    // SM ID
) (
    input  logic clk,
    input  logic rst_n,
    
    interface_gpc_router.left_port router_if
);

    // ============================================================================
    // 使用宏定义
    // ============================================================================
    localparam int WARP_COUNT = `CONFIG_SM_WARP_COUNT;        // 支持的warp数量
    localparam int THREAD_COUNT = `CONFIG_WARP_THREAD_NUMBER;  // 每个warp的线程数
    localparam int CUDA_CORE_COUNT = `CONFIG_SM_CUDA_CORE_COUNT; // CUDA核心数量
    
    // ============================================================================
    // 内部接口声明
    // ============================================================================
    
    // Warp分发接口 - Frontend <-> CUDA Core
    interface_sm_warp_dispatch warp_dispatch_if[CUDA_CORE_COUNT]();
    
    // L1 Cache接口 - CUDA Core <-> L1 Cache
    interface_sm_l1cache l1_cache_if[CUDA_CORE_COUNT]();
    
    // ============================================================================
    // SM Frontend模块实例化 - 负责Block拆分为warp的调度和L1缓存管理
    // ============================================================================
    rvgpu_sm_frontend #(
        .SM_ID(SM_ID)
    ) u_sm_frontend (
        .clk(clk),
        .rst_n(rst_n),
        .router_if(router_if),
        .warp_dispatch_if(warp_dispatch_if),
        .l1_cache_if(l1_cache_if)
    );

    // ============================================================================
    // CUDA Core模块实例化
    // ============================================================================
    genvar i;
    generate
        for (i = 0; i < CUDA_CORE_COUNT; i = i + 1) begin : cuda_core_gen
            // CUDA Core单元实例化
            rvgpu_cudacore_top #(
                .CORE_ID(i),
                .WARP_COUNT(WARP_COUNT),
                .THREAD_COUNT(THREAD_COUNT)
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