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

`ifndef RVGPU_SM_FRONTEND_SV
`define RVGPU_SM_FRONTEND_SV

`include "rvgpu_typedef.svh"
`include "rvgpu_config.svh"
`include "interface_gpc_router.svh"
`include "types_gpc_router_message.svh"
`include "interface_sm_warp_dispatch.svh"
`include "interface_sm_l1cache.svh"
`include "interface_fifo_stream.svh"
`include "rvgpu_fifo_pkg.svh"

module rvgpu_sm_frontend #(
    parameter int SM_ID = 0
) (
    input  logic clk,
    input  logic rst_n,
    
    // 外部路由器接口
    interface_gpc_router.left_port router_if,
    
    // Warp分发接口 - 连接CUDA Core
    interface_sm_warp_dispatch.frontend_port warp_dispatch_if[`CONFIG_SM_CUDA_CORE_COUNT],
    
    // L1 Cache接口 - 连接CUDA Core
    interface_sm_l1cache.cache l1_cache_if[`CONFIG_SM_CUDA_CORE_COUNT]
);

    interface_gpc_router router_block_scheduler_if();
    interface_gpc_router router_l1cache_if();
    
    // ============================================================================
    // 路由器仲裁器实例化
    // ============================================================================
    
    rvgpu_sm_router_arbiter #(
        .SM_ID(SM_ID)
    ) u_router_arbiter (
        .clk(clk),
        .rst_n(rst_n),
        .router_if(router_if),
        .block_scheduler_if(router_block_scheduler_if.right_port),
        .l1cache_if(router_l1cache_if.right_port)
    );
    
    // ============================================================================
    // Block调度器实例化
    // ============================================================================
    
    rvgpu_sm_block_scheduler #(
        .SM_ID(SM_ID)
    ) u_block_scheduler (
        .clk(clk),
        .rst_n(rst_n),
        .router_if(router_block_scheduler_if.left_port),
        .warp_dispatch_if(warp_dispatch_if)
    );
    
    // ============================================================================
    // L1 Cache顶层模块实例化
    // ============================================================================
    
    rvgpu_sm_l1_cache_top #(
        .SM_ID(SM_ID)
    ) u_l1_cache_top (
        .clk(clk),
        .rst_n(rst_n),
        .router_if(router_l1cache_if.left_port),
        .core_if(l1_cache_if)
    );

endmodule : rvgpu_sm_frontend

`endif // RVGPU_SM_FRONTEND_SV