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

`ifndef RVGPU_L2CACHE_NOC_ADAPTER_SV
`define RVGPU_L2CACHE_NOC_ADAPTER_SV

`include "rvgpu_l2cache_pkg.svh"
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

module rvgpu_l2cache_noc_adapter #(
    parameter l2cache_config_t L2CACHE_CONFIG = DEFAULT_L2CACHE_CONFIG
) (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // Controller Interface
    l2cache_noc_if.noc_adapter noc_if,
    
    // External NOC Interface
    rvgpu_internal_noc_if.device noc_external_if
);

    //=============================================================================
    // 状态机定义
    //=============================================================================
    
    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_PROCESS_REQ,
        STATE_WAIT_RESP
    } state_t;
    
    state_t state_r, state_nxt;
    
    //=============================================================================
    // 内部信号
    //=============================================================================
    
    // 请求缓存
    logic [L2CACHE_CONFIG.noc_header_width-1:0] req_header_r;
    logic [L2CACHE_CONFIG.noc_data_width-1:0] req_data_r;
    logic [L2CACHE_CONFIG.noc_data_width/8-1:0] req_strb_r;
    logic req_last_r;
    logic req_valid_r;
    
    // 响应缓存
    logic [L2CACHE_CONFIG.noc_header_width-1:0] resp_header_r;
    logic [L2CACHE_CONFIG.noc_data_width-1:0] resp_data_r;
    logic [1:0] resp_status_r;
    logic resp_last_r;
    logic resp_valid_r;
    
    //=============================================================================
    // 组合逻辑
    //=============================================================================
    
    always_comb begin
        // 默认值
        state_nxt = state_r;
        noc_if.req_valid = 1'b0;
        noc_if.req_header = '0;
        noc_if.req_data = '0;
        noc_if.req_strb = '0;
        noc_if.req_last = 1'b0;
        noc_if.resp_ready = 1'b1;
        
        noc_external_if.s_req_ready = 1'b0;
        noc_external_if.s_resp_valid = 1'b0;
        noc_external_if.s_resp_header = '0;
        noc_external_if.s_resp_data = '0;
        noc_external_if.s_resp_status = '0;
        noc_external_if.s_resp_last = 1'b0;
        
        // 状态机
        case (state_r)
            STATE_IDLE: begin
                // 空闲状态：接受新请求，发送响应
                noc_external_if.s_req_ready = 1'b1;
                
                if (resp_valid_r) begin
                    noc_external_if.s_resp_valid = 1'b1;
                    noc_external_if.s_resp_header = resp_header_r;
                    noc_external_if.s_resp_data = resp_data_r;
                    noc_external_if.s_resp_status = resp_status_r;
                    noc_external_if.s_resp_last = resp_last_r;
                end
                
                if (noc_external_if.s_req_valid && noc_external_if.s_req_ready) begin
                    state_nxt = STATE_PROCESS_REQ;
                end
            end
            
            STATE_PROCESS_REQ: begin
                // 处理请求状态：向控制器发送请求
                if (req_valid_r) begin
                    noc_if.req_valid = 1'b1;
                    noc_if.req_header = req_header_r;
                    noc_if.req_data = req_data_r;
                    noc_if.req_strb = req_strb_r;
                    noc_if.req_last = req_last_r;
                    
                    if (noc_if.req_ready) begin
                        state_nxt = STATE_WAIT_RESP;
                    end
                end else begin
                    state_nxt = STATE_IDLE;
                end
            end
            
            STATE_WAIT_RESP: begin
                // 等待响应状态：等待控制器响应
                noc_if.resp_ready = 1'b1;
                
                if (noc_if.resp_valid) begin
                    state_nxt = STATE_IDLE;
                end
            end
            
            default: begin
                state_nxt = STATE_IDLE;
            end
        endcase
    end
    
    //=============================================================================
    // 时序逻辑
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_r <= STATE_IDLE;
            req_valid_r <= 1'b0;
            resp_valid_r <= 1'b0;
        end else begin
            state_r <= state_nxt;
            
            // 缓存外部请求
            if (noc_external_if.s_req_valid && noc_external_if.s_req_ready) begin
                req_header_r <= noc_external_if.s_req_header;
                req_data_r <= noc_external_if.s_req_data;
                req_strb_r <= noc_external_if.s_req_strb;
                req_last_r <= noc_external_if.s_req_last;
                req_valid_r <= 1'b1;
            end
            
            // 缓存控制器响应
            if (noc_if.resp_valid && noc_if.resp_ready) begin
                resp_header_r <= noc_if.resp_header;
                resp_data_r <= noc_if.resp_data;
                resp_status_r <= noc_if.resp_status;
                resp_last_r <= noc_if.resp_last;
                resp_valid_r <= 1'b1;
                req_valid_r <= 1'b0;  // 清除请求缓存
            end
            
            // 清除响应缓存
            if (noc_external_if.s_resp_valid && noc_external_if.s_resp_ready) begin
                resp_valid_r <= 1'b0;
            end
        end
    end
    
    //=============================================================================
    // Debug输出
    //=============================================================================
    
    generate 
        if (L2CACHE_CONFIG.debug_enable == 1) begin
            always_ff @(posedge clk) begin
                if (noc_external_if.s_req_valid && noc_external_if.s_req_ready) begin
                    $display("@%0t: [L2CACHE_NOC] External Request Accepted: %s", $time, noc_request_mem_read_to_string(noc_external_if.s_req_header, noc_external_if.s_req_data));
                end
                
                if (noc_external_if.s_resp_valid && noc_external_if.s_resp_ready) begin
                    $display("@%0t: [L2CACHE_NOC] External Response Accepted: %s", $time, noc_response_mem_read_to_string(noc_external_if.s_resp_header, noc_external_if.s_resp_data));
                end
            end
        end
    endgenerate

endmodule : rvgpu_l2cache_noc_adapter

`endif // RVGPU_L2CACHE_NOC_ADAPTER_SV 