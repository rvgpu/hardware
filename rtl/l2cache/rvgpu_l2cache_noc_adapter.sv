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
    // Local Parameters and Types
    //=============================================================================
    
    // 从配置中提取的本地参数
    localparam int NOC_HEADER_WIDTH = L2CACHE_CONFIG.noc_header_width;
    localparam int NOC_DATA_WIDTH = L2CACHE_CONFIG.noc_data_width;
    
    // 控制器状态机参数
    localparam int CTRL_STATE_BITS = 2;
    localparam int CTRL_STATE_IDLE = 2'b00;
    localparam int CTRL_STATE_PROCESS_REQ = 2'b01;
    localparam int CTRL_STATE_WAIT_RESP = 2'b10;
    
    // 请求队列深度
    localparam int REQ_QUEUE_DEPTH = 16;
    localparam int REQ_QUEUE_BITS = $clog2(REQ_QUEUE_DEPTH);
    
    // 响应状态
    localparam int RESP_OKAY = 2'b00;
    localparam int RESP_SLVERR = 2'b10;
    
    //=============================================================================
    // Internal Registers and Signals
    //=============================================================================
    
    // 控制器状态机寄存器
    logic [CTRL_STATE_BITS-1:0] ctrl_state_r, ctrl_state_nxt;
    
    // 请求队列
    typedef struct packed {
        logic [NOC_HEADER_WIDTH-1:0] header;
        logic [NOC_DATA_WIDTH-1:0] data;
        logic [NOC_DATA_WIDTH/8-1:0] strb;
        logic last;
        logic is_valid;  // 是否为有效请求（非转发）
    } noc_request_t;
    
    noc_request_t req_queue [REQ_QUEUE_DEPTH];
    logic [REQ_QUEUE_BITS-1:0] req_queue_head_r, req_queue_head_nxt;
    logic [REQ_QUEUE_BITS-1:0] req_queue_tail_r, req_queue_tail_nxt;
    logic req_queue_full_r, req_queue_full_nxt;
    logic req_queue_empty_r, req_queue_empty_nxt;
    
    // 响应队列
    typedef struct packed {
        logic [NOC_HEADER_WIDTH-1:0] header;
        logic [NOC_DATA_WIDTH-1:0] data;
        logic [1:0] status;
        logic last;
    } noc_response_t;
    
    noc_response_t resp_queue [REQ_QUEUE_DEPTH];
    logic [REQ_QUEUE_BITS-1:0] resp_queue_head_r, resp_queue_head_nxt;
    logic [REQ_QUEUE_BITS-1:0] resp_queue_tail_r, resp_queue_tail_nxt;
    logic resp_queue_full_r, resp_queue_full_nxt;
    logic resp_queue_empty_r, resp_queue_empty_nxt;
    
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
    // wire out_resp_accept = noc_external_if.m_resp_valid && noc_external_if.m_resp_ready;
    
    //=============================================================================
    // 组合逻辑 - 状态机和输出控制
    //=============================================================================
    
    always_comb begin : comb_logic
        // 默认值
        ctrl_state_nxt = ctrl_state_r;
        req_queue_head_nxt = req_queue_head_r;
        req_queue_tail_nxt = req_queue_tail_r;
        req_queue_full_nxt = req_queue_full_r;
        req_queue_empty_nxt = req_queue_empty_r;
        resp_queue_head_nxt = resp_queue_head_r;
        resp_queue_tail_nxt = resp_queue_tail_r;
        resp_queue_full_nxt = resp_queue_full_r;
        resp_queue_empty_nxt = resp_queue_empty_r;
        
        // 外部NOC接口输出默认值
        // 队列未满时接受新请求，队列满时拉低ready信号
        noc_external_if.s_req_ready = !req_queue_full_r;
        noc_external_if.s_resp_valid = 1'b0;
        noc_external_if.s_resp_header = (!resp_queue_empty_r) ? resp_queue[resp_queue_head_r].header : '0;
        noc_external_if.s_resp_data = (!resp_queue_empty_r) ? resp_queue[resp_queue_head_r].data : '0;
        noc_external_if.s_resp_status = (!resp_queue_empty_r) ? resp_queue[resp_queue_head_r].status : '0;
        noc_external_if.s_resp_last = (!resp_queue_empty_r) ? resp_queue[resp_queue_head_r].last : 1'b0;
        
        // 控制器接口输出默认值
        noc_if.req_valid = 1'b0;
        noc_if.req_header = (!req_queue_empty_r) ? req_queue[req_queue_head_r].header : '0;
        noc_if.req_data = (!req_queue_empty_r) ? req_queue[req_queue_head_r].data : '0;
        noc_if.req_strb = (!req_queue_empty_r) ? req_queue[req_queue_head_r].strb : '0;
        noc_if.req_last = (!req_queue_empty_r) ? req_queue[req_queue_head_r].last : 1'b0;
        
        noc_if.resp_ready = 1'b1;
        
        // 解析当前请求（从队列头部读取）
        parsed_header = (!req_queue_empty_r) ? noc_header_t'(req_queue[req_queue_head_r].header) : '0;
        parsed_addr = (!req_queue_empty_r) ? req_queue[req_queue_head_r].data[63:0] : '0;
        parsed_size = (!req_queue_empty_r) ? req_queue[req_queue_head_r].data[71:64] : '0;
        parsed_trans_id = parsed_header.trans_id;
        parsed_src_node = parsed_header.src_node;
        parsed_dest_node = parsed_header.dest_node;
        
        // NOC接口逻辑：直接发送响应（如果有）
        if (!resp_queue_empty_r) begin
            noc_external_if.s_resp_valid = 1'b1;
            noc_external_if.s_resp_header = resp_queue[resp_queue_head_r].header;
            noc_external_if.s_resp_data = resp_queue[resp_queue_head_r].data;
            noc_external_if.s_resp_status = resp_queue[resp_queue_head_r].status;
            noc_external_if.s_resp_last = resp_queue[resp_queue_head_r].last;
            
            if (resp_accept) begin
                // 更新响应队列头部
                resp_queue_head_nxt = resp_queue_head_r + 1;
                if (resp_queue_head_nxt == resp_queue_tail_r) begin
                    resp_queue_empty_nxt = 1'b1;
                end
                resp_queue_full_nxt = 1'b0;
            end
        end
        
        // 控制器状态机
        case (ctrl_state_r)
            CTRL_STATE_IDLE: begin
                // 控制器空闲状态：处理队列中的请求
                if (!req_queue_empty_r) begin
                    if (req_queue[req_queue_head_r].is_valid) begin
                        // 有效请求：处理
                        ctrl_state_nxt = CTRL_STATE_PROCESS_REQ;
                    end else begin
                        // 无效请求：直接丢弃并更新队列头部
                        req_queue_head_nxt = req_queue_head_r + 1;
                        if (req_queue_head_nxt == req_queue_tail_r) begin
                            req_queue_empty_nxt = 1'b1;
                        end
                        req_queue_full_nxt = 1'b0;
                    end
                end
            end
            
            CTRL_STATE_PROCESS_REQ: begin
                // 处理控制器请求状态
                noc_if.req_valid = 1'b1;
                noc_if.req_header = req_queue[req_queue_head_r].header;
                noc_if.req_data = req_queue[req_queue_head_r].data;
                noc_if.req_strb = req_queue[req_queue_head_r].strb;
                noc_if.req_last = req_queue[req_queue_head_r].last;
                
                if (noc_if.req_ready) begin
                    ctrl_state_nxt = CTRL_STATE_WAIT_RESP;
                    $display("@%0t: [L2CACHE_NOC] req_header=0x%h, req_data=0x%h, req_strb=0x%h, req_last=%0d", 
                        $time, noc_if.req_header, noc_if.req_data, noc_if.req_strb, noc_if.req_last);
                end
            end
            
            CTRL_STATE_WAIT_RESP: begin
                // 等待控制器响应状态
                noc_if.resp_ready = 1'b1;
                
                if (noc_if.resp_valid) begin
                    // 将响应加入队列并更新队列状态
                    resp_queue[resp_queue_tail_r].header = noc_if.resp_header;
                    resp_queue[resp_queue_tail_r].data = noc_if.resp_data;
                    resp_queue[resp_queue_tail_r].status = noc_if.resp_status;
                    resp_queue[resp_queue_tail_r].last = noc_if.resp_last;
                    
                    resp_queue_tail_nxt = resp_queue_tail_r + 1;
                    resp_queue_empty_nxt = 1'b0;
                    if (resp_queue_tail_nxt == resp_queue_head_r) begin
                        resp_queue_full_nxt = 1'b1;
                    end
                    
                    // 更新请求队列头部
                    req_queue_head_nxt = req_queue_head_r + 1;
                    if (req_queue_head_nxt == req_queue_tail_r) begin
                        req_queue_empty_nxt = 1'b1;
                    end
                    req_queue_full_nxt = 1'b0;
                    
                    ctrl_state_nxt = CTRL_STATE_IDLE;
                end
            end
            
            default: begin
                ctrl_state_nxt = CTRL_STATE_IDLE;
            end
        endcase
        
        // 请求队列管理：所有外部请求都进入队列
        // 使用时序逻辑确保每个请求只被处理一次
        if (noc_external_if.s_req_valid && noc_external_if.s_req_ready) begin
            // 将新请求加入队列
            req_queue[req_queue_tail_r].header = noc_external_if.s_req_header;
            req_queue[req_queue_tail_r].data = noc_external_if.s_req_data;
            req_queue[req_queue_tail_r].strb = noc_external_if.s_req_strb;
            req_queue[req_queue_tail_r].last = noc_external_if.s_req_last;
            // 判断是否为有效请求（当前节点支持的消息类型）
            req_queue[req_queue_tail_r].is_valid = (noc_external_if.s_req_header[31:24] == MSG_MEM_READ_REQ) ||
                                                  (noc_external_if.s_req_header[31:24] == MSG_MEM_WRITE_REQ);
            
            // 更新队列状态
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
            ctrl_state_r <= CTRL_STATE_IDLE;
            req_queue_head_r <= '0;
            req_queue_tail_r <= '0;
            req_queue_full_r <= 1'b0;
            req_queue_empty_r <= 1'b1;
            resp_queue_head_r <= '0;
            resp_queue_tail_r <= '0;
            resp_queue_full_r <= 1'b0;
            resp_queue_empty_r <= 1'b1;
        end else begin
            // 状态更新
            ctrl_state_r <= ctrl_state_nxt;
            req_queue_head_r <= req_queue_head_nxt;
            req_queue_tail_r <= req_queue_tail_nxt;
            req_queue_full_r <= req_queue_full_nxt;
            req_queue_empty_r <= req_queue_empty_nxt;
            resp_queue_head_r <= resp_queue_head_nxt;
            resp_queue_tail_r <= resp_queue_tail_nxt;
            resp_queue_full_r <= resp_queue_full_nxt;
            resp_queue_empty_r <= resp_queue_empty_nxt;
        end
    end
    
    //=============================================================================
    // 调试输出 (仅在仿真时)
    //=============================================================================
    
    generate
    if (L2CACHE_CONFIG.debug_enable) begin : gen_debug
        // 队列状态跟踪寄存器
        logic prev_queue_empty;
        
        always_ff @(posedge clk) begin
            if (!rst_n) begin
                prev_queue_empty <= 1'b1;
            end else begin
                prev_queue_empty <= req_queue_empty_r;
            end
        end
        
        always_ff @(posedge clk) begin
            // 监控外部请求
            if (req_accept) begin
                noc_header_t req_header_struct;
                noc_msg_type_t msg_type;
                noc_node_id_t src_node, dest_node;
                req_header_struct = noc_header_t'(noc_external_if.s_req_header);
                msg_type = noc_msg_type_t'(req_header_struct.msg_type);
                src_node = noc_node_id_t'(req_header_struct.src_node);
                dest_node = noc_node_id_t'(req_header_struct.dest_node);
                $display("@%0t: [L2CACHE_NOC] External Request: type=0x%h, src=%0d, dest=%0d, trans_id=%0d", 
                         $time, req_header_struct.msg_type, src_node, dest_node, req_header_struct.trans_id);
            end
            
            // 监控外部响应
            if (resp_accept) begin
                noc_header_t resp_header_struct;
                resp_header_struct = noc_header_t'(resp_queue[resp_queue_head_r].header);
                $display("@%0t: [L2CACHE_NOC] External Response: type=0x%h, status=%0d, trans_id=%0d", 
                         $time, resp_header_struct.msg_type, resp_queue[resp_queue_head_r].status, resp_header_struct.trans_id);
            end
            
            // 监控控制器通信
            if (noc_if.req_valid && noc_if.req_ready) begin
                noc_header_t current_header_struct;
                current_header_struct = noc_header_t'(req_queue[req_queue_head_r].header);
                $display("@%0t: [L2CACHE_NOC] Controller Request: type=0x%h, addr=0x%h, size=%0d", 
                         $time, current_header_struct.msg_type, parsed_addr, parsed_size);
            end
            
            if (noc_if.resp_valid && noc_if.resp_ready) begin
                noc_header_t resp_header_struct;
                resp_header_struct = noc_header_t'(noc_if.resp_header);
                $display("@%0t: [L2CACHE_NOC] Controller Response: type=0x%h, status=%0d", 
                         $time, resp_header_struct.msg_type, noc_if.resp_status);
            end
            
            // 监控队列状态
            if (req_queue_full_r) begin
                $display("@%0t: [L2CACHE_NOC] Warning: Request queue full", $time);
            end
            
            // 只在队列从非空变为空时打印一次
            if (!prev_queue_empty && req_queue_empty_r && !noc_external_if.s_req_valid) begin
                $display("@%0t: [L2CACHE_NOC] Info: Request queue became empty", $time);
            end
        end
    end
    endgenerate

endmodule : rvgpu_l2cache_noc_adapter

`endif // RVGPU_L2CACHE_NOC_ADAPTER_SV 