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

`ifndef RVGPU_TOPLEVEL_SV
`define RVGPU_TOPLEVEL_SV

`include "rvgpu_config.svh"
`include "rvgpu_interface_axi.svh"
`include "rvgpu_internal_noc_pkg.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_control_unit_pkg.svh"
`include "rvgpu_l2cache_common.svh"

`ifndef RVGPU_INTERNAL_NOC_PKG_IMPORTED
`define RVGPU_INTERNAL_NOC_PKG_IMPORTED
import rvgpu_internal_noc_pkg::*;
`endif // RVGPU_INTERNAL_NOC_PKG_IMPORTED

`ifndef RVGPU_CONTROL_UNIT_PKG_IMPORTED
`define RVGPU_CONTROL_UNIT_PKG_IMPORTED
import rvgpu_control_unit_pkg::*;
`endif // RVGPU_CONTROL_UNIT_PKG_IMPORTED

module rvgpu_toplevel (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // Host Interface (AXI Slave)
    host_if.slave host_if,
    
    // Memory Interface (AXI Master) - Each L2Cache Slice has one
    memory_if.master mem_if [`L2CACHE_SLICE_NUMBER],
    
    // GPU Interrupt Output
    output logic gpu_irq
);
    rvgpu_internal_noc_if control_unit_noc_if();
    rvgpu_internal_noc_if l2cache_noc_if();
    rvgpu_internal_noc_if gpc_noc_if [2]();

    rvgpu_control_unit u_control_unit (
        .clk(clk),
        .rst_n(rst_n),
        .host_axi_if(host_if),
        .noc_if(control_unit_noc_if.device),
        .gpu_irq(gpu_irq)  // 连接到gpu_irq输出端口
    );

    rvgpu_l2cache u_l2cache (
        .clk(clk),
        .rst_n(rst_n),
        .noc_if(l2cache_noc_if.device),
        .mem_if(mem_if[0])  // 目前只使用第一个master接口
    );

    rvgpu_gpc_top #(.GPC_ID(0)) u_gpc_0 (
        .clk(clk),
        .rst_n(rst_n),
        .noc_if(gpc_noc_if[0].device)
    );

    rvgpu_gpc_top #(.GPC_ID(1)) u_gpc_1 (
        .clk(clk),
        .rst_n(rst_n),
        .noc_if(gpc_noc_if[1].device)
    );

    rvgpu_internal_noc u_internal_noc (
        .clk(clk),
        .rst_n(rst_n),
        .control_unit(control_unit_noc_if.noc),
        .l2cache(l2cache_noc_if.noc),
        .shader_core(gpc_noc_if)
    );

endmodule : rvgpu_toplevel

`endif // RVGPU_TOPLEVEL_SV