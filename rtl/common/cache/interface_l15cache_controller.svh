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

`ifndef RVGPU_INTERFACE_L15CACHE_CONTROLLER_SVH
`define RVGPU_INTERFACE_L15CACHE_CONTROLLER_SVH

`include "rvgpu_typedef.svh"
`include "types_l15cache.svh"
`include "types_l15cache_controller.svh"
`include "types_cache_op.svh"
`include "types_cache_resp.svh"
`include "const_l15cache.svh"

// L1.5缓存控制器接口
interface interface_l15cache_controller;
    // 控制器请求接口
    logic                    ctrl_req_valid;
    l15cache_request_t       ctrl_req_data;
    logic                    ctrl_req_ready;
    
    // 控制器响应接口
    logic                    ctrl_resp_valid;
    l15cache_response_t      ctrl_resp_data;
    logic                    ctrl_resp_ready;
    
    // 控制器端口（收请求，发响应）
    modport ctrl_port (
        input  ctrl_req_valid, ctrl_req_data,
        output ctrl_req_ready,
        output ctrl_resp_valid, ctrl_resp_data,
        input  ctrl_resp_ready
    );
    
    // 缓冲区端口（发请求，收响应）
    modport buffer_port (
        output ctrl_req_valid, ctrl_req_data,
        input  ctrl_req_ready,
        input  ctrl_resp_valid, ctrl_resp_data,
        output ctrl_resp_ready
    );
    
endinterface : interface_l15cache_controller

`endif // RVGPU_INTERFACE_L15CACHE_CONTROLLER_SVH 