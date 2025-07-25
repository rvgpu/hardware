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

`ifndef GPC_BLOCK_RASTER_IF_SVH
`define GPC_BLOCK_RASTER_IF_SVH

`include "rvgpu_typedef.svh"

// Block Scheduler与Raster Engine之间的接口
interface gpc_block_raster_if;
    // 命令通道 (Block Scheduler -> Raster Engine)
    logic                cmd_valid;      // 命令有效
    logic                cmd_ready;      // Raster Engine准备好接收命令
    logic [63:0]         cmd_addr;       // 命令地址
    logic [63:0]         cmd_data;       // 命令数据
    logic [31:0]         cmd_size;       // 命令大小
    
    // 完成通道 (Raster Engine -> Block Scheduler)
    logic                complete_valid;  // 完成信号有效
    logic                complete_ready;  // Block Scheduler准备好接收完成信号
    logic [31:0]         complete_id;     // 完成的命令ID
    logic                complete_status; // 完成状态 (0=成功, 1=失败)
    
    // 模块端口
    modport scheduler (
        output cmd_valid, cmd_addr, cmd_data, cmd_size, complete_ready,
        input  cmd_ready, complete_valid, complete_id, complete_status
    );
    
    modport raster (
        input  cmd_valid, cmd_addr, cmd_data, cmd_size, complete_ready,
        output cmd_ready, complete_valid, complete_id, complete_status
    );
    
endinterface : gpc_block_raster_if

`endif // GPC_BLOCK_RASTER_IF_SVH 