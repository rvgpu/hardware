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

`ifndef RVGPU_JOB_BLOCK_SVH
`define RVGPU_JOB_BLOCK_SVH

//=============================================================================
// Command/Job Block 两层调度设计说明
//=============================================================================
//
// 1. command_t（见 rvgpu_command_package.svh）
//    - 由 Host 下发，描述一次 kernel 启动的全局信息，包括：
//      * command_header_t   [127:0]   ：next_command, payload_size, flags, command_type
//      * command_program_t  [255:128] ：program_addr, work_dim, argument_size
//    - 一次 NOC/L2 传输 256bit，正好传递一个 command_t。
//
// 2. job_block_t（本文件定义）
//    - 由 JD 根据 command_t 拆分生成，代表一个 block 的调度单元。
//    - 字段包括：
//      * arglist_ptr        [255:196]：参数列表指针
//      * reserved1          [195:154]：保留
//      * argument_size      [153:128]：参数数量
//      * program_addr       [127:64] ：程序入口
//      * reserved0          [63:32]  ：保留
//      * current_block_id   [31:0]   ：当前 block 的 ID
//    - job_block_t 也是 256bit，便于一次 NOC 传输。
//    - JD 会根据 command_t 的 work_dim，生成多个 job_block_t，分别下发给各 GPC。
//
// 3. 调度流程
//    - JD 先接收并解析 command_t。
//    - 按照 work_dim 拆分出所有 block，生成对应 job_block_t。
//    - 每个 job_block_t 作为一个调度单元，通过 NOC 下发给 GPC。
//    - GPC 收到 job_block_t 后，进一步调度 warp。
//
// 这样实现了 coarse-grained（command）和 fine-grained（job_block）两层调度。
//=============================================================================

typedef struct packed {
    logic [63:0]                arglist_ptr;        // [255:196]
    logic [31:0]                reserved1;          // [195:154]
    logic [31:0]                argument_size;      // [153:128]
    logic [63:0]                program_addr;       // [127:64]
    logic [31:0]                reserved0;          // [63:32]
    logic [31:0]                current_block_id;   // [31:0]
} job_block_t;

function automatic build_job_block(
    input logic [63:0]                arglist_ptr,
    input logic [31:0]                argument_size,
    input logic [63:0]                program_addr,
    input logic [31:0]                current_block_id
);
    job_block_t job_block;
    job_block.arglist_ptr = arglist_ptr;
    job_block.reserved1 = 32'h0;
    job_block.argument_size = argument_size;
    job_block.program_addr = program_addr;
    job_block.reserved0 = 32'h0;
    job_block.current_block_id = current_block_id;
    return job_block;
endfunction

`endif // RVGPU_JOB_BLOCK_SVH