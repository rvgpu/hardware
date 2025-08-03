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

`ifndef RVGPU_GPC_L15_CACHE_SV
`define RVGPU_GPC_L15_CACHE_SV


`include "types_cache_op.svh"
`include "const_l15cache.svh"
`include "types_l15cache.svh"
`include "function_cache_lru.svh"

`include "interface_l15cache_tag.svh"
`include "interface_l15cache_data.svh"
`include "rvgpu_internal_noc_if.svh"

`ifndef RVGPU_INTERNAL_NOC_PKG_IMPORTED
`define RVGPU_INTERNAL_NOC_PKG_IMPORTED
import rvgpu_internal_noc_pkg::*;
`endif // RVGPU_INTERNAL_NOC_PKG_IMPORTED

module rvgpu_gpc_l15cache (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // NOC Interface - GPU内部通信
    rvgpu_internal_noc_if.device noc_if,
    
    // Requester Interface Array - TPC、Block Scheduler、Raster等
    interface_l15cache.cache requester_if[L15CACHE_NUM_REQUESTERS]
);

    //=============================================================================
    // Internal Interface Instances
    //=============================================================================
    
    interface_l15cache_tag controller_tag();
    interface_l15cache_data controller_data();
    interface_l15cache_controller ctrl_if();

    //=============================================================================
    // L1.5 Cache Controller Instance
    //=============================================================================
    
    rvgpu_gpc_l15cache_controller u_l15cache_controller (
        .clk(clk),
        .rst_n(rst_n),
        
        // NOC Interface
        .noc_if(noc_if),
        
        // Tag Array Interface
        .tag_if(controller_tag.ctrl_port),
        
        // Data Array Interface
        .data_if(controller_data.ctrl_port),
        
        // Controller Interface
        .ctrl_if(ctrl_if.ctrl_port)
    );

    //=============================================================================
    // L1.5 Cache Request Buffer Instance
    //=============================================================================
    
    rvgpu_gpc_l15cache_request_buffer u_l15cache_request_buffer (
        .clk(clk),
        .rst_n(rst_n),
        
        // Multiple Requester Interfaces
        .requester_if(requester_if),
        
        // Controller Interface
        .ctrl_if(ctrl_if.buffer_port)
    );

    //=============================================================================
    // L1.5 Cache Tag Array Instance
    //=============================================================================
    
    rvgpu_gpc_l15cache_tag_array u_l15cache_tag_array (
        .clk(clk),
        .rst_n(rst_n),
        
        // Controller Interface
        .tag_if(controller_tag.tag_port)
    );

    //=============================================================================
    // L1.5 Cache Data Array Instance
    //=============================================================================
    
    rvgpu_gpc_l15cache_data_array u_l15cache_data_array (
        .clk(clk),
        .rst_n(rst_n),
        
        // Controller Interface
        .data_if(controller_data.data_port)
    );



endmodule : rvgpu_gpc_l15cache

`endif // RVGPU_GPC_L15_CACHE_SV
