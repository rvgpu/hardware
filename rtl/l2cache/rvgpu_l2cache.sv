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

`ifndef RVGPU_L2CACHE_SV
`define RVGPU_L2CACHE_SV

`include "rvgpu_l2cache_pkg.svh"
`include "rvgpu_l2cache_if.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_interface_axi.svh"

`ifndef RVGPU_L2CACHE_PKG_IMPORTED
`define RVGPU_L2CACHE_PKG_IMPORTED
import rvgpu_l2cache_pkg::*;
`endif // RVGPU_L2CACHE_PKG_IMPORTED

`ifndef RVGPU_INTERNAL_NOC_PKG_IMPORTED
`define RVGPU_INTERNAL_NOC_PKG_IMPORTED
import rvgpu_internal_noc_pkg::*;
`endif // RVGPU_INTERNAL_NOC_PKG_IMPORTED

module rvgpu_l2cache #(
    parameter l2cache_config_t L2CACHE_CONFIG = DEFAULT_L2CACHE_CONFIG
) (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // NOC Interface - GPU内部通信
    rvgpu_internal_noc_if.device noc_if,
    
    // Memory Interface - 外部内存访问
    memory_if.master mem_if
);

    //=============================================================================
    // Internal Interface Instances
    //=============================================================================
    
    // 控制器与子模块的接口
    l2cache_tag_if #(.L2CACHE_CONFIG(L2CACHE_CONFIG)) controller_tag();
    l2cache_data_if #(.L2CACHE_CONFIG(L2CACHE_CONFIG)) controller_data();
    l2cache_axi_if #(.L2CACHE_CONFIG(L2CACHE_CONFIG)) controller_axi();
    l2cache_noc_if #(.L2CACHE_CONFIG(L2CACHE_CONFIG)) controller_noc();

    //=============================================================================
    // L2 Cache Controller Instance
    //=============================================================================
    
    rvgpu_l2cache_controller #(
        .L2CACHE_CONFIG(L2CACHE_CONFIG)
    ) u_l2cache_controller (
        .clk(clk),
        .rst_n(rst_n),
        
        // NOC Interface
        .noc_if(controller_noc.controller),
        
        // Tag Array Interface
        .tag_if(controller_tag.controller),
        
        // Data Array Interface
        .data_if(controller_data.controller),
        
        // AXI Interface
        .axi_if(controller_axi.controller)
    );

    //=============================================================================
    // L2 Cache Tag Array Instance
    //=============================================================================
    
    rvgpu_l2cache_tag_array #(
        .L2CACHE_CONFIG(L2CACHE_CONFIG)
    ) u_l2cache_tag_array (
        .clk(clk),
        .rst_n(rst_n),
        
        // Controller Interface
        .tag_if(controller_tag.tag_array)
    );

    //=============================================================================
    // L2 Cache Data Array Instance
    //=============================================================================
    
    rvgpu_l2cache_data_array #(
        .L2CACHE_CONFIG(L2CACHE_CONFIG)
    ) u_l2cache_data_array (
        .clk(clk),
        .rst_n(rst_n),
        
        // Controller Interface
        .data_if(controller_data.data_array)
    );

    //=============================================================================
    // L2 Cache AXI Adapter Instance
    //=============================================================================
    
    rvgpu_l2cache_axi_adapter #(
        .L2CACHE_CONFIG(L2CACHE_CONFIG)
    ) u_l2cache_axi_adapter (
        .clk(clk),
        .rst_n(rst_n),
        
        // Controller Interface
        .axi_if(controller_axi.axi_adapter),
        
        // Memory Interface
        .mem_if(mem_if)
    );

    //=============================================================================
    // L2 Cache NOC Adapter Instance
    //=============================================================================
    
    rvgpu_l2cache_noc_adapter #(
        .L2CACHE_CONFIG(L2CACHE_CONFIG)
    ) u_l2cache_noc_adapter (
        .clk(clk),
        .rst_n(rst_n),
        
        // Controller Interface
        .noc_if(controller_noc.noc_adapter),
        
        // NOC Interface
        .noc_external_if(noc_if)
    );

endmodule : rvgpu_l2cache

`endif // RVGPU_L2CACHE_SV 