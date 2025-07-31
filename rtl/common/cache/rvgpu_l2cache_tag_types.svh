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

`ifndef RVGPU_L2CACHE_TAG_TYPES_SVH
`define RVGPU_L2CACHE_TAG_TYPES_SVH

`include "rvgpu_l2cache_common.svh"

//=============================================================================
// 单个Way的Tag条目结构
//=============================================================================

typedef struct packed {
    logic [L2CACHE_TAG_BITS-1:0] tag;     // 地址标签
    logic valid;                                         // 有效位
    logic dirty;                                         // 脏位
    cache_mesi_state_t mesi_state;                       // MESI状态
} l2cache_way_tag_t;

//=============================================================================
// 完整的Tag条目结构（ways number * way数组 + LRU信息）
//=============================================================================

typedef struct packed {
    l2cache_way_tag_t [L2CACHE_WAYS-1:0] ways;         // 8路Tag条目数组
    logic [L2CACHE_WAYS-1:0] lru;                      // LRU位（每个way对应一位）
} l2cache_tag_entry_t;

localparam int L2CACHE_TAG_DATA_WIDTH = $bits(l2cache_tag_entry_t);
    
//=============================================================================
// 辅助函数
//=============================================================================
    
// Tag条目转换为原始数据
function automatic logic [L2CACHE_TAG_DATA_WIDTH-1:0] l2cache_tag_entry_to_raw(
    input l2cache_tag_entry_t entry
);
    logic [L2CACHE_TAG_DATA_WIDTH-1:0] raw;
    logic [31:0] offset = 0;
        
    // 序列化Tag条目 - 按way顺序序列化
    for (int i = 0; i < L2CACHE_WAYS; i++) begin
        raw[offset +: L2CACHE_TAG_BITS] = entry.ways[i].tag;
        offset += L2CACHE_TAG_BITS;
    end
        
    for (int i = 0; i < L2CACHE_WAYS; i++) begin
        raw[offset +: 1] = entry.ways[i].valid;
        offset += 1;
    end
        
    for (int i = 0; i < L2CACHE_WAYS; i++) begin
        raw[offset +: 1] = entry.ways[i].dirty;
        offset += 1;
    end
        
    for (int i = 0; i < L2CACHE_WAYS; i++) begin
        raw[offset +: 2] = entry.ways[i].mesi_state;
        offset += 2;
    end
        
    // 序列化LRU位
    raw[offset +: L2CACHE_WAYS] = entry.lru;
    offset += L2CACHE_WAYS;
        
    return raw;
endfunction
    
// 原始数据转换为Tag条目
function automatic l2cache_tag_entry_t raw_to_l2cache_tag_entry(
    input logic [L2CACHE_TAG_DATA_WIDTH-1:0] raw
);
    l2cache_tag_entry_t entry;
    logic [31:0] offset = 0;
        
    // 反序列化Tag条目 - 按way顺序反序列化
    for (int i = 0; i < L2CACHE_WAYS; i++) begin
        entry.ways[i].tag = raw[offset +: L2CACHE_TAG_BITS];
        offset += L2CACHE_TAG_BITS;
    end
        
    for (int i = 0; i < L2CACHE_WAYS; i++) begin
        entry.ways[i].valid = raw[offset +: 1];
        offset += 1;
    end
        
    for (int i = 0; i < L2CACHE_WAYS; i++) begin
        entry.ways[i].dirty = raw[offset +: 1];
        offset += 1;
    end
        
    for (int i = 0; i < L2CACHE_WAYS; i++) begin
        entry.ways[i].mesi_state = raw[offset +: 2];
        offset += 2;
    end
        
    // 反序列化LRU位
    entry.lru = raw[offset +: L2CACHE_WAYS];
    offset += L2CACHE_WAYS;
        
    return entry;
endfunction

`endif // RVGPU_L2CACHE_TAG_TYPES_SVH