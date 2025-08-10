//=============================================================================
// Copyright © 2025 RVGPU Team
// Licensed under the Apache License, Version 2.0 (the "License");
// You may not use this file except in compliance with the License.
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

`ifndef RVGPU_INTERFACE_SM_REGFILE_SVH
`define RVGPU_INTERFACE_SM_REGFILE_SVH

`include "rvgpu_typedef.svh"

// SM寄存器文件读写接口（多端口）
interface interface_sm_regfile #(
    parameter int WARP_COUNT = 32,
    parameter int THREAD_COUNT = 32,
    parameter int READ_PORTS = 3,
    parameter int WRITE_PORTS = 2
);
    // 读端口
    logic [READ_PORTS-1:0]                                read_enable;
    logic [$clog2(WARP_COUNT)-1:0]                        read_warp_id[READ_PORTS];
    logic [4:0]                                           read_reg_addr[READ_PORTS];
    logic [31:0]                                          read_data[READ_PORTS][THREAD_COUNT];

    // 写端口
    logic [WRITE_PORTS-1:0]                               write_enable;
    logic [$clog2(WARP_COUNT)-1:0]                        write_warp_id[WRITE_PORTS];
    logic [4:0]                                           write_reg_addr[WRITE_PORTS];
    logic [31:0]                                          write_data[WRITE_PORTS][THREAD_COUNT];
    logic [THREAD_COUNT-1:0]                              write_mask[WRITE_PORTS];

    // 读写两端的视角
    modport rf_user (
        output read_enable, read_warp_id, read_reg_addr,
        input  read_data,
        output write_enable, write_warp_id, write_reg_addr, write_data, write_mask
    );

    modport rf_storage (
        input  read_enable, read_warp_id, read_reg_addr,
        output read_data,
        input  write_enable, write_warp_id, write_reg_addr, write_data, write_mask
    );

endinterface : interface_sm_regfile

`endif // RVGPU_INTERFACE_SM_REGFILE_SVH


