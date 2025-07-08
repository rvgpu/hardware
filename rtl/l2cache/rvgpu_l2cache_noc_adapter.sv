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

//=============================================================================
// RVGPU L2 Cache NOC Adapter
// 
// 主要功能：
// 1. NOC协议转换
// 2. 请求解析和路由
// 3. 响应生成和发送
// 4. 消息类型处理
// 5. 节点ID管理
//=============================================================================

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
    // Local Parameters and Types
    //=============================================================================
    
    // 从配置中提取的本地参数
    localparam int NOC_HEADER_WIDTH = L2CACHE_CONFIG.noc_header_width;
    localparam int NOC_DATA_WIDTH = L2CACHE_CONFIG.noc_data_width;
    
    // 状态机参数
    localparam int STATE_BITS = 3;
    localparam int STATE_IDLE = 3'b000;
    localparam int STATE_PROCESS_REQ = 3'b001;
    localparam int STATE_WAIT_RESP = 3'b010;
    localparam int STATE_SEND_RESP = 3'b011;
    localparam int STATE_FORWARD_REQ = 3'b100;
    
    // 请求队列深度
    localparam int REQ_QUEUE_DEPTH = 16;
    localparam int REQ_QUEUE_BITS = $clog2(REQ_QUEUE_DEPTH);
    
    // 响应状态
    localparam int RESP_OKAY = 2'b00;
    localparam int RESP_SLVERR = 2'b10;
    
    // 消息类型
    localparam int MSG_MEM_READ_REQ = 8'h01;
    localparam int MSG_MEM_WRITE_REQ = 8'h02;
    localparam int MSG_MEM_READ_RESP = 8'h03;
    localparam int MSG_MEM_WRITE_RESP = 8'h04;
    localparam int MSG_CACHE_INVALIDATE = 8'h05;
    localparam int MSG_CACHE_FLUSH = 8'h06;
    
    // NOC头部类型定义
    typedef struct packed {
        logic [7:0] msg_type;
        logic [7:0] trans_id;
        logic [7:0] src_node;
        logic [7:0] dest_node;
        logic [1:0] local_addr;
    } noc_header_t;
    
    //=============================================================================
    // Internal Registers and Signals
    //=============================================================================
    
    // 状态机寄存器
    logic [STATE_BITS-1:0] state_r, state_nxt;
    
    // 当前请求寄存器
    logic [NOC_HEADER_WIDTH-1:0] current_header_r, current_header_nxt;
    logic [NOC_DATA_WIDTH-1:0] current_data_r, current_data_nxt;
    logic [NOC_DATA_WIDTH/8-1:0] current_strb_r, current_strb_nxt;
    logic current_last_r, current_last_nxt;
    
    // 当前响应寄存器
    logic [NOC_HEADER_WIDTH-1:0] resp_header_r, resp_header_nxt;
    logic [NOC_DATA_WIDTH-1:0] resp_data_r, resp_data_nxt;
    logic [1:0] resp_status_r, resp_status_nxt;
    logic resp_last_r, resp_last_nxt;
    
    // 请求队列
    typedef struct packed {
        logic [NOC_HEADER_WIDTH-1:0] header;
        logic [NOC_DATA_WIDTH-1:0] data;
        logic [NOC_DATA_WIDTH/8-1:0] strb;
        logic last;
        logic is_forward;
    } noc_request_t;
    
    noc_request_t req_queue [REQ_QUEUE_DEPTH];
    logic [REQ_QUEUE_BITS-1:0] req_queue_head_r, req_queue_head_nxt;
    logic [REQ_QUEUE_BITS-1:0] req_queue_tail_r, req_queue_tail_nxt;
    logic req_queue_full_r, req_queue_full_nxt;
    logic req_queue_empty_r, req_queue_empty_nxt;
    
    // 消息解析寄存器
    noc_header_t parsed_header;
    logic [63:0] parsed_addr;
    logic [7:0] parsed_size;
    logic [7:0] parsed_trans_id;
    logic [7:0] parsed_src_node;
    logic [7:0] parsed_dest_node;
    
    //=============================================================================
    // 握手信号定义
    //=============================================================================
    
    wire req_accept = noc_external_if.s_req_valid && noc_external_if.s_req_ready;
    wire resp_accept = noc_external_if.s_resp_valid && noc_external_if.s_resp_ready;
    wire out_req_accept = noc_external_if.m_req_valid && noc_external_if.m_req_ready;
    wire out_resp_accept = noc_external_if.m_resp_valid && noc_external_if.m_resp_ready;
    
    //=============================================================================
    // 组合逻辑 - 状态机和输出控制
    //=============================================================================
    
    always_comb begin : comb_logic
        // 默认值
        state_nxt = state_r;
        current_header_nxt = current_header_r;
        current_data_nxt = current_data_r;
        current_strb_nxt = current_strb_r;
        current_last_nxt = current_last_r;
        resp_header_nxt = resp_header_r;
        resp_data_nxt = resp_data_r;
        resp_status_nxt = resp_status_r;
        resp_last_nxt = resp_last_r;
        req_queue_head_nxt = req_queue_head_r;
        req_queue_tail_nxt = req_queue_tail_r;
        req_queue_full_nxt = req_queue_full_r;
        req_queue_empty_nxt = req_queue_empty_r;
        
        // 外部NOC接口输出默认值
        noc_external_if.s_req_ready = (state_r == STATE_IDLE) && !req_queue_full_r;
        noc_external_if.s_resp_valid = 1'b0;
        noc_external_if.s_resp_header = resp_header_r;
        noc_external_if.s_resp_data = resp_data_r;
        noc_external_if.s_resp_status = resp_status_r;
        noc_external_if.s_resp_last = resp_last_r;
        
        noc_external_if.m_req_valid = 1'b0;
        noc_external_if.m_req_header = current_header_r;
        noc_external_if.m_req_data = current_data_r;
        noc_external_if.m_req_strb = current_strb_r;
        noc_external_if.m_req_last = current_last_r;
        noc_external_if.m_resp_ready = 1'b0;
        
        // 控制器接口输出默认值
        noc_if.req_valid = 1'b0;
        noc_if.req_header = current_header_r;
        noc_if.req_data = current_data_r;
        noc_if.req_strb = current_strb_r;
        noc_if.req_last = current_last_r;
        
        noc_if.resp_ready = 1'b1;
        
        // 注意：out_req_* 信号在noc_adapter modport中是input，不能驱动
        // 这些信号由外部NOC网络驱动
        
        // noc_if.out_resp_ready = 1'b1; // 注释掉，modport input不能驱动
        
        // 解析当前请求
        parsed_header = noc_header_t'(current_header_r);
        parsed_addr = current_data_r[63:0];
        parsed_size = current_data_r[71:64];
        parsed_trans_id = parsed_header.trans_id;
        parsed_src_node = parsed_header.src_node;
        parsed_dest_node = parsed_header.dest_node;
        
        case (state_r)
            STATE_IDLE: begin
                // 空闲状态：处理新请求
                if (noc_external_if.s_req_valid && noc_external_if.s_req_ready) begin
                    // 接收外部请求
                    current_header_nxt = noc_external_if.s_req_header;
                    current_data_nxt = noc_external_if.s_req_data;
                    current_strb_nxt = noc_external_if.s_req_strb;
                    current_last_nxt = noc_external_if.s_req_last;
                    
                    // 解析请求类型
                    case (parsed_header.msg_type)
                        MSG_MEM_READ_REQ: begin
                            // 内存读请求：转发给控制器
                            state_nxt = STATE_PROCESS_REQ;
                        end
                        MSG_MEM_WRITE_REQ: begin
                            // 内存写请求：转发给控制器
                            state_nxt = STATE_PROCESS_REQ;
                        end
                        MSG_CACHE_INVALIDATE: begin
                            // 缓存失效请求：转发给控制器
                            state_nxt = STATE_PROCESS_REQ;
                        end
                        MSG_CACHE_FLUSH: begin
                            // 缓存刷新请求：转发给控制器
                            state_nxt = STATE_PROCESS_REQ;
                        end
                        default: begin
                            // 未知请求：转发给其他节点
                            state_nxt = STATE_FORWARD_REQ;
                        end
                    endcase
                end else if (!req_queue_empty_r) begin
                    // 处理队列中的请求
                    current_header_nxt = req_queue[req_queue_head_r].header;
                    current_data_nxt = req_queue[req_queue_head_r].data;
                    current_strb_nxt = req_queue[req_queue_head_r].strb;
                    current_last_nxt = req_queue[req_queue_head_r].last;
                    
                    if (req_queue[req_queue_head_r].is_forward) begin
                        state_nxt = STATE_FORWARD_REQ;
                    end else begin
                        state_nxt = STATE_PROCESS_REQ;
                    end
                end
            end
            
            STATE_PROCESS_REQ: begin
                // 处理请求状态
                noc_if.req_valid = 1'b1;
                noc_if.req_header = current_header_r;
                noc_if.req_data = current_data_r;
                noc_if.req_strb = current_strb_r;
                noc_if.req_last = current_last_r;
                
                if (noc_if.req_ready) begin
                    state_nxt = STATE_WAIT_RESP;
                end
            end
            
            STATE_WAIT_RESP: begin
                // 等待响应状态
                noc_if.resp_ready = 1'b1;
                
                if (noc_if.resp_valid) begin
                    // 接收响应
                    resp_header_nxt = noc_if.resp_header;
                    resp_data_nxt = noc_if.resp_data;
                    resp_status_nxt = noc_if.resp_status;
                    resp_last_nxt = noc_if.resp_last;
                    
                    state_nxt = STATE_SEND_RESP;
                end
            end
            
            STATE_SEND_RESP: begin
                // 发送响应状态
                noc_external_if.s_resp_valid = 1'b1;
                noc_external_if.s_resp_header = resp_header_r;
                noc_external_if.s_resp_data = resp_data_r;
                noc_external_if.s_resp_status = resp_status_r;
                noc_external_if.s_resp_last = resp_last_r;
                
                if (resp_accept) begin
                    state_nxt = STATE_IDLE;
                    
                    // 更新队列
                    if (!req_queue_empty_r) begin
                        req_queue_head_nxt = req_queue_head_r + 1;
                        if (req_queue_head_nxt == req_queue_tail_r) begin
                            req_queue_empty_nxt = 1'b1;
                        end
                        req_queue_full_nxt = 1'b0;
                    end
                end
            end
            
            STATE_FORWARD_REQ: begin
                // 转发请求状态
                noc_external_if.m_req_valid = 1'b1;
                noc_external_if.m_req_header = current_header_r;
                noc_external_if.m_req_data = current_data_r;
                noc_external_if.m_req_strb = current_strb_r;
                noc_external_if.m_req_last = current_last_r;
                
                if (out_req_accept) begin
                    // 等待转发响应
                    noc_external_if.m_resp_ready = 1'b1;
                    
                    if (noc_external_if.m_resp_valid) begin
                        // 接收转发响应
                        resp_header_nxt = noc_external_if.m_resp_header;
                        resp_data_nxt = noc_external_if.m_resp_data;
                        resp_status_nxt = noc_external_if.m_resp_status;
                        resp_last_nxt = noc_external_if.m_resp_last;
                        
                        state_nxt = STATE_SEND_RESP;
                    end
                end
            end
            
            default: begin
                // 错误状态
                state_nxt = STATE_IDLE;
                resp_status_nxt = RESP_SLVERR;
            end
        endcase
        
        // 请求队列管理
        if (noc_external_if.s_req_valid && noc_external_if.s_req_ready) begin
            req_queue[req_queue_tail_r].header = noc_external_if.s_req_header;
            req_queue[req_queue_tail_r].data = noc_external_if.s_req_data;
            req_queue[req_queue_tail_r].strb = noc_external_if.s_req_strb;
            req_queue[req_queue_tail_r].last = noc_external_if.s_req_last;
            req_queue[req_queue_tail_r].is_forward = (parsed_header.msg_type != MSG_MEM_READ_REQ) &&
                                                    (parsed_header.msg_type != MSG_MEM_WRITE_REQ) &&
                                                    (parsed_header.msg_type != MSG_CACHE_INVALIDATE) &&
                                                    (parsed_header.msg_type != MSG_CACHE_FLUSH);
            
            req_queue_tail_nxt = req_queue_tail_r + 1;
            req_queue_empty_nxt = 1'b0;
            if (req_queue_tail_nxt == req_queue_head_r) begin
                req_queue_full_nxt = 1'b1;
            end
        end
    end
    
    //=============================================================================
    // 时序逻辑 - 寄存器更新
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // 复位逻辑
            state_r <= STATE_IDLE;
            current_header_r <= '0;
            current_data_r <= '0;
            current_strb_r <= '0;
            current_last_r <= 1'b0;
            resp_header_r <= '0;
            resp_data_r <= '0;
            resp_status_r <= '0;
            resp_last_r <= 1'b0;
            req_queue_head_r <= '0;
            req_queue_tail_r <= '0;
            req_queue_full_r <= 1'b0;
            req_queue_empty_r <= 1'b1;
        end else begin
            // 状态更新
            state_r <= state_nxt;
            current_header_r <= current_header_nxt;
            current_data_r <= current_data_nxt;
            current_strb_r <= current_strb_nxt;
            current_last_r <= current_last_nxt;
            resp_header_r <= resp_header_nxt;
            resp_data_r <= resp_data_nxt;
            resp_status_r <= resp_status_nxt;
            resp_last_r <= resp_last_nxt;
            req_queue_head_r <= req_queue_head_nxt;
            req_queue_tail_r <= req_queue_tail_nxt;
            req_queue_full_r <= req_queue_full_nxt;
            req_queue_empty_r <= req_queue_empty_nxt;
        end
    end
    
    //=============================================================================
    // 调试输出 (仅在仿真时)
    //=============================================================================
    
    generate
    if (L2CACHE_CONFIG.debug_enable) begin : gen_debug
        always_ff @(posedge clk) begin
            // 监控外部请求
            if (req_accept) begin
                $display("@%0t: [L2CACHE_NOC] External Request: type=0x%h, src=%0d, dest=%0d, trans_id=%0d", 
                         $time, parsed_header.msg_type, parsed_src_node, parsed_dest_node, parsed_trans_id);
            end
            
            // 监控外部响应
            if (resp_accept) begin
                noc_header_t resp_header_struct;
                resp_header_struct = noc_header_t'(resp_header_r);
                $display("@%0t: [L2CACHE_NOC] External Response: type=0x%h, status=%0d, trans_id=%0d", 
                         $time, resp_header_struct.msg_type, resp_status_r, resp_header_struct.trans_id);
            end
            
            // 监控转发请求
            if (out_req_accept) begin
                noc_header_t current_header_struct;
                current_header_struct = noc_header_t'(current_header_r);
                $display("@%0t: [L2CACHE_NOC] Forward Request: type=0x%h, src=%0d, dest=%0d, trans_id=%0d", 
                         $time, current_header_struct.msg_type, parsed_src_node, parsed_dest_node, parsed_trans_id);
            end
            
            // 监控转发响应
            if (out_resp_accept) begin
                noc_header_t resp_header_struct;
                resp_header_struct = noc_header_t'(resp_header_r);
                $display("@%0t: [L2CACHE_NOC] Forward Response: type=0x%h, status=%0d, trans_id=%0d", 
                         $time, resp_header_struct.msg_type, resp_status_r, resp_header_struct.trans_id);
            end
            
            // 监控控制器通信
            if (noc_if.req_valid && noc_if.req_ready) begin
                $display("@%0t: [L2CACHE_NOC] Controller Request: type=0x%h, addr=0x%h, size=%0d", 
                         $time, parsed_header.msg_type, parsed_addr, parsed_size);
            end
            
            if (noc_if.resp_valid && noc_if.resp_ready) begin
                noc_header_t resp_header_struct;
                resp_header_struct = noc_header_t'(resp_header_r);
                $display("@%0t: [L2CACHE_NOC] Controller Response: type=0x%h, status=%0d", 
                         $time, resp_header_struct.msg_type, resp_status_r);
            end
            
            // 监控队列状态
            if (req_queue_full_r) begin
                $display("@%0t: [L2CACHE_NOC] Warning: Request queue full", $time);
            end
            
            if (req_queue_empty_r && !noc_external_if.s_req_valid) begin
                $display("@%0t: [L2CACHE_NOC] Info: Request queue empty", $time);
            end
        end
    end
    endgenerate

endmodule : rvgpu_l2cache_noc_adapter

`endif // RVGPU_L2CACHE_NOC_ADAPTER_SV 