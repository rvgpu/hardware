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

`ifndef RVGPU_TYPES_L15CACHE_SVH
`define RVGPU_TYPES_L15CACHE_SVH



`include "types_cache_op.svh"
`include "types_cache_resp.svh"
`include "const_l15cache.svh"

//=============================================================================
// L1.5 Cache Response Status Types
//=============================================================================

// 使用通用的缓存响应状态类型
typedef cache_resp_status_t l15cache_resp_status_t;

//=============================================================================
// L1.5 Cache Data Structures
//=============================================================================

// 缓存行数据结构
typedef struct packed {
    logic [L15CACHE_LINE_WIDTH-1:0]     data; // 512位缓存行数据
    logic [L15CACHE_LINE_WIDTH_BYTES-1:0] strb; // 64字节使能位
} l15cache_line_t;

//=============================================================================
// L1.5 Cache Request/Response Types
//=============================================================================

// 缓存请求结构
typedef struct packed {
    logic [63:0] addr;           // 64位地址
    logic [3:0]  size;           // 请求大小
    logic        read;           // 读操作标志
    logic        write;          // 写操作标志
    logic [7:0]  trans_id;       // 事务ID
    logic [7:0]  src_node;       // 源节点
    logic [1:0]  src_local;      // 本地源ID
    logic [511:0] data;          // 写数据
    logic [63:0] strb;           // 写掩码
} l15cache_request_t;

// 缓存响应结构
typedef struct packed {
    logic [511:0] data;          // 读数据
    logic [1:0]  status;         // 响应状态
    logic [7:0]  trans_id;       // 事务ID
    logic [7:0]  dest_node;      // 目标节点
    logic        hit;            // 命中标志
    logic        dirty;          // 脏标志
} l15cache_response_t;

// 缓存地址解析结构
typedef struct packed {
    logic [L15CACHE_TAG_BITS-1:0] tag;    // Tag位
    logic [L15CACHE_INDEX_BITS-1:0] index; // 索引位
    logic [L15CACHE_OFFSET_BITS-1:0] offset; // 偏移位
} l15cache_addr_t;

//=============================================================================
// L1.5 Cache Tag Types
//=============================================================================

// 单个way的tag结构
typedef struct packed {
    logic [L15CACHE_TAG_BITS-1:0]    tag;      // Tag位
    logic                                   valid;    // 有效位
    logic                                   dirty;    // 脏位
    cache_mesi_state_t                      mesi_state; // MESI状态
} l15cache_way_tag_t;

// 完整的tag条目结构（包含所有way）
typedef struct {
    l15cache_way_tag_t ways [L15CACHE_WAYS-1:0]; // 8个way的tag
    logic [L15CACHE_WAYS-1:0] lru;       // LRU位
} l15cache_tag_entry_t;

//=============================================================================
// Address Structure Related Functions
//=============================================================================

// 将64位地址转换为缓存地址结构
function automatic l15cache_addr_t addr64_to_l15cache_addr(
    input logic [63:0] addr64
);
    l15cache_addr_t addr;
    addr.tag = addr64[63:L15CACHE_INDEX_BITS + L15CACHE_OFFSET_BITS];
    addr.index = addr64[L15CACHE_INDEX_BITS + L15CACHE_OFFSET_BITS - 1:L15CACHE_OFFSET_BITS];
    addr.offset = addr64[L15CACHE_OFFSET_BITS - 1:0];
    return addr;
endfunction

// 将缓存地址结构转换为64位地址
function automatic logic [63:0] l15cache_addr_to_addr64(
    input l15cache_addr_t addr
);
    logic [63:0] addr64;
    addr64[63:L15CACHE_INDEX_BITS + L15CACHE_OFFSET_BITS] = addr.tag;
    addr64[L15CACHE_INDEX_BITS + L15CACHE_OFFSET_BITS - 1:L15CACHE_OFFSET_BITS] = addr.index;
    addr64[L15CACHE_OFFSET_BITS - 1:0] = addr.offset;
    return addr64;
endfunction

//=============================================================================
// Tag Entry Serialization Functions
//=============================================================================

// 将tag条目转换为原始数据
function automatic logic [511:0] l15cache_tag_entry_to_raw(
    input l15cache_tag_entry_t tag_entry
);
    logic [511:0] raw_data;
    int offset;
    
    raw_data = '0;
    offset = 0;
    
    // 序列化每个way的tag
    for (int i = 0; i < L15CACHE_WAYS; i++) begin
        raw_data[offset +: L15CACHE_TAG_BITS] = tag_entry.ways[i].tag;
        offset += L15CACHE_TAG_BITS;
        
        raw_data[offset] = tag_entry.ways[i].valid;
        offset += 1;
        
        raw_data[offset] = tag_entry.ways[i].dirty;
        offset += 1;
        
        raw_data[offset +: 2] = tag_entry.ways[i].mesi_state;
        offset += 2;
    end
    
    // 序列化LRU位
    raw_data[offset +: L15CACHE_LRU_BITS] = tag_entry.lru;
    
    return raw_data;
endfunction

// 将原始数据转换为tag条目
function automatic l15cache_tag_entry_t raw_to_l15cache_tag_entry(
    input logic [511:0] raw_data
);
    l15cache_tag_entry_t tag_entry;
    int offset;
    
    offset = 0;
    
    // 反序列化每个way的tag
    for (int i = 0; i < L15CACHE_WAYS; i++) begin
        tag_entry.ways[i].tag = raw_data[offset +: L15CACHE_TAG_BITS];
        offset += L15CACHE_TAG_BITS;
        
        tag_entry.ways[i].valid = raw_data[offset];
        offset += 1;
        
        tag_entry.ways[i].dirty = raw_data[offset];
        offset += 1;
        
        tag_entry.ways[i].mesi_state = cache_mesi_state_t'(raw_data[offset +: 2]);
        offset += 2;
    end
    
    // 反序列化LRU位
    tag_entry.lru = raw_data[offset +: L15CACHE_LRU_BITS];
    
    return tag_entry;
endfunction

`endif // RVGPU_TYPES_L15CACHE_SVH 