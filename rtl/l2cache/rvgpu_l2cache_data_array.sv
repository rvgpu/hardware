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

`ifndef RVGPU_L2CACHE_DATA_ARRAY_SV
`define RVGPU_L2CACHE_DATA_ARRAY_SV

`include "rvgpu_l2cache_common.svh"
`include "rvgpu_l2cache_if.svh"
`include "rvgpu_sram_if.svh"
`include "rvgpu_l2cache_common.svh"

module rvgpu_l2cache_data_array (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // Controller Interface
    l2cache_data_if.data_array data_if
);

    //=============================================================================
    // Local Parameters and Types
    //=============================================================================
    
    // Data Array State Machine States
    typedef enum logic [1:0] {
        L2CACHE_DATA_STATE_IDLE = 2'b00,        // 空闲状态
        L2CACHE_DATA_STATE_LINE_READ = 2'b01,   // 缓存行读操作 - 发起SRAM读取
        L2CACHE_DATA_STATE_LINE_READ_WAIT = 2'b10, // 缓存行读等待 - 等待SRAM读取完成
        L2CACHE_DATA_STATE_LINE_WRITE = 2'b11   // 缓存行写操作
    } l2cache_data_state_t;
    
    // 数据数组相关参数
    localparam int L2CACHE_DATA_WIDTH = L2CACHE_LINE_WIDTH;
    localparam int L2CACHE_DATA_ADDR_WIDTH = L2CACHE_INDEX_BITS;
    localparam int L2CACHE_DATA_DEPTH = L2CACHE_SETS;
    localparam int L2CACHE_DATA_STATE_BITS = 2;
    
    //=============================================================================
    // Internal Registers and Signals
    //=============================================================================
    
    // 状态机寄存器
    logic [L2CACHE_DATA_STATE_BITS-1:0] state_r, state_nxt;
    
    // 访问请求寄存器
    logic [L2CACHE_DATA_ADDR_WIDTH-1:0] access_index_r, access_index_nxt;
    logic [L2CACHE_WAYS-1:0] access_way_r, access_way_nxt;
    
    // 访问结果寄存器
    logic line_read_done_r, line_read_done_nxt;
    logic line_write_done_r, line_write_done_nxt;
    l2cache_line_t line_read_data_r, line_read_data_nxt;
    
    // SRAM接口信号
    logic [L2CACHE_WAYS-1:0] sram_ce_r, sram_ce_nxt;
    logic [L2CACHE_WAYS-1:0] sram_we_r, sram_we_nxt;
    logic [L2CACHE_DATA_ADDR_WIDTH-1:0] sram_addr_r, sram_addr_nxt;
    logic [L2CACHE_DATA_WIDTH-1:0] sram_wdata_r, sram_wdata_nxt;
    logic [L2CACHE_DATA_WIDTH-1:0] sram_rdata [L2CACHE_WAYS];
    
    // Way索引转换函数
    function automatic logic [2:0] way_to_index(input logic [L2CACHE_WAYS-1:0] way_vector);
        logic [2:0] result;
        result = 3'b000;
        for (int i = 0; i < L2CACHE_WAYS; i++) begin
            if (way_vector[i]) result = i[2:0];
        end
        return result;
    endfunction
    
    //=============================================================================
    // SRAM实例化 (每个way一个SRAM)
    //=============================================================================
    
    // SRAM接口实例数组
    rvgpu_sram_if #(
        .WIDTH(L2CACHE_DATA_WIDTH),
        .HEIGHT(L2CACHE_DATA_DEPTH)
    ) sram_if_inst [L2CACHE_WAYS]();
    
    // 连接时钟
    for (genvar i = 0; i < L2CACHE_WAYS; i++) begin : gen_sram_clk
        assign sram_if_inst[i].clk = clk;
    end
    
    // SRAM实例数组
    for (genvar i = 0; i < L2CACHE_WAYS; i++) begin : gen_sram
        rvgpu_sram_sp #(
            .WIDTH(L2CACHE_DATA_WIDTH),
            .HEIGHT(L2CACHE_DATA_DEPTH),
            .RAMNAME("L2CACHE_DATA_SRAM")
        ) u_data_sram_way (
            .sram_if(sram_if_inst[i].sram_port)
        );
        
        // SRAM接口控制 - 每个way独立连接
        assign sram_if_inst[i].ce = sram_ce_r[i];
        assign sram_if_inst[i].we = sram_we_r[i];
        assign sram_if_inst[i].addr = sram_addr_r;
        assign sram_if_inst[i].wdata = sram_wdata_r;
        assign sram_rdata[i] = sram_if_inst[i].rdata;
    end
    
    //=============================================================================
    // 组合逻辑 - 状态机和输出控制
    //=============================================================================
    
    always_comb begin : comb_logic
        // 默认值
        state_nxt = state_r;
        access_index_nxt = access_index_r;
        access_way_nxt = access_way_r;
        line_read_done_nxt = line_read_done_r;
        line_write_done_nxt = line_write_done_r;
        line_read_data_nxt = line_read_data_r;
        sram_ce_nxt = sram_ce_r;
        sram_we_nxt = sram_we_r;
        sram_addr_nxt = sram_addr_r;
        sram_wdata_nxt = sram_wdata_r;
        
        // 接口输出默认值
        data_if.line_read_ready = (state_r == L2CACHE_DATA_STATE_IDLE);
        data_if.line_write_ready = (state_r == L2CACHE_DATA_STATE_IDLE);
        data_if.line_read_done = line_read_done_r;
        data_if.line_read_data = line_read_data_r;
        data_if.line_write_done = line_write_done_r;
        
        case (state_r)
            L2CACHE_DATA_STATE_IDLE: begin
                // 空闲状态：等待新请求
                line_read_done_nxt = 1'b0;
                line_write_done_nxt = 1'b0;
                
                if (data_if.line_read_valid && data_if.line_read_ready) begin
                    // 开始缓存行读操作
                    state_nxt = L2CACHE_DATA_STATE_LINE_READ;
                    access_index_nxt = data_if.line_read_index;
                    access_way_nxt = data_if.line_read_way;
                    
                    // 激活对应way的SRAM
                    sram_ce_nxt = data_if.line_read_way;
                    sram_we_nxt = '0;
                    sram_addr_nxt = data_if.line_read_index;
                end else if (data_if.line_write_valid && data_if.line_write_ready) begin
                    // 开始缓存行写操作
                    state_nxt = L2CACHE_DATA_STATE_LINE_WRITE;
                    access_index_nxt = data_if.line_write_index;
                    access_way_nxt = data_if.line_write_way;
                    line_read_data_nxt = data_if.line_write_data;
                    
                    // 激活对应way的SRAM
                    sram_ce_nxt = data_if.line_write_way;
                    sram_we_nxt = data_if.line_write_way;
                    sram_addr_nxt = data_if.line_write_index;
                    sram_wdata_nxt = data_if.line_write_data.data;
                end
            end
            
            L2CACHE_DATA_STATE_LINE_READ: begin
                // 缓存行读操作状态 - 发起SRAM读取
                sram_ce_nxt = '0; // 停止SRAM访问
                state_nxt = L2CACHE_DATA_STATE_LINE_READ_WAIT;
            end
            
            L2CACHE_DATA_STATE_LINE_READ_WAIT: begin
                // 缓存行读等待状态 - 等待SRAM读取完成
                sram_ce_nxt = '0; // 停止SRAM访问
                
                // 读取完整缓存行
                line_read_data_nxt.data = sram_rdata[way_to_index(access_way_r)];
                line_read_data_nxt.strb = '1; // 完整行
                line_read_done_nxt = 1'b1;
                
                // 返回空闲状态
                state_nxt = L2CACHE_DATA_STATE_IDLE;
            end
            
            L2CACHE_DATA_STATE_LINE_WRITE: begin
                // 缓存行写操作状态
                sram_ce_nxt = '0; // 停止SRAM访问
                
                // 写完成
                line_write_done_nxt = 1'b1;
                
                // 返回空闲状态
                state_nxt = L2CACHE_DATA_STATE_IDLE;
            end
            
            default: begin
                // 错误状态
                state_nxt = L2CACHE_DATA_STATE_IDLE;
                line_read_data_nxt = 'x;
            end
        endcase
    end
    
    //=============================================================================
    // 时序逻辑 - 寄存器更新
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // 复位逻辑
            state_r <= L2CACHE_DATA_STATE_IDLE;
            access_index_r <= '0;
            access_way_r <= '0;
            line_read_done_r <= 1'b0;
            line_write_done_r <= 1'b0;
            line_read_data_r <= '0;
            sram_ce_r <= '0;
            sram_we_r <= '0;
            sram_addr_r <= '0;
            sram_wdata_r <= '0;
        end else begin
            // 状态更新
            state_r <= state_nxt;
            access_index_r <= access_index_nxt;
            access_way_r <= access_way_nxt;
            line_read_done_r <= line_read_done_nxt;
            line_write_done_r <= line_write_done_nxt;
            line_read_data_r <= line_read_data_nxt;
            sram_ce_r <= sram_ce_nxt;
            sram_we_r <= sram_we_nxt;
            sram_addr_r <= sram_addr_nxt;
            sram_wdata_r <= sram_wdata_nxt;
        end
    end

endmodule : rvgpu_l2cache_data_array

`endif // RVGPU_L2CACHE_DATA_ARRAY_SV 