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

`ifndef RVGPU_COMMAND_PACKAGE_SVH
`define RVGPU_COMMAND_PACKAGE_SVH

`include "rvgpu_config.svh"

//=============================================================================
// Host控制GPU的Command包
//=============================================================================

typedef enum logic [3:0] {
    CMD_COMPUTE_JOB      = 4'h0,  // 计算任务
    CMD_MEMORY_COPY      = 4'h1,  // 内存拷贝
    CMD_SYNCHRONIZATION  = 4'h2   // 同步操作
} command_type_t;

// Header 的定义： [95:0]
typedef struct packed {
    logic [15:0] grid_z;
    logic [15:0] grid_y;
    logic [15:0] grid_x;
    logic [3:0]  cluster_z;
    logic [11:0] block_z;
    logic [3:0]  cluster_y;
    logic [11:0] block_y;
    logic [3:0]  cluster_x;
    logic [11:0] block_x;
} job_dimention_t;

typedef struct packed {
    job_dimention_t     job_dim;
    logic [23:0]        reserved0;
    logic               last;
    logic [2:0]         size;       // 0: 128 bits, 1: 256 bits, 2: 512 bits, 3: 1024 bits
    logic [3:0]         cmd_type;   // 0: compute, 1: memory, 2: synchronization
} command_compute_header_t;

// Program 的定义： [127:0]
typedef struct packed {
    logic [31:0]            reserved0;
    logic [31:0]            argument_size; // [31:0]
    logic [63:0]            program_addr;  // [127:64]
} command_compute_program_t;

typedef struct packed {
    command_compute_program_t   prog;       // [255:128] program
    command_compute_header_t    header;     // [127:0] header
} command_compute_t;

typedef union packed {
    command_compute_t       compute;
} command_t;

//=============================================================================
// 功能函数的定义
//=============================================================================

function automatic string command_compute_header_to_string(
    input command_compute_header_t header
);
    case (header.cmd_type)
        CMD_COMPUTE_JOB: 
            return $sformatf("{grid: {%d, %d, %d}, cluster: {%d, %d, %d}, block: {%d, %d, %d}, last: %d, size: %h, type: %h}", header.job_dim.grid_x, header.job_dim.grid_y, header.job_dim.grid_z, header.job_dim.cluster_x, header.job_dim.cluster_y, header.job_dim.cluster_z, header.job_dim.block_x, header.job_dim.block_y, header.job_dim.block_z, header.last, header.size, header.cmd_type);
        CMD_MEMORY_COPY: 
            return $sformatf("memory copy");
        CMD_SYNCHRONIZATION: 
            return $sformatf("synchronization");
        default: 
            return $sformatf("unknown type: %h", header.cmd_type);
    endcase
endfunction

function automatic string command_compute_program_to_string(
    input command_compute_program_t prog
);
    return $sformatf("{arg_size: %d, program_addr: %h}", prog.argument_size, prog.program_addr);
endfunction

function automatic string command_compute_to_string(
    input command_compute_t cmd
);
    return $sformatf("header: %s, program: %s", command_compute_header_to_string(cmd.header), command_compute_program_to_string(cmd.prog));
endfunction

`endif // RVGPU_COMMAND_PACKAGE_SVH 