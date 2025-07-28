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

`ifndef RVGPU_GPC_TOP_SV
`define RVGPU_GPC_TOP_SV

`include "rvgpu_typedef.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_noc_message.svh"
`include "rvgpu_mmu_if.svh"  // 使用通用MMU接口

`include "ldst_sm_if.svh"
`include "gpc_block_tpc_if.svh"
`include "gpc_block_raster_if.svh"
`include "rvgpu_gpc_pkg.svh"

`ifndef RVGPU_GPC_PKG_IMPORTED
`define RVGPU_GPC_PKG_IMPORTED
import rvgpu_gpc_pkg::*;
`endif // RVGPU_GPC_PKG_IMPORTED

module rvgpu_gpc_top #(
    parameter gpc_parameter_t GPC_CONFIG = DEFAULT_GPC_CONFIG,
    parameter int GPC_ID = 0
) (
    input  logic clk,
    input  logic rst_n,
    rvgpu_internal_noc_if.device noc_if
);
    // 内部接口声明
    gpc_block_raster_if      block_raster_if();
    gpc_block_tpc_if         block_tpc_if[GPC_CONFIG.num_tpc]();
    gpc_l15_cache_if         l15_cache_if[GPC_CONFIG.num_tpc+2]();  // NUM_TPC个TPC + Block Scheduler + Raster
    rvgpu_internal_noc_if    l15_noc_if();                          // L1.5缓存NOC接口
    // GPC MMU接口
    mmu_if               gpc_mmu_if[GPC_CONFIG.num_tpc+1]();    // NUM_TPC个TPC + Block Scheduler
    rvgpu_internal_noc_if    mmu_noc_if();                          // MMU NOC接口
    rvgpu_internal_noc_if    scheduler_noc_if();                    // Scheduler NOC接口
    // L0 TLB更新接口
    tlb_update_if        l0_tlb_if[GPC_CONFIG.num_tpc]();
    
    // 内部信号
    logic [7:0] active_warps_count[GPC_CONFIG.num_tpc];  // 每个TPC的活跃warp数量
    logic [7:0] sm_utilization[GPC_CONFIG.num_tpc];      // 每个TPC的SM利用率
    
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
        .TLB_ENTRIES(128),  // 使用固定值
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
        .tpc_if(block_tpc_if),
        .raster_if(block_raster_if),
        .l15_if(l15_cache_if[GPC_CONFIG.num_tpc].requester),
        .mmu_if(gpc_mmu_if[GPC_CONFIG.num_tpc].requester_port)
    );
    
    // L1.5 Cache实例化
    rvgpu_gpc_l15_cache #(
        .NUM_REQUESTERS(GPC_CONFIG.num_tpc+2)
    ) u_l15_cache (
        .clk(clk),
        .rst_n(rst_n),
        .noc_if(l15_noc_if.device),
        .requester_if(l15_cache_if)
    );
    
    // Raster Engine实例化
    rvgpu_gpc_raster u_raster (
        .clk(clk),
        .rst_n(rst_n),
        .raster_if(block_raster_if.raster),
        .l15_if(l15_cache_if[GPC_CONFIG.num_tpc+1].requester)
    );
    
    // TPC实例化
    genvar i;
    generate
        for (i = 0; i < GPC_CONFIG.num_tpc; i++) begin : tpc_gen
            rvgpu_tpc_top #(
                .TPC_ID(i),
                .NUM_SM(2),  // 使用固定值
                .MAX_WARPS_PER_SM(32)  // 使用固定值
            ) u_tpc (
                .clk(clk),
                .rst_n(rst_n),
                .tpc_if(block_tpc_if[i].tpc),
                .l15_if(l15_cache_if[i].requester),
                .tlb_if(gpc_mmu_if[i].requester_port),
                .tlb_update_if(l0_tlb_if[i].receiver),
                .active_warps_count(active_warps_count[i]),
                .sm_utilization(sm_utilization[i])
            );
        end
    endgenerate
    
    // 接口连接已通过端口直接完成

endmodule : rvgpu_gpc_top

`endif // RVGPU_GPC_TOP_SV 