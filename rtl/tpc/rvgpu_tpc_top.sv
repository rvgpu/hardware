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
`include "rvgpu_config.svh"

module rvgpu_tpc_top #(
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
    
    // 内部路由器节点实例
    rvgpu_tpc_router_node #(
        .TPC_ID(TPC_ID),
        .IS_LAST(TPC_ID == (`CONFIG_GPC_TPC_NUMBER - 1))  // 动态判断是否为最后一个TPC
    ) u_tpc_router (
        .clk(clk),
        .rst_n(rst_n),
        .left_if(upstream_if),
        .right_if(downstream_if),
        .sm0_if(sm0_router_if),
        .sm1_if(sm1_router_if)
    );
    
    // SM实例化
    rvgpu_sm_top #(
        .SM_ID(0)
    ) u_sm0 (
        .clk(clk),
        .rst_n(rst_n),
        .router_if(sm0_router_if.left_port)
    );
    
    rvgpu_sm_top #(
        .SM_ID(1)
    ) u_sm1 (
        .clk(clk),
        .rst_n(rst_n),
        .router_if(sm1_router_if.left_port)
    );

endmodule : rvgpu_tpc_top

`endif // RVGPU_TPC_TOP_SV 