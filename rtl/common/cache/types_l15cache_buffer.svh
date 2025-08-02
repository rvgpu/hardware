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

`ifndef RVGPU_TYPES_L15CACHE_BUFFER_SVH
`define RVGPU_TYPES_L15CACHE_BUFFER_SVH


`include "types_cache_op.svh"
`include "const_l15cache.svh"
`include "types_l15cache.svh"

//=============================================================================
// L1.5 Cache Request Buffer Types
//=============================================================================

// 请求缓冲区仲裁器类型
typedef struct packed {
    logic [L15CACHE_NUM_REQUESTERS-1:0] req_valid;    // 请求有效信号
    logic [L15CACHE_NUM_REQUESTERS-1:0] req_grant;    // 请求授权信号
    logic [$clog2(L15CACHE_NUM_REQUESTERS)-1:0] arbiter_ptr; // 仲裁器指针
    logic [$clog2(L15CACHE_NUM_REQUESTERS)-1:0] resp_requester; // 响应请求者ID
} l15cache_arbiter_t;

// 请求格式化结果类型
typedef struct packed {
    l15cache_request_t formatted_req;  // 格式化后的请求
    logic              req_valid;      // 请求有效
    logic [2:0]        requester_id;   // 请求者ID
} l15cache_request_format_t;

`endif // RVGPU_TYPES_L15CACHE_BUFFER_SVH 