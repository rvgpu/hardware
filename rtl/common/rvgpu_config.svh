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
// Host Interface Configuration
//=============================================================================
`define HOST_INTERFACE_ADDR_WIDTH           64
`define HOST_INTERFACE_DATA_WIDTH           64

//=============================================================================
// Memory Interface Configuration
//=============================================================================
`define MEMORY_INTERFACE_ADDR_WIDTH         64
`define MEMORY_INTERFACE_DATA_WIDTH         128

//=============================================================================
// ShaderCore Configuration
//=============================================================================
`define SHADER_CORE_NUMBER                  2

//=============================================================================
// L2Cache Configuration
//=============================================================================
`define L2CACHE_SLICE_NUMBER                1
`define L2CACHE_SIZE                        512  // KB

//=============================================================================
// Debug Configuration
//=============================================================================
// `define RVGPU_ON_SIMULATION              1

`endif // RVGPU_CONFIG_SVH