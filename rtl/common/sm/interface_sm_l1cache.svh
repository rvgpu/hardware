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

`ifndef INTERFACE_SM_L1CACHE_SVH
`define INTERFACE_SM_L1CACHE_SVH

`include "rvgpu_typedef.svh"
`include "rvgpu_config.svh"

// L1 Cache接口
// 用于CUDA Core与L1 Cache之间的通信
interface interface_sm_l1cache #(
    parameter int WARP_COUNT = `CONFIG_SM_WARP_COUNT,
    parameter int THREAD_COUNT = `CONFIG_WARP_THREAD_NUMBER
);
    // 请求
    logic req_valid;
    logic [$clog2(WARP_COUNT)-1:0] req_warp_id;
    logic [THREAD_COUNT-1:0] req_mask;
    logic [THREAD_COUNT-1:0][31:0] req_addr;
    logic [THREAD_COUNT-1:0][31:0] req_data;
    logic [2:0] req_size;
    logic req_is_load;
    logic req_is_shared;
    logic req_ready;
    
    // 响应
    logic resp_valid;
    logic [$clog2(WARP_COUNT)-1:0] resp_warp_id;
    logic [THREAD_COUNT-1:0] resp_mask;
    logic [THREAD_COUNT-1:0][31:0] resp_data;
    logic resp_ready;
    
    // Core端口
    modport core (
        output req_valid, req_warp_id, req_mask, req_addr, req_data, req_size, req_is_load, req_is_shared,
        input  req_ready,
        input  resp_valid, resp_warp_id, resp_mask, resp_data,
        output resp_ready
    );
    
    // Cache端口
    modport cache (
        input  req_valid, req_warp_id, req_mask, req_addr, req_data, req_size, req_is_load, req_is_shared,
        output req_ready,
        output resp_valid, resp_warp_id, resp_mask, resp_data,
        input  resp_ready
    );
endinterface

`endif // INTERFACE_SM_L1CACHE_SVH