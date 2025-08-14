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

`ifndef RVGPU_TPC_TOP_SV
`define RVGPU_TPC_TOP_SV

`include "rvgpu_typedef.svh"
`include "interface_gpc_router.svh"
`include "gpc_block_tpc_if.svh"
`include "ldst_sm_if.svh"
`include "interface_l15cache.svh"
`include "rvgpu_mmu_if.svh"

module rvgpu_tpc_top #(
    parameter int NUM_SM = 2,                // 每个TPC中的SM数量
    parameter int MAX_WARPS_PER_SM = 32,     // 每个SM最大warp数
    parameter int TPC_ID = 0                 // TPC ID
) (
    input  logic clk,
    input  logic rst_n,
    
    // 路由器接口
    interface_gpc_router.left_port upstream_if,      // 连接上游（Frontend或前一个TPC）
    interface_gpc_router.right_port downstream_if    // 连接下游（下一个TPC，最后一个TPC没有此接口）
);
    
    // SM路由器接口 - 必须在实例化前声明
    interface_gpc_router sm0_router_if();
    interface_gpc_router sm1_router_if();
    
    // SM功能接口 - 每个SM需要的接口
    gpc_block_tpc_if sm0_block_dispatch_if();
    gpc_block_tpc_if sm1_block_dispatch_if();
    ldst_sm_if sm0_ldst_if();
    ldst_sm_if sm1_ldst_if();
    interface_l15cache sm0_l15_icache_if();
    interface_l15cache sm1_l15_icache_if();
    mmu_if sm0_tlb_if();
    mmu_if sm1_tlb_if();
    
    // 内部路由器节点实例
    rvgpu_tpc_router_node #(
        .TPC_ID(TPC_ID),
        .IS_LAST(0)  // 由外部控制是否为最后一个
    ) u_tpc_router (
        .clk(clk),
        .rst_n(rst_n),
        .left_if(upstream_if),
        .right_if(downstream_if),
        .sm0_if(sm0_router_if),
        .sm1_if(sm1_router_if)
    );
    
    // SM实例化 - 分别实例化每个SM，连接所有必需的接口
    rvgpu_sm_top #(
        .SM_ID(0),
        .WARP_COUNT(MAX_WARPS_PER_SM),
        .MAX_THREAD_PER_WARP(32),
        .MAX_ACTIVE_WARPS(16),
        .NUM_CUDA_CORES(4)
    ) u_sm0 (
        .clk(clk),
        .rst_n(rst_n),
        .router_if(sm0_router_if.left_port),
        .block_dispatch_if(sm0_block_dispatch_if.sm),
        .ldst_if(sm0_ldst_if.sm),
        .l15_icache_if(sm0_l15_icache_if.requester),
        .tlb_if(sm0_tlb_if.requester_port)
    );
    
    rvgpu_sm_top #(
        .SM_ID(1),
        .WARP_COUNT(MAX_WARPS_PER_SM),
        .MAX_THREAD_PER_WARP(32),
        .MAX_ACTIVE_WARPS(16),
        .NUM_CUDA_CORES(4)
    ) u_sm1 (
        .clk(clk),
        .rst_n(rst_n),
        .router_if(sm1_router_if.left_port),
        .block_dispatch_if(sm1_block_dispatch_if.sm),
        .ldst_if(sm1_ldst_if.sm),
        .l15_icache_if(sm1_l15_icache_if.requester),
        .tlb_if(sm1_tlb_if.requester_port)
    );

endmodule : rvgpu_tpc_top

`endif // RVGPU_TPC_TOP_SV 