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
`define RVGPU_CONST_NOC_CONFIG_HEADER_WIDTH 32
`define RVGPU_CONST_NOC_CONFIG_DATA_WIDTH 256
`define RVGPU_CONST_NOC_CONFIG_NUM_SHADER_CORES `SHADER_CORE_NUMBER

// ================================================
//  Control Unit Configuration
// ================================================
`define RVGPU_CONST_CONTROL_UNIT_CONFIG_AXI_ADDR_WIDTH `HOST_INTERFACE_ADDR_WIDTH
`define RVGPU_CONST_CONTROL_UNIT_CONFIG_AXI_DATA_WIDTH `HOST_INTERFACE_DATA_WIDTH
`define RVGPU_CONST_CONTROL_UNIT_CONFIG_MAX_PAYLOAD_SIZE 256

`define RVGPU_CONST_CU_PAGE_SIZE 4096
`define RVGPU_CONST_CU_TLB_ENTRIES 128
`define RVGPU_CONST_CU_VA_WIDTH 39
`define RVGPU_CONST_CU_PA_WIDTH 39

`define RVGPU_CONST_CU_PAGE_OFFSET_BITS $clog2(`RVGPU_CONST_CU_PAGE_SIZE)
`define RVGPU_CONST_CU_TLB_INDEX_BITS $clog2(`RVGPU_CONST_CU_TLB_ENTRIES)
`define RVGPU_CONST_CU_TLB_TAG_BITS `RVGPU_CONST_CU_VA_WIDTH - `RVGPU_CONST_CU_TLB_INDEX_BITS - `RVGPU_CONST_CU_PAGE_OFFSET_BITS
`define RVGPU_CONST_CU_TLB_PPN_BITS `RVGPU_CONST_CU_PA_WIDTH - `RVGPU_CONST_CU_PAGE_OFFSET_BITS

`endif // RVGPU_CONSTANT_SVH