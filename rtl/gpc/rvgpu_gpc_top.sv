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
`include "interface_gpc_router.svh"

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
    
    // 路由器接口连接
    interface_gpc_router router_chain[GPC_CONFIG.num_tpc+1]();  // +1 for frontend
    
    // GPC前端实例 - 整合所有GPC功能模块和内部路由器
    rvgpu_gpc_frontend #(
        .GPC_CONFIG(GPC_CONFIG),
        .GPC_ID(GPC_ID)
    ) u_gpc_frontend (
        .clk(clk),
        .rst_n(rst_n),
        .noc_if(noc_if),
        .router_if(router_chain[0].right_port)  // Frontend使用right_port
    );
    
    // TPC实例化 - 每个TPC有两个路由器接口
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
                .upstream_if(router_chain[i].left_port),      // TPC使用left_port接收上游
                .downstream_if(router_chain[i+1].right_port)   // TPC使用right_port连接下游
            );
        end
    endgenerate

endmodule : rvgpu_gpc_top

`endif // RVGPU_GPC_TOP_SV 