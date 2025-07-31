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

`ifndef RVGPU_CONFIG_SVH
`define RVGPU_CONFIG_SVH

//=============================================================================
// Host Interface Configuration (AXI-Lite Slave)
//=============================================================================
`define CONFIG_HOST_INTERFACE_ADDR_WIDTH    64
`define CONFIG_HOST_INTERFACE_DATA_WIDTH    64

//=============================================================================
// Memory Interface Configuration (AXI Master)
//=============================================================================
`define CONFIG_MEMORY_INTERFACE_ADDR_WIDTH  64
`define CONFIG_MEMORY_INTERFACE_DATA_WIDTH  256

//=============================================================================
// GPC(Graphics Processing Core) Configuration
//=============================================================================
`define CONFIG_GPC_NUMBER                   2      // GPC数量
`define CONFIG_GPC_TPC_NUMBER               4      // 每个GPC的TPC数量
`define CONFIG_TPC_SM_NUMBER                2      // 每个TPC的SM数量
`define CONFIG_SM_CUDACORE_NUMBER           32     // 每个SM的CUDACore数量
`define CONFIG_WARP_THREAD_NUMBER           32     // 每个WARP的线程数

//=============================================================================
// L2Cache Configuration
//=============================================================================
`define CONFIG_L2CACHE_SLICE_NUMBER         1
`define CONFIG_L2CACHE_WAYS                 8
`define CONFIG_L2CACHE_SETS                 1024
`define CONFIG_L2CACHE_LINE_WIDTH           256
`define CONFIG_L2CACHE_SIZE                 (`CONFIG_L2CACHE_WAYS * `CONFIG_L2CACHE_SETS * `CONFIG_L2CACHE_LINE_WIDTH / 8)

//=============================================================================
// Debug Configuration
//=============================================================================
`define CONFIG_DEBUG_EN                     1
`define CONFIG_DEBUG_MODULE                 32'hFFFFFFFF
`define CONFIG_DEBUG_CU_MASK                32'h00000001
`define CONFIG_DEBUG_GPC_MASK               32'h00000002
`define CONFIG_DEBUG_L2CACHE_MASK           32'h00000004
`define CONFIG_DEBUG_MMU_MASK               32'h00000008
`define CONFIG_DEBUG_NOC_MASK               32'h00000010

`endif // RVGPU_CONFIG_SVH