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

//=============================================================================
// Command Package Header: Define the header of command package
//=============================================================================

// Command Package Header (64位/8字节)
typedef struct packed {
    logic [15:0] payload_size;   // [63:48] 负载数据大小
    logic [15:0] flags;          // [47:32] 标志位  
    logic [31:0] command_type;   // [31:0]  命令类型
} command_header_t;
    
// 命令类型定义
typedef enum logic [31:0] {
    CMD_COMPUTE_JOB      = 32'h00000001,  // 计算任务
    CMD_MEMORY_COPY      = 32'h00000002,  // 内存拷贝
    CMD_SYNCHRONIZATION  = 32'h00000003   // 同步操作
} command_type_t;
    
// 标志位定义
typedef struct packed {
    logic [13:0] reserved;      // [15:2] 保留位
    logic        high_priority; // [1] 高优先级任务
    logic        last_package;  // [0] 最后一个Package
} command_flags_t;

`endif // RVGPU_COMMAND_PACKAGE_SVH 