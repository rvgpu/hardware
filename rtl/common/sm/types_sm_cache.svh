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

`ifndef TYPES_SM_CACHE_SVH
`define TYPES_SM_CACHE_SVH

`include "rvgpu_typedef.svh"

// 缓存状态
typedef enum logic [1:0] {
    e_CACHE_INVALID,  // 无效
    e_CACHE_SHARED,   // 共享（只读）
    e_CACHE_MODIFIED, // 已修改（独占）
    e_CACHE_EXCLUSIVE // 独占（未修改）
} e_cache_state_t;

// 缓存操作类型
typedef enum logic [1:0] {
    e_CACHE_OP_LOAD,  // 读操作
    e_CACHE_OP_STORE, // 写操作
    e_CACHE_OP_FLUSH, // 刷新操作
    e_CACHE_OP_INVAL  // 失效操作
} e_cache_op_t;

// 缓存行
typedef struct packed {
    logic valid;                // 有效位
    e_cache_state_t state;      // 缓存状态
    logic [31:0] tag;           // 标签
    logic [31:0] data[];        // 数据（可变长度）
} t_cache_line;

// 缓存请求
typedef struct packed {
    e_cache_op_t op;            // 操作类型
    logic [63:0] addr;          // 地址
    logic [31:0] data;          // 数据（写操作）
    logic [2:0] size;           // 访问大小
    logic [31:0] warp_id;       // Warp ID
    logic [31:0] thread_mask;   // 线程掩码
} t_cache_request;

// 缓存响应
typedef struct packed {
    logic valid;                // 响应有效
    logic hit;                  // 命中标志
    logic [31:0] data;          // 数据
    logic [31:0] warp_id;       // Warp ID
    logic [31:0] thread_mask;   // 线程掩码
} t_cache_response;

// 类型相关函数

// 检查缓存状态是否有效
function automatic logic tf_is_cache_valid(e_cache_state_t state);
    return (state != e_CACHE_INVALID);
endfunction

// 检查缓存状态是否可读
function automatic logic tf_is_cache_readable(e_cache_state_t state);
    return (state != e_CACHE_INVALID);
endfunction

// 检查缓存状态是否可写
function automatic logic tf_is_cache_writable(e_cache_state_t state);
    return (state == e_CACHE_MODIFIED || state == e_CACHE_EXCLUSIVE);
endfunction

// 从地址中提取索引和标签
function automatic void tf_extract_addr_info(
    input logic [63:0] addr,
    input int line_size_bytes,
    input int num_sets,
    output logic [$clog2(num_sets)-1:0] index,
    output logic [63:0] tag,
    output logic [$clog2(line_size_bytes)-1:0] offset
);
    int set_index_width = $clog2(num_sets);
    int offset_width = $clog2(line_size_bytes);
    
    offset = addr[offset_width-1:0];
    index = addr[offset_width+set_index_width-1:offset_width];
    tag = addr[63:offset_width+set_index_width];
endfunction

`endif // TYPES_SM_CACHE_SVH
