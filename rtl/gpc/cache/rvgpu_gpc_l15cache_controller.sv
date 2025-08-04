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

`ifndef RVGPU_GPC_L15_CACHE_CONTROLLER_SV
`define RVGPU_GPC_L15_CACHE_CONTROLLER_SV



`include "types_cache_op.svh"
`include "const_l15cache.svh"
`include "types_l15cache.svh"
`include "function_cache_lru.svh"
`include "interface_l15cache_tag.svh"
`include "interface_l15cache_data.svh"
`include "rvgpu_debug.svh"
`include "rvgpu_fifo_if.svh"
`include "types_l15cache_controller.svh"
`include "interface_l15cache_controller.svh"



`ifndef RVGPU_INTERNAL_NOC_PKG_IMPORTED
`define RVGPU_INTERNAL_NOC_PKG_IMPORTED
import rvgpu_internal_noc_pkg::*;
`endif

module rvgpu_gpc_l15cache_controller #(
    parameter int GPC_ID = 0
) (
    // Clock and Reset
    input  logic clk,
    input  logic rst_n,

    // Network-on-Chip Interface
    rvgpu_internal_noc_if.device noc_if,
    
    // Tag Array Interface
    interface_l15cache_tag.ctrl_port tag_if,
    
    // Data Array Interface
    interface_l15cache_data.ctrl_port data_if,
    
    // Controller Interface
    interface_l15cache_controller.ctrl_port ctrl_if
);
    //=============================================================================
    // 状态机定义
    //=============================================================================

    typedef enum logic [3:0] {
        L15_STATE_IDLE          = 4'h0,    // 空闲状态
        L15_STATE_TAG_LOOKUP    = 4'h1,    // Tag查找
        L15_STATE_TAG_WAIT      = 4'h2,    // Tag等待
        L15_STATE_DATA_READ     = 4'h3,    // 数据读操作
        L15_STATE_MISS_HANDLE   = 4'h4,    // 未命中处理
        L15_STATE_MEMORY_ACCESS = 4'h5,    // 内存访问
        L15_STATE_TAG_UPDATE    = 4'h6,    // Tag更新
        L15_STATE_DATA_WRITE    = 4'h7,    // 数据写操作
        L15_STATE_RESPONSE      = 4'h8,    // 响应
        L15_STATE_WRITE_BACK    = 4'h9,    // 写回
        L15_STATE_EVICT         = 4'ha,    // 驱逐
        L15_STATE_SYNC          = 4'hb,    // 同步
        L15_STATE_ERROR         = 4'hc     // 错误状态
    } l15cache_state_t;

    //=============================================================================
    // Local Parameters and Types
    //=============================================================================
    
    // Request queue configuration
    localparam int REQ_QUEUE_DEPTH = 16;
    localparam int REQ_QUEUE_BITS  = $clog2(REQ_QUEUE_DEPTH);
    localparam int REQ_DATA_WIDTH  = $bits(l15cache_request_t);
    
    //=============================================================================
    // Internal Signals and Registers
    //=============================================================================
    
    // State machine registers
    l15cache_state_t state_r, state_nxt;
    
    // Current request and response registers
    l15cache_request_t  current_req_r, current_req_nxt;
    l15cache_response_t current_resp_r, current_resp_nxt;
    
    // Address parsing registers
    l15cache_addr_t current_addr_r, current_addr_nxt;
    
    // Cache access result registers
    logic cache_hit_r, cache_hit_nxt;
    logic [L15CACHE_WAYS-1:0] hit_way_r, hit_way_nxt;
    logic [L15CACHE_WAYS-1:0] selected_way_r, selected_way_nxt;
    
    // Control flags
    logic line_read_valid_r, line_read_valid_nxt;
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
    
    wire noc_req_accept  = noc_if.s_req_valid && noc_if.s_req_ready;
    wire noc_resp_accept = noc_if.s_resp_valid && noc_if.s_resp_ready;
    wire tag_lookup_accept = tag_if.lookup_valid && tag_if.lookup_ready;
    wire tag_update_accept = tag_if.update_valid && tag_if.update_ready;
    wire data_line_read_accept = data_if.line_read_valid && data_if.line_read_ready;
    wire data_line_write_accept = data_if.line_write_valid && data_if.line_write_ready;
    wire req_accept = ctrl_if.ctrl_req_valid && ctrl_if.ctrl_req_ready;


    
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
        line_read_valid_nxt = line_read_valid_r;
        line_write_valid_nxt = line_write_valid_r;

        
        // Default interface outputs
        noc_if.s_req_ready = !req_fifo_if.full;
        noc_if.s_resp_valid = 1'b0;
        noc_if.s_resp_header = '0;
        noc_if.s_resp_data = '0;
        noc_if.s_resp_status = CACHE_RESP_OKAY;
        noc_if.s_resp_last = 1'b0;
        
        // NOC master interface defaults
        noc_if.m_req_valid = 1'b0;
        noc_if.m_req_header = '0;
        noc_if.m_req_data = '0;
        noc_if.m_req_strb = '0;
        noc_if.m_req_last = 1'b0;
        noc_if.m_resp_ready = 1'b0;
        
        tag_if.lookup_valid = 1'b0;
        tag_if.lookup_index = '0;
        tag_if.lookup_tag = '0;
        tag_if.update_valid = 1'b0;
        tag_if.update_index = '0;
        tag_if.update_way = '0;
        tag_if.update_entry = '{default: '0};
        
        data_if.line_read_valid = 1'b0;
        data_if.line_read_index = '0;
        data_if.line_read_way = '0;
        data_if.line_write_valid = 1'b0;
        data_if.line_write_index = '0;
        data_if.line_write_way = '0;
        data_if.line_write_data = '0;
        
        // FIFO control
        req_fifo_if.read_en = 1'b0;
        req_fifo_if.write_en = 1'b0;
        req_fifo_if.write_data = '0;
        
        // Request interface
        ctrl_if.ctrl_req_ready = (state_r == L15_STATE_IDLE);
        ctrl_if.ctrl_resp_valid = 1'b0;
        ctrl_if.ctrl_resp_data = '0;
        
        // State machine logic
        case (state_r)
            L15_STATE_IDLE: begin
                // Idle state: wait for new requests
                line_read_valid_nxt = 1'b0;
                line_write_valid_nxt = 1'b0;
                
                // Process request from single interface
                if (ctrl_if.ctrl_req_valid) begin
                    state_nxt = L15_STATE_TAG_LOOKUP;
                    
                    // Use request data directly
                    current_req_nxt = ctrl_if.ctrl_req_data;
                    
                    // Update current address
                    current_addr_nxt = addr64_to_l15cache_addr(current_req_nxt.addr);
                end
            end
            
            L15_STATE_TAG_LOOKUP: begin
                // Tag lookup state: initiate lookup request
                tag_if.lookup_valid = 1'b1;
                tag_if.lookup_index = current_addr_r.index;
                tag_if.lookup_tag = current_addr_r.tag;
                
                if (tag_if.lookup_ready) begin
                    state_nxt = L15_STATE_TAG_WAIT;
                end
            end
            
            L15_STATE_TAG_WAIT: begin
                // Tag wait state: wait for lookup completion
                if (tag_if.lookup_done) begin
                    cache_hit_nxt = tag_if.lookup_hit;
                    hit_way_nxt = tag_if.hit_way;
                    
                    if (tag_if.lookup_hit) begin
                        // Cache hit - choose read or write state based on request type
                        if (current_req_r.read) begin
                            // Read hit: access data array
                            state_nxt = L15_STATE_DATA_READ;
                            `DEBUG_PRINT("L15CACHE_CTRL", $sformatf("Tag Lookup: read hit, way=%0d", tag_if.hit_way));
                        end else begin
                            // Write hit: update tag and data simultaneously
                            state_nxt = L15_STATE_TAG_UPDATE;
                            selected_way_nxt = hit_way_r;
                            `DEBUG_PRINT("L15CACHE_CTRL", $sformatf("Tag Lookup: write hit, way=%0d", tag_if.hit_way));
                        end
                    end else begin
                        // Cache miss
                        state_nxt = L15_STATE_MISS_HANDLE;
                        selected_way_nxt = (1 << select_lru_way(extract_lru_bits(tag_if.tag_entry)));
                        `DEBUG_PRINT("L15CACHE_CTRL", $sformatf("Tag Lookup: miss, way=%0d", tag_if.hit_way));
                    end
                end
            end
            
            L15_STATE_DATA_READ: begin
                // Data read state: initiate data read request
                if (!line_read_valid_r) begin
                    line_read_valid_nxt = 1'b1;
                    data_if.line_read_valid = 1'b1;
                end else begin
                    data_if.line_read_valid = line_read_valid_r;
                end
                
                data_if.line_read_index = current_addr_r.index;
                data_if.line_read_way = hit_way_r;
                
                // Wait for data read completion
                if (data_if.line_read_done) begin
                    line_read_valid_nxt = 1'b0;
                    state_nxt = L15_STATE_RESPONSE;
                    
                    // Prepare response
                    current_resp_nxt.data = data_if.line_read_data.data;
                    current_resp_nxt.status = CACHE_RESP_OKAY;
                    current_resp_nxt.trans_id = current_req_r.trans_id;
                    current_resp_nxt.dest_node = current_req_r.src_node;
                    current_resp_nxt.hit = 1'b1;
                    current_resp_nxt.dirty = 1'b0;
                end
            end
            
            L15_STATE_MISS_HANDLE: begin
                // Miss handling state: initiate memory access via NOC
                if (current_req_r.read) begin
                    // Read miss: send request to L2 cache via NOC
                    noc_if.m_req_valid = 1'b1;
                    noc_if.m_req_header = build_noc_header_mem_request(
                        current_req_r.trans_id, 
                        noc_node_id_t'(NODE_SHADER_0 + GPC_ID), 
                        current_req_r.src_local
                    );
                    noc_if.m_req_data = current_req_r.addr;
                    noc_if.m_req_strb = '1;
                    noc_if.m_req_last = 1'b1;
                    
                    if (noc_if.m_req_ready) begin
                        state_nxt = L15_STATE_MEMORY_ACCESS;
                        `DEBUG_PRINT("L15CACHE_CTRL", $sformatf("Memory read request: addr=0x%h", current_req_r.addr));
                    end
                end else begin
                    // Write miss: write directly to memory (no cache update)
                    noc_if.m_req_valid = 1'b1;
                    noc_if.m_req_header = build_noc_header_mem_request(
                        current_req_r.trans_id, 
                        noc_node_id_t'(NODE_SHADER_0 + GPC_ID), 
                        current_req_r.src_local
                    );
                    noc_if.m_req_data = current_req_r.data;
                    noc_if.m_req_strb = current_req_r.strb;
                    noc_if.m_req_last = 1'b1;
                    
                    if (noc_if.m_req_ready) begin
                        state_nxt = L15_STATE_RESPONSE;
                        
                        // Prepare response for write miss
                        current_resp_nxt.data = '0;
                        current_resp_nxt.status = CACHE_RESP_OKAY;
                        current_resp_nxt.trans_id = current_req_r.trans_id;
                        current_resp_nxt.dest_node = current_req_r.src_node;
                        current_resp_nxt.hit = 1'b0;
                        current_resp_nxt.dirty = 1'b0;
                    end
                end
            end
            
            L15_STATE_MEMORY_ACCESS: begin
                // Memory access state: wait for memory response
                noc_if.m_resp_ready = 1'b1;
                
                if (noc_if.m_resp_valid) begin
                    if (noc_if.m_resp_status == CACHE_RESP_OKAY) begin
                        // Memory read successful, proceed to tag and data update
                        state_nxt = L15_STATE_TAG_UPDATE;
                        `DEBUG_PRINT("L15CACHE_CTRL", $sformatf("Memory response received, proceeding to tag update: index=0x%h, way=%0d", 
                                   current_addr_r.index, selected_way_r));
                    end else begin
                        // Memory access error
                        state_nxt = L15_STATE_RESPONSE;
                        current_resp_nxt.data = '0;
                        current_resp_nxt.status = CACHE_RESP_SLVERR;
                        current_resp_nxt.trans_id = current_req_r.trans_id;
                        current_resp_nxt.dest_node = current_req_r.src_node;
                        current_resp_nxt.hit = 1'b0;
                        current_resp_nxt.dirty = 1'b0;
                    end
                end
            end
            
            L15_STATE_TAG_UPDATE: begin
                // Tag update state: update tag array
                if (!tag_if.update_valid) begin
                    // Initiate tag update
                    tag_if.update_valid = 1'b1;
                    tag_if.update_index = current_addr_r.index;
                    tag_if.update_way = selected_way_r;
                    tag_if.update_entry = tag_if.tag_entry;
                    
                    // Update selected way based on operation type
                    if (cache_hit_r) begin
                        // Write hit: update dirty bit and LRU
                        tag_if.update_entry.ways[way_to_index(selected_way_r)].dirty = 1'b1;
                        tag_if.update_entry.lru[way_to_index(selected_way_r)] = 1'b0; // 设为最近使用
                        // 更新其他way的LRU位
                        for (int i = 0; i < L15CACHE_WAYS; i++) begin
                            if (i != way_to_index(selected_way_r)) begin
                                tag_if.update_entry.lru[i] = 1'b1;
                            end
                        end
                    end else begin
                        // Cache miss: update tag, valid, dirty, and LRU
                        tag_if.update_entry.ways[way_to_index(selected_way_r)].tag = current_addr_r.tag;
                        tag_if.update_entry.ways[way_to_index(selected_way_r)].valid = 1'b1;
                        tag_if.update_entry.ways[way_to_index(selected_way_r)].dirty = 1'b0;
                        tag_if.update_entry.ways[way_to_index(selected_way_r)].mesi_state = CACHE_MESI_EXCLUSIVE;
                        tag_if.update_entry.lru[way_to_index(selected_way_r)] = 1'b0; // 设为最近使用
                        // 更新其他way的LRU位
                        for (int i = 0; i < L15CACHE_WAYS; i++) begin
                            if (i != way_to_index(selected_way_r)) begin
                                tag_if.update_entry.lru[i] = 1'b1;
                            end
                        end
                    end
                end
                
                // Wait for tag update completion
                if (tag_if.update_done) begin
                    state_nxt = L15_STATE_DATA_WRITE;
                    `DEBUG_PRINT("L15CACHE_CTRL", $sformatf("Tag update done, proceeding to data write: index=0x%h, way=%0d", 
                               current_addr_r.index, selected_way_r));
                end
            end
            
            L15_STATE_DATA_WRITE: begin
                // Data write state: initiate data write request
                if (!line_write_valid_r) begin
                    line_write_valid_nxt = 1'b1;
                    data_if.line_write_valid = 1'b1;
                end else begin
                    data_if.line_write_valid = line_write_valid_r;
                end
                
                data_if.line_write_index = current_addr_r.index;
                data_if.line_write_way = selected_way_r;
                
                if (cache_hit_r) begin
                    // Write hit: write request data
                    data_if.line_write_data.data = current_req_r.data;
                    data_if.line_write_data.strb = current_req_r.strb;
                end else begin
                    // Cache miss: write memory data
                    data_if.line_write_data.data = noc_if.m_resp_data;
                    data_if.line_write_data.strb = '1;
                end
                
                // Wait for data write completion
                if (data_if.line_write_done) begin
                    line_write_valid_nxt = 1'b0;
                    state_nxt = L15_STATE_RESPONSE;
                    
                    // Prepare response
                    if (cache_hit_r) begin
                        // Write hit response
                        current_resp_nxt.data = '0;
                        current_resp_nxt.status = CACHE_RESP_OKAY;
                        current_resp_nxt.trans_id = current_req_r.trans_id;
                        current_resp_nxt.dest_node = current_req_r.src_node;
                        current_resp_nxt.hit = 1'b1;
                        current_resp_nxt.dirty = 1'b1;
                    end else begin
                        // Cache miss response
                        current_resp_nxt.data = noc_if.m_resp_data;
                        current_resp_nxt.status = CACHE_RESP_OKAY;
                        current_resp_nxt.trans_id = current_req_r.trans_id;
                        current_resp_nxt.dest_node = current_req_r.src_node;
                        current_resp_nxt.hit = 1'b0;
                        current_resp_nxt.dirty = 1'b0;
                    end
                    
                    `DEBUG_PRINT("L15CACHE_CTRL", $sformatf("Data write done, response data=0x%h", current_resp_nxt.data));
                end
            end
            
            L15_STATE_RESPONSE: begin
                // Response state: send response to requester
                ctrl_if.ctrl_resp_valid = 1'b1;
                ctrl_if.ctrl_resp_data = current_resp_r;
                
                if (ctrl_if.ctrl_resp_ready && ctrl_if.ctrl_resp_valid) begin
                    current_resp_nxt = '0;
                    state_nxt = L15_STATE_IDLE;
                end
            end
            
            default: begin
                // Error state: return to idle
                state_nxt = L15_STATE_IDLE;
            end
        endcase
    end

    //=============================================================================
    // Helper Functions
    //=============================================================================
    
    // Convert way vector to way index
    function automatic logic [2:0] way_to_index(
        input logic [L15CACHE_WAYS-1:0] way_vector
    );
        logic [2:0] result;
        
        result = 3'b000;
        for (int i = 0; i < L15CACHE_WAYS; i++) begin
            if (way_vector[i]) result = i[2:0];
        end
        
        return result;
    endfunction
    
    // Extract LRU bits from new tag entry structure
    function automatic logic [7:0] extract_lru_bits(
        input l15cache_tag_entry_t tag_entry
    );
        return tag_entry.lru;
    endfunction
     
    //=============================================================================
    // Sequential Logic - Register Updates
    //=============================================================================
     
    always_ff @(posedge clk) begin : seq_logic
        if (!rst_n) begin
            // Reset all registers
            state_r <= L15_STATE_IDLE;
            current_req_r <= '0;
            current_resp_r <= '0;
            current_addr_r <= '0;
            cache_hit_r <= 1'b0;
            hit_way_r <= '0;
            selected_way_r <= '0;
            line_read_valid_r <= 1'b0;
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
            line_read_valid_r <= line_read_valid_nxt;
            line_write_valid_r <= line_write_valid_nxt;
        end
    end
     
endmodule : rvgpu_gpc_l15cache_controller
     
`endif // RVGPU_GPC_L15_CACHE_CONTROLLER_SV 