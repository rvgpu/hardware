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

`ifndef RVGPU_INTERFACE_L15CACHE_SVH
`define RVGPU_INTERFACE_L15CACHE_SVH

`include "rvgpu_typedef.svh"
`include "types_l15cache.svh"
`include "types_cache_op.svh"
`include "types_cache_resp.svh"
`include "const_l15cache.svh"

// L1.5缓存接口
interface interface_l15cache;
    // 请求通道
    logic                req_valid;      // 请求有效
    logic                req_is_read;    // 1=读请求, 0=写请求
    logic [3:0]          req_size;       // 访问大小
    cache_op_type_t      req_type;       // 访问类型
    logic [63:0]         req_paddr;      // 物理地址
    logic [L15CACHE_LINE_WIDTH-1:0] req_data;  // 写数据
    logic [L15CACHE_LINE_WIDTH_BYTES-1:0] req_mask; // 写掩码
    logic [31:0]         req_id;         // 请求ID
    logic                req_ready;      // 缓存准备好接收请求
    
    // 响应通道
    logic                resp_valid;     // 响应有效
    logic [L15CACHE_LINE_WIDTH-1:0] resp_data; // 读数据
    cache_resp_status_t  resp_status;    // 响应状态
    logic [31:0]         resp_id;        // 响应ID
    logic                resp_ready;     // 请求者准备好接收响应
    
    // 控制信号
    logic                flush;          // 刷新请求
    
    // 状态信号
    logic [7:0]          pending_count;  // 未完成请求数量
    
    // requester视角（发请求，收响应）
    modport requester (
        output req_valid, req_is_read, req_size, req_type, req_paddr, req_data, req_mask, req_id,
        input  req_ready,
        input  resp_valid, resp_data, resp_status, resp_id,
        output resp_ready,
        output flush,
        input  pending_count
    );
    
    // cache视角（收请求，发响应）
    modport cache (
        input  req_valid, req_is_read, req_size, req_type, req_paddr, req_data, req_mask, req_id,
        output req_ready,
        output resp_valid, resp_data, resp_status, resp_id,
        input  resp_ready,
        input  flush,
        output pending_count
    );
    
endinterface : interface_l15cache

`endif // RVGPU_INTERFACE_L15CACHE_SVH 