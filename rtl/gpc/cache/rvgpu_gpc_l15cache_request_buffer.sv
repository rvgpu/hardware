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

`ifndef RVGPU_GPC_L15_CACHE_REQUEST_BUFFER_SV
`define RVGPU_GPC_L15_CACHE_REQUEST_BUFFER_SV

`include "types_cache_mesi.svh"
`include "const_l15cache.svh"
`include "types_l15cache.svh"
`include "function_cache_lru.svh"

`include "rvgpu_fifo_if.svh"
`include "types_l15cache_buffer.svh"
`include "gpc_l15_cache_if.svh"

module rvgpu_gpc_l15cache_request_buffer (
    input  logic clk,
    input  logic rst_n,

    // Multiple Requester Interfaces (TPC + Block Scheduler + Raster)
    gpc_l15_cache_if.cache requester_if[L15CACHE_NUM_REQUESTERS],
    
    // Single Controller Interface
    output logic                    ctrl_req_valid,
    output l15cache_request_t       ctrl_req_data,
    input  logic                    ctrl_req_ready,
    
    input  logic                    ctrl_resp_valid,
    input  l15cache_response_t      ctrl_resp_data,
    output logic                    ctrl_resp_ready
);

    // Request buffer configuration
    localparam int REQ_BUFFER_DEPTH = 32;
    localparam int REQ_BUFFER_BITS  = $clog2(REQ_BUFFER_DEPTH);
    localparam int REQ_DATA_WIDTH   = $bits(l15cache_request_t);
    localparam int REQUESTER_BITS   = $clog2(L15CACHE_NUM_REQUESTERS);
    
    // Request FIFO interface
    rvgpu_fifo_basic_if #(
        .DATA_WIDTH(REQ_DATA_WIDTH),
        .INDEX_BITS(REQ_BUFFER_BITS)
    ) req_fifo_if();
    
    // Requester arbitration
    logic [L15CACHE_NUM_REQUESTERS-1:0] req_valid_array;
    logic [L15CACHE_NUM_REQUESTERS-1:0] req_grant_array;
    logic [REQUESTER_BITS-1:0] arbiter_ptr;
    logic [REQUESTER_BITS-1:0] resp_requester_r;
    
    // Request formatting
    l15cache_request_t formatted_req;
    logic req_formatted_valid;
    
    // FIFO Instantiation
    rvgpu_fifo_basic #(
        .DATA_WIDTH(REQ_DATA_WIDTH),
        .INDEX_BITS(REQ_BUFFER_BITS)
    ) u_req_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .fifo_if(req_fifo_if.fifo_port)
    );
    
    // 将请求有效信号组合成数组 - 展开循环
    assign req_valid_array[0] = requester_if[0].req_valid;
    assign req_valid_array[1] = requester_if[1].req_valid;
    assign req_valid_array[2] = requester_if[2].req_valid;
    assign req_valid_array[3] = requester_if[3].req_valid;
    assign req_valid_array[4] = requester_if[4].req_valid;
    assign req_valid_array[5] = requester_if[5].req_valid;
    
    // 仲裁逻辑
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            arbiter_ptr <= '0;
            req_grant_array <= '0;
        end else begin
            req_grant_array <= '0;
            
            if (!req_fifo_if.full) begin
                // 检查arbiter_ptr位置
                if (req_valid_array[arbiter_ptr]) begin
                    req_grant_array[arbiter_ptr] <= 1'b1;
                    arbiter_ptr <= (arbiter_ptr + 1) % L15CACHE_NUM_REQUESTERS;
                end
                // 检查arbiter_ptr+1位置
                else if (req_valid_array[(arbiter_ptr + 1) % L15CACHE_NUM_REQUESTERS]) begin
                    req_grant_array[(arbiter_ptr + 1) % L15CACHE_NUM_REQUESTERS] <= 1'b1;
                    arbiter_ptr <= (arbiter_ptr + 2) % L15CACHE_NUM_REQUESTERS;
                end
                // 检查arbiter_ptr+2位置
                else if (req_valid_array[(arbiter_ptr + 2) % L15CACHE_NUM_REQUESTERS]) begin
                    req_grant_array[(arbiter_ptr + 2) % L15CACHE_NUM_REQUESTERS] <= 1'b1;
                    arbiter_ptr <= (arbiter_ptr + 3) % L15CACHE_NUM_REQUESTERS;
                end
                // 检查arbiter_ptr+3位置
                else if (req_valid_array[(arbiter_ptr + 3) % L15CACHE_NUM_REQUESTERS]) begin
                    req_grant_array[(arbiter_ptr + 3) % L15CACHE_NUM_REQUESTERS] <= 1'b1;
                    arbiter_ptr <= (arbiter_ptr + 4) % L15CACHE_NUM_REQUESTERS;
                end
                // 检查arbiter_ptr+4位置
                else if (req_valid_array[(arbiter_ptr + 4) % L15CACHE_NUM_REQUESTERS]) begin
                    req_grant_array[(arbiter_ptr + 4) % L15CACHE_NUM_REQUESTERS] <= 1'b1;
                    arbiter_ptr <= (arbiter_ptr + 5) % L15CACHE_NUM_REQUESTERS;
                end
                // 检查arbiter_ptr+5位置
                else if (req_valid_array[(arbiter_ptr + 5) % L15CACHE_NUM_REQUESTERS]) begin
                    req_grant_array[(arbiter_ptr + 5) % L15CACHE_NUM_REQUESTERS] <= 1'b1;
                    arbiter_ptr <= (arbiter_ptr + 6) % L15CACHE_NUM_REQUESTERS;
                end
            end
        end
    end
    
    // Request formatting
    always_comb begin
        formatted_req = '0;
        req_formatted_valid = 1'b0;
        
        if (req_grant_array[0]) begin
            formatted_req.addr = requester_if[0].req_paddr;
            formatted_req.size = requester_if[0].req_size;
            formatted_req.read = requester_if[0].req_is_read;
            formatted_req.write = !requester_if[0].req_is_read;
            formatted_req.trans_id = requester_if[0].req_id;
            formatted_req.src_node = 0;
            formatted_req.src_local = 2'b00;
            formatted_req.data = requester_if[0].req_data;
            formatted_req.strb = requester_if[0].req_mask;
            req_formatted_valid = 1'b1;
        end
        else if (req_grant_array[1]) begin
            formatted_req.addr = requester_if[1].req_paddr;
            formatted_req.size = requester_if[1].req_size;
            formatted_req.read = requester_if[1].req_is_read;
            formatted_req.write = !requester_if[1].req_is_read;
            formatted_req.trans_id = requester_if[1].req_id;
            formatted_req.src_node = 0;
            formatted_req.src_local = 2'b01;
            formatted_req.data = requester_if[1].req_data;
            formatted_req.strb = requester_if[1].req_mask;
            req_formatted_valid = 1'b1;
        end
        else if (req_grant_array[2]) begin
            formatted_req.addr = requester_if[2].req_paddr;
            formatted_req.size = requester_if[2].req_size;
            formatted_req.read = requester_if[2].req_is_read;
            formatted_req.write = !requester_if[2].req_is_read;
            formatted_req.trans_id = requester_if[2].req_id;
            formatted_req.src_node = 0;
            formatted_req.src_local = 2'b10;
            formatted_req.data = requester_if[2].req_data;
            formatted_req.strb = requester_if[2].req_mask;
            req_formatted_valid = 1'b1;
        end
        else if (req_grant_array[3]) begin
            formatted_req.addr = requester_if[3].req_paddr;
            formatted_req.size = requester_if[3].req_size;
            formatted_req.read = requester_if[3].req_is_read;
            formatted_req.write = !requester_if[3].req_is_read;
            formatted_req.trans_id = requester_if[3].req_id;
            formatted_req.src_node = 0;
            formatted_req.src_local = 2'b11;
            formatted_req.data = requester_if[3].req_data;
            formatted_req.strb = requester_if[3].req_mask;
            req_formatted_valid = 1'b1;
        end
        else if (req_grant_array[4]) begin
            formatted_req.addr = requester_if[4].req_paddr;
            formatted_req.size = requester_if[4].req_size;
            formatted_req.read = requester_if[4].req_is_read;
            formatted_req.write = !requester_if[4].req_is_read;
            formatted_req.trans_id = requester_if[4].req_id;
            formatted_req.src_node = 0;
            formatted_req.src_local = 2'b00;
            formatted_req.data = requester_if[4].req_data;
            formatted_req.strb = requester_if[4].req_mask;
            req_formatted_valid = 1'b1;
        end
        else if (req_grant_array[5]) begin
            formatted_req.addr = requester_if[5].req_paddr;
            formatted_req.size = requester_if[5].req_size;
            formatted_req.read = requester_if[5].req_is_read;
            formatted_req.write = !requester_if[5].req_is_read;
            formatted_req.trans_id = requester_if[5].req_id;
            formatted_req.src_node = 0;
            formatted_req.src_local = 2'b01;
            formatted_req.data = requester_if[5].req_data;
            formatted_req.strb = requester_if[5].req_mask;
            req_formatted_valid = 1'b1;
        end
    end
    
    // FIFO control
    always_comb begin
        req_fifo_if.read_en = ctrl_req_ready && !req_fifo_if.empty;
        req_fifo_if.write_en = req_formatted_valid;
        req_fifo_if.write_data = formatted_req;
        
        ctrl_req_valid = !req_fifo_if.empty;
        ctrl_req_data = req_fifo_if.read_data;
    end
    
    // Track requester for response routing
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            resp_requester_r <= '0;
        end else begin
            if (ctrl_req_valid && ctrl_req_ready) begin
                if (req_grant_array[0]) begin
                    resp_requester_r <= 3'b000;
                end
                else if (req_grant_array[1]) begin
                    resp_requester_r <= 3'b001;
                end
                else if (req_grant_array[2]) begin
                    resp_requester_r <= 3'b010;
                end
                else if (req_grant_array[3]) begin
                    resp_requester_r <= 3'b011;
                end
                else if (req_grant_array[4]) begin
                    resp_requester_r <= 3'b100;
                end
                else if (req_grant_array[5]) begin
                    resp_requester_r <= 3'b101;
                end
            end
        end
    end
    
    // Response routing
    always_comb begin
        ctrl_resp_ready = 1'b0;
        
        // 初始化所有响应信号
        requester_if[0].resp_valid = 1'b0;
        requester_if[0].resp_data = '0;
        requester_if[0].resp_error = 1'b0;
        requester_if[0].resp_id = '0;
        
        requester_if[1].resp_valid = 1'b0;
        requester_if[1].resp_data = '0;
        requester_if[1].resp_error = 1'b0;
        requester_if[1].resp_id = '0;
        
        requester_if[2].resp_valid = 1'b0;
        requester_if[2].resp_data = '0;
        requester_if[2].resp_error = 1'b0;
        requester_if[2].resp_id = '0;
        
        requester_if[3].resp_valid = 1'b0;
        requester_if[3].resp_data = '0;
        requester_if[3].resp_error = 1'b0;
        requester_if[3].resp_id = '0;
        
        requester_if[4].resp_valid = 1'b0;
        requester_if[4].resp_data = '0;
        requester_if[4].resp_error = 1'b0;
        requester_if[4].resp_id = '0;
        
        requester_if[5].resp_valid = 1'b0;
        requester_if[5].resp_data = '0;
        requester_if[5].resp_error = 1'b0;
        requester_if[5].resp_id = '0;
        
        if (ctrl_resp_valid) begin
            case (resp_requester_r)
                3'b000: begin
                    requester_if[0].resp_valid = 1'b1;
                    requester_if[0].resp_data = ctrl_resp_data.data;
                    requester_if[0].resp_error = (ctrl_resp_data.status != CACHE_RESP_OKAY);
                    requester_if[0].resp_id = ctrl_resp_data.trans_id;
                    ctrl_resp_ready = requester_if[0].resp_ready;
                end
                3'b001: begin
                    requester_if[1].resp_valid = 1'b1;
                    requester_if[1].resp_data = ctrl_resp_data.data;
                    requester_if[1].resp_error = (ctrl_resp_data.status != CACHE_RESP_OKAY);
                    requester_if[1].resp_id = ctrl_resp_data.trans_id;
                    ctrl_resp_ready = requester_if[1].resp_ready;
                end
                3'b010: begin
                    requester_if[2].resp_valid = 1'b1;
                    requester_if[2].resp_data = ctrl_resp_data.data;
                    requester_if[2].resp_error = (ctrl_resp_data.status != CACHE_RESP_OKAY);
                    requester_if[2].resp_id = ctrl_resp_data.trans_id;
                    ctrl_resp_ready = requester_if[2].resp_ready;
                end
                3'b011: begin
                    requester_if[3].resp_valid = 1'b1;
                    requester_if[3].resp_data = ctrl_resp_data.data;
                    requester_if[3].resp_error = (ctrl_resp_data.status != CACHE_RESP_OKAY);
                    requester_if[3].resp_id = ctrl_resp_data.trans_id;
                    ctrl_resp_ready = requester_if[3].resp_ready;
                end
                3'b100: begin
                    requester_if[4].resp_valid = 1'b1;
                    requester_if[4].resp_data = ctrl_resp_data.data;
                    requester_if[4].resp_error = (ctrl_resp_data.status != CACHE_RESP_OKAY);
                    requester_if[4].resp_id = ctrl_resp_data.trans_id;
                    ctrl_resp_ready = requester_if[4].resp_ready;
                end
                3'b101: begin
                    requester_if[5].resp_valid = 1'b1;
                    requester_if[5].resp_data = ctrl_resp_data.data;
                    requester_if[5].resp_error = (ctrl_resp_data.status != CACHE_RESP_OKAY);
                    requester_if[5].resp_id = ctrl_resp_data.trans_id;
                    ctrl_resp_ready = requester_if[5].resp_ready;
                end
                default: begin
                    ctrl_resp_ready = 1'b0;
                end
            endcase
        end
    end
    
    // Requester ready signals - 展开循环
    always_comb begin
        requester_if[0].req_ready = req_grant_array[0] && !req_fifo_if.full;
        requester_if[1].req_ready = req_grant_array[1] && !req_fifo_if.full;
        requester_if[2].req_ready = req_grant_array[2] && !req_fifo_if.full;
        requester_if[3].req_ready = req_grant_array[3] && !req_fifo_if.full;
        requester_if[4].req_ready = req_grant_array[4] && !req_fifo_if.full;
        requester_if[5].req_ready = req_grant_array[5] && !req_fifo_if.full;
    end
    
endmodule : rvgpu_gpc_l15cache_request_buffer

`endif // RVGPU_GPC_L15_CACHE_REQUEST_BUFFER_SV