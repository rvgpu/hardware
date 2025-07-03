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

`ifndef RVGPU_AXI_ADAPTER_SV
`define RVGPU_AXI_ADAPTER_SV

`include "rvgpu_control_unit_pkg.svh"
`include "rvgpu_control_unit_if.svh"

`ifndef RVGPU_CONTROL_UNIT_PKG_IMPORTED
`define RVGPU_CONTROL_UNIT_PKG_IMPORTED
import rvgpu_control_unit_pkg::*;
`endif // RVGPU_CONTROL_UNIT_PKG_IMPORTED

//=============================================================================
// RVGPU AXI-Lite to Control Interface Adapter
// 实现标准AXI4-Lite协议到内部control_if的转换
//=============================================================================
module rvgpu_axi_adapter #(
    parameter int ADDR_WIDTH = 64,
    parameter int DATA_WIDTH = 64
) (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // AXI4-Lite Host Interface
    host_if.slave axi_if,
    
    // Control Interface to Command Processor
    control_if.axiadapter_port ctrl_if
);

    //=============================================================================
    // Local Parameters and Types
    //=============================================================================
    
    // AXI4-Lite写通道状态机
    typedef enum logic [2:0] {
        W_IDLE      = 3'b000,   // 空闲状态
        W_ADDR      = 3'b001,   // 接收写地址
        W_DATA      = 3'b010,   // 接收写数据
        W_CTRL_REQ  = 3'b011,   // 发送控制请求
        W_CTRL_RESP = 3'b100,   // 等待控制响应
        W_BRESP     = 3'b101    // 发送写响应
    } write_state_t;
    
    // AXI4-Lite读通道状态机
    typedef enum logic [2:0] {
        R_IDLE      = 3'b000,   // 空闲状态
        R_ADDR      = 3'b001,   // 接收读地址
        R_CTRL_REQ  = 3'b010,   // 发送控制请求
        R_CTRL_RESP = 3'b011,   // 等待控制响应
        R_DATA      = 3'b100    // 发送读数据
    } read_state_t;
    
    //=============================================================================
    // Internal Signals and Registers
    //=============================================================================
    
    // 状态机寄存器
    write_state_t write_state_q, write_state_d;
    read_state_t  read_state_q,  read_state_d;
    
    // 写事务寄存器
    logic [ADDR_WIDTH-1:0]      write_addr_q, write_addr_d;
    logic [DATA_WIDTH-1:0]      write_data_q, write_data_d;
    logic [DATA_WIDTH/8-1:0]    write_strb_q, write_strb_d;
    
    // 读事务寄存器
    logic [ADDR_WIDTH-1:0]      read_addr_q, read_addr_d;
    logic [DATA_WIDTH-1:0]      read_data_q, read_data_d;
    logic [1:0]                 read_resp_q, read_resp_d;
    
    // 控制接口仲裁信号
    logic write_ctrl_req, read_ctrl_req;
    logic ctrl_req_is_write;
    logic current_op_is_write;  // 记住当前操作是写还是读
    
    //=============================================================================
    // 1. 时序逻辑 - 状态寄存器更新
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // 复位所有状态寄存器
            write_state_q <= W_IDLE;
            read_state_q  <= R_IDLE;
            
            write_addr_q <= '0;
            write_data_q <= '0;
            write_strb_q <= '0;
            
            read_addr_q <= '0;
            read_data_q <= '0;
            read_resp_q <= 2'b00;
            
            current_op_is_write <= 1'b0;  // 初始化操作类型
        end else begin
            // 更新状态寄存器
            write_state_q <= write_state_d;
            read_state_q  <= read_state_d;
            
            write_addr_q <= write_addr_d;
            write_data_q <= write_data_d;
            write_strb_q <= write_strb_d;
            
            read_addr_q <= read_addr_d;
            read_data_q <= read_data_d;
            read_resp_q <= read_resp_d;
            
            // 更新操作类型
            if (write_ctrl_req) begin
                current_op_is_write <= 1'b1;
            end else if (read_ctrl_req) begin
                current_op_is_write <= 1'b0;
            end
        end
    end
    
    //=============================================================================
    // 2.组合逻辑 - 写通道状态转换
    //=============================================================================
    
    always_comb begin
        // 默认保持当前状态和寄存器值
        write_state_d = write_state_q;
        write_addr_d  = write_addr_q;
        write_data_d  = write_data_q;
        write_strb_d  = write_strb_q;
        
        write_ctrl_req = 1'b0;
        
        case (write_state_q)
            W_IDLE: begin
                if (axi_if.awvalid) begin
                    // 接收到写地址请求
                    write_state_d = W_ADDR;
                end
            end
            
            W_ADDR: begin
                if (axi_if.awvalid && axi_if.awready) begin
                    // 地址握手完成，保存地址信息
                    write_addr_d = axi_if.awaddr;
                    
                    // AXI-Lite: 直接转到数据状态
                    write_state_d = W_DATA;
                end
            end
            
            W_DATA: begin
                if (axi_if.wvalid && axi_if.wready) begin
                    // 数据握手完成，保存数据信息
                    write_data_d = axi_if.wdata;
                    write_strb_d = axi_if.wstrb;
                    write_state_d = W_CTRL_REQ;
                end
            end
            
            W_CTRL_REQ: begin
                write_ctrl_req = 1'b1;
                if (ctrl_if.req_valid && ctrl_if.req_ready) begin
                    // 控制请求发送成功
                    write_state_d = W_CTRL_RESP;
                end
            end
            
            W_CTRL_RESP: begin
                if (ctrl_if.resp_valid && ctrl_if.resp_ready) begin
                    // 控制响应收到
                    write_state_d = W_BRESP;
                end
            end
            
            W_BRESP: begin
                if (axi_if.bvalid && axi_if.bready) begin
                    // 写响应握手完成
                    write_state_d = W_IDLE;
                end
            end
            
            default: begin
                write_state_d = W_IDLE;
            end
        endcase
    end
    
    //=============================================================================
    // 2. 组合逻辑 - 读通道状态转换
    //=============================================================================
    
    always_comb begin
        // 默认保持当前状态和寄存器值
        read_state_d = read_state_q;
        read_addr_d  = read_addr_q;
        read_data_d  = read_data_q;
        read_resp_d  = read_resp_q;
        
        read_ctrl_req = 1'b0;
        
        case (read_state_q)
            R_IDLE: begin
                if (axi_if.arvalid) begin
                    // 接收到读地址请求
                    read_state_d = R_ADDR;
                end
            end
            
            R_ADDR: begin
                if (axi_if.arvalid && axi_if.arready) begin
                    // 地址握手完成，保存地址信息
                    read_addr_d = axi_if.araddr;
                    read_state_d = R_CTRL_REQ;
                end
            end
            
            R_CTRL_REQ: begin
                read_ctrl_req = 1'b1;
                if (ctrl_if.req_valid && ctrl_if.req_ready) begin
                    // 控制请求发送成功
                    read_state_d = R_CTRL_RESP;
                end
            end
            
            R_CTRL_RESP: begin
                if (ctrl_if.resp_valid && ctrl_if.resp_ready) begin
                    // 控制响应收到，保存响应数据
                    read_data_d = ctrl_if.resp_data;
                    read_resp_d = ctrl_if.resp_status;
                    read_state_d = R_DATA;
                end
            end
            
            R_DATA: begin
                if (axi_if.rvalid && axi_if.rready) begin
                    // 读数据握手完成
                    read_state_d = R_IDLE;
                end
            end
            
            default: begin
                read_state_d = R_IDLE;
            end
        endcase
    end
    
    //=============================================================================
    // 控制接口仲裁逻辑
    //=============================================================================
    
    always_comb begin
        // 简单的固定优先级仲裁：写优先
        if (write_ctrl_req) begin
            ctrl_req_is_write = 1'b1;
        end else if (read_ctrl_req) begin
            ctrl_req_is_write = 1'b0;
        end else begin
            ctrl_req_is_write = 1'b0;
        end
    end
    
    //=============================================================================
    // 3. 组合逻辑 - AXI接口输出
    //=============================================================================
    
    // 写地址通道输出
    always_comb begin
        axi_if.awready = 1'b0;
        
        case (write_state_q)
            W_ADDR: begin
                axi_if.awready = 1'b1;
            end
            default: begin
                axi_if.awready = 1'b0;
            end
        endcase
    end
    
    // 写数据通道输出
    always_comb begin
        axi_if.wready = 1'b0;
        
        case (write_state_q)
            W_DATA: begin
                axi_if.wready = 1'b1;
            end
            default: begin
                axi_if.wready = 1'b0;
            end
        endcase
    end
    
    // 写响应通道输出
    always_comb begin
        axi_if.bvalid = 1'b0;
        axi_if.bresp  = 2'b00;
        
        case (write_state_q)
            W_BRESP: begin
                axi_if.bvalid = 1'b1;
                axi_if.bresp  = ctrl_if.resp_status;
            end
            default: begin
                axi_if.bvalid = 1'b0;
                axi_if.bresp  = 2'b00;
            end
        endcase
    end
    
    // 读地址通道输出
    always_comb begin
        axi_if.arready = 1'b0;
        
        case (read_state_q)
            R_ADDR: begin
                axi_if.arready = 1'b1;
            end
            default: begin
                axi_if.arready = 1'b0;
            end
        endcase
    end
    
    // 读数据通道输出
    always_comb begin
        axi_if.rvalid = 1'b0;
        axi_if.rdata  = '0;
        axi_if.rresp  = 2'b00;
        axi_if.rlast  = 1'b0;
        
        case (read_state_q)
            R_DATA: begin
                axi_if.rvalid = 1'b1;
                axi_if.rdata  = read_data_q;
                axi_if.rresp  = read_resp_q;
                axi_if.rlast  = 1'b1;  // AXI-Lite单次传输总是最后一拍
            end
            default: begin
                axi_if.rvalid = 1'b0;
                axi_if.rdata  = '0;
                axi_if.rresp  = 2'b00;
                axi_if.rlast  = 1'b0;
            end
        endcase
    end
    
    //=============================================================================
    // 2. 组合逻辑 - 控制接口输出
    //=============================================================================
    
    always_comb begin
        ctrl_if.req_valid = 1'b0;
        ctrl_if.req_addr  = '0;
        ctrl_if.req_data  = '0;
        ctrl_if.req_strb  = '0;
        ctrl_if.req_we    = 1'b0;
        ctrl_if.resp_ready = 1'b0;
        
        if (write_ctrl_req) begin
            // 写请求
            ctrl_if.req_valid = 1'b1;
            ctrl_if.req_addr  = write_addr_q;
            ctrl_if.req_data  = write_data_q;
            ctrl_if.req_strb  = write_strb_q;
            ctrl_if.req_we    = 1'b1;
            
        end else if (read_ctrl_req) begin
            // 读请求
            ctrl_if.req_valid = 1'b1;
            ctrl_if.req_addr  = read_addr_q;
            ctrl_if.req_data  = '0;
            ctrl_if.req_strb  = {(DATA_WIDTH/8){1'b1}};  // 读操作全选择
            ctrl_if.req_we    = 1'b0;
        end
        
        // 设置resp_ready基于当前操作类型和状态
        if (current_op_is_write && write_state_q == W_CTRL_RESP) begin
            ctrl_if.resp_ready = 1'b1;
        end else if (!current_op_is_write && read_state_q == R_CTRL_RESP) begin
            ctrl_if.resp_ready = 1'b1;
        end
    end

endmodule : rvgpu_axi_adapter

`endif // RVGPU_AXI_ADAPTER_SV 