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

`ifndef RVGPU_CONSTANT_MMU_SVH
`define RVGPU_CONSTANT_MMU_SVH

`include "rvgpu_constant.svh"

//=============================================================================
// 公共MMU配置 - 所有MMU类型共用
//=============================================================================

// 地址位宽 - 所有MMU类型共用
`define RVGPU_CONST_MMU_VA_WIDTH                `RVGPU_CONST_CU_VA_WIDTH
`define RVGPU_CONST_MMU_PA_WIDTH                `RVGPU_CONST_CU_PA_WIDTH
`define RVGPU_CONST_MMU_PAGE_SIZE               `RVGPU_CONST_CU_PAGE_SIZE
`define RVGPU_CONST_MMU_PAGE_OFFSET_BITS        `RVGPU_CONST_CU_PAGE_OFFSET_BITS
`define RVGPU_CONST_MMU_PPN_BITS                `RVGPU_CONST_MMU_PA_WIDTH - `RVGPU_CONST_MMU_PAGE_OFFSET_BITS

//=============================================================================
// CU TLB特定配置
//=============================================================================

// CU TLB条目数量
`define RVGPU_CONST_CU_TLB_ENTRIES              128
`define RVGPU_CONST_CU_TLB_INDEX_BITS           $clog2(`RVGPU_CONST_CU_TLB_ENTRIES)
`define RVGPU_CONST_CU_TLB_TAG_BITS             `RVGPU_CONST_MMU_VA_WIDTH - `RVGPU_CONST_CU_TLB_INDEX_BITS - `RVGPU_CONST_MMU_PAGE_OFFSET_BITS

//=============================================================================
// GPC TLB特定配置
//=============================================================================

// GPC TLB条目数量
`define RVGPU_CONST_GPC_MMU_TLB_ENTRIES         64
`define RVGPU_CONST_GPC_MMU_TLB_INDEX_BITS      $clog2(`RVGPU_CONST_GPC_MMU_TLB_ENTRIES)
`define RVGPU_CONST_GPC_MMU_TLB_TAG_BITS        `RVGPU_CONST_MMU_VA_WIDTH - `RVGPU_CONST_GPC_MMU_TLB_INDEX_BITS - `RVGPU_CONST_MMU_PAGE_OFFSET_BITS

`endif // RVGPU_CONSTANT_MMU_SVH 