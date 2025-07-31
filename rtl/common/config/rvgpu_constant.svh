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

// This file define the constant for RVGPU, user can not modify it.

`ifndef RVGPU_CONSTANT_SVH
`define RVGPU_CONSTANT_SVH

`include "rvgpu_config.svh"

// ================================================
//  Internal NOC Configuration
// ================================================
`define RVGPU_CONST_NOC_NUM_SHADER_CORES        `GPC_NUMBER
`define RVGPU_CONST_NOC_HEADER_WIDTH            32
`define RVGPU_CONST_NOC_DATA_WIDTH              256

// ================================================
//  Control Unit Configuration
// ================================================
`define RVGPU_CONST_CU_AXI_ADDR_WIDTH           `HOST_INTERFACE_ADDR_WIDTH
`define RVGPU_CONST_CU_AXI_DATA_WIDTH           `HOST_INTERFACE_DATA_WIDTH
`define RVGPU_CONST_CU_MAX_PAYLOAD_SIZE         256
`define RVGPU_CONST_CU_VA_WIDTH                 39
`define RVGPU_CONST_CU_PA_WIDTH                 39

`define RVGPU_CONST_CU_PAGE_SIZE                4096
`define RVGPU_CONST_CU_PAGE_OFFSET_BITS         $clog2(`RVGPU_CONST_CU_PAGE_SIZE)
`define RVGPU_CONST_CU_PAGE_INDEX_BITS          $clog2(`RVGPU_CONST_CU_PAGE_SIZE / 8)

// ================================================
//  L2Cache Configuration
// ================================================
`define RVGPU_CONST_L2CACHE_AXI_ADDR_WIDTH      `MEMORY_INTERFACE_ADDR_WIDTH
`define RVGPU_CONST_L2CACHE_AXI_DATA_WIDTH      `MEMORY_INTERFACE_DATA_WIDTH

`define RVGPU_CONST_L2CACHE_SIZE                `L2CACHE_CONFIG_SIZE
`define RVGPU_CONST_L2CACHE_SLICE_NUMBER        `L2CACHE_SLICE_NUMBER

`define RVGPU_CONST_L2CACHE_LINE_WIDTH          `L2CACHE_CONFIG_LINE_WIDTH
`define RVGPU_CONST_L2CACHE_WAYS                `L2CACHE_CONFIG_WAYS
`define RVGPU_CONST_L2CACHE_SETS                `L2CACHE_CONFIG_SETS
`define RVGPU_CONST_L2CACHE_LINE_STRB           (`RVGPU_CONST_L2CACHE_LINE_WIDTH / 8)
`define RVGPU_CONST_L2CACHE_OFFSET_BITS         $clog2(`RVGPU_CONST_L2CACHE_LINE_WIDTH / 8)
`define RVGPU_CONST_L2CACHE_INDEX_BITS          $clog2(`RVGPU_CONST_L2CACHE_SETS)
`define RVGPU_CONST_L2CACHE_TAG_BITS            32

`define RVGPU_CONST_L2CACHE_LRU_BITS            8

// ================================================
//  MMU Configuration
// ================================================
// 地址位宽 - 所有MMU类型共用
`define RVGPU_CONST_MMU_VA_WIDTH                `RVGPU_CONST_CU_VA_WIDTH
`define RVGPU_CONST_MMU_PA_WIDTH                `RVGPU_CONST_CU_PA_WIDTH
`define RVGPU_CONST_MMU_PAGE_SIZE               `RVGPU_CONST_CU_PAGE_SIZE
`define RVGPU_CONST_MMU_PAGE_OFFSET_BITS        `RVGPU_CONST_CU_PAGE_OFFSET_BITS
`define RVGPU_CONST_MMU_PPN_BITS                `RVGPU_CONST_MMU_PA_WIDTH - `RVGPU_CONST_MMU_PAGE_OFFSET_BITS
`define RVGPU_CONST_MMU_VPN_BITS                `RVGPU_CONST_MMU_VA_WIDTH - `RVGPU_CONST_MMU_PAGE_OFFSET_BITS

// CU TLB条目数量
`define RVGPU_CONST_CU_TLB_ENTRIES              128
`define RVGPU_CONST_CU_TLB_INDEX_BITS           $clog2(`RVGPU_CONST_CU_TLB_ENTRIES)
`define RVGPU_CONST_CU_TLB_TAG_BITS             `RVGPU_CONST_MMU_VA_WIDTH - `RVGPU_CONST_CU_TLB_INDEX_BITS - `RVGPU_CONST_MMU_PAGE_OFFSET_BITS

// GPC TLB条目数量
`define RVGPU_CONST_GPC_MMU_TLB_ENTRIES         64
`define RVGPU_CONST_GPC_MMU_TLB_INDEX_BITS      $clog2(`RVGPU_CONST_GPC_MMU_TLB_ENTRIES)
`define RVGPU_CONST_GPC_MMU_TLB_TAG_BITS        `RVGPU_CONST_MMU_VA_WIDTH - `RVGPU_CONST_GPC_MMU_TLB_INDEX_BITS - `RVGPU_CONST_MMU_PAGE_OFFSET_BITS

`endif // RVGPU_CONSTANT_SVH