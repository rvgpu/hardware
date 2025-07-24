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

`ifndef RVGPU_GPC_L1_DATA_ARRAY_SV
`define RVGPU_GPC_L1_DATA_ARRAY_SV

`include "rvgpu_typedef.svh"
`include "rvgpu_sram_if.svh"

// L1 Cache数据数组模块
// 使用SRAM模块存储数据
module rvgpu_gpc_l15_data_array #(
    parameter int CACHE_SIZE = 256 * 1024,    // 缓存大小，单位字节
    parameter int LINE_SIZE = 64,             // 缓存行大小，单位字节
    parameter int ASSOCIATIVITY = 8,          // 相联度
    parameter int ADDR_WIDTH = 40             // 物理地址宽度
) (
    input  logic clk,
    input  logic rst_n,
    
    // 读接口
    input  logic                      read_valid,
    input  logic [ADDR_WIDTH-1:0]     read_addr,
    input  logic [$clog2(ASSOCIATIVITY)-1:0] read_way,
    output logic                      read_ready,
    output logic                      read_resp_valid,
    output logic [LINE_SIZE*8-1:0]    read_data,
    
    // 写接口
    input  logic                      write_valid,
    input  logic [ADDR_WIDTH-1:0]     write_addr,
    input  logic [$clog2(ASSOCIATIVITY)-1:0] write_way,
    input  logic [LINE_SIZE*8-1:0]    write_data,
    input  logic [LINE_SIZE-1:0]      write_mask,
    output logic                      write_ready
);
    // 计算索引位宽
    localparam int NUM_SETS = (CACHE_SIZE / LINE_SIZE) / ASSOCIATIVITY;
    localparam int INDEX_WIDTH = $clog2(NUM_SETS);
    localparam int TAG_WIDTH = ADDR_WIDTH - INDEX_WIDTH - $clog2(LINE_SIZE);
    
    // 地址分解
    logic [INDEX_WIDTH-1:0] read_index;
    logic [INDEX_WIDTH-1:0] write_index;
    
    // SRAM接口
    rvgpu_sram_if #(
        .ADDR_WIDTH(INDEX_WIDTH + $clog2(ASSOCIATIVITY)),
        .DATA_WIDTH(LINE_SIZE * 8)
    ) sram_if();
    
    // 地址分解
    assign read_index = read_addr[ADDR_WIDTH-TAG_WIDTH-1:$clog2(LINE_SIZE)];
    assign write_index = write_addr[ADDR_WIDTH-TAG_WIDTH-1:$clog2(LINE_SIZE)];
    
    // 读写控制逻辑
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_ready <= 1'b0;
            write_ready <= 1'b0;
            read_resp_valid <= 1'b0;
            sram_if.req_valid <= 1'b0;
        end else begin
            // 默认状态
            read_ready <= 1'b0;
            write_ready <= 1'b0;
            read_resp_valid <= 1'b0;
            
            // 处理读请求
            if (read_valid && !sram_if.req_valid) begin
                sram_if.req_valid <= 1'b1;
                sram_if.req_addr <= {read_way, read_index};
                sram_if.req_write <= 1'b0;
                sram_if.req_wdata <= '0;
                sram_if.req_wmask <= '0;
                read_ready <= 1'b1;
            end
            
            // 处理写请求
            else if (write_valid && !sram_if.req_valid) begin
                sram_if.req_valid <= 1'b1;
                sram_if.req_addr <= {write_way, write_index};
                sram_if.req_write <= 1'b1;
                sram_if.req_wdata <= write_data;
                
                // 生成字节掩码
                for (int i = 0; i < LINE_SIZE; i++) begin
                    sram_if.req_wmask[i*8 +: 8] <= {8{write_mask[i]}};
                end
                
                write_ready <= 1'b1;
            end
            
            // 处理SRAM响应
            if (sram_if.resp_valid) begin
                sram_if.req_valid <= 1'b0;
                
                if (!sram_if.req_write) begin
                    // 读响应
                    read_resp_valid <= 1'b1;
                    read_data <= sram_if.resp_rdata;
                end
            end
        end
    end
    
    // 实例化SRAM
    rvgpu_sram_sp_sim #(
        .ADDR_WIDTH(INDEX_WIDTH + $clog2(ASSOCIATIVITY)),
        .DATA_WIDTH(LINE_SIZE * 8)
    ) u_sram (
        .clk(clk),
        .rst_n(rst_n),
        .sram_if(sram_if)
    );

endmodule : rvgpu_gpc_l1_data_array

`endif // RVGPU_GPC_L1_DATA_ARRAY_SV 