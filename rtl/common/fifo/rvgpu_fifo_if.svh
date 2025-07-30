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

`ifndef RVGPU_FIFO_IF_SVH
`define RVGPU_FIFO_IF_SVH

interface rvgpu_fifo_stream_if #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned FIFO_DEPTH = 16
);
  // 写入接口 (Stream风格)
  logic                    wr_valid;
  logic                    wr_ready;
  logic [DATA_WIDTH-1:0]   wr_data;
  
  // 读取接口 (Stream风格)
  logic                    rd_valid;
  logic                    rd_ready;
  logic [DATA_WIDTH-1:0]   rd_data;
  
  // 状态输出
  logic [FIFO_DEPTH:0]    state_oh;
  
  // 握手信号
  modport fifo_port (
    input  wr_valid, wr_data,
    output wr_ready,
    output rd_valid, rd_data,
    input  rd_ready,
    output state_oh
  );
  
  modport use_port (
    output wr_valid, wr_data,
    input  wr_ready,
    input  rd_valid, rd_data,
    output rd_ready,
    input  state_oh
  );

endinterface : rvgpu_fifo_stream_if

//=============================================================================
// Basic FIFO接口定义
//=============================================================================
interface rvgpu_fifo_basic_if #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned INDEX_BITS = 8
);
  // 写入接口
  logic                    write_en;
  logic [DATA_WIDTH-1:0]   write_data;
  
  // 读取接口
  logic                    read_en;
  logic [DATA_WIDTH-1:0]   read_data;
  
  // 状态输出
  logic                    full;
  logic                    empty;
  
  // 接口定义
  modport fifo_port (
    input  write_en, write_data,
    input  read_en,
    output read_data,
    output full, empty
  );
  
  modport use_port (
    output write_en, write_data,
    output read_en,
    input  read_data,
    input  full, empty
  );

endinterface : rvgpu_fifo_basic_if

`endif // RVGPU_FIFO_IF_SVH 