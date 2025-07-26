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
`define HOST_INTERFACE_ADDR_WIDTH           64
`define HOST_INTERFACE_DATA_WIDTH           64

//=============================================================================
// Memory Interface Configuration (AXI Master)
//=============================================================================
`define MEMORY_INTERFACE_ADDR_WIDTH         64
`define MEMORY_INTERFACE_DATA_WIDTH         256

//=============================================================================
// GPC(Graphics Processing Core) Configuration
//=============================================================================
`define GPC_NUMBER                          2      // GPC数量
`define GPC_TPC_NUMBER                      4      // 每个GPC的TPC数量
`define TPC_SM_NUMBER                       2      // 每个TPC的SM数量
`define SM_CUDACORE_NUMBER                  32     // 每个SM的CUDACore数量
`define WARP_THREAD_NUMBER                  32     // 每个WARP的线程数

//=============================================================================
// L2Cache Configuration
//=============================================================================
`define L2CACHE_SLICE_NUMBER                1
`define L2CACHE_SIZE                        512  // KB

//=============================================================================
// Debug Configuration
//=============================================================================
`define RVGPU_CONFIG_DEBUG_ENABLE           1

`endif // RVGPU_CONFIG_SVH