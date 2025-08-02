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

`ifndef RVGPU_CONST_L15CACHE_SVH
`define RVGPU_CONST_L15CACHE_SVH

`include "rvgpu_config.svh"
`include "rvgpu_internal_noc_pkg.svh"

`ifndef RVGPU_INTERNAL_NOC_PKG_IMPORTED
`define RVGPU_INTERNAL_NOC_PKG_IMPORTED
import rvgpu_internal_noc_pkg::*;
`endif // RVGPU_INTERNAL_NOC_PKG_IMPORTED

//=============================================================================
// L1.5 Cache Configuration Parameters
//=============================================================================
// 缓存配置参数
localparam int L15CACHE_LINE_WIDTH          = 512;  // 64字节缓存行
localparam int L15CACHE_LINE_WIDTH_BYTES    = L15CACHE_LINE_WIDTH / 8;
localparam int L15CACHE_SETS                = 512;  // 512个set
localparam int L15CACHE_WAYS                = 8;    // 8路组相联
localparam int L15CACHE_INDEX_BITS          = 9;    // log2(512)
localparam int L15CACHE_OFFSET_BITS         = 6;    // log2(64)
localparam int L15CACHE_TAG_BITS            = 25;   // 40-9-6=25位tag

localparam int L15CACHE_LRU_BITS            = L15CACHE_WAYS;    // 8路LRU位

localparam int L15CACHE_SIZE_BYTES          = 256 * 1024;  // 256KB
localparam int L15CACHE_SIZE_KB             = L15CACHE_SIZE_BYTES / 1024;

// NOC接口相关参数
localparam int L15CACHE_NOC_DATA_WIDTH      = `RVGPU_CONST_NOC_DATA_WIDTH;
localparam int L15CACHE_NOC_HEADER_WIDTH    = `RVGPU_CONST_NOC_HEADER_WIDTH;

// L1.5 Cache请求者数量参数
localparam int L15CACHE_NUM_REQUESTERS      = 6;  // TPC + Block Scheduler + Raster

`endif // RVGPU_CONST_L15CACHE_SVH 