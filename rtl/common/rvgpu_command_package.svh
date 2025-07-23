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

// 标志位定义
typedef struct packed {
    logic [13:0] reserved;      // [15:2] 保留位
    logic        high_priority; // [1] 高优先级任务
    logic        last_package;  // [0] 最后一个Package
} command_flags_t;

typedef enum logic [31:0] {
    CMD_COMPUTE_JOB      = 32'h00000001,  // 计算任务
    CMD_MEMORY_COPY      = 32'h00000002,  // 内存拷贝
    CMD_SYNCHRONIZATION  = 32'h00000003   // 同步操作
} command_type_t;

// Command Package Header (64位/8字节)
typedef struct packed {
    logic [63:0]        next_command;   // [127:64]
    logic [15:0]        payload_size;   // [63:48] 负载数据大小
    command_flags_t     flags;          // [47:32] 标志位  
    command_type_t      command_type;   // [31:0]  命令类型
} command_header_t;

typedef struct packed {
    logic [7:0] x;
    logic [7:0] y;
    logic [7:0] z;
    logic [7:0] w;
} command_work_dim_t;

typedef struct packed {
    logic [31:0]            argument_size; // [31:0]
    command_work_dim_t      work_dim;      // [63:32]
    logic [63:0]            program_addr;  // [127:64]
} command_program_t;

typedef struct packed {
    command_program_t   prog;       // [255:128]
    command_header_t    header;     // [127:0]
} command_t;

function automatic command_header_t build_command_header(
    input logic [15:0] payload_size,
    input logic [15:0] flags,
    input logic [31:0] command_type
);
    command_header_t header;
    header.payload_size = payload_size;
    header.flags = flags;
    header.command_type = command_type;
    return header;
endfunction

function automatic logic [7:0] command_get_block_count(
    input command_t cmd
);
    return cmd.prog.work_dim.x;
endfunction

function automatic string command_header_to_string(
    input command_header_t header
);
    return $sformatf("{next: %h, size: %h, flags: {%d, %d}, type: %h}", header.next_command, header.payload_size, header.flags.high_priority, header.flags.last_package, header.command_type);
endfunction

function automatic string command_program_to_string(
    input command_program_t prog
);
    return $sformatf("{arg_size: %d, work_dim: {%d, %d, %d, %d}, prog_addr: %h}", prog.argument_size, prog.work_dim.x, prog.work_dim.y, prog.work_dim.z, prog.work_dim.w, prog.program_addr);
endfunction

function automatic string command_to_string(
    input command_t cmd
);
    return $sformatf("header: %s, program: %s", command_header_to_string(cmd.header), command_program_to_string(cmd.prog));
endfunction

`endif // RVGPU_COMMAND_PACKAGE_SVH 