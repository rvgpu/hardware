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

`ifndef RVGPU_L2CACHE_CONTROLLER_SV
`define RVGPU_L2CACHE_CONTROLLER_SV

`include "rvgpu_l2cache_pkg.svh"
`include "rvgpu_debug.svh"
`include "rvgpu_l2cache_if.svh"
`include "rvgpu_internal_noc_if.svh"

`ifndef RVGPU_L2CACHE_PKG_IMPORTED
`define RVGPU_L2CACHE_PKG_IMPORTED
import rvgpu_l2cache_pkg::*;
`endif // RVGPU_L2CACHE_PKG_IMPORTED

`ifndef RVGPU_INTERNAL_NOC_PKG_IMPORTED
`define RVGPU_INTERNAL_NOC_PKG_IMPORTED
import rvgpu_internal_noc_pkg::*;
`endif // RVGPU_INTERNAL_NOC_PKG_IMPORTED

//=============================================================================
// RVGPU L2 Cache Controller
// 
// 主要功能：
// 1. 缓存状态机管理
// 2. NOC请求解析和处理
// 3. Tag和数据数组协调访问
// 4. 缓存命中/未命中处理
// 5. 替换策略实现
// 6. 缓存一致性管理
//=============================================================================

module rvgpu_l2cache_controller #(
    parameter l2cache_config_t L2CACHE_CONFIG = DEFAULT_L2CACHE_CONFIG
) (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // NOC Interface
    l2cache_noc_if.controller noc_if,
    
    // Tag Array Interface
    l2cache_tag_if.controller tag_if,
    
    // Data Array Interface
    l2cache_data_if.controller data_if,
    
    // AXI Interface
    l2cache_axi_if.controller axi_if
);

    //=============================================================================
    // Local Parameters and Types
    //=============================================================================
    
    // 状态机参数
    localparam int STATE_BITS = 4;
    localparam int L2_STATE_IDLE = 4'b0000;
    localparam int L2_STATE_TAG_LOOKUP = 4'b0001;
    localparam int L2_STATE_TAG_WAIT = 4'b0010;
    localparam int L2_STATE_DATA_ACCESS = 4'b0011;
    localparam int L2_STATE_MISS_HANDLE = 4'b0100;
    localparam int L2_STATE_MEMORY_ACCESS = 4'b1000;
    localparam int L2_STATE_TAG_UPDATE_WAIT = 4'b1001;
    
    // 请求队列深度
    localparam int REQ_QUEUE_DEPTH = 16;
    localparam int REQ_QUEUE_BITS = $clog2(REQ_QUEUE_DEPTH);
    
    // 节点ID
    localparam int NODE_L2_CACHE = 8'h02;
    
    // 状态类型定义
    typedef logic [STATE_BITS-1:0] l2cache_state_t;
    
    // 请求和响应类型定义
    typedef struct packed {
        logic [63:0] addr;
        logic [7:0] size;
        logic read;
        logic write;
        logic [7:0] trans_id;
        logic [7:0] src_node;
        logic [255:0] data;
        logic [31:0] strb;
    } l2cache_request_t;
    
    typedef struct packed {
        logic [255:0] data;
        logic [1:0] status;
        logic [7:0] trans_id;
        logic [7:0] dest_node;
        logic hit;
        logic dirty;
    } l2cache_response_t;
    
    // 性能计数器类型定义
    typedef struct packed {
        logic [31:0] hit_count;
        logic [31:0] miss_count;
        logic [31:0] read_count;
        logic [31:0] write_count;
        logic [31:0] error_count;
    } l2cache_perf_counters_t;
    
    // 使用 rvgpu_internal_noc_pkg 中定义的类型
    // noc_header_t 已在包中定义
    
    // 响应状态
    localparam int RESP_OKAY = 2'b00;
    localparam int RESP_SLVERR = 2'b10;
    
    // MESI状态
    localparam int MESI_INVALID = 2'b00;
    localparam int MESI_EXCLUSIVE = 2'b01;
    localparam int MESI_SHARED = 2'b10;
    localparam int MESI_MODIFIED = 2'b11;
    
    // 使用 rvgpu_internal_noc_pkg 中定义的类型
    // noc_msg_type_t 已在包中定义
    
    // 从配置中提取的本地参数
    localparam int TAG_BITS = L2CACHE_CONFIG.tag_bits;
    localparam int INDEX_BITS = L2CACHE_CONFIG.index_bits;
    localparam int OFFSET_BITS = L2CACHE_CONFIG.offset_bits;
    localparam int WAYS = L2CACHE_CONFIG.ways;
    localparam int LRU_BITS = L2CACHE_CONFIG.lru_bits;
    
    //=============================================================================
    // Internal Registers and Signals
    //=============================================================================
    
    // 状态机寄存器
    l2cache_state_t state_r, state_nxt;
    
    // 当前请求寄存器
    l2cache_request_t current_req_r, current_req_nxt;
    l2cache_response_t current_resp_r, current_resp_nxt;
    
    // 地址解析寄存器
    logic [TAG_BITS-1:0] current_tag_r, current_tag_nxt;
    logic [INDEX_BITS-1:0] current_index_r, current_index_nxt;
    logic [OFFSET_BITS-1:0] current_offset_r, current_offset_nxt;
    
    // 缓存访问结果寄存器
    logic cache_hit_r, cache_hit_nxt;
    logic [WAYS-1:0] hit_way_r, hit_way_nxt;
    logic [WAYS-1:0] selected_way_r, selected_way_nxt;
    
    // 请求队列
    l2cache_request_t req_queue [REQ_QUEUE_DEPTH];
    logic [REQ_QUEUE_BITS-1:0] req_queue_head_r, req_queue_head_nxt;
    logic [REQ_QUEUE_BITS-1:0] req_queue_tail_r, req_queue_tail_nxt;
    logic req_queue_full_r, req_queue_full_nxt;
    logic req_queue_empty_r, req_queue_empty_nxt;
    
    // 性能计数器
    l2cache_perf_counters_t perf_counters_r, perf_counters_nxt;
    
    // 调试寄存器
    logic [63:0] debug_addr_r, debug_addr_nxt;
    logic [7:0] debug_trans_id_r, debug_trans_id_nxt;
    logic cache_busy_r, cache_busy_nxt;
    logic write_valid_r, write_valid_nxt;
    logic read_valid_r, read_valid_nxt; 
    logic line_read_valid_r, line_read_valid_nxt;
    logic line_write_valid_r, line_write_valid_nxt;
    

    //=============================================================================
    // 握手信号定义
    //=============================================================================
    
    wire noc_req_accept = noc_if.req_valid && noc_if.req_ready;
    wire noc_resp_accept = noc_if.resp_valid && noc_if.resp_ready;
    wire tag_lookup_accept = tag_if.lookup_valid && tag_if.lookup_ready;
    wire tag_update_accept = tag_if.update_valid && tag_if.update_ready;
    wire data_read_accept = data_if.read_valid && data_if.read_ready;
    wire data_write_accept = data_if.write_valid && data_if.write_ready;
    wire axi_read_accept = axi_if.read_req_valid && axi_if.read_req_ready;
    wire axi_write_accept = axi_if.write_req_valid && axi_if.write_req_ready;
    
    //=============================================================================
    // 组合逻辑 - 状态机和输出控制
    //=============================================================================
    
    always_comb begin : comb_logic
        // 默认值
        state_nxt = state_r;
        current_req_nxt = current_req_r;
        current_resp_nxt = current_resp_r;
        current_tag_nxt = current_tag_r;
        current_index_nxt = current_index_r;
        current_offset_nxt = current_offset_r;
        cache_hit_nxt = cache_hit_r;
        hit_way_nxt = hit_way_r;
        selected_way_nxt = selected_way_r;
        req_queue_head_nxt = req_queue_head_r;
        req_queue_tail_nxt = req_queue_tail_r;
        req_queue_full_nxt = req_queue_full_r;
        req_queue_empty_nxt = req_queue_empty_r;
        perf_counters_nxt = perf_counters_r;
        cache_busy_nxt = cache_busy_r;
        write_valid_nxt = write_valid_r;
        read_valid_nxt = read_valid_r;
        line_read_valid_nxt = line_read_valid_r;
        line_write_valid_nxt = line_write_valid_r;
        // 接口输出默认值   
        noc_if.req_ready = !req_queue_full_r; // 只要队列不满就可以接受新请求
        noc_if.resp_valid = 1'b0;
        noc_if.resp_header = '0;
        noc_if.resp_data = '0;
        noc_if.resp_status = RESP_OKAY;
        noc_if.resp_last = 1'b0;
        
        tag_if.lookup_valid = 1'b0;
        tag_if.lookup_index = '0;
        tag_if.update_valid = 1'b0;
        tag_if.update_index = '0;
        tag_if.update_way = '0;
        tag_if.update_entry = '0;
        
        data_if.read_valid = 1'b0;
        data_if.read_index = '0;
        data_if.read_way = '0;
        data_if.read_offset = '0;
        data_if.read_size = '0;
        data_if.write_valid = 1'b0;
        data_if.write_index = '0;
        data_if.write_way = '0;
        data_if.write_offset = '0;
        data_if.write_data = '0;
        data_if.write_strb = '0;
        data_if.write_size = '0;
        
        axi_if.read_req_valid = 1'b0;
        axi_if.read_req_addr = '0;
        axi_if.read_req_len = '0;
        axi_if.read_req_size = '0;
        axi_if.read_req_id = '0;
        axi_if.read_resp_ready = 1'b0;
        axi_if.write_req_valid = 1'b0;
        axi_if.write_req_addr = '0;
        axi_if.write_req_len = '0;
        axi_if.write_req_size = '0;
        axi_if.write_req_id = '0;
        axi_if.write_data_valid = 1'b0;
        axi_if.write_data = '0;
        axi_if.write_strb = '0;
        axi_if.write_last = 1'b0;
        axi_if.write_resp_ready = 1'b0;
        
        case (state_r)
            L2_STATE_IDLE: begin
                // 空闲状态：等待新请求
                cache_busy_nxt = 1'b0;
                write_valid_nxt = 1'b0;
                read_valid_nxt = 1'b0;
                
                // 只处理队列中的请求，新请求先入队
                if (!req_queue_empty_r) begin
                    // 从队列中取出请求
                    current_req_nxt = req_queue[req_queue_head_r];
                    state_nxt = L2_STATE_TAG_LOOKUP;
                    cache_busy_nxt = 1'b1;
                    
                    // 解析地址
                    current_tag_nxt = extract_tag(current_req_nxt.addr, L2CACHE_CONFIG);
                    current_index_nxt = extract_index(current_req_nxt.addr, L2CACHE_CONFIG);
                    current_offset_nxt = extract_offset(current_req_nxt.addr, L2CACHE_CONFIG);
                    
                    // 更新队列头指针（在下一个周期生效）
                    req_queue_head_nxt = req_queue_head_r + 1;
                    if (req_queue_head_nxt == req_queue_tail_r) begin
                        req_queue_empty_nxt = 1'b1;
                    end
                    req_queue_full_nxt = 1'b0;
                end
            end
            
            L2_STATE_TAG_LOOKUP: begin
                // Tag查找状态 - 发起查找请求
                tag_if.lookup_valid = 1'b1;
                tag_if.lookup_index = current_index_r;
                tag_if.lookup_tag = current_tag_r;
                
                if (tag_if.lookup_ready) begin
                    // 握手成功，进入等待状态
                    state_nxt = L2_STATE_TAG_WAIT;
                end
            end
            
            L2_STATE_TAG_WAIT: begin
                // Tag等待状态 - 等待查找完成
                tag_if.lookup_valid = 1'b0; // 清除valid信号
                
                if (tag_if.lookup_done) begin
                    // 检查命中
                    cache_hit_nxt = tag_if.lookup_hit;
                    hit_way_nxt = tag_if.hit_way;
                    
                    if (tag_if.lookup_hit) begin
                        // 缓存命中
                        state_nxt = L2_STATE_DATA_ACCESS;
                        perf_counters_nxt.hit_count = perf_counters_r.hit_count + 1;

                        `DEBUG_PRINT("L2CACHE_CTRL", $sformatf("Tag Lookup: hit=%0d, way=%0d", tag_if.lookup_hit, tag_if.hit_way));
                    end else begin
                        // 缓存未命中
                        state_nxt = L2_STATE_MISS_HANDLE;
                        perf_counters_nxt.miss_count = perf_counters_r.miss_count + 1;
                        
                        // 选择替换way
                        selected_way_nxt = select_lru_way(tag_if.tag_entry.lru);

                        `DEBUG_PRINT("L2CACHE_CTRL", $sformatf("Tag Lookup: miss, way=%0d", tag_if.hit_way));
                    end
                end
            end
            
            L2_STATE_DATA_ACCESS: begin
                // 数据访问状态
                if (current_req_r.read) begin
                    // 读操作
                    if(!read_valid_r) begin
                        read_valid_nxt = 1'b1;
                    end

                    data_if.read_valid = read_valid_r;
                    data_if.read_index = current_index_r;
                    data_if.read_way = hit_way_r;
                    data_if.read_offset = current_offset_r;
                    data_if.read_size = current_req_r.size;
                    
                    if (data_if.read_ready) begin
                        read_valid_nxt = 1'b0;
                        // 准备响应
                        current_resp_nxt.data = data_if.read_data;
                        current_resp_nxt.status = RESP_OKAY;
                        current_resp_nxt.trans_id = current_req_r.trans_id;
                        current_resp_nxt.dest_node = current_req_r.src_node;
                        current_resp_nxt.hit = 1'b1;
                        current_resp_nxt.dirty = 1'b0;
                        
                        state_nxt = L2_STATE_IDLE;
                        
                        // 更新性能计数器
                        perf_counters_nxt.read_count = perf_counters_r.read_count + 1;
                    end
                end else begin
                    // 写操作
                    if(!write_valid_r) begin
                        write_valid_nxt = 1'b1;
                    end

                    data_if.write_valid = write_valid_r;
                    data_if.write_index = current_index_r;
                    data_if.write_way = hit_way_r;
                    data_if.write_offset = current_offset_r;
                    data_if.write_data = current_req_r.data;
                    data_if.write_strb = current_req_r.strb;
                    data_if.write_size = current_req_r.size;
                    
                    if (data_if.write_ready) begin
                        write_valid_nxt = 1'b0;
                        // 准备响应
                        current_resp_nxt.data = '0;
                        current_resp_nxt.status = RESP_OKAY;
                        current_resp_nxt.trans_id = current_req_r.trans_id;
                        current_resp_nxt.dest_node = current_req_r.src_node;
                        current_resp_nxt.hit = 1'b1;
                        current_resp_nxt.dirty = 1'b1;
                        
                        state_nxt = L2_STATE_IDLE;
                        
                        // 更新性能计数器
                        perf_counters_nxt.write_count = perf_counters_r.write_count + 1;
                    end
                end
            end
            
            L2_STATE_MISS_HANDLE: begin
                // 未命中处理状态
                if (current_req_r.read) begin
                    // 读未命中：从内存加载
                    axi_if.read_req_valid = 1'b1;
                    axi_if.read_req_addr = {current_tag_r, current_index_r, 6'b0}; // 对齐到缓存行
                    axi_if.read_req_len = 0; // 单次传输
                    axi_if.read_req_size = current_req_r.size; 
                    axi_if.read_req_id = current_req_r.trans_id;
                    
                    if (axi_if.read_req_ready) begin
                        $display("@%0t: [L2CACHE_CTRL] miss handle: req_addr:0x%h, req_size:%d", $time, axi_if.read_req_addr, axi_if.read_req_size);
                        state_nxt = L2_STATE_MEMORY_ACCESS;
                    end
                end else begin
                    // 写未命中：直接写内存
                    axi_if.write_req_valid = 1'b1;
                    axi_if.write_req_addr = current_req_r.addr;
                    axi_if.write_req_len = 0;
                    axi_if.write_req_size = current_req_r.size[2:0]; // 从请求payload中获取size
                    axi_if.write_req_id = current_req_r.trans_id;
                    
                    if (axi_if.write_req_ready) begin
                        axi_if.write_data_valid = 1'b1;
                        axi_if.write_data = current_req_r.data;
                        axi_if.write_strb = current_req_r.strb;
                        axi_if.write_last = 1'b1;
                        
                        if (axi_if.write_data_ready) begin
                            state_nxt = L2_STATE_IDLE;
                            
                            // 准备响应
                            current_resp_nxt.data = '0;
                            current_resp_nxt.status = RESP_OKAY;
                            current_resp_nxt.trans_id = current_req_r.trans_id;
                            current_resp_nxt.dest_node = current_req_r.src_node;
                            current_resp_nxt.hit = 1'b0;
                            current_resp_nxt.dirty = 1'b0;
                        end
                    end
                end
            end
            
            L2_STATE_MEMORY_ACCESS: begin
                // 内存访问状态
                axi_if.read_resp_ready = 1'b1;
                
                if (axi_if.read_resp_valid) begin
                    if (axi_if.read_resp_status == RESP_OKAY) begin
                        // 内存读取成功，发起tag更新请求
                        tag_if.update_valid = 1'b1;
                        tag_if.update_index = current_index_r;
                        tag_if.update_way = selected_way_r;
                        // 保持现有的tag条目，只更新选中的way
                        tag_if.update_entry = tag_if.tag_entry;
                        // 更新选中way的状态
                        tag_if.update_entry.tag[way_to_index(selected_way_r)] = current_tag_r;
                        tag_if.update_entry.valid[way_to_index(selected_way_r)] = 1'b1;
                        tag_if.update_entry.dirty[way_to_index(selected_way_r)] = 1'b0;
                        tag_if.update_entry.mesi_state[way_to_index(selected_way_r)] = MESI_EXCLUSIVE;
                        tag_if.update_entry.lru = update_lru(tag_if.tag_entry.lru, selected_way_r);
                        
                        if (tag_if.update_ready) begin
                            // 握手成功，进入等待状态
                            state_nxt = L2_STATE_TAG_UPDATE_WAIT;
                        end

                        `DEBUG_PRINT("L2CACHE_CTRL", $sformatf("MEM Responsed, Tag Update: index=0x%h, way=%0d", tag_if.update_index, tag_if.update_way));
                    end else begin
                        // 内存访问错误
                        state_nxt = L2_STATE_IDLE;
                        
                        current_resp_nxt.data = '0;
                        current_resp_nxt.status = RESP_SLVERR;
                        current_resp_nxt.trans_id = current_req_r.trans_id;
                        current_resp_nxt.dest_node = current_req_r.src_node;
                        current_resp_nxt.hit = 1'b0;
                        current_resp_nxt.dirty = 1'b0;
                        
                        perf_counters_nxt.error_count = perf_counters_r.error_count + 1;
                    end
                end
            end
            
            L2_STATE_TAG_UPDATE_WAIT: begin
                // Tag更新等待状态 - 等待更新完成
                tag_if.update_valid = 1'b0; // 清除valid信号
                
                if (tag_if.update_done) begin
                    // 更新数据数组
                    if(!line_write_valid_r) begin
                        line_write_valid_nxt = 1'b1;
                    end
                    data_if.line_write_valid = line_write_valid_r;
                    data_if.line_write_index = current_index_r;
                    data_if.line_write_way = selected_way_r;
                    data_if.line_write_data.data = axi_if.read_resp_data;
                    data_if.line_write_data.strb = '1;
                    
                    if (data_if.line_write_ready) begin
                        line_write_valid_nxt = 1'b0;
                        state_nxt = L2_STATE_IDLE;
                        
                        // 准备响应
                        current_resp_nxt.data = axi_if.read_resp_data;
                        current_resp_nxt.status = RESP_OKAY;
                        current_resp_nxt.trans_id = current_req_r.trans_id;
                        current_resp_nxt.dest_node = current_req_r.src_node;
                        current_resp_nxt.hit = 1'b0;
                        current_resp_nxt.dirty = 1'b0;
                        `DEBUG_PRINT("L2CACHE_CTRL", $sformatf("Line Write Done, resp_data=0x%h", current_resp_nxt.data));
                    end
                end
            end
            
            default: begin
                // 错误状态
                state_nxt = L2_STATE_IDLE;
                perf_counters_nxt.error_count = perf_counters_r.error_count + 1;
            end
        endcase
        
        // 响应发送逻辑
        if (current_resp_r.trans_id != 0) begin
            noc_if.resp_valid = 1'b1;
            noc_if.resp_header = build_noc_header(
                current_req_r.read ? MSG_MEM_READ_RESP : MSG_MEM_WRITE_RESP,
                current_resp_r.trans_id,
                NODE_L2_CACHE,
                current_resp_r.dest_node
            );
            noc_if.resp_data = current_resp_r.data;
            noc_if.resp_status = current_resp_r.status;
            noc_if.resp_last = 1'b1;
            
            if (noc_if.resp_ready) begin
                current_resp_nxt = '0;
            end
        end
        
        // 请求队列管理 - 只处理入队逻辑
        if (noc_req_accept && !req_queue_full_r) begin
            req_queue[req_queue_tail_r] = parse_noc_request(noc_if.req_header, noc_if.req_data);
            req_queue_tail_nxt = req_queue_tail_r + 1;
            req_queue_empty_nxt = 1'b0;
            if (req_queue_tail_nxt == req_queue_head_r) begin
                req_queue_full_nxt = 1'b1;
            end
        end
    end
    
    //=============================================================================
    // 辅助函数
    //=============================================================================

    // 解析NOC请求
    function automatic l2cache_request_t parse_noc_request(
        input noc_header_t header,
        input noc_payload_t payload
    );
        l2cache_request_t req;
        noc_header_t noc_header;
        
        noc_header = noc_header_t'(header);
        
        req.addr = payload.req_mem_read.addr;
        req.size = payload.req_mem_read.size;
        req.strb = 32'hffffffff;
        req.read = (noc_header.msg_type == MSG_MEM_READ_REQ);
        req.write = (noc_header.msg_type == MSG_MEM_WRITE_REQ);
        req.trans_id = noc_header.trans_id;
        req.src_node = noc_header.src_node;
        req.data = payload.payload_256b;
        
        return req;
    endfunction
    
    // 从地址中提取Tag
    function automatic logic [TAG_BITS-1:0] extract_tag(
        input logic [63:0] addr,
        input l2cache_config_t config
    );
        // 使用固定位宽，避免动态位选择
        logic [TAG_BITS-1:0] tag;
        tag = addr >> (config.index_bits + config.offset_bits);
        return tag;
    endfunction
    
    // 从地址中提取Index
    function automatic logic [INDEX_BITS-1:0] extract_index(
        input logic [63:0] addr,
        input l2cache_config_t config
    );
        // 使用固定位宽，避免动态位选择
        logic [INDEX_BITS-1:0] index;
        index = (addr >> config.offset_bits) & ((1 << config.index_bits) - 1);
        return index;
    endfunction
    
    // 从地址中提取Offset
    function automatic logic [OFFSET_BITS-1:0] extract_offset(
        input logic [63:0] addr,
        input l2cache_config_t config
    );
        // 使用固定位宽，避免动态位选择
        logic [OFFSET_BITS-1:0] offset;
        offset = addr & ((1 << config.offset_bits) - 1);
        return offset;
    endfunction
    
    // 选择LRU替换的way
    function automatic logic [WAYS-1:0] select_lru_way(
        input logic [LRU_BITS-1:0] lru
    );
        // 简单的LRU实现：选择最久未使用的way
        logic [WAYS-1:0] way;
        logic [2:0] way_index;
        way = '0;
        // 使用LRU的低3位作为way索引（假设8路组相联）
        way_index = lru[2:0];
        if (way_index < WAYS) begin
            way[way_index] = 1'b1;
        end else begin
            way[0] = 1'b1; // 默认选择way 0
        end
        return way;
    endfunction
    
    // 更新LRU信息
    function automatic logic [LRU_BITS-1:0] update_lru(
        input logic [LRU_BITS-1:0] old_lru,
        input logic [WAYS-1:0] used_way
    );
        // 简单的LRU更新：将使用的way标记为最近使用
        logic [LRU_BITS-1:0] new_lru;
        new_lru = old_lru;
        // 这里可以实现更复杂的LRU算法
        return new_lru;
    endfunction
    
    // Way索引转换函数
    function automatic logic [2:0] way_to_index(input logic [WAYS-1:0] way_vector);
        logic [2:0] result;
        result = 3'b000;
        for (int i = 0; i < WAYS; i++) begin
            if (way_vector[i]) result = i[2:0];
        end
        return result;
    endfunction
    
    // 构建NOC头部
    function automatic logic [31:0] build_noc_header(
        input logic [7:0] msg_type,
        input logic [7:0] trans_id,
        input logic [7:0] src_node,
        input logic [7:0] dest_node
    );
        noc_header_t header;
        logic [31:0] result;
        header.msg_type = msg_type;
        header.trans_id = trans_id;
        header.src_node = src_node;
        header.dest_node = dest_node;
        header.local_addr = 2'b00;
        result = {header.msg_type, header.trans_id, header.src_node, header.dest_node, header.local_addr};
        return result;
    endfunction
    
    //=============================================================================
    // 时序逻辑 - 寄存器更新
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // 复位逻辑
            state_r <= L2_STATE_IDLE;
            current_req_r <= '0;
            current_resp_r <= '0;
            current_tag_r <= '0;
            current_index_r <= '0;
            current_offset_r <= '0;
            cache_hit_r <= 1'b0;
            hit_way_r <= '0;
            selected_way_r <= '0;
            req_queue_head_r <= '0;
            req_queue_tail_r <= '0;
            req_queue_full_r <= 1'b0;
            req_queue_empty_r <= 1'b1;
            perf_counters_r <= '0;

            cache_busy_r <= 1'b0;
            write_valid_r <= 1'b0;
            read_valid_r <= 1'b0;
            line_read_valid_r <= 1'b0;
            line_write_valid_r <= 1'b0;
        end else begin
            // 状态更新
            state_r <= state_nxt;
            current_req_r <= current_req_nxt;
            current_resp_r <= current_resp_nxt;
            current_tag_r <= current_tag_nxt;
            current_index_r <= current_index_nxt;
            current_offset_r <= current_offset_nxt;
            cache_hit_r <= cache_hit_nxt;
            hit_way_r <= hit_way_nxt;
            selected_way_r <= selected_way_nxt;
            req_queue_head_r <= req_queue_head_nxt;
            req_queue_tail_r <= req_queue_tail_nxt;
            req_queue_full_r <= req_queue_full_nxt;
            req_queue_empty_r <= req_queue_empty_nxt;
            perf_counters_r <= perf_counters_nxt;

            cache_busy_r <= cache_busy_nxt;
            write_valid_r <= write_valid_nxt;
            read_valid_r <= read_valid_nxt;
            line_read_valid_r <= line_read_valid_nxt;
            line_write_valid_r <= line_write_valid_nxt;
        end
    end
endmodule : rvgpu_l2cache_controller

`endif // RVGPU_L2CACHE_CONTROLLER_SV 