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

`ifndef RVGPU_SM_L1_CACHE_TOP_SV
`define RVGPU_SM_L1_CACHE_TOP_SV

`include "rvgpu_typedef.svh"
`include "rvgpu_config.svh"
`include "interface_gpc_router.svh"
`include "interface_sm_l1cache.svh"
`include "interface_sm_l1_tag_array.svh"
`include "interface_sm_l1_data_array.svh"

module rvgpu_sm_l1_cache_top #(
    parameter int SM_ID = 0
) (
    input  logic clk,
    input  logic rst_n,
    
    // 路由器接口 - 连接到router_arbiter
    interface_gpc_router.left_port router_if,
    
    // L1 Cache接口 - 连接到CUDA Core
    interface_sm_l1cache.cache core_if[`CONFIG_SM_CUDA_CORE_COUNT]
);

    // ============================================================================
    // 内部接口
    // ============================================================================
    
    // 仲裁器和控制器之间的接口
    interface_sm_l1cache arbiter_controller_if();
    
    // Tag Array接口
    interface_sm_l1_tag_array tag_if();
    
    // Data Array接口
    interface_sm_l1_data_array data_if();
    
    // ============================================================================
    // L1 Cache子模块实例化
    // ============================================================================
    
    // L1仲裁器实例化 - 处理4个CUDA Core的请求
    rvgpu_sm_l1_arbiter #(
        .SM_ID(SM_ID)
    ) u_l1_arbiter (
        .clk(clk),
        .rst_n(rst_n),
        .core_if(core_if),
        .controller_if(arbiter_controller_if)
    );
    
    // L1 Controller实例化 - 处理Cache的核心逻辑
    rvgpu_sm_l1_controller #(
        .SM_ID(SM_ID)
    ) u_l1_controller (
        .clk(clk),
        .rst_n(rst_n),
        .arbiter_if(arbiter_controller_if),
        .tag_if(tag_if),
        .data_if(data_if),
        .router_if(router_if)  // 连接到router，处理L1.5访问
    );
    
    // L1 Tag Array实例化
    rvgpu_sm_l1_tag_array #(
        .SM_ID(SM_ID)
    ) u_l1_tag_array (
        .clk(clk),
        .rst_n(rst_n),
        .tag_if(tag_if)
    );
    
    // L1 Data Array实例化
    rvgpu_sm_l1_data_array #(
        .SM_ID(SM_ID)
    ) u_l1_data_array (
        .clk(clk),
        .rst_n(rst_n),
        .data_if(data_if)
    );

endmodule : rvgpu_sm_l1_cache_top

`endif // RVGPU_SM_L1_CACHE_TOP_SV