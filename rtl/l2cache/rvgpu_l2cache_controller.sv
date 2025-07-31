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

`include "rvgpu_l2cache_common.svh"
`include "rvgpu_debug.svh"
`include "rvgpu_l2cache_if.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_fifo_if.svh"
`include "rvgpu_l2cache_common.svh"
`include "rvgpu_l2cache_types.svh"

`ifndef RVGPU_INTERNAL_NOC_PKG_IMPORTED
`define RVGPU_INTERNAL_NOC_PKG_IMPORTED
import rvgpu_internal_noc_pkg::*;
`endif

//=============================================================================
// L2 Cache Controller Module
//=============================================================================
// This module implements the L2 cache controller with the following features:
// - FIFO-based request queue for better throughput
// - Tag lookup and data access pipeline
// - Memory access for cache misses
// - Write-back and write-through support
// - MESI cache coherence protocol support
//=============================================================================

module rvgpu_l2cache_controller (
    // Clock and Reset
    input  logic clk,
    input  logic rst_n,

    // Network-on-Chip Interface
    l2cache_noc_if.controller noc_if,
    
    // Tag Array Interface
    l2cache_tag_if.controller tag_if,
    
    // Data Array Interface
    l2cache_data_if.controller data_if,
    
    // AXI Memory Interface
    l2cache_axi_if.controller axi_if
);

    //=============================================================================
    // Local Parameters and Types
    //=============================================================================
    
    // L2 Cache Controller State Machine States
    typedef enum logic [3:0] {
        L2_STATE_IDLE          = 4'h0,    // 空闲状态
        L2_STATE_TAG_LOOKUP    = 4'h1,    // Tag查找
        L2_STATE_TAG_WAIT      = 4'h2,    // Tag等待
        L2_STATE_DATA_ACCESS   = 4'h3,    // 数据访问
        L2_STATE_MISS_HANDLE   = 4'h4,    // 未命中处理
        L2_STATE_MEMORY_ACCESS = 4'h5,    // 内存访问
        L2_STATE_TAG_UPDATE    = 4'h6,    // Tag更新
        L2_STATE_RESPONSE      = 4'h7,    // 响应
        L2_STATE_WRITE_BACK    = 4'h8,    // 写回
        L2_STATE_EVICT         = 4'h9,    // 驱逐
        L2_STATE_SYNC          = 4'ha,    // 同步
        L2_STATE_ERROR         = 4'hb     // 错误状态
    } l2cache_state_t;
    
    // Request queue configuration
    localparam int REQ_QUEUE_DEPTH = 16;
    localparam int REQ_QUEUE_BITS  = $clog2(REQ_QUEUE_DEPTH);
    localparam int REQ_DATA_WIDTH  = $bits(l2cache_request_t);
    
    //=============================================================================
    // Internal Signals and Registers
    //=============================================================================
    
    // State machine registers
    l2cache_state_t state_r, state_nxt;
    
    // Current request and response registers
    l2cache_request_t  current_req_r, current_req_nxt;
    l2cache_response_t current_resp_r, current_resp_nxt;
    
    // Address parsing registers
    l2cache_addr_t current_addr_r, current_addr_nxt;
    
    // Cache access result registers
    logic cache_hit_r, cache_hit_nxt;
    logic [L2CACHE_WAYS-1:0] hit_way_r, hit_way_nxt;
    logic [L2CACHE_WAYS-1:0] selected_way_r, selected_way_nxt;
    
    // Control flags
    logic read_valid_r, read_valid_nxt;
    logic write_valid_r, write_valid_nxt;
    logic line_write_valid_r, line_write_valid_nxt;
    
    // Request FIFO interface
    rvgpu_fifo_basic_if #(
        .DATA_WIDTH(REQ_DATA_WIDTH),
        .INDEX_BITS(REQ_QUEUE_BITS)
    ) req_fifo_if();
    
    //=============================================================================
    // FIFO Instantiation
    //=============================================================================
    
    rvgpu_fifo_basic #(
        .DATA_WIDTH(REQ_DATA_WIDTH),
        .INDEX_BITS(REQ_QUEUE_BITS)
    ) u_req_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .fifo_if(req_fifo_if.fifo_port)
    );
    
    //=============================================================================
    // Handshake Signal Definitions
    //=============================================================================
    
    wire noc_req_accept  = noc_if.req_valid && noc_if.req_ready;
    wire noc_resp_accept = noc_if.resp_valid && noc_if.resp_ready;
    wire tag_lookup_accept = tag_if.lookup_valid && tag_if.lookup_ready;
    wire tag_update_accept = tag_if.update_valid && tag_if.update_ready;
    wire data_read_accept = data_if.read_valid && data_if.read_ready;
    wire data_write_accept = data_if.write_valid && data_if.write_ready;
    wire axi_read_accept = axi_if.read_req_valid && axi_if.read_req_ready;
    wire axi_write_accept = axi_if.write_req_valid && axi_if.write_req_ready;

    //=============================================================================
    // Combinational Logic - State Machine and Interface Control
    //=============================================================================
    
    always_comb begin : comb_logic
        // Default values for next state and outputs
        state_nxt = state_r;
        current_req_nxt = current_req_r;
        current_resp_nxt = current_resp_r;
        current_addr_nxt = current_addr_r;
        cache_hit_nxt = cache_hit_r;
        hit_way_nxt = hit_way_r;
        selected_way_nxt = selected_way_r;
        read_valid_nxt = read_valid_r;
        write_valid_nxt = write_valid_r;
        line_write_valid_nxt = line_write_valid_r;
        
        // Default interface outputs
        noc_if.req_ready = !req_fifo_if.full;
        noc_if.resp_valid = 1'b0;
        noc_if.resp_header = '0;
        noc_if.resp_data = '0;
        noc_if.resp_status = L2CACHE_RESP_OKAY;
        noc_if.resp_last = 1'b0;
        
        tag_if.lookup_valid = 1'b0;
        tag_if.lookup_index = '0;
        tag_if.lookup_tag = '0;
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
        data_if.line_write_valid = 1'b0;
        data_if.line_write_index = '0;
        data_if.line_write_way = '0;
        data_if.line_write_data = '0;
        
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
        
        // FIFO control
        req_fifo_if.read_en = 1'b0;
        req_fifo_if.write_en = 1'b0;
        req_fifo_if.write_data = '0;
        
        // State machine logic
        case (state_r)
            L2_STATE_IDLE: begin
                // Idle state: wait for new requests
                read_valid_nxt = 1'b0;
                write_valid_nxt = 1'b0;
                line_write_valid_nxt = 1'b0;
                
                // Process requests from FIFO
                if (!req_fifo_if.empty) begin
                    req_fifo_if.read_en = 1'b1;
                    state_nxt = L2_STATE_TAG_LOOKUP;
                    
                    // Update current request and address
                    current_req_nxt = l2cache_request_t'(req_fifo_if.read_data);
                    current_addr_nxt = addr64_to_l2cache_addr(current_req_nxt.addr);
                end
            end
            
            L2_STATE_TAG_LOOKUP: begin
                // Tag lookup state: initiate lookup request
                tag_if.lookup_valid = 1'b1;
                tag_if.lookup_index = current_addr_r.index;
                tag_if.lookup_tag = current_addr_r.tag;
                
                if (tag_if.lookup_ready) begin
                    state_nxt = L2_STATE_TAG_WAIT;
                end
            end
            
            L2_STATE_TAG_WAIT: begin
                // Tag wait state: wait for lookup completion
                if (tag_if.lookup_done) begin
                    cache_hit_nxt = tag_if.lookup_hit;
                    hit_way_nxt = tag_if.hit_way;
                    
                    if (tag_if.lookup_hit) begin
                        // Cache hit
                        state_nxt = L2_STATE_DATA_ACCESS;
                        `DEBUG_PRINT("L2CACHE_CTRL", $sformatf("Tag Lookup: hit=1, way=%0d", tag_if.hit_way));
                    end else begin
                        // Cache miss
                        state_nxt = L2_STATE_MISS_HANDLE;
                        selected_way_nxt = (1 << select_lru_way(extract_lru_bits(tag_if.tag_entry)));
                        `DEBUG_PRINT("L2CACHE_CTRL", $sformatf("Tag Lookup: miss, way=%0d", tag_if.hit_way));
                    end
                end
            end
            
            L2_STATE_DATA_ACCESS: begin
                // Data access state: read/write cache data
                if (current_req_r.read) begin
                    // Read operation
                    if (!read_valid_r) begin
                        read_valid_nxt = 1'b1;
                    end
                    
                    data_if.read_valid = read_valid_r;
                    data_if.read_index = current_addr_r.index;
                    data_if.read_way = hit_way_r;
                    data_if.read_offset = current_addr_r.offset;
                    data_if.read_size = current_req_r.size;
                    
                    if (data_if.read_ready) begin
                        read_valid_nxt = 1'b0;
                        state_nxt = L2_STATE_RESPONSE;
                        
                        // Prepare response
                        current_resp_nxt.data = data_if.read_data;
                        current_resp_nxt.status = L2CACHE_RESP_OKAY;
                        current_resp_nxt.trans_id = current_req_r.trans_id;
                        current_resp_nxt.dest_node = current_req_r.src_node;
                        current_resp_nxt.hit = 1'b1;
                        current_resp_nxt.dirty = 1'b0;
                    end
                end else begin
                    // Write operation
                    if (!write_valid_r) begin
                        write_valid_nxt = 1'b1;
                    end
                    
                    data_if.write_valid = write_valid_r;
                    data_if.write_index = current_addr_r.index;
                    data_if.write_way = hit_way_r;
                    data_if.write_offset = current_addr_r.offset;
                    data_if.write_data = current_req_r.data;
                    data_if.write_strb = current_req_r.strb;
                    data_if.write_size = current_req_r.size;
                    
                    if (data_if.write_ready) begin
                        write_valid_nxt = 1'b0;
                        state_nxt = L2_STATE_RESPONSE;
                        
                        // Prepare response
                        current_resp_nxt.data = '0;
                        current_resp_nxt.status = L2CACHE_RESP_OKAY;
                        current_resp_nxt.trans_id = current_req_r.trans_id;
                        current_resp_nxt.dest_node = current_req_r.src_node;
                        current_resp_nxt.hit = 1'b1;
                        current_resp_nxt.dirty = 1'b1;
                    end
                end
            end
            
            L2_STATE_MISS_HANDLE: begin
                // Miss handling state: initiate memory access
                if (current_req_r.read) begin
                    // Read miss: load from memory
                    axi_if.read_req_valid = 1'b1;
                    axi_if.read_req_addr = request_mem_addr_aligned(current_addr_r);
                    axi_if.read_req_len = 0;
                    axi_if.read_req_size = current_req_r.size;
                    axi_if.read_req_id = current_req_r.trans_id;
                    
                    if (axi_if.read_req_ready) begin
                        state_nxt = L2_STATE_MEMORY_ACCESS;
                        `DEBUG_PRINT("L2CACHE_CTRL", $sformatf("Memory read request: addr=0x%h, size=%d", 
                                   axi_if.read_req_addr, axi_if.read_req_size));
                    end
                end else begin
                    // Write miss: write to memory
                    if (!write_valid_r) begin
                        axi_if.write_req_valid = 1'b1;
                        axi_if.write_req_addr = current_req_r.addr;
                        axi_if.write_req_len = 0;
                        axi_if.write_req_size = current_req_r.size[2:0];
                        axi_if.write_req_id = current_req_r.trans_id;
                        
                        if (axi_if.write_req_ready) begin
                            write_valid_nxt = 1'b1;
                        end
                    end else begin
                        axi_if.write_data_valid = 1'b1;
                        axi_if.write_data = current_req_r.data;
                        axi_if.write_strb = current_req_r.strb;
                        axi_if.write_last = 1'b1;
                        
                        if (axi_if.write_data_ready) begin
                            state_nxt = L2_STATE_RESPONSE;
                            write_valid_nxt = 1'b0;
                            
                            // Prepare response
                            current_resp_nxt.data = '0;
                            current_resp_nxt.status = L2CACHE_RESP_OKAY;
                            current_resp_nxt.trans_id = current_req_r.trans_id;
                            current_resp_nxt.dest_node = current_req_r.src_node;
                            current_resp_nxt.hit = 1'b0;
                            current_resp_nxt.dirty = 1'b0;
                        end
                    end
                end
            end
            
            L2_STATE_MEMORY_ACCESS: begin
                // Memory access state: wait for memory response
                axi_if.read_resp_ready = 1'b1;
                
                if (axi_if.read_resp_valid) begin
                    if (axi_if.read_resp_status == L2CACHE_RESP_OKAY) begin
                        // Memory read successful, update tag array
                        tag_if.update_valid = 1'b1;
                        tag_if.update_index = current_addr_r.index;
                        tag_if.update_way = selected_way_r;
                        tag_if.update_entry = tag_if.tag_entry;
                        
                        // Update selected way
                        tag_if.update_entry.ways[way_to_index(selected_way_r)].tag = current_addr_r.tag;
                        tag_if.update_entry.ways[way_to_index(selected_way_r)].valid = 1'b1;
                        tag_if.update_entry.ways[way_to_index(selected_way_r)].dirty = 1'b0;
                        tag_if.update_entry.ways[way_to_index(selected_way_r)].mesi_state = CACHE_MESI_EXCLUSIVE;
                        // 更新LRU位
                        tag_if.update_entry.lru[way_to_index(selected_way_r)] = 1'b0; // 设为最近使用
                        // 更新其他way的LRU位
                        for (int i = 0; i < L2CACHE_WAYS; i++) begin
                            if (i != way_to_index(selected_way_r)) begin
                                tag_if.update_entry.lru[i] = 1'b1;
                            end
                        end
                        
                        if (tag_if.update_ready) begin
                            state_nxt = L2_STATE_TAG_UPDATE;
                        end
                        
                        `DEBUG_PRINT("L2CACHE_CTRL", $sformatf("Memory response received, updating tag: index=0x%h, way=%0d", 
                                   tag_if.update_index, tag_if.update_way));
                    end else begin
                        // Memory access error
                        state_nxt = L2_STATE_RESPONSE;
                        current_resp_nxt.data = '0;
                        current_resp_nxt.status = L2CACHE_RESP_SLVERR;
                        current_resp_nxt.trans_id = current_req_r.trans_id;
                        current_resp_nxt.dest_node = current_req_r.src_node;
                        current_resp_nxt.hit = 1'b0;
                        current_resp_nxt.dirty = 1'b0;
                    end
                end
            end
            
            L2_STATE_TAG_UPDATE: begin
                // Tag update state: wait for tag update completion
                if (tag_if.update_done) begin
                    // Update data array
                    if (!line_write_valid_r) begin
                        line_write_valid_nxt = 1'b1;
                    end
                    
                    data_if.line_write_valid = line_write_valid_r;
                    data_if.line_write_index = current_addr_r.index;
                    data_if.line_write_way = selected_way_r;
                    data_if.line_write_data.data = axi_if.read_resp_data;
                    data_if.line_write_data.strb = '1;
                    
                    if (data_if.line_write_ready) begin
                        line_write_valid_nxt = 1'b0;
                        state_nxt = L2_STATE_RESPONSE;
                        
                        // Prepare response
                        current_resp_nxt.data = axi_if.read_resp_data;
                        current_resp_nxt.status = L2CACHE_RESP_OKAY;
                        current_resp_nxt.trans_id = current_req_r.trans_id;
                        current_resp_nxt.dest_node = current_req_r.src_node;
                        current_resp_nxt.hit = 1'b0;
                        current_resp_nxt.dirty = 1'b0;
                        
                        `DEBUG_PRINT("L2CACHE_CTRL", $sformatf("Cache line written, response data=0x%h", current_resp_nxt.data));
                    end
                end
            end
            
            L2_STATE_RESPONSE: begin
                // Response state: send response to NOC
                if (current_resp_r.trans_id != 0) begin
                    noc_if.resp_valid = 1'b1;
                    noc_if.resp_header = build_noc_header_mem_response(
                        current_resp_r.trans_id, 
                        current_resp_r.dest_node, 
                        current_req_r.src_local
                    );
                    noc_if.resp_data = current_resp_r.data;
                    noc_if.resp_status = current_resp_r.status;
                    noc_if.resp_last = 1'b1;
                    
                    if (noc_if.resp_ready) begin
                        current_resp_nxt = '0;
                        state_nxt = L2_STATE_IDLE;
                    end
                end else begin
                    state_nxt = L2_STATE_IDLE;
                end
            end
            
            default: begin
                // Error state: return to idle
                state_nxt = L2_STATE_IDLE;
            end
        endcase
        
        // Request FIFO management: enqueue new requests
        if (noc_req_accept && !req_fifo_if.full) begin
            req_fifo_if.write_en = 1'b1;
            req_fifo_if.write_data = l2cache_request_t'(parse_noc_request(noc_if.req_header, noc_if.req_data));
        end
    end

    //=============================================================================
    // Helper Functions
    //=============================================================================
    
    // Parse NOC request into internal format
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
        req.src_local = noc_header.src_local;
        req.data = payload.payload_256b;
        
        return req;
    endfunction

    // 新增：结构体unpack函数
    function automatic l2cache_request_t unpack_l2cache_request(logic [$bits(l2cache_request_t)-1:0] bits);
        return l2cache_request_t'(bits);
    endfunction

    // Convert way vector to way index
    function automatic logic [2:0] way_to_index(
        input logic [L2CACHE_WAYS-1:0] way_vector
    );
        logic [2:0] result;
        
        result = 3'b000;
        for (int i = 0; i < L2CACHE_WAYS; i++) begin
            if (way_vector[i]) result = i[2:0];
        end
        
        return result;
    endfunction
    
    // Extract LRU bits from new tag entry structure
    function automatic logic [7:0] extract_lru_bits(
        input l2cache_tag_entry_t tag_entry
    );
        return tag_entry.lru;
    endfunction
     
     //=============================================================================
     // Sequential Logic - Register Updates
     //=============================================================================
     
     always_ff @(posedge clk) begin : seq_logic
         if (!rst_n) begin
             // Reset all registers
             state_r <= L2_STATE_IDLE;
             current_req_r <= '0;
             current_resp_r <= '0;
             current_addr_r <= '0;
             cache_hit_r <= 1'b0;
             hit_way_r <= '0;
             selected_way_r <= '0;
             read_valid_r <= 1'b0;
             write_valid_r <= 1'b0;
             line_write_valid_r <= 1'b0;
         end else begin
             // Update registers with next values
             state_r <= state_nxt;
             current_req_r <= current_req_nxt;
             current_resp_r <= current_resp_nxt;
             current_addr_r <= current_addr_nxt;
             cache_hit_r <= cache_hit_nxt;
             hit_way_r <= hit_way_nxt;
             selected_way_r <= selected_way_nxt;
             read_valid_r <= read_valid_nxt;
             write_valid_r <= write_valid_nxt;
             line_write_valid_r <= line_write_valid_nxt;
         end
     end
     
 endmodule : rvgpu_l2cache_controller
     
 `endif // RVGPU_L2CACHE_CONTROLLER_SV
