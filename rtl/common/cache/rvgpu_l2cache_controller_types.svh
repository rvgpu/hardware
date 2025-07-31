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

`ifndef RVGPU_L2CACHE_CONTROLLER_TYPES_SVH
`define RVGPU_L2CACHE_CONTROLLER_TYPES_SVH

`include "rvgpu_l2cache_common.svh"

// 缓存访问请求结构
typedef struct packed {
    logic [63:0]    addr;             // 访问地址
    logic [7:0]     size;             // 访问大小
    logic           read;             // 读操作
    logic           write;            // 写操作
    logic [7:0]     trans_id;         // 事务ID
    logic [7:0]     src_node;         // 源节点ID
    logic [1:0]     src_local;        // 源本地地址
    logic [255:0]   data;             // 写数据
    logic [31:0]    strb;             // 写使能
} l2cache_request_t;

// 缓存访问响应结构
typedef struct packed {
    logic [255:0] data;               // 读数据
    logic [1:0]   status;             // 响应状态
    logic [7:0]   trans_id;           // 事务ID
    logic [7:0]   dest_node;          // 目标节点ID
    logic         hit;                // 缓存命中
    logic         dirty;              // 脏位
} l2cache_response_t; 

// 缓存地址结构定义: {tag, index, offset} 
// offset：表示cache line内的offset，位宽为 $log2(CACHE_LINE)。比如cacheline为64字节，offset就是0-63，位宽为6
// index：表示cache set的index，位宽为 $log2(CACHE_SET)。比如 1024个set，则index位宽为10
// tag：表示cache tag，位宽为 $log2(CACHE_TAG)。比如cache tag为32位，则tag位宽为32
typedef struct packed {
    logic [`RVGPU_CONST_L2CACHE_TAG_BITS-1:0]       tag;
    logic [`RVGPU_CONST_L2CACHE_INDEX_BITS-1:0]     index;
    logic [`RVGPU_CONST_L2CACHE_OFFSET_BITS-1:0]    offset;
} l2cache_addr_t;

// 缓存地址转换为64位地址
function automatic logic [63:0] l2cache_addr_to_addr64(l2cache_addr_t addr);
    return {addr.tag, addr.index, addr.offset};
endfunction

// 64位地址转换为缓存地址
function automatic l2cache_addr_t addr64_to_l2cache_addr(logic [63:0] addr64);
    localparam int OFFSET_LO = 0;
    localparam int OFFSET_HI = `RVGPU_CONST_L2CACHE_OFFSET_BITS - 1;
    localparam int INDEX_LO = OFFSET_HI + 1;
    localparam int INDEX_HI = INDEX_LO + `RVGPU_CONST_L2CACHE_INDEX_BITS - 1;
    localparam int TAG_LO = INDEX_HI + 1;
    localparam int TAG_HI = TAG_LO + `RVGPU_CONST_L2CACHE_TAG_BITS - 1;

    l2cache_addr_t addr;
    addr.tag = addr64[TAG_HI:TAG_LO];
    addr.index = addr64[INDEX_HI:INDEX_LO];
    addr.offset = addr64[OFFSET_HI:OFFSET_LO];
    return addr;
endfunction

// 获取对齐的内存请求地址
function automatic logic [63:0] request_mem_addr_aligned(l2cache_addr_t addr);
    logic [`RVGPU_CONST_L2CACHE_OFFSET_BITS-1:0] zero_offset = 0;
    return {addr.tag, addr.index, zero_offset};
endfunction

`endif // RVGPU_L2CACHE_CONTROLLER_TYPES_SVH