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
    gpc_l15_cache_if.cache requester_if[L15CACHE_NUM_REQUESTERS]
);

    //=============================================================================
    // Internal Interface Instances
    //=============================================================================
    
    // 控制器与子模块的接口
    l15cache_tag_if controller_tag();
    l15cache_data_if controller_data();
    
    // 控制器请求接口
    logic                    ctrl_req_valid;
    l15cache_request_t       ctrl_req_data;
    logic                    ctrl_req_ready;
    logic                    ctrl_resp_valid;
    l15cache_response_t      ctrl_resp_data;
    logic                    ctrl_resp_ready;

    //=============================================================================
    // L1.5 Cache Controller Instance
    //=============================================================================
    
    rvgpu_gpc_l15cache_controller u_l15cache_controller (
        .clk(clk),
        .rst_n(rst_n),
        
        // NOC Interface
        .noc_if(noc_if),
        
        // Tag Array Interface
        .tag_if(controller_tag.controller),
        
        // Data Array Interface
        .data_if(controller_data.controller),
        
        // Single Request Interface
        .req_valid(ctrl_req_valid),
        .req_data(ctrl_req_data),
        .req_ready(ctrl_req_ready),
        .resp_valid(ctrl_resp_valid),
        .resp_data(ctrl_resp_data),
        .resp_ready(ctrl_resp_ready)
    );

    //=============================================================================
    // L1.5 Cache Request Buffer Instance
    //=============================================================================
    
    rvgpu_gpc_l15cache_request_buffer u_l15cache_request_buffer (
        .clk(clk),
        .rst_n(rst_n),
        
        // Multiple Requester Interfaces
        .requester_if(requester_if),
        
        // Single Controller Interface
        .ctrl_req_valid(ctrl_req_valid),
        .ctrl_req_data(ctrl_req_data),
        .ctrl_req_ready(ctrl_req_ready),
        .ctrl_resp_valid(ctrl_resp_valid),
        .ctrl_resp_data(ctrl_resp_data),
        .ctrl_resp_ready(ctrl_resp_ready)
    );

    //=============================================================================
    // L1.5 Cache Tag Array Instance
    //=============================================================================
    
    rvgpu_gpc_l15cache_tag_array u_l15cache_tag_array (
        .clk(clk),
        .rst_n(rst_n),
        
        // Controller Interface
        .tag_if(controller_tag.tag_array)
    );

    //=============================================================================
    // L1.5 Cache Data Array Instance
    //=============================================================================
    
    rvgpu_gpc_l15cache_data_array u_l15cache_data_array (
        .clk(clk),
        .rst_n(rst_n),
        
        // Controller Interface
        .data_if(controller_data.data_array)
    );



endmodule : rvgpu_gpc_l15cache

`endif // RVGPU_GPC_L15_CACHE_SV
