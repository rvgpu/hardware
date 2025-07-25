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

`ifndef GPC_L15_NOC_IF_SVH
`define GPC_L15_NOC_IF_SVH

`include "rvgpu_typedef.svh"

// NOC适配器和L1.5缓存之间的接口
interface gpc_l15_noc_if;
    // NOC适配器 -> L1.5缓存 请求信号
    logic                req_valid;      // 请求有效
    logic                req_is_read;    // 1=读请求, 0=写请求
    logic [3:0]          req_size;       // 访问大小
    logic [3:0]          req_type;       // 访问类型
    logic [63:0]         req_paddr;      // 物理地址
    logic [1023:0]       req_data;       // 写数据
    logic [127:0]        req_mask;       // 写掩码
    logic [31:0]         req_id;         // 请求ID
    logic                req_ready;      // L1.5缓存准备好接收请求

    // L1.5缓存 -> NOC适配器 响应信号
    logic                resp_valid;     // 响应有效
    logic [1023:0]       resp_data;      // 读数据
    logic                resp_error;     // 错误标志
    logic [31:0]         resp_id;        // 响应ID
    logic                resp_ready;     // NOC适配器准备好接收响应

    // 控制信号
    logic                flush;          // 刷新请求
    logic [7:0]          pending_count;  // 未完成请求数

    // NOC适配器视角（发请求，收响应）
    modport noc_adapter (
        output req_valid, req_is_read, req_size, req_type, req_paddr, req_data, req_mask, req_id,
        input  req_ready,
        input  resp_valid, resp_data, resp_error, resp_id,
        output resp_ready,
        output flush,
        input  pending_count
    );

    // L1.5 Cache视角（收请求，发响应）
    modport cache (
        input  req_valid, req_is_read, req_size, req_type, req_paddr, req_data, req_mask, req_id,
        output req_ready,
        output resp_valid, resp_data, resp_error, resp_id,
        input  resp_ready,
        input  flush,
        output pending_count
    );
    
endinterface : gpc_l15_noc_if

`endif // GPC_L15_NOC_IF_SVH 