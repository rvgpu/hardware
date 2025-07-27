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
//=============================================================================
module rvgpu_axi_adapter #(
    parameter host_axi_config_t HOST_CONFIG = DEFAULT_HOST_AXI_CONFIG
) (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // AXI4-Lite Host Interface
    host_if.slave axi_if,
    
    // Control Interface to Command Processor
    control_if.axiadapter_port ctrl_cp
);

    //=============================================================================
    // Local Parameters and Types
    //=============================================================================
    
    // 状态位编码 - 状态值直接对应AXI信号输出
    // 例如：STATE_EXPECT_RD=5'b10000 表示 axi_if.arready=1, 其他信号=0
    localparam STATE_BITS       = 5;
    localparam STATE_EXPECT_RD  = 5'b10000;  // 等待读地址 (arready=1)
    localparam STATE_READ_DATA  = 5'b00000;  // 读数据阶段 (所有信号=0)
    localparam STATE_READ_RESP  = 5'b00010;  // 读响应阶段 (rvalid=1)
    localparam STATE_EXPECT_WR  = 5'b01100;  // 等待写地址和数据 (awready=1, wready=1)
    localparam STATE_EXPECT_AW  = 5'b01000;  // 等待写地址 (awready=1)
    localparam STATE_EXPECT_W   = 5'b00100;  // 等待写数据 (wready=1)
    localparam STATE_WRITE_RESP = 5'b00001;  // 写响应阶段 (bvalid=1)

    // 状态位定义 - 每个位对应一个AXI信号
    localparam STATE_BIT_AR = 4;  // 读地址就绪 (axi_if.arready)
    localparam STATE_BIT_AW = 3;  // 写地址就绪 (axi_if.awready)
    localparam STATE_BIT_W  = 2;  // 写数据就绪 (axi_if.wready)
    localparam STATE_BIT_R  = 1;  // 读数据有效 (axi_if.rvalid)
    localparam STATE_BIT_B  = 0;  // 写响应有效 (axi_if.bvalid)

    //=============================================================================
    // Internal Signals and Registers
    //=============================================================================
    
    // 状态机寄存器
    logic [STATE_BITS-1:0]  state_r, state_nxt;
    logic                   state_clken;
    
    // 地址和数据寄存器
    reg [HOST_CONFIG.addr_width-1:0]    addr_r, addr_nxt;
    reg [HOST_CONFIG.data_width-1:0]    data_r, data_nxt;
    reg [HOST_CONFIG.strb_width-1:0]  strb_r, strb_nxt;
    reg [1:0]               resp_r, resp_nxt;
    
    // 控制信号
    reg                     addr_clken;
    reg                     data_clken;
    reg                     resp_clken;
    reg                     ctrl_we_r, ctrl_we_nxt;
    reg                     ctrl_re;
    
    //=============================================================================
    // 握手信号定义
    //=============================================================================
    
    wire aw_accept = axi_if.awvalid && axi_if.awready;
    wire w_accept  = axi_if.wvalid  && axi_if.wready;
    wire b_accept  = axi_if.bvalid  && axi_if.bready;
    wire ar_accept = axi_if.arvalid && axi_if.arready;
    wire r_accept  = axi_if.rvalid  && axi_if.rready;

    //=============================================================================
    // 组合逻辑 - 状态机和输出控制
    //=============================================================================
    
    always_comb begin : comb_logic
        // 默认值
        state_nxt = state_r;
        state_clken = 1'b0;
        addr_clken = 1'b0;
        data_clken = 1'b0;
        resp_clken = 1'b0;
        ctrl_we_nxt = 1'b0;
        ctrl_re = 1'b0;
        
        // AXI接口输出（基于状态位）
        axi_if.arready = state_r[STATE_BIT_AR];
        axi_if.awready = state_r[STATE_BIT_AW];
        axi_if.wready  = state_r[STATE_BIT_W ];
        axi_if.rvalid  = state_r[STATE_BIT_R ];
        axi_if.bvalid  = state_r[STATE_BIT_B ];
        
        // 读数据输出
        axi_if.rdata = data_r;
        axi_if.rresp = resp_r;
        axi_if.rlast = 1'b1;  // AXI-Lite总是单次传输
        
        // 写响应输出
        axi_if.bresp = resp_r;
        
        // 控制接口输出
        ctrl_cp.ctrl_we = ctrl_we_r;
        ctrl_cp.ctrl_addr = addr_r;
        ctrl_cp.ctrl_wdata = data_r;

        case (state_r)
            STATE_EXPECT_RD: begin
                // 等待读地址或写请求
                if (ar_accept) begin
                    state_nxt = STATE_READ_DATA;
                    state_clken = 1'b1;
                    addr_clken = 1'b1;
                    resp_clken = 1'b1;
                end else if (axi_if.arvalid) begin
                    // 有读请求但未握手，保持状态
                    state_nxt = STATE_EXPECT_RD;
                end else if (axi_if.awvalid || axi_if.wvalid) begin
                    state_nxt = STATE_EXPECT_WR;
                    state_clken = 1'b1;
                end
            end

            STATE_READ_DATA: begin
                // 读数据阶段：直接获取CP数据并转到响应状态
                ctrl_re = 1'b1;
                data_clken = 1'b1;
                state_nxt = STATE_READ_RESP;
                state_clken = 1'b1;
            end

            STATE_READ_RESP: begin
                // 读响应阶段：等待主机接收数据
                if (r_accept) begin
                    state_nxt = STATE_EXPECT_RD;
                    state_clken = 1'b1;
                end
            end

            STATE_EXPECT_WR: begin
                // 等待写地址和数据
                if (aw_accept && w_accept) begin
                    // 同时收到地址和数据，直接发送给CP
                    state_nxt = STATE_WRITE_RESP;
                    state_clken = 1'b1;
                    addr_clken = 1'b1;
                    data_clken = 1'b1;
                    resp_clken = 1'b1;
                    ctrl_we_nxt = 1'b1;
                end else if (aw_accept) begin
                    // 只收到地址
                    state_nxt = STATE_EXPECT_W;
                    state_clken = 1'b1;
                    addr_clken = 1'b1;
                    resp_clken = 1'b1;
                end else if (w_accept) begin
                    // 只收到数据
                    state_nxt = STATE_EXPECT_AW;
                    state_clken = 1'b1;
                    data_clken = 1'b1;
                end else if (axi_if.awvalid || axi_if.wvalid) begin
                    // 有写请求但未握手，保持状态
                    state_nxt = STATE_EXPECT_WR;
                end else if (axi_if.arvalid) begin
                    // 切换到读状态
                    state_nxt = STATE_EXPECT_RD;
                    state_clken = 1'b1;
                end
            end

            STATE_EXPECT_AW: begin
                // 等待写地址
                if (aw_accept) begin
                    state_nxt = STATE_WRITE_RESP;
                    state_clken = 1'b1;
                    addr_clken = 1'b1;
                    resp_clken = 1'b1;
                    ctrl_we_nxt = 1'b1;
                end
            end

            STATE_EXPECT_W: begin
                // 等待写数据
                if (w_accept) begin
                    state_nxt = STATE_WRITE_RESP;
                    state_clken = 1'b1;
                    data_clken = 1'b1;
                    ctrl_we_nxt = 1'b1;
                end
            end

            STATE_WRITE_RESP: begin
                // 写响应阶段：等待主机接收响应
                if (b_accept) begin
                    state_nxt = STATE_EXPECT_RD;
                    state_clken = 1'b1;
                end else begin
                    // 保持写请求有效直到响应完成
                    ctrl_we_nxt = 1'b1;
                end
            end

            default: begin
                state_nxt = STATE_EXPECT_RD;
                state_clken = 1'b1;
            end
        endcase

        // 地址更新逻辑
        if (aw_accept) begin
            addr_nxt = axi_if.awaddr;
        end else if (ar_accept) begin
            addr_nxt = axi_if.araddr;
        end else begin
            addr_nxt = addr_r;
        end

        // 数据更新逻辑
        if (w_accept) begin
            data_nxt = axi_if.wdata;
            strb_nxt = axi_if.wstrb;
        end else if (ctrl_re) begin
            data_nxt = ctrl_cp.ctrl_rdata;  // 直接从CP获取读数据
            strb_nxt = {(HOST_CONFIG.strb_width){1'b1}};
        end else begin
            data_nxt = data_r;
            strb_nxt = strb_r;
        end

        // 响应更新逻辑
        if (aw_accept || ar_accept) begin
            resp_nxt = 2'b00;  // OKAY
        end else begin
            resp_nxt = resp_r;
        end
    end

    //=============================================================================
    // 时序逻辑 - 寄存器更新
    //=============================================================================
    
    // 复位逻辑 - 同步复位
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_r <= STATE_EXPECT_RD;
            ctrl_we_r <= 1'b0;
            addr_r <= {HOST_CONFIG.addr_width{1'b0}};
        end else begin
            if (state_clken) begin
                state_r <= state_nxt;
            end
            ctrl_we_r <= ctrl_we_nxt;
            if (addr_clken) begin
                addr_r <= addr_nxt;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (data_clken) begin
            data_r <= data_nxt;
            strb_r <= strb_nxt;
        end
        if (resp_clken) begin
            resp_r <= resp_nxt;
        end
    end

endmodule : rvgpu_axi_adapter

`endif // RVGPU_AXI_ADAPTER_SV 