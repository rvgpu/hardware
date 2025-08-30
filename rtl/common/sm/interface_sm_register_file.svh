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

`ifndef INTERFACE_SM_REGISTER_FILE_SVH
`define INTERFACE_SM_REGISTER_FILE_SVH

`include "rvgpu_typedef.svh"
`include "rvgpu_config.svh"

// 寄存器文件接口
// 用于CUDA Core访问共享寄存器文件
interface interface_sm_register_file #(
    parameter int WARP_COUNT = `CONFIG_SM_WARP_COUNT,
    parameter int THREAD_COUNT = `CONFIG_WARP_THREAD_NUMBER
);
    // 时钟和复位
    logic clk;
    logic rst_n;
    
    // 读端口 (3个)
    logic [2:0] read_enable;
    logic [2:0][$clog2(WARP_COUNT)-1:0] read_warp_id;
    logic [2:0][4:0] read_reg_addr;
    logic [2:0][THREAD_COUNT-1:0][31:0] read_data;
    
    // 写端口 (1个)
    logic write_enable;
    logic [$clog2(WARP_COUNT)-1:0] write_warp_id;
    logic [4:0] write_reg_addr;
    logic [THREAD_COUNT-1:0][31:0] write_data;
    logic [THREAD_COUNT-1:0] write_mask;
    
    // Core端口
    modport core (
        input  clk, rst_n,
        output read_enable, read_warp_id, read_reg_addr,
        input  read_data,
        output write_enable, write_warp_id, write_reg_addr, write_data, write_mask
    );
    
    // 寄存器文件端口
    modport regfile (
        input  clk, rst_n,
        input  read_enable, read_warp_id, read_reg_addr,
        output read_data,
        input  write_enable, write_warp_id, write_reg_addr, write_data, write_mask
    );
endinterface

`endif // INTERFACE_SM_REGISTER_FILE_SVH
