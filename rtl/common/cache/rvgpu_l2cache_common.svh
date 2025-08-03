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

`include "rvgpu_config.svh"
`include "rvgpu_internal_noc_pkg.svh"

`ifndef RVGPU_INTERNAL_NOC_PKG_IMPORTED
`define RVGPU_INTERNAL_NOC_PKG_IMPORTED
import rvgpu_internal_noc_pkg::*;
`endif // RVGPU_INTERNAL_NOC_PKG_IMPORTED

//=============================================================================
// L2 Cache Configuration Parameters
//=============================================================================

// AXI地址和数据位宽
localparam int L2CACHE_AXI_ADDR_WIDTH       = `RVGPU_CONST_L2CACHE_AXI_ADDR_WIDTH;
localparam int L2CACHE_AXI_DATA_WIDTH       = `RVGPU_CONST_L2CACHE_AXI_DATA_WIDTH;

// 缓存配置参数
localparam int L2CACHE_SLICE_NUMBER         = `RVGPU_CONST_L2CACHE_SLICE_NUMBER;

// 缓存大小的计算
localparam int L2CACHE_LINE_WIDTH           = `RVGPU_CONST_L2CACHE_LINE_WIDTH;
localparam int L2CACHE_LINE_WIDTH_BYTES     = L2CACHE_LINE_WIDTH / 8;
localparam int L2CACHE_SETS                 = `RVGPU_CONST_L2CACHE_SETS;
localparam int L2CACHE_WAYS                 = `RVGPU_CONST_L2CACHE_WAYS;
localparam int L2CACHE_INDEX_BITS           = `RVGPU_CONST_L2CACHE_INDEX_BITS;
localparam int L2CACHE_OFFSET_BITS          = `RVGPU_CONST_L2CACHE_OFFSET_BITS;
localparam int L2CACHE_TAG_BITS             = `RVGPU_CONST_L2CACHE_TAG_BITS;

localparam int L2CACHE_LRU_BITS             = `RVGPU_CONST_L2CACHE_LRU_BITS;

localparam int L2CACHE_SIZE_BYTES           = `RVGPU_CONST_L2CACHE_SIZE;
localparam int L2CACHE_SIZE_KB              = `RVGPU_CONST_L2CACHE_SIZE / 1024;

// NOC接口相关参数
localparam int L2CACHE_NOC_DATA_WIDTH       = `RVGPU_CONST_NOC_DATA_WIDTH;
localparam int L2CACHE_NOC_HEADER_WIDTH     = `RVGPU_CONST_NOC_HEADER_WIDTH;

//=============================================================================
// 通用缓存定义
//=============================================================================


`include "types_cache_mesi.svh"
`include "types_cache_op.svh"
`include "types_cache_resp_status.svh"

//=============================================================================
// L2 Cache Data Structures
//=============================================================================

// 使用通用的缓存响应状态类型
typedef cache_resp_status_t l2cache_resp_status_t;

// 缓存行数据结构
typedef struct packed {
    logic [`RVGPU_CONST_L2CACHE_LINE_WIDTH-1:0]     data; // 512位缓存行数据
    logic [`RVGPU_CONST_L2CACHE_LINE_STRB-1:0]      strb; // 64字节使能位
} l2cache_line_t;

`endif // RVGPU_L2CACHE_COMMON_SVH 