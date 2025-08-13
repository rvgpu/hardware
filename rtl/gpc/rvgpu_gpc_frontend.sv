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

`ifndef RVGPU_GPC_FRONTEND_SV
`define RVGPU_GPC_FRONTEND_SV

`include "rvgpu_typedef.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_noc_message.svh"
`include "rvgpu_mmu_if.svh"
`include "interface_gpc_router.svh"

`include "ldst_sm_if.svh"
`include "gpc_block_raster_if.svh"
`include "rvgpu_gpc_pkg.svh"

`ifndef RVGPU_GPC_PKG_IMPORTED
`define RVGPU_GPC_PKG_IMPORTED
import rvgpu_gpc_pkg::*;
`endif // RVGPU_GPC_PKG_IMPORTED

// GPC前端模块 - 整合所有GPC功能模块和内部路由器
module rvgpu_gpc_frontend #(
    parameter gpc_parameter_t GPC_CONFIG = DEFAULT_GPC_CONFIG,
    parameter int GPC_ID = 0
) (
    input  logic clk,
    input  logic rst_n,
    
    // 外部NOC接口
    rvgpu_internal_noc_if.device noc_if,
    
    // 路由器接口 - 连接TPC0
    interface_gpc_router.down_port router_if
);
    
    // 内部NOC接口
    rvgpu_internal_noc_if    l15_noc_if();                          // L1.5缓存NOC接口
    rvgpu_internal_noc_if    mmu_noc_if();                          // MMU NOC接口
    rvgpu_internal_noc_if    scheduler_noc_if();                    // Scheduler NOC接口
    
    // 内部功能模块接口 - 必须声明以支持模块实例化
    gpc_block_raster_if      block_raster_if();                      // Block Raster接口
    interface_l15cache       l15_cache_if[GPC_CONFIG.num_tpc+2]();  // L1.5 Cache接口
    mmu_if                   gpc_mmu_if[GPC_CONFIG.num_tpc+1]();    // GPC MMU接口
    gpc_tlb_update_if        l0_tlb_if[GPC_CONFIG.num_tpc]();       // L0 TLB更新接口
    interface_gpc_router     block_scheduler_router_if();            // Block Scheduler路由器接口
    rvgpu_internal_noc_if    raster_noc_if();                        // Raster NOC接口
    // 创建路由器接口来桥接NOC和路由器
    interface_gpc_router l15_router_if();
    interface_gpc_router mmu_router_if();
    interface_gpc_router raster_router_if();
    
    // NOC Adapter实例化
    rvgpu_gpc_noc_adapter #(.GPC_ID(GPC_ID)) u_noc_adapter (
        .clk(clk),
        .rst_n(rst_n),
        .noc_external_if(noc_if),
        .l15_cache_if(l15_noc_if.noc),
        .mmu_if(mmu_noc_if.noc),
        .scheduler_if(scheduler_noc_if.noc)
    );
    
    // GPC MMU实例
    rvgpu_gpc_mmu #(
        .MAX_REQUESTS(16),  // 使用固定值
        .GPC_ID(GPC_ID)
    ) u_gpc_mmu (
        .clk(clk),
        .rst_n(rst_n),
        .bs_if(gpc_mmu_if[GPC_CONFIG.num_tpc].mmu_port),
        .tpc_if(gpc_mmu_if[0:GPC_CONFIG.num_tpc-1]),
        .l0_tlb_if(l0_tlb_if),
        .noc_if(mmu_noc_if.device)
    );
    
    // GPC路由器实例 - 连接Block Scheduler和TPC路由器链
    rvgpu_gpc_router #(
        .GPC_CONFIG(GPC_CONFIG),
        .GPC_ID(GPC_ID)
    ) u_gpc_router (
        .clk(clk),
        .rst_n(rst_n),
        .l15_if(l15_router_if.up_port),                   // L1.5 Cache路由器接口
        .mmu_if(mmu_router_if.up_port),                   // MMU路由器接口
        .block_if(block_scheduler_router_if.up_port),      // Block Scheduler使用up_port发送消息
        .raster_if(raster_router_if.up_port),              // Raster路由器接口
        .tpc_router_if(router_if)                          // 连接到TPC路由器链
    );
    
    // GPC Block Scheduler实例
    rvgpu_gpc_block_scheduler #(
        .GPC_ID(GPC_ID),
        .NUM_TPC(GPC_CONFIG.num_tpc),
        .MAX_WARPS_PER_BLOCK(32),  // 使用固定值
        .ADDR_WIDTH(40)
    ) u_gpc_block_scheduler (
        .clk(clk),
        .rst_n(rst_n),
        .noc_if(scheduler_noc_if.device),
        .router_if(block_scheduler_router_if.down_port),   // Block Scheduler使用down_port接收消息
        .raster_if(block_raster_if)
    );
    
    // GPC Raster Engine实例
    rvgpu_gpc_raster #(
        .GPC_ID(GPC_ID)
    ) u_gpc_raster (
        .clk(clk),
        .rst_n(rst_n),
        .raster_if(block_raster_if.raster),
        .l15_if(l15_cache_if[GPC_CONFIG.num_tpc+1].requester)
    );
    
    // GPC L1.5 Cache实例
    rvgpu_gpc_l15cache #(
        .GPC_ID(GPC_ID)
    ) u_gpc_l15cache (
        .clk(clk),
        .rst_n(rst_n),
        .noc_if(l15_noc_if.device),
        .requester_if(l15_cache_if)
    );

endmodule : rvgpu_gpc_frontend

`endif // RVGPU_GPC_FRONTEND_SV
