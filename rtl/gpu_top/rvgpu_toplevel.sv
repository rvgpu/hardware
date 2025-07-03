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

`ifndef RVGPU_INTERNAL_NOC_PKG_IMPORTED
`define RVGPU_INTERNAL_NOC_PKG_IMPORTED
import rvgpu_internal_noc_pkg::*;
`endif // RVGPU_INTERNAL_NOC_PKG_IMPORTED

module rvgpu_toplevel #(
    // Structure Parameter: system_config_t
    parameter system_config_t SYS_CONFIG = get_default_system_config()
) (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // Host Interface (AXI Slave)
    host_if.slave host_if,
    
    // Memory Interface (AXI Master) - Each L2Cache Slice has one
    memory_if.master mem_if [`L2CACHE_SLICE_NUMBER]
);

    // 创建NOC配置
    internal_noc_interface_t noc_config;
    assign noc_config = get_default_internal_noc_interface();

    rvgpu_internal_noc_if #(.NOC_CONFIG(noc_config)) control_unit_noc_if();
    rvgpu_internal_noc_if #(.NOC_CONFIG(noc_config)) l2cache_noc_if();
    rvgpu_internal_noc_if #(.NOC_CONFIG(noc_config)) shader_core_noc_if [`SHADER_CORE_NUMBER];

    // Control Unit
    rvgpu_control_unit u_control_unit #(.NOC_CONFIG(noc_config)) (
        .clk(clk),
        .rst_n(rst_n),
        .host_if(host_if),
        .noc_if(control_unit_noc_if.device)
    );

    // L2Cache
    rvgpu_l2cache u_l2cache #(.NOC_CONFIG(noc_config)) (
        .clk(clk),
        .rst_n(rst_n),
        .noc_if(l2cache_noc_if.device),
        .mem_if(mem_if)
    );

    // Shader Core
    rvgpu_shader_core u_shader_core_0 #(.NOC_CONFIG(noc_config)) (
        .clk(clk),
        .rst_n(rst_n),
        .noc_if(shader_core_noc_if.device)
    );

    // Shader Core
    rvgpu_shader_core u_shader_core_1 #(.NOC_CONFIG(noc_config)) (
        .clk(clk),
        .rst_n(rst_n),
        .noc_if(shader_core_noc_if.device)
    );

    // Noc
    rvgpu_internal_noc_2sc u_internal_noc_2sc #(.NOC_CONFIG(noc_config)) (
        .clk(clk),
        .rst_n(rst_n),
        .control_unit_noc_if(control_unit_noc_if.noc),
        .l2cache_noc_if(l2cache_noc_if.noc),
        .shader_core_noc_if({shader_core_noc_if[1].noc, shader_core_noc_if[0].noc}),
    );

endmodule : rvgpu_toplevel

`endif // RVGPU_TOPLEVEL_SV
