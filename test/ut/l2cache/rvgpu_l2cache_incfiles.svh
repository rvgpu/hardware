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

//=============================================================================
// RVGPU L2 Cache Include File
// 
// 包含所有 L2 Cache 测试所需的 RTL 文件
//=============================================================================

`ifndef RVGPU_L2CACHE_INCFILES_SVH
`define RVGPU_L2CACHE_INCFILES_SVH

// 通用文件
`include "rvgpu_constant.svh"
`include "rvgpu_config.svh"
`include "clk_and_reset.svh"

// NOC 相关文件
`include "rvgpu_internal_noc_pkg.svh"
`include "rvgpu_internal_noc_if.svh"

// GPU Top 接口文件
`include "rvgpu_interface_axi.svh"

// SRAM 接口文件
`include "rvgpu_sram_if.svh"
`include "rvgpu_sram_sp_sim.sv"

// L2 Cache 相关文件
`include "rvgpu_l2cache_common.svh"
`include "rvgpu_l2cache_if.svh"
`include "rvgpu_l2cache_controller.sv"
`include "rvgpu_l2cache_tag_array.sv"
`include "rvgpu_l2cache_data_array.sv"
`include "rvgpu_l2cache_axi_adapter.sv"
`include "rvgpu_l2cache_noc_adapter.sv"
`include "rvgpu_fifo_basic.sv"
`include "rvgpu_l2cache.sv"

`endif // RVGPU_L2CACHE_INCFILES_SVH 
