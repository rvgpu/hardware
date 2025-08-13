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
  localparam int unsigned PTR_WIDTH = INDEX_BITS;          // 指针位宽
  
  //=============================================================================
  // 内部信号定义
  //=============================================================================
  // 双指针系统
  logic [PTR_WIDTH-1:0] write_ptr_r;   // 写指针
  logic [PTR_WIDTH-1:0] read_ptr_r;    // 读指针
  logic [PTR_WIDTH:0] element_count_r;  // 当前元素数量
  
  // 数据存储
  logic [DATA_WIDTH-1:0] data_r [FIFO_DEPTH-1:0];
  
  // 控制信号
  logic write_valid, read_valid;
  logic write_ready, read_ready;
  
  //=============================================================================
  // 指针管理逻辑
  //=============================================================================
  // 写指针递增 - 环形缓冲
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      write_ptr_r <= '0;
    end else if (write_valid && write_ready) begin
      if (write_ptr_r == FIFO_DEPTH - 1) begin
        write_ptr_r <= '0;  // 环形回绕
      end else begin
        write_ptr_r <= write_ptr_r + 1'b1;
      end
    end
  end
  
  // 读指针递增 - 环形缓冲
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      read_ptr_r <= '0;
    end else if (read_valid && read_ready) begin
      if (read_ptr_r == FIFO_DEPTH - 1) begin
        read_ptr_r <= '0;  // 环形回绕
      end else begin
        read_ptr_r <= read_ptr_r + 1'b1;
      end
    end
  end
  
  //=============================================================================
  // 元素计数器
  //=============================================================================
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      element_count_r <= '0;
    end else begin
      case ({write_valid && write_ready, read_valid && read_ready})
        2'b10: begin  // 只写
          if (element_count_r < FIFO_DEPTH) begin
            element_count_r <= element_count_r + 1'b1;
          end
        end
        2'b01: begin  // 只读
          if (element_count_r > 0) begin
            element_count_r <= element_count_r - 1'b1;
          end
        end
        2'b11: begin  // 同时读写
          // 元素数量保持不变
        end
        default: begin
          // 无操作
        end
      endcase
    end
  end
  
  //=============================================================================
  // 满空判断逻辑
  //=============================================================================
  assign fifo_if.empty = (element_count_r == 0);
  assign fifo_if.full = (element_count_r == FIFO_DEPTH);
  
  //=============================================================================
  // 流控制逻辑
  //=============================================================================
  assign write_ready = !fifo_if.full;
  assign read_ready = !fifo_if.empty;
  
  // 接口连接
  assign write_valid = fifo_if.write_en;
  assign read_valid = fifo_if.read_en;
  
  //=============================================================================
  // 数据存储逻辑
  //=============================================================================
  // 数据写入
  always_ff @(posedge clk) begin
    if (write_valid && write_ready) begin
      data_r[write_ptr_r] <= fifo_if.write_data;
    end
  end
  
  // 数据读取
  assign fifo_if.read_data = data_r[read_ptr_r];

endmodule : rvgpu_fifo_basic 