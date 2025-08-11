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
`include "rvgpu_mmu_if.svh"

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
    interface_l15cache         l15_cache_if[GPC_CONFIG.num_tpc+2]();  // NUM_TPC个TPC + Block Scheduler + Raster
    mmu_if                   gpc_mmu_if[GPC_CONFIG.num_tpc+1]();    // NUM_TPC个TPC + Block Scheduler
    gpc_tlb_update_if        l0_tlb_if[GPC_CONFIG.num_tpc]();       // L0 TLB更新接口
    
    // GPC前端实例 - 整合所有GPC功能模块
    rvgpu_gpc_frontend #(
        .GPC_CONFIG(GPC_CONFIG),
        .GPC_ID(GPC_ID)
    ) u_gpc_frontend (
        .clk(clk),
        .rst_n(rst_n),
        .noc_if(noc_if),
        .block_raster_if(block_raster_if),
        .block_tpc_if(block_tpc_if),
        .l15_cache_if(l15_cache_if),
        .gpc_mmu_if(gpc_mmu_if),
        .l0_tlb_if(l0_tlb_if)
    );
    
    // 内部信号
    logic [7:0] active_warps_count[GPC_CONFIG.num_tpc];  // 每个TPC的活跃warp数量
    logic [7:0] sm_utilization[GPC_CONFIG.num_tpc];      // 每个TPC的SM利用率
    
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

endmodule : rvgpu_gpc_top

`endif // RVGPU_GPC_TOP_SV 