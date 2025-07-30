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

`include "rvgpu_fifo_if.svh"

module rvgpu_fifo_basic #(
  parameter int unsigned DATA_WIDTH = 32,    // 数据位宽
  parameter int unsigned INDEX_BITS = 8      // 索引位宽，深度 = 2^INDEX_BITS
) (
  input  wire                    clk,        // 时钟信号
  input  wire                    rst_n,      // 低电平复位信号
  rvgpu_fifo_basic_if.fifo_port  fifo_if     // FIFO接口
);

  //=============================================================================
  // 参数计算
  //=============================================================================
  localparam int unsigned FIFO_DEPTH = (1 << INDEX_BITS);  // FIFO深度 = 2^INDEX_BITS
  localparam int unsigned PTR_WIDTH = INDEX_BITS + 1;      // 指针位宽 (比索引多1位用于满空判断)
  
  //=============================================================================
  // 内部信号定义
  //=============================================================================
  // 指针寄存器 (使用PTR_WIDTH位，比实际索引多1位)
  logic [PTR_WIDTH-1:0] write_ptr_r;   // 写指针寄存器
  logic [PTR_WIDTH-1:0] read_ptr_r;    // 读指针寄存器
  
  // 指针下一状态
  logic [PTR_WIDTH-1:0] write_ptr_next;  // 写指针下一状态
  logic [PTR_WIDTH-1:0] read_ptr_next;   // 读指针下一状态
  
  // 索引信号 (用于数据存储的索引)
  logic [INDEX_BITS-1:0] write_index;   // 写索引
  logic [INDEX_BITS-1:0] read_index;    // 读索引
  
  // 数据存储
  logic [DATA_WIDTH-1:0] data_r [FIFO_DEPTH-1:0];  // 数据存储数组
  
  //=============================================================================
  // 指针逻辑
  //=============================================================================
  // 写指针递增逻辑 (循环指针)
  assign write_ptr_next = (write_ptr_r == (1 << INDEX_BITS) - 1) ? '0 : write_ptr_r + 1'b1;
  
  // 读指针递增逻辑 (循环指针)
  assign read_ptr_next = (read_ptr_r == (1 << INDEX_BITS) - 1) ? '0 : read_ptr_r + 1'b1;
  
  //=============================================================================
  // 指针寄存器
  //=============================================================================
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      write_ptr_r  <= '0;
      read_ptr_r   <= '0;
    end else begin
      // 写指针更新
      if (fifo_if.write_en) begin
        write_ptr_r <= write_ptr_next;
      end
      
      // 读指针更新
      if (fifo_if.read_en) begin
        read_ptr_r <= read_ptr_next;
      end
    end
  end
  
  //=============================================================================
  // 满空状态逻辑
  //=============================================================================
  // 空状态: 写指针等于读指针
  assign fifo_if.empty = (write_ptr_r == read_ptr_r);
  
  // 满状态: 写指针等于读指针的下一位置
  assign fifo_if.full = (write_ptr_r == read_ptr_next);
  
  //=============================================================================
  // 索引计算
  //=============================================================================
  // 直接使用指针的低INDEX_BITS位作为索引
  assign write_index = write_ptr_r[INDEX_BITS-1:0];
  assign read_index  = read_ptr_r[INDEX_BITS-1:0];
  
  //=============================================================================
  // 数据存储逻辑
  //=============================================================================
  // 数据写入
  always_ff @(posedge clk) begin
    if (fifo_if.write_en) begin
      data_r[write_index] <= fifo_if.write_data;
    end
  end
  
  // 数据读取 (组合逻辑)
  assign fifo_if.read_data = data_r[read_index];

endmodule : rvgpu_fifo_basic 