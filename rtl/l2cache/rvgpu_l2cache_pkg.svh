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

`ifndef RVGPU_L2CACHE_PKG_SV
`define RVGPU_L2CACHE_PKG_SV

`include "rvgpu_config.svh"
`include "rvgpu_internal_noc_pkg.svh"

`ifndef RVGPU_INTERNAL_NOC_PKG_IMPORTED
`define RVGPU_INTERNAL_NOC_PKG_IMPORTED
import rvgpu_internal_noc_pkg::*;
`endif // RVGPU_INTERNAL_NOC_PKG_IMPORTED

package rvgpu_l2cache_pkg;
    //=============================================================================
    // L2 Cache Configuration Parameters
    //=============================================================================
    
    // 基本配置参数
    typedef struct packed {
        int unsigned cache_size;           // 缓存总容量(KB)
        int unsigned slice_number;         // slice数量
        int unsigned line_size;            // 缓存行大小(字节)
        int unsigned ways;                 // 组相联度
        int unsigned sets;                 // 组数
        int unsigned tag_bits;             // Tag位宽
        int unsigned index_bits;           // 索引位宽
        int unsigned offset_bits;          // 偏移位宽
        int unsigned lru_bits;             // LRU位宽
        int unsigned axi_data_width;       // AXI数据位宽
        int unsigned axi_addr_width;       // AXI地址位宽
        int unsigned noc_data_width;       // NOC数据位宽
        int unsigned noc_header_width;     // NOC header位宽
        logic        debug_enable;         // 调试功能使能
    } l2cache_config_t;
    
    // 默认配置参数
    localparam l2cache_config_t DEFAULT_L2CACHE_CONFIG = '{
        cache_size: `RVGPU_CONST_L2CACHE_SIZE,
        slice_number: `RVGPU_CONST_L2CACHE_SLICE_NUMBER,
        line_size: `RVGPU_CONST_L2CACHE_LINE_SIZE,
        ways: `RVGPU_CONST_L2CACHE_WAYS,
        sets: `RVGPU_CONST_L2CACHE_SETS,
        tag_bits: `RVGPU_CONST_L2CACHE_TAG_BITS,
        index_bits: `RVGPU_CONST_L2CACHE_INDEX_BITS,
        offset_bits: `RVGPU_CONST_L2CACHE_OFFSET_BITS,
        lru_bits: `RVGPU_CONST_L2CACHE_LRU_BITS,
        axi_data_width: `RVGPU_CONST_L2CACHE_AXI_DATA_WIDTH,
        axi_addr_width: `RVGPU_CONST_L2CACHE_AXI_ADDR_WIDTH,
        noc_data_width: `RVGPU_CONST_NOC_DATA_WIDTH,
        noc_header_width: `RVGPU_CONST_NOC_HEADER_WIDTH,
        debug_enable: 1'b1
    };
    
    //=============================================================================
    // L2 Cache Data Structures
    //=============================================================================
    
    // Tag条目结构（使用固定大小，避免循环依赖）
    typedef struct packed {
        logic [7:0][31:0] tag;           // 每个way的地址标签（最多8路）
        logic [7:0] valid;                // 每个way的有效位
        logic [7:0] dirty;                // 每个way的脏位
        logic [7:0][1:0] mesi_state;     // 每个way的MESI状态
        logic [7:0] lru;                  // LRU计数器（8位对应8路）
    } l2cache_tag_entry_t;
    
    // 缓存行数据结构
    typedef struct packed {
        logic [511:0] data;               // 64字节缓存行数据
        logic [63:0]  strb;               // 字节使能位
    } l2cache_line_t;
    
    // 缓存访问请求结构
    typedef struct packed {
        logic [63:0] addr;                // 访问地址
        logic [7:0]  size;                // 访问大小
        logic        read;                // 读操作
        logic        write;               // 写操作
        logic [7:0]  trans_id;            // 事务ID
        logic [3:0]  src_node;            // 源节点ID
        logic [255:0] data;               // 写数据
        logic [31:0] strb;                // 写使能
    } l2cache_request_t;
    
    // 缓存访问响应结构
    typedef struct packed {
        logic [255:0] data;               // 读数据
        logic [1:0]   status;             // 响应状态
        logic [7:0]   trans_id;           // 事务ID
        logic [3:0]   dest_node;          // 目标节点ID
        logic         hit;                // 缓存命中
        logic         dirty;              // 脏位
    } l2cache_response_t;
    
    //=============================================================================
    // MESI状态定义
    //=============================================================================
    
    typedef enum logic [1:0] {
        MESI_INVALID   = 2'b00,           // 无效状态
        MESI_SHARED    = 2'b01,           // 共享状态
        MESI_EXCLUSIVE = 2'b10,           // 独占状态
        MESI_MODIFIED  = 2'b11            // 已修改状态
    } mesi_state_t;
    
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
    // 缓存状态机状态定义
    //=============================================================================
    
    typedef enum logic [3:0] {
        L2_STATE_IDLE          = 4'h0,    // 空闲状态
        L2_STATE_TAG_LOOKUP    = 4'h1,    // Tag查找
        L2_STATE_DATA_ACCESS   = 4'h2,    // 数据访问
        L2_STATE_MISS_HANDLE   = 4'h3,    // 未命中处理
        L2_STATE_MEMORY_ACCESS = 4'h4,    // 内存访问
        L2_STATE_WRITE_BACK    = 4'h5,    // 写回
        L2_STATE_EVICT         = 4'h6,    // 驱逐
        L2_STATE_SYNC          = 4'h7,    // 同步
        L2_STATE_ERROR         = 4'h8     // 错误状态
    } l2cache_state_t;
    
    //=============================================================================
    // 性能计数器结构
    //=============================================================================
    
    typedef struct packed {
        logic [31:0] hit_count;           // 命中计数
        logic [31:0] miss_count;          // 未命中计数
        logic [31:0] read_count;          // 读操作计数
        logic [31:0] write_count;         // 写操作计数
        logic [31:0] eviction_count;      // 驱逐计数
        logic [31:0] writeback_count;     // 写回计数
        logic [31:0] prefetch_count;      // 预取计数
        logic [31:0] error_count;         // 错误计数
    } l2cache_perf_counters_t;
    
    //=============================================================================
    // 地址解析函数
    //=============================================================================
    
    // 从地址中提取Tag
    function automatic logic [31:0] extract_tag(
        input logic [63:0] addr,
        input l2cache_config_t config
    );
        return addr[63:32];
    endfunction
    
    // 从地址中提取索引
    function automatic logic [9:0] extract_index(
        input logic [63:0] addr,
        input l2cache_config_t config
    );
        return addr[31:22];
    endfunction
    
    // 从地址中提取偏移
    function automatic logic [5:0] extract_offset(
        input logic [63:0] addr,
        input l2cache_config_t config
    );
        return addr[21:16];
    endfunction
    
    // 从地址中提取行内偏移
    function automatic logic [5:0] extract_line_offset(
        input logic [63:0] addr,
        input l2cache_config_t config
    );
        return addr[5:0];
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
        input mesi_state_t state
    );
        return (state != MESI_INVALID);
    endfunction
    
    // 检查是否为独占状态
    function automatic logic is_exclusive_state(
        input mesi_state_t state
    );
        return (state == MESI_EXCLUSIVE || state == MESI_MODIFIED);
    endfunction
    
    // 检查是否为修改状态
    function automatic logic is_modified_state(
        input mesi_state_t state
    );
        return (state == MESI_MODIFIED);
    endfunction
    
    // 状态转换函数
    function automatic mesi_state_t next_mesi_state(
        input mesi_state_t current_state,
        input logic is_read,
        input logic is_write,
        input logic is_remote_access
    );
        case (current_state)
            MESI_INVALID: begin
                if (is_read && !is_remote_access)
                    return MESI_EXCLUSIVE;
                else if (is_read && is_remote_access)
                    return MESI_SHARED;
                else
                    return MESI_INVALID;
            end
            MESI_SHARED: begin
                if (is_write)
                    return MESI_MODIFIED;
                else
                    return MESI_SHARED;
            end
            MESI_EXCLUSIVE: begin
                if (is_write)
                    return MESI_MODIFIED;
                else if (is_remote_access)
                    return MESI_SHARED;
                else
                    return MESI_EXCLUSIVE;
            end
            MESI_MODIFIED: begin
                if (is_remote_access)
                    return MESI_SHARED;
                else
                    return MESI_MODIFIED;
            end
            default: return MESI_INVALID;
        endcase
    endfunction
    
    //=============================================================================
    // 调试和监控函数
    //=============================================================================
    
    // 获取状态名称
    function automatic string get_state_name(
        input l2cache_state_t state
    );
        case (state)
            L2_STATE_IDLE: return "IDLE";
            L2_STATE_TAG_LOOKUP: return "TAG_LOOKUP";
            L2_STATE_DATA_ACCESS: return "DATA_ACCESS";
            L2_STATE_MISS_HANDLE: return "MISS_HANDLE";
            L2_STATE_MEMORY_ACCESS: return "MEMORY_ACCESS";
            L2_STATE_WRITE_BACK: return "WRITE_BACK";
            L2_STATE_EVICT: return "EVICT";
            L2_STATE_SYNC: return "SYNC";
            L2_STATE_ERROR: return "ERROR";
            default: return "UNKNOWN";
        endcase
    endfunction
    
    // 获取MESI状态名称
    function automatic string get_mesi_name(
        input mesi_state_t state
    );
        case (state)
            MESI_INVALID: return "INVALID";
            MESI_SHARED: return "SHARED";
            MESI_EXCLUSIVE: return "EXCLUSIVE";
            MESI_MODIFIED: return "MODIFIED";
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

endpackage : rvgpu_l2cache_pkg

`endif // RVGPU_L2CACHE_PKG_SV 
