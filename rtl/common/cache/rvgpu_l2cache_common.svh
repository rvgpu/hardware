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

`ifndef RVGPU_L2CACHE_COMMON_SVH
`define RVGPU_L2CACHE_COMMON_SVH

`include "rvgpu_l2cache_pkg.svh"

`ifndef RVGPU_L2CACHE_PKG_IMPORTED
`define RVGPU_L2CACHE_PKG_IMPORTED
import rvgpu_l2cache_pkg::*;
`endif // RVGPU_L2CACHE_PKG_IMPORTED

// AXI地址和数据位宽（基于CONST定义）
localparam int L2CACHE_AXI_ADDR_WIDTH = `RVGPU_CONST_L2CACHE_AXI_ADDR_WIDTH;
localparam int L2CACHE_AXI_DATA_WIDTH = `RVGPU_CONST_L2CACHE_AXI_DATA_WIDTH;

// 缓存行宽度

// 缓存配置参数（基于CONST定义）
localparam int L2CACHE_SLICE_NUMBER = `RVGPU_CONST_L2CACHE_SLICE_NUMBER;


// 缓存大小的计算
localparam int L2CACHE_SIZE_KB = `RVGPU_CONST_L2CACHE_SIZE;
localparam int L2CACHE_SIZE_BYTES = L2CACHE_SIZE_KB * 1024;

localparam int L2CACHE_LINE_WIDTH = `RVGPU_CONST_L2CACHE_LINE_WIDTH;  // 256位缓存行
localparam int L2CACHE_LINE_BYTES = L2CACHE_LINE_WIDTH / 8;

// 根据缓存大小计算其他参数
localparam int L2CACHE_SETS = `RVGPU_CONST_L2CACHE_SETS;
localparam int L2CACHE_INDEX_BITS = `RVGPU_CONST_L2CACHE_INDEX_BITS;
localparam int L2CACHE_OFFSET_BITS = `RVGPU_CONST_L2CACHE_OFFSET_BITS;
localparam int L2CACHE_TAG_BITS = `RVGPU_CONST_L2CACHE_TAG_BITS;
localparam int L2CACHE_WAYS = `RVGPU_CONST_L2CACHE_WAYS;
localparam int L2CACHE_LRU_BITS = `RVGPU_CONST_L2CACHE_LRU_BITS;

//=============================================================================
// 队列深度参数
//=============================================================================

// 请求队列深度
localparam int L2CACHE_REQ_QUEUE_DEPTH = 16;
localparam int L2CACHE_REQ_QUEUE_BITS = $clog2(L2CACHE_REQ_QUEUE_DEPTH);

// 事务队列深度
localparam int L2CACHE_TRANS_QUEUE_DEPTH = 8;
localparam int L2CACHE_TRANS_QUEUE_BITS = $clog2(L2CACHE_TRANS_QUEUE_DEPTH);

//=============================================================================
// 响应状态码
//=============================================================================

// AXI响应状态
localparam int L2CACHE_RESP_OKAY   = 2'b00;
localparam int L2CACHE_RESP_SLVERR = 2'b10;
localparam int L2CACHE_RESP_DECERR = 2'b11;

//=============================================================================
// MESI缓存一致性状态
//=============================================================================

// MESI状态定义
localparam int L2CACHE_MESI_INVALID   = 2'b00;
localparam int L2CACHE_MESI_EXCLUSIVE = 2'b01;
localparam int L2CACHE_MESI_SHARED    = 2'b10;
localparam int L2CACHE_MESI_MODIFIED  = 2'b11;

//=============================================================================
// 数据数组相关参数
//=============================================================================

// 数据数组状态机状态
localparam int L2CACHE_DATA_STATE_BITS = 3;
localparam int L2CACHE_DATA_STATE_IDLE = 3'b000;
localparam int L2CACHE_DATA_STATE_READ = 3'b001;
localparam int L2CACHE_DATA_STATE_WRITE = 3'b010;
localparam int L2CACHE_DATA_STATE_LINE_READ = 3'b011;
localparam int L2CACHE_DATA_STATE_LINE_WRITE = 3'b100;

// 数据数组参数
localparam int L2CACHE_DATA_WIDTH = L2CACHE_LINE_WIDTH;
localparam int L2CACHE_DATA_ADDR_WIDTH = L2CACHE_INDEX_BITS;
localparam int L2CACHE_DATA_DEPTH = L2CACHE_SETS;

//=============================================================================
// 标签数组相关参数
//=============================================================================

// 标签数组状态机状态
localparam int L2CACHE_TAG_STATE_BITS = 2;
localparam int L2CACHE_TAG_STATE_IDLE = 2'b00;
localparam int L2CACHE_TAG_STATE_LOOKUP = 2'b01;
localparam int L2CACHE_TAG_STATE_UPDATE = 2'b10;
localparam int L2CACHE_TAG_STATE_WAIT = 2'b11;

// 标签数组参数
localparam int L2CACHE_TAG_DATA_WIDTH = $bits(l2cache_tag_entry_t);
localparam int L2CACHE_TAG_ADDR_WIDTH = L2CACHE_INDEX_BITS;
localparam int L2CACHE_TAG_DEPTH = L2CACHE_SETS;

//=============================================================================
// NOC接口相关参数（基于CONST定义）
//=============================================================================

// NOC数据位宽
localparam int L2CACHE_NOC_DATA_WIDTH = `RVGPU_CONST_NOC_DATA_WIDTH;
localparam int L2CACHE_NOC_HEADER_WIDTH = `RVGPU_CONST_NOC_HEADER_WIDTH;

`endif // RVGPU_L2CACHE_COMMON_SVH 