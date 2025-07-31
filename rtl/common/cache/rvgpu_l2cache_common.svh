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

`ifndef RVGPU_L2CACHE_COMMON_SVH
`define RVGPU_L2CACHE_COMMON_SVH

`include "rvgpu_config.svh"
`include "rvgpu_internal_noc_pkg.svh"

`ifndef RVGPU_INTERNAL_NOC_PKG_IMPORTED
`define RVGPU_INTERNAL_NOC_PKG_IMPORTED
import rvgpu_internal_noc_pkg::*;
`endif // RVGPU_INTERNAL_NOC_PKG_IMPORTED

//=============================================================================
// L2 Cache Configuration Parameters
//=============================================================================

// AXI地址和数据位宽
localparam int L2CACHE_AXI_ADDR_WIDTH       = `RVGPU_CONST_L2CACHE_AXI_ADDR_WIDTH;
localparam int L2CACHE_AXI_DATA_WIDTH       = `RVGPU_CONST_L2CACHE_AXI_DATA_WIDTH;

// 缓存配置参数
localparam int L2CACHE_SLICE_NUMBER         = `RVGPU_CONST_L2CACHE_SLICE_NUMBER;

// 缓存大小的计算
localparam int L2CACHE_LINE_WIDTH           = `RVGPU_CONST_L2CACHE_LINE_WIDTH;
localparam int L2CACHE_LINE_WIDTH_BYTES     = L2CACHE_LINE_WIDTH / 8;
localparam int L2CACHE_SETS                 = `RVGPU_CONST_L2CACHE_SETS;
localparam int L2CACHE_WAYS                 = `RVGPU_CONST_L2CACHE_WAYS;
localparam int L2CACHE_INDEX_BITS           = `RVGPU_CONST_L2CACHE_INDEX_BITS;
localparam int L2CACHE_OFFSET_BITS          = `RVGPU_CONST_L2CACHE_OFFSET_BITS;
localparam int L2CACHE_TAG_BITS             = `RVGPU_CONST_L2CACHE_TAG_BITS;

localparam int L2CACHE_LRU_BITS             = `RVGPU_CONST_L2CACHE_LRU_BITS;

localparam int L2CACHE_SIZE_BYTES           = `RVGPU_CONST_L2CACHE_SIZE;
localparam int L2CACHE_SIZE_KB              = `RVGPU_CONST_L2CACHE_SIZE / 1024;

// NOC接口相关参数
localparam int L2CACHE_NOC_DATA_WIDTH       = `RVGPU_CONST_NOC_DATA_WIDTH;
localparam int L2CACHE_NOC_HEADER_WIDTH     = `RVGPU_CONST_NOC_HEADER_WIDTH;

//=============================================================================
// L2 Cache Data Structures
//=============================================================================

typedef enum logic [1:0] {
    L2CACHE_RESP_OKAY   = 2'b00,
    L2CACHE_RESP_SLVERR = 2'b10,
    L2CACHE_RESP_DECERR = 2'b11
} l2cache_resp_status_t;

// 缓存地址结构定义
typedef struct packed {
    logic [`RVGPU_CONST_L2CACHE_TAG_BITS-1:0]       tag;
    logic [`RVGPU_CONST_L2CACHE_INDEX_BITS-1:0]     index;
    logic [`RVGPU_CONST_L2CACHE_OFFSET_BITS-1:0]    offset;
} cache_addr_t;

// Tag条目结构
typedef struct packed {
    logic [7:0][31:0] tag;           // 每个way的地址标签（最多8路）
    logic [7:0] valid;                // 每个way的有效位
    logic [7:0] dirty;                // 每个way的脏位
    logic [7:0][1:0] mesi_state;     // 每个way的MESI状态
    logic [7:0] lru;                  // LRU计数器（8位对应8路）
} l2cache_tag_entry_t;

// 缓存行数据结构
typedef struct packed {
    logic [`RVGPU_CONST_L2CACHE_LINE_WIDTH-1:0]     data; // 512位缓存行数据
    logic [`RVGPU_CONST_L2CACHE_LINE_STRB-1:0]      strb; // 64字节使能位
} l2cache_line_t;

// 缓存访问请求结构
typedef struct packed {
    logic [63:0] addr;                // 访问地址
    logic [7:0]  size;                // 访问大小
    logic        read;                // 读操作
    logic        write;               // 写操作
    logic [7:0]  trans_id;            // 事务ID
    logic [7:0]  src_node;            // 源节点ID
    logic [1:0]  src_local;           // 源本地地址
    logic [255:0] data;               // 写数据
    logic [31:0] strb;                // 写使能
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

//=============================================================================
// MESI状态定义
//=============================================================================

typedef enum logic [1:0] {
    CACHE_MESI_INVALID   = 2'b00,  //无效状态
    CACHE_MESI_EXCLUSIVE = 2'b01,  //独占状态
    CACHE_MESI_SHARED    = 2'b10,  //共享状态
    CACHE_MESI_MODIFIED  = 2'b11   //修改状态
} cache_mesi_state_t;

//=============================================================================
// 缓存操作类型定义
//=============================================================================

typedef enum logic [3:0] {
    CACHE_OP_READ      = 4'h0,        // 读操作
    CACHE_OP_WRITE     = 4'h1,        // 写操作
    CACHE_OP_INVALIDATE = 4'h2,       // 无效化操作
    CACHE_OP_FLUSH     = 4'h3,        // 刷新操作
    CACHE_OP_PREFETCH  = 4'h4,        // 预取操作
    CACHE_OP_EVICT     = 4'h5,        // 驱逐操作
    CACHE_OP_SYNC      = 4'h6,        // 同步操作
    CACHE_OP_DEBUG     = 4'h7         // 调试操作
} cache_op_type_t;

//=============================================================================
// 地址转换函数
//=============================================================================

// 缓存地址转换为64位地址
function automatic logic [63:0] cache_addr_to_addr64(cache_addr_t addr);
    return {addr.tag, addr.index, addr.offset};
endfunction

// 64位地址转换为缓存地址
function automatic cache_addr_t addr64_to_cache_addr(logic [63:0] addr64);
    localparam int OFFSET_LO = 0;
    localparam int OFFSET_HI = `RVGPU_CONST_L2CACHE_OFFSET_BITS - 1;
    localparam int INDEX_LO = OFFSET_HI + 1;
    localparam int INDEX_HI = INDEX_LO + `RVGPU_CONST_L2CACHE_INDEX_BITS - 1;
    localparam int TAG_LO = INDEX_HI + 1;
    localparam int TAG_HI = TAG_LO + `RVGPU_CONST_L2CACHE_TAG_BITS - 1;

    cache_addr_t addr;
    addr.tag = addr64[TAG_HI:TAG_LO];
    addr.index = addr64[INDEX_HI:INDEX_LO];
    addr.offset = addr64[OFFSET_HI:OFFSET_LO];
    return addr;
endfunction

// 获取对齐的内存请求地址
function automatic logic [63:0] request_mem_addr_aligned(cache_addr_t addr);
    logic [`RVGPU_CONST_L2CACHE_OFFSET_BITS-1:0] zero_offset = 0;
    return {addr.tag, addr.index, zero_offset};
endfunction

//=============================================================================
// LRU管理函数
//=============================================================================

// 更新LRU计数器
function automatic logic [7:0] update_lru(
    input logic [7:0] current_lru,
    input logic [2:0] accessed_way
);
    logic [7:0] new_lru;
    new_lru = current_lru;
    new_lru[accessed_way] = 1'b0;  // 访问的way设为最新
    // 其他way的LRU位递增
    for (int i = 0; i < 8; i++) begin
        if (i != accessed_way && current_lru[i]) begin
            new_lru[i] = 1'b1;
        end
    end
    return new_lru;
endfunction

// 选择LRU way进行替换
function automatic logic [2:0] select_lru_way(
    input logic [7:0] lru_bits
);
    logic [2:0] selected_way;
    selected_way = 3'b000;
    for (int i = 0; i < 8; i++) begin
        if (lru_bits[i]) begin
            selected_way = i[2:0];
        end
    end
    return selected_way;
endfunction

//=============================================================================
// MESI状态管理函数
//=============================================================================

// 检查是否为有效状态
function automatic logic is_valid_state(
    input cache_mesi_state_t state
);
    return (state != CACHE_MESI_INVALID);
endfunction

// 检查是否为独占状态
function automatic logic is_exclusive_state(
    input cache_mesi_state_t state
);
    return (state == CACHE_MESI_EXCLUSIVE || state == CACHE_MESI_MODIFIED);
endfunction

// 检查是否为修改状态
function automatic logic is_modified_state(
    input cache_mesi_state_t state
);
    return (state == CACHE_MESI_MODIFIED);
endfunction

// 状态转换函数
function automatic cache_mesi_state_t next_mesi_state(
    input cache_mesi_state_t current_state,
    input logic is_read,
    input logic is_write,
    input logic is_remote_access
);
    case (current_state)
        CACHE_MESI_INVALID: begin
            if (is_read && !is_remote_access)
                return CACHE_MESI_EXCLUSIVE;
            else if (is_read && is_remote_access)
                return CACHE_MESI_SHARED;
            else
                return CACHE_MESI_INVALID;
        end
        CACHE_MESI_SHARED: begin
            if (is_write)
                return CACHE_MESI_MODIFIED;
            else
                return CACHE_MESI_SHARED;
        end
        CACHE_MESI_EXCLUSIVE: begin
            if (is_write)
                return CACHE_MESI_MODIFIED;
            else if (is_remote_access)
                return CACHE_MESI_SHARED;
            else
                return CACHE_MESI_EXCLUSIVE;
        end
        CACHE_MESI_MODIFIED: begin
            if (is_remote_access)
                return CACHE_MESI_SHARED;
            else
                return CACHE_MESI_MODIFIED;
        end
        default: return CACHE_MESI_INVALID;
    endcase
endfunction

//=============================================================================
// 调试和监控函数
//=============================================================================

// 获取MESI状态名称
function automatic string get_mesi_name(
    input cache_mesi_state_t state
);
    case (state)
        CACHE_MESI_INVALID: return "INVALID";
        CACHE_MESI_SHARED: return "SHARED";
        CACHE_MESI_EXCLUSIVE: return "EXCLUSIVE";
        CACHE_MESI_MODIFIED: return "MODIFIED";
        default: return "UNKNOWN";
    endcase
endfunction

// 获取操作类型名称
function automatic string get_op_name(
    input cache_op_type_t op
);
    case (op)
        CACHE_OP_READ: return "READ";
        CACHE_OP_WRITE: return "WRITE";
        CACHE_OP_INVALIDATE: return "INVALIDATE";
        CACHE_OP_FLUSH: return "FLUSH";
        CACHE_OP_PREFETCH: return "PREFETCH";
        CACHE_OP_EVICT: return "EVICT";
        CACHE_OP_SYNC: return "SYNC";
        CACHE_OP_DEBUG: return "DEBUG";
        default: return "UNKNOWN";
    endcase
endfunction

`endif // RVGPU_L2CACHE_COMMON_SVH 