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

`include "rvgpu_fifo_pkg.svh"
`include "interface_fifo_stream.svh"

module rvgpu_fifo_stream #(
  parameter int unsigned DATA_WIDTH     = rvgpu_fifo_pkg::DEFAULT_DATA_WIDTH,
  parameter int unsigned FIFO_DEPTH     = rvgpu_fifo_pkg::DEFAULT_FIFO_DEPTH
) (
  input  wire clk,                    // 时钟信号
  input  wire rst_n,                  // 低电平复位信号
  interface_fifo_stream.fifo_port fifo_if // FIFO接口
);

  //=============================================================================
  // 参数计算
  //=============================================================================
  localparam int unsigned PTR_WIDTH = $clog2(FIFO_DEPTH);  // 指针位宽
  
  //=============================================================================
  // 内部信号定义
  //=============================================================================
  // 指针寄存器
  logic [PTR_WIDTH-1:0] wr_ptr_r;    // 写指针寄存器
  logic [PTR_WIDTH-1:0] rd_ptr_r;    // 读指针寄存器
  
  // 状态寄存器
  logic full_r;                       // 满状态寄存器
  logic empty_r;                      // 空状态寄存器
  
  // 指针下一状态
  logic [PTR_WIDTH-1:0] wr_ptr_next; // 写指针下一状态
  logic [PTR_WIDTH-1:0] rd_ptr_next; // 读指针下一状态
  
  // 状态下一状态
  logic full_next;                    // 满状态下一状态
  logic empty_next;                   // 空状态下一状态
  
  // 控制信号
  logic full_empty_en;                // 满空状态使能
  logic wr_ptr_en;                    // 写指针使能
  logic rd_ptr_en;                    // 读指针使能
  logic wr_en;                        // 写使能
  
  // 数据存储
  logic [DATA_WIDTH-1:0] data_r [FIFO_DEPTH-1:0];  // 数据存储数组
  
  // one-hot编码信号
  logic [FIFO_DEPTH-1:0] wr_ptr_oh;  // 写指针one-hot编码
  logic [FIFO_DEPTH-1:0] rd_ptr_oh;  // 读指针one-hot编码
  
  //=============================================================================
  // 指针逻辑
  //=============================================================================
  // 写指针递增逻辑 (循环指针)
  assign wr_ptr_next = (wr_ptr_r == FIFO_DEPTH-1) ? '0 : wr_ptr_r + 1'b1;
  
  // 读指针递增逻辑 (循环指针)
  assign rd_ptr_next = (rd_ptr_r == FIFO_DEPTH-1) ? '0 : rd_ptr_r + 1'b1;
  
  //=============================================================================
  // 满空状态逻辑
  //=============================================================================
  // 满状态: 写入有效但读取未就绪，且写指针下一位置等于读指针
  assign full_next = fifo_if.wr_valid & ~fifo_if.rd_ready & (wr_ptr_next == rd_ptr_r);
  
  // 空状态: 写入无效但读取就绪，且读指针下一位置等于写指针
  assign empty_next = ~fifo_if.wr_valid & fifo_if.rd_ready & (rd_ptr_next == wr_ptr_r);
  
  // 满空状态更新使能
  assign full_empty_en = (full_r ? fifo_if.rd_ready : full_next) | 
                         (empty_r ? fifo_if.wr_valid : empty_next);
  
  //=============================================================================
  // 状态寄存器
  //=============================================================================
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      full_r  <= 1'b0;
      empty_r <= 1'b1;
    end else if (full_empty_en) begin
      full_r  <= full_next;
      empty_r <= empty_next;
    end
  end
  
  //=============================================================================
  // 输出信号
  //=============================================================================
  assign fifo_if.rd_valid = ~empty_r;         // 读取有效 = 非空
  assign fifo_if.wr_ready = ~full_r;          // 写入就绪 = 非满
  
  //=============================================================================
  // 指针控制逻辑
  //=============================================================================
  // 写指针使能: 非满且写入有效，或者空状态下的读取
  assign wr_ptr_en = (~full_r & fifo_if.wr_valid) | empty_next;
  
  // 读指针使能: 非空且读取就绪且非空状态
  assign rd_ptr_en = ~empty_r & fifo_if.rd_ready & ~empty_next;
  
  // 写指针下一状态选择
  logic [PTR_WIDTH-1:0] wr_ptr_nxt;
  assign wr_ptr_nxt = fifo_if.wr_valid ? wr_ptr_next : rd_ptr_r;
  
  //=============================================================================
  // 指针寄存器
  //=============================================================================
  // 写指针寄存器
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wr_ptr_r <= '0;
    end else if (wr_ptr_en) begin
      wr_ptr_r <= wr_ptr_nxt;
    end
  end
  
  // 读指针寄存器
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rd_ptr_r <= '0;
    end else if (rd_ptr_en) begin
      rd_ptr_r <= rd_ptr_next;
    end
  end
  
  //=============================================================================
  // 数据存储逻辑
  //=============================================================================
  // 写使能
  assign wr_en = ~full_r & fifo_if.wr_valid;
  
  // 数据写入
  always_ff @(posedge clk) begin
    if (wr_en) begin
      data_r[wr_ptr_r] <= fifo_if.wr_data;
    end
  end
  
  // 数据读取
  assign fifo_if.rd_data = data_r[rd_ptr_r];
  
  //=============================================================================
  // One-hot编码生成
  //=============================================================================
  // 写指针one-hot编码
  genvar i;
  generate
    for (i = 0; i < FIFO_DEPTH; i = i + 1) begin : gen_wr_oh
      assign wr_ptr_oh[i] = (wr_ptr_r == i);
    end
  endgenerate
  
  // 读指针one-hot编码
  genvar j;
  generate
    for (j = 0; j < FIFO_DEPTH; j = j + 1) begin : gen_rd_oh
      assign rd_ptr_oh[j] = (rd_ptr_r == j);
    end
  endgenerate
  
  //=============================================================================
  // 状态one-hot编码输出
  //=============================================================================
  // 空状态 (state_oh[0])
  assign fifo_if.state_oh[0] = empty_r;
  
  // 满状态 (state_oh[FIFO_DEPTH])
  assign fifo_if.state_oh[FIFO_DEPTH] = full_r;
  
  // 中间状态 (state_oh[1:FIFO_DEPTH-1])
  // 使用读指针和写指针的one-hot编码计算中间状态
  logic [2*FIFO_DEPTH-3:0] wr_ptr_oh_ext;
  assign wr_ptr_oh_ext = {wr_ptr_oh[FIFO_DEPTH-2:0], wr_ptr_oh[FIFO_DEPTH-1:1]};
  
  genvar k;
  generate
    for (k = 1; k < FIFO_DEPTH; k = k + 1) begin : gen_state_oh
      assign fifo_if.state_oh[k] = |(rd_ptr_oh & wr_ptr_oh_ext[k-1 +: FIFO_DEPTH]);
    end
  endgenerate

endmodule : rvgpu_fifo_stream 