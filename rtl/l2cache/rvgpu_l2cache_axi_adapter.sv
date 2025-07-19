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

`ifndef RVGPU_L2CACHE_AXI_ADAPTER_SV
`define RVGPU_L2CACHE_AXI_ADAPTER_SV

`include "rvgpu_l2cache_pkg.svh"
`include "rvgpu_l2cache_if.svh"
`include "rvgpu_interface_axi.svh"

`ifndef RVGPU_L2CACHE_PKG_IMPORTED
`define RVGPU_L2CACHE_PKG_IMPORTED
import rvgpu_l2cache_pkg::*;
`endif // RVGPU_L2CACHE_PKG_IMPORTED

//=============================================================================
// RVGPU L2 Cache AXI Adapter
// 
// 主要功能：
// 1. AXI4协议转换
// 2. 读写请求管理
// 3. 突发传输支持
// 4. 事务ID管理
// 5. 错误处理和状态报告
//=============================================================================

module rvgpu_l2cache_axi_adapter #(
    parameter l2cache_config_t L2CACHE_CONFIG = DEFAULT_L2CACHE_CONFIG
) (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // Controller Interface
    l2cache_axi_if.axi_adapter axi_if,
    
    // Memory Interface
    memory_if.master mem_if
);

    //=============================================================================
    // Local Parameters and Types
    //=============================================================================
    
    // 从配置中提取的本地参数
    localparam int AXI_ADDR_WIDTH = L2CACHE_CONFIG.axi_addr_width;
    localparam int AXI_DATA_WIDTH = L2CACHE_CONFIG.axi_data_width;
    
    // 状态机参数
    localparam int STATE_BITS = 4;
    localparam int STATE_IDLE = 4'b0000;
    localparam int STATE_READ_ADDR = 4'b0001;
    localparam int STATE_READ_DATA = 4'b0010;
    localparam int STATE_WRITE_ADDR = 4'b0100;
    localparam int STATE_WRITE_DATA = 4'b1000;
    
    // 事务队列深度
    localparam int TRANS_QUEUE_DEPTH = 8;
    localparam int TRANS_QUEUE_BITS = $clog2(TRANS_QUEUE_DEPTH);
    
    //=============================================================================
    // Internal Registers and Signals
    //=============================================================================
    
    // 状态机寄存器
    logic [STATE_BITS-1:0] state_r, state_nxt;
    
    // 当前事务寄存器
    logic [AXI_ADDR_WIDTH-1:0] current_addr_r, current_addr_nxt;
    logic [7:0] current_len_r, current_len_nxt;
    logic [2:0] current_size_r, current_size_nxt;
    logic [7:0] current_id_r, current_id_nxt;
    logic [AXI_DATA_WIDTH-1:0] current_data_r, current_data_nxt;
    logic [AXI_DATA_WIDTH/8-1:0] current_strb_r, current_strb_nxt;
    
    // 事务计数器
    logic [7:0] trans_count_r, trans_count_nxt;
    logic [7:0] resp_count_r, resp_count_nxt;
    
    // 事务队列
    typedef struct packed {
        logic [AXI_ADDR_WIDTH-1:0] addr;
        logic [7:0] len;
        logic [2:0] size;
        logic [7:0] id;
        logic read;
    } axi_transaction_t;
    
    axi_transaction_t trans_queue [TRANS_QUEUE_DEPTH];
    logic [TRANS_QUEUE_BITS-1:0] trans_queue_head_r, trans_queue_head_nxt;
    logic [TRANS_QUEUE_BITS-1:0] trans_queue_tail_r, trans_queue_tail_nxt;
    logic trans_queue_full_r, trans_queue_full_nxt;
    logic trans_queue_empty_r, trans_queue_empty_nxt;
    
    // 响应寄存器
    logic [AXI_DATA_WIDTH-1:0] resp_data_r, resp_data_nxt;
    logic [1:0] resp_status_r, resp_status_nxt;
    logic resp_last_r, resp_last_nxt;
    logic [7:0] resp_id_r, resp_id_nxt;
    
    // 地址有效信号寄存器
    logic arvalid_r, arvalid_nxt;
    
    //=============================================================================
    // 握手信号定义
    //=============================================================================
    
    wire read_addr_accept = mem_if.arvalid && mem_if.arready;
    wire read_data_accept = mem_if.rvalid && mem_if.rready;
    wire write_addr_accept = mem_if.awvalid && mem_if.awready;
    wire write_data_accept = mem_if.wvalid && mem_if.wready;
    wire write_resp_accept = mem_if.bvalid && mem_if.bready;
    
    //=============================================================================
    // 组合逻辑 - 状态机和输出控制
    //=============================================================================
    
    always_comb begin : comb_logic
        // 默认值
        state_nxt = state_r;
        current_addr_nxt = current_addr_r;
        current_len_nxt = current_len_r;
        current_size_nxt = current_size_r;
        current_id_nxt = current_id_r;
        current_data_nxt = current_data_r;
        current_strb_nxt = current_strb_r;
        trans_count_nxt = trans_count_r;
        resp_count_nxt = resp_count_r;
        trans_queue_head_nxt = trans_queue_head_r;
        trans_queue_tail_nxt = trans_queue_tail_r;
        trans_queue_full_nxt = trans_queue_full_r;
        trans_queue_empty_nxt = trans_queue_empty_r;
        resp_data_nxt = resp_data_r;
        resp_status_nxt = resp_status_r;
        resp_last_nxt = resp_last_r;
        resp_id_nxt = resp_id_r;
        arvalid_nxt = arvalid_r;
        
        // 内存接口输出默认值
        mem_if.arvalid = 1'b0;
        mem_if.araddr = '0;
        mem_if.arlen = '0;
        mem_if.arsize = '0;
        mem_if.arburst = 2'b01; // INCR
        mem_if.arid = '0;
        
        mem_if.rready = 1'b0;
        
        mem_if.awvalid = 1'b0;
        mem_if.awaddr = '0;
        mem_if.awlen = '0;
        mem_if.awsize = '0;
        mem_if.awburst = 2'b01; // INCR
        mem_if.awid = '0;
        
        mem_if.wvalid = 1'b0;
        mem_if.wdata = '0;
        mem_if.wstrb = '0;
        mem_if.wlast = 1'b0;
        
        mem_if.bready = 1'b0;
        
        // 控制器接口输出默认值
        axi_if.read_req_ready = (state_r == STATE_IDLE) && !trans_queue_full_r;
        axi_if.read_resp_valid = 1'b0;
        axi_if.read_resp_data = resp_data_r;
        axi_if.read_resp_status = resp_status_r;
        axi_if.read_resp_last = resp_last_r;
        axi_if.read_resp_id = resp_id_r;
        
        axi_if.write_req_ready = (state_r == STATE_IDLE) && !trans_queue_full_r;
        axi_if.write_data_ready = 1'b0;
        axi_if.write_resp_valid = 1'b0;
        axi_if.write_resp_status = resp_status_r;
        axi_if.write_resp_id = resp_id_r;
        
        case (state_r)
            STATE_IDLE: begin
                // 空闲状态：处理新请求
                if (axi_if.read_req_valid && axi_if.read_req_ready) begin
                    // 读请求
                    state_nxt = STATE_READ_ADDR;
                    current_addr_nxt = axi_if.read_req_addr;
                    current_len_nxt = axi_if.read_req_len;
                    current_size_nxt = axi_if.read_req_size;
                    current_id_nxt = axi_if.read_req_id;
                    
                    // 发送读地址
                    arvalid_nxt = 1'b1;
                    mem_if.araddr = axi_if.read_req_addr;
                    mem_if.arlen = axi_if.read_req_len;
                    mem_if.arsize = axi_if.read_req_size;
                    mem_if.arid = axi_if.read_req_id;
                end else if (axi_if.write_req_valid && axi_if.write_req_ready) begin
                    // 写请求
                    state_nxt = STATE_WRITE_ADDR;
                    current_addr_nxt = axi_if.write_req_addr;
                    current_len_nxt = axi_if.write_req_len;
                    current_size_nxt = axi_if.write_req_size;
                    current_id_nxt = axi_if.write_req_id;
                    
                    // 发送写地址
                    mem_if.awvalid = 1'b1;
                    mem_if.awaddr = axi_if.write_req_addr;
                    mem_if.awlen = axi_if.write_req_len;
                    mem_if.awsize = axi_if.write_req_size;
                    mem_if.awid = axi_if.write_req_id;
                end else if (axi_if.write_data_valid && axi_if.write_data_ready) begin
                    // 写数据
                    state_nxt = STATE_WRITE_DATA;
                    current_data_nxt = axi_if.write_data;
                    current_strb_nxt = axi_if.write_strb;
                    
                    // 发送写数据
                    mem_if.wvalid = 1'b1;
                    mem_if.wdata = axi_if.write_data;
                    mem_if.wstrb = axi_if.write_strb;
                    mem_if.wlast = axi_if.write_last;
                end
            end
            
            STATE_READ_ADDR: begin
                // 读地址状态
                mem_if.araddr = current_addr_r;
                mem_if.arlen = current_len_r;
                mem_if.arsize = current_size_r;
                mem_if.arid = current_id_r;
                
                if (read_addr_accept) begin
                    // 握手成功，清除arvalid信号
                    arvalid_nxt = 1'b0;
                    state_nxt = STATE_READ_DATA;
                    trans_count_nxt = 0;
                end else begin
                    // 继续发送地址
                    arvalid_nxt = 1'b1;
                end
            end
            
            STATE_READ_DATA: begin
                // 读数据状态
                mem_if.rready = 1'b1;
                
                if (read_data_accept) begin
                    // 接收读数据
                    resp_data_nxt = mem_if.rdata;
                    resp_status_nxt = mem_if.rresp;
                    resp_last_nxt = mem_if.rlast;
                    resp_id_nxt = mem_if.rid;
                    
                    // 发送给控制器
                    axi_if.read_resp_valid = 1'b1;
                    axi_if.read_resp_data = mem_if.rdata;
                    axi_if.read_resp_status = mem_if.rresp;
                    axi_if.read_resp_last = mem_if.rlast;
                    axi_if.read_resp_id = mem_if.rid;
                    
                    trans_count_nxt = trans_count_r + 1;
                    
                    if (mem_if.rlast) begin
                        state_nxt = STATE_IDLE;
                    end
                end
            end
            
            STATE_WRITE_ADDR: begin
                // 写地址状态
                mem_if.awvalid = 1'b1;
                mem_if.awaddr = current_addr_r;
                mem_if.awlen = current_len_r;
                mem_if.awsize = current_size_r;
                mem_if.awid = current_id_r;
                
                if (write_addr_accept) begin
                    state_nxt = STATE_WRITE_DATA;
                    trans_count_nxt = 0;
                end
            end
            
            STATE_WRITE_DATA: begin
                // 写数据状态
                mem_if.wvalid = 1'b1;
                mem_if.wdata = current_data_r;
                mem_if.wstrb = current_strb_r;
                mem_if.wlast = (trans_count_r == current_len_r);
                
                if (write_data_accept) begin
                    trans_count_nxt = trans_count_r + 1;
                    
                    if (trans_count_r == current_len_r) begin
                        // 等待写响应
                        mem_if.bready = 1'b1;
                        
                        if (write_resp_accept) begin
                            // 写响应
                            resp_status_nxt = mem_if.bresp;
                            resp_id_nxt = mem_if.bid;
                            
                            axi_if.write_resp_valid = 1'b1;
                            axi_if.write_resp_status = mem_if.bresp;
                            axi_if.write_resp_id = mem_if.bid;
                            
                            state_nxt = STATE_IDLE;
                        end
                    end else begin
                        // 继续发送数据
                        axi_if.write_data_ready = 1'b1;
                        
                        if (axi_if.write_data_valid) begin
                            current_data_nxt = axi_if.write_data;
                            current_strb_nxt = axi_if.write_strb;
                        end
                    end
                end
            end
            
            default: begin
                // 错误状态
                state_nxt = STATE_IDLE;
                resp_status_nxt = 2'b11; // SLVERR
            end
        endcase
        
        // 事务队列管理
        if (axi_if.read_req_valid && axi_if.read_req_ready) begin
            trans_queue[trans_queue_tail_r].addr = axi_if.read_req_addr;
            trans_queue[trans_queue_tail_r].len = axi_if.read_req_len;
            trans_queue[trans_queue_tail_r].size = axi_if.read_req_size;
            trans_queue[trans_queue_tail_r].id = axi_if.read_req_id;
            trans_queue[trans_queue_tail_r].read = 1'b1;
            
            trans_queue_tail_nxt = trans_queue_tail_r + 1;
            trans_queue_empty_nxt = 1'b0;
            if (trans_queue_tail_nxt == trans_queue_head_r) begin
                trans_queue_full_nxt = 1'b1;
            end
        end
        
        if (axi_if.write_req_valid && axi_if.write_req_ready) begin
            trans_queue[trans_queue_tail_r].addr = axi_if.write_req_addr;
            trans_queue[trans_queue_tail_r].len = axi_if.write_req_len;
            trans_queue[trans_queue_tail_r].size = axi_if.write_req_size;
            trans_queue[trans_queue_tail_r].id = axi_if.write_req_id;
            trans_queue[trans_queue_tail_r].read = 1'b0;
            
            trans_queue_tail_nxt = trans_queue_tail_r + 1;
            trans_queue_empty_nxt = 1'b0;
            if (trans_queue_tail_nxt == trans_queue_head_r) begin
                trans_queue_full_nxt = 1'b1;
            end
        end
        
        // 设置arvalid信号
        mem_if.arvalid = arvalid_r;
    end
    
    //=============================================================================
    // 时序逻辑 - 寄存器更新
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // 复位逻辑
            state_r <= STATE_IDLE;
            current_addr_r <= '0;
            current_len_r <= '0;
            current_size_r <= '0;
            current_id_r <= '0;
            current_data_r <= '0;
            current_strb_r <= '0;
            trans_count_r <= '0;
            resp_count_r <= '0;
            trans_queue_head_r <= '0;
            trans_queue_tail_r <= '0;
            trans_queue_full_r <= 1'b0;
            trans_queue_empty_r <= 1'b1;
            resp_data_r <= '0;
            resp_status_r <= '0;
            resp_last_r <= 1'b0;
            resp_id_r <= '0;
            arvalid_r <= 1'b0;
        end else begin
            // 状态更新
            state_r <= state_nxt;
            current_addr_r <= current_addr_nxt;
            current_len_r <= current_len_nxt;
            current_size_r <= current_size_nxt;
            current_id_r <= current_id_nxt;
            current_data_r <= current_data_nxt;
            current_strb_r <= current_strb_nxt;
            trans_count_r <= trans_count_nxt;
            resp_count_r <= resp_count_nxt;
            trans_queue_head_r <= trans_queue_head_nxt;
            trans_queue_tail_r <= trans_queue_tail_nxt;
            trans_queue_full_r <= trans_queue_full_nxt;
            trans_queue_empty_r <= trans_queue_empty_nxt;
            resp_data_r <= resp_data_nxt;
            resp_status_r <= resp_status_nxt;
            resp_last_r <= resp_last_nxt;
            resp_id_r <= resp_id_nxt;
            arvalid_r <= arvalid_nxt;
        end
    end

endmodule : rvgpu_l2cache_axi_adapter

`endif // RVGPU_L2CACHE_AXI_ADAPTER_SV 