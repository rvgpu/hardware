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
`include "rvgpu_internal_noc_pkg.svh"
`include "gpc_l15_cache_if.svh"
`include "gpc_mmu_if.svh"
`include "gpc_l0_tlb_if.svh"
`include "ldst_sm_if.svh"
`include "gpc_block_tpc_if.svh"
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
    gpc_mmu_if               gpc_mmu_if[GPC_CONFIG.num_tpc+1]();    // NUM_TPC个TPC + Block Scheduler
    rvgpu_internal_noc_if    mmu_noc_if();                          // MMU NOC接口
    rvgpu_internal_noc_if    scheduler_noc_if();                    // Scheduler NOC接口
    gpc_l0_tlb_if            l0_tlb_if[GPC_CONFIG.num_tpc]();
    
    // 内部信号
    logic [7:0] active_warps_count[GPC_CONFIG.num_tpc];  // 每个TPC的活跃warp数量
    logic [7:0] sm_utilization[GPC_CONFIG.num_tpc];      // 每个TPC的SM利用率
    
    // NOC Adapter实例化
    rvgpu_gpc_noc_adapter u_noc_adapter (
        .clk(clk),
        .rst_n(rst_n),
        .noc_external_if(noc_if),
        .l15_cache_if(l15_noc_if.noc),
        .mmu_if(mmu_noc_if.noc),
        .scheduler_if(scheduler_noc_if.noc)
    );
    
    // GPC MMU实例化
    rvgpu_gpc_mmu #(
        .TLB_ENTRIES(128),
        .MAX_REQUESTS(16),
        .GPC_ID(GPC_ID)
    ) u_gpc_mmu (
        .clk(clk),
        .rst_n(rst_n),
        .bs_if(gpc_mmu_if[GPC_CONFIG.num_tpc].gpc_mmu),
        .tpc_if(gpc_mmu_if[0:GPC_CONFIG.num_tpc-1]),
        .l0_tlb_if(l0_tlb_if),
        .noc_if(mmu_noc_if.device)
    );
    
    // Block Scheduler实例化
    rvgpu_gpc_block_scheduler u_block_scheduler (
        .clk(clk),
        .rst_n(rst_n),
        .noc_if(scheduler_noc_if.device),
        .tpc_if(block_tpc_if),
        .raster_if(block_raster_if.scheduler),
        .l15_if(l15_cache_if[GPC_CONFIG.num_tpc].requester),
        .tlb_if(gpc_mmu_if[GPC_CONFIG.num_tpc].requester)
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
                .NUM_SM(GPC_CONFIG.num_sm_per_tpc),
                .MAX_WARPS_PER_SM(32),
                .TPC_ID(i)
            ) u_tpc (
                .clk(clk),
                .rst_n(rst_n),
                .block_dispatch_if(block_tpc_if[i].tpc),
                .l15_if(l15_cache_if[i].requester),
                .tlb_if(l0_tlb_if[i].tpc),
                .active_warps_count(active_warps_count[i]),
                .sm_utilization(sm_utilization[i])
            );
        end
    endgenerate
    
    // 接口连接已通过端口直接完成

endmodule : rvgpu_gpc_top

`endif // RVGPU_GPC_TOP_SV 