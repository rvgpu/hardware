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
    
    //=============================================================================
    // Internal Registers and Signals
    //=============================================================================
    
    // 状态机寄存器
    logic [L2CACHE_DATA_STATE_BITS-1:0] state_r, state_nxt;
    
    // 访问请求寄存器
    logic [L2CACHE_DATA_ADDR_WIDTH-1:0] access_index_r, access_index_nxt;
    logic [L2CACHE_WAYS-1:0] access_way_r, access_way_nxt;
    logic [L2CACHE_OFFSET_BITS-1:0] access_offset_r, access_offset_nxt;
    logic [7:0] access_size_r, access_size_nxt;
    logic [255:0] access_data_r, access_data_nxt;
    logic [31:0] access_strb_r, access_strb_nxt;
    
    // 访问结果寄存器
    logic [255:0] read_data_r, read_data_nxt;
    logic [31:0] read_strb_r, read_strb_nxt;
    logic read_done_r, read_done_nxt;
    logic write_done_r, write_done_nxt;
    logic line_read_done_r, line_read_done_nxt;
    logic line_write_done_r, line_write_done_nxt;
    l2cache_line_t line_read_data_r, line_read_data_nxt;
    
    // SRAM接口信号
    logic [L2CACHE_WAYS-1:0] sram_ce_r, sram_ce_nxt;
    logic [L2CACHE_WAYS-1:0] sram_we_r, sram_we_nxt;
    logic [L2CACHE_DATA_ADDR_WIDTH-1:0] sram_addr_r, sram_addr_nxt;
    logic [L2CACHE_DATA_WIDTH-1:0] sram_wdata_r, sram_wdata_nxt;
    logic [L2CACHE_DATA_WIDTH-1:0] sram_rdata [L2CACHE_WAYS];
    
    // 数据掩码和选择信号
    logic [255:0] read_mask;
    logic [255:0] write_mask;
    logic [255:0] merged_data;
    logic [255:0] way_data;
    
    // Way索引转换函数
    function automatic logic [2:0] way_to_index(input logic [L2CACHE_WAYS-1:0] way_vector);
        logic [2:0] result;
        result = 3'b000;
        for (int i = 0; i < L2CACHE_WAYS; i++) begin
            if (way_vector[i]) result = i[2:0];
        end
        return result;
    endfunction
    
    // Way索引转换函数（用于数组索引）
    function automatic logic [2:0] way_to_index_for_array(input logic [L2CACHE_WAYS-1:0] way_vector);
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
        access_offset_nxt = access_offset_r;
        access_size_nxt = access_size_r;
        access_data_nxt = access_data_r;
        access_strb_nxt = access_strb_r;
        read_data_nxt = read_data_r;
        read_strb_nxt = read_strb_r;
        read_done_nxt = read_done_r;
        write_done_nxt = write_done_r;
        line_read_done_nxt = line_read_done_r;
        line_write_done_nxt = line_write_done_r;
        line_read_data_nxt = line_read_data_r;
        sram_ce_nxt = sram_ce_r;
        sram_we_nxt = sram_we_r;
        sram_addr_nxt = sram_addr_r;
        sram_wdata_nxt = sram_wdata_r;
        
        // SRAM接口控制 - 在generate块中处理
        
        // 接口输出默认值
        data_if.read_ready = (state_r == L2CACHE_DATA_STATE_IDLE);
        data_if.write_ready = (state_r == L2CACHE_DATA_STATE_IDLE);
        data_if.line_read_ready = (state_r == L2CACHE_DATA_STATE_IDLE);
        data_if.line_write_ready = (state_r == L2CACHE_DATA_STATE_IDLE);
        data_if.read_data = read_data_r;
        data_if.read_strb = read_strb_r;
        data_if.read_done = read_done_r;
        data_if.write_done = write_done_r;
        data_if.line_read_done = line_read_done_r;
        data_if.line_read_data = line_read_data_r;
        data_if.line_write_done = line_write_done_r;
        
        case (state_r)
            L2CACHE_DATA_STATE_IDLE: begin
                // 空闲状态：等待新请求
                read_done_nxt = 1'b0;
                write_done_nxt = 1'b0;
                line_read_done_nxt = 1'b0;
                line_write_done_nxt = 1'b0;
                
                if (data_if.read_valid) begin
                    // 开始读操作
                    state_nxt = L2CACHE_DATA_STATE_READ;
                    access_index_nxt = data_if.read_index;
                    access_way_nxt = data_if.read_way;
                    access_offset_nxt = data_if.read_offset;
                    access_size_nxt = data_if.read_size;
                    
                    // 激活对应way的SRAM
                    sram_ce_nxt = data_if.read_way;
                    sram_we_nxt = '0;
                    sram_addr_nxt = data_if.read_index;
                end else if (data_if.write_valid) begin
                    // 开始写操作
                    state_nxt = L2CACHE_DATA_STATE_WRITE;
                    access_index_nxt = data_if.write_index;
                    access_way_nxt = data_if.write_way;
                    access_offset_nxt = data_if.write_offset;
                    access_data_nxt = data_if.write_data;
                    access_strb_nxt = data_if.write_strb;
                    access_size_nxt = data_if.write_size;
                    
                    // 激活对应way的SRAM
                    sram_ce_nxt = data_if.write_way;
                    sram_we_nxt = data_if.write_way;
                    sram_addr_nxt = data_if.write_index;
                    sram_wdata_nxt = merge_write_data(data_if.write_data, data_if.write_strb, sram_rdata[way_to_index_for_array(data_if.write_way)]);
                end else if (data_if.line_read_valid) begin
                    // 开始缓存行读操作
                    state_nxt = L2CACHE_DATA_STATE_LINE_READ;
                    access_index_nxt = data_if.line_read_index;
                    access_way_nxt = data_if.line_read_way;
                    
                    // 激活对应way的SRAM
                    sram_ce_nxt = data_if.line_read_way;
                    sram_we_nxt = '0;
                    sram_addr_nxt = data_if.line_read_index;
                end else if (data_if.line_write_valid) begin
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
            
            L2CACHE_DATA_STATE_READ: begin
                // 读操作状态
                sram_ce_nxt = '0; // 停止SRAM访问
                
                // 从选中的way读取数据
                way_data = sram_rdata[way_to_index_for_array(access_way_r)];
                
                // 根据偏移和大小提取数据
                read_data_nxt = extract_read_data(way_data, access_offset_r, access_size_r);
                read_strb_nxt = generate_read_strb(access_offset_r, access_size_r);
                read_done_nxt = 1'b1;
                
                // 返回空闲状态
                state_nxt = L2CACHE_DATA_STATE_IDLE;
            end
            
            L2CACHE_DATA_STATE_WRITE: begin
                // 写操作状态
                sram_ce_nxt = '0; // 停止SRAM访问
                
                // 写完成
                write_done_nxt = 1'b1;
                
                // 返回空闲状态
                state_nxt = L2CACHE_DATA_STATE_IDLE;
            end
            
            L2CACHE_DATA_STATE_LINE_READ: begin
                // 缓存行读操作状态
                sram_ce_nxt = '0; // 停止SRAM访问
                
                // 读取完整缓存行
                line_read_data_nxt.data = sram_rdata[way_to_index_for_array(access_way_r)];
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
                read_data_nxt = 'x;
                read_strb_nxt = 'x;
                line_read_data_nxt = 'x;
            end
        endcase
    end
    
    //=============================================================================
    // 辅助函数
    //=============================================================================
    
    // 合并写数据（支持字节级写）
    function automatic logic [255:0] merge_write_data(
        input logic [255:0] write_data,
        input logic [31:0] write_strb,
        input logic [255:0] original_data
    );
        logic [255:0] merged;
        
        for (int i = 0; i < 32; i++) begin
            if (write_strb[i]) begin
                merged[i*8 +: 8] = write_data[i*8 +: 8];
            end else begin
                merged[i*8 +: 8] = original_data[i*8 +: 8];
            end
        end
        
        return merged;
    endfunction
    
    // 提取读数据
    function automatic logic [255:0] extract_read_data(
        input logic [255:0] line_data,
        input logic [L2CACHE_OFFSET_BITS-1:0] offset,
        input logic [7:0] size
    );
        logic [255:0] extracted;
        logic [31:0] start_byte = offset;
        logic [31:0] num_bytes = size;
        
        extracted = '0;
        for (int i = 0; i < num_bytes; i++) begin
            if (start_byte + i < 256) begin
                extracted[i*8 +: 8] = line_data[(start_byte + i)*8 +: 8];
            end
        end
        
        return extracted;
    endfunction
    
    // 生成读掩码
    function automatic logic [31:0] generate_read_strb(
        input logic [L2CACHE_OFFSET_BITS-1:0] offset,
        input logic [7:0] size
    );
        logic [31:0] strb;
        logic [31:0] start_byte = offset;
        logic [31:0] num_bytes = size;
        
        strb = '0;
        for (int i = 0; i < num_bytes; i++) begin
            if (start_byte + i < 32) begin
                strb[start_byte + i] = 1'b1;
            end
        end
        
        return strb;
    endfunction
    
    //=============================================================================
    // 时序逻辑 - 寄存器更新
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // 复位逻辑
            state_r <= L2CACHE_DATA_STATE_IDLE;
            access_index_r <= '0;
            access_way_r <= '0;
            access_offset_r <= '0;
            access_size_r <= '0;
            access_data_r <= '0;
            access_strb_r <= '0;
            read_data_r <= '0;
            read_strb_r <= '0;
            read_done_r <= 1'b0;
            write_done_r <= 1'b0;
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
            access_offset_r <= access_offset_nxt;
            access_size_r <= access_size_nxt;
            access_data_r <= access_data_nxt;
            access_strb_r <= access_strb_nxt;
            read_data_r <= read_data_nxt;
            read_strb_r <= read_strb_nxt;
            read_done_r <= read_done_nxt;
            write_done_r <= write_done_nxt;
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