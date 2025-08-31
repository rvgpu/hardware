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

`ifndef INTERFACE_FIFO_STREAM_SVH
`define INTERFACE_FIFO_STREAM_SVH

interface interface_fifo_stream #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned FIFO_DEPTH = 16
);
  // 写入接口
  logic                    wr_valid;
  logic                    wr_ready;
  logic [DATA_WIDTH-1:0]   wr_data;
  
  // 读取接口
  logic                    rd_valid;
  logic                    rd_ready;
  logic [DATA_WIDTH-1:0]   rd_data;
  
  // 状态输出
  logic [FIFO_DEPTH:0]    state_oh;
  
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

endinterface : interface_fifo_stream

`endif // INTERFACE_FIFO_STREAM_SVH
