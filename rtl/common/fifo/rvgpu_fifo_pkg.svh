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

`ifndef RVGPU_FIFO_PKG_SVH
`define RVGPU_FIFO_PKG_SVH

package rvgpu_fifo_pkg;

  //=============================================================================
  // 常量定义
  //=============================================================================
  // 默认FIFO参数
  localparam int unsigned DEFAULT_FIFO_DEPTH = 16;     // 默认FIFO深度
  localparam int unsigned DEFAULT_DATA_WIDTH = 32;     // 默认数据宽度
  localparam int unsigned DEFAULT_INDEX_BITS = 8;      // 默认索引位宽
  
  //=============================================================================
  // 类型定义
  //=============================================================================
  // FIFO状态枚举
  typedef enum logic [1:0] {
    FIFO_EMPTY = 2'b00,    // FIFO为空
    FIFO_PARTIAL = 2'b01,  // FIFO部分满
    FIFO_FULL = 2'b10      // FIFO满
  } fifo_state_e;
  
  // FIFO类型枚举
  typedef enum logic [1:0] {
    FIFO_TYPE_BASIC = 2'b00,      // 基础FIFO
    FIFO_TYPE_STREAM = 2'b01      // Stream FIFO
  } fifo_type_e;
  
  //=============================================================================
  // 函数定义
  //=============================================================================
  // 计算FIFO深度所需的指针位宽
  function automatic int unsigned get_ptr_width(int unsigned depth);
    return $clog2(depth);
  endfunction
  
  // 计算FIFO深度所需的索引位宽
  function automatic int unsigned get_index_bits(int unsigned depth);
    return $clog2(depth);
  endfunction
  
  // 检查FIFO深度是否为2的幂
  function automatic logic is_power_of_2(int unsigned depth);
    return (depth & (depth - 1)) == 0;
  endfunction
  
  // 获取FIFO类型名称 (用于调试)
  function automatic string get_fifo_type_name(fifo_type_e fifo_type);
    case (fifo_type)
      FIFO_TYPE_BASIC:      return "BASIC";
      FIFO_TYPE_STREAM:     return "STREAM";
      default:              return "UNKNOWN";
    endcase
  endfunction

endpackage : rvgpu_fifo_pkg

`endif // RVGPU_FIFO_PKG_SVH 