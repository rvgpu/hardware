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

`ifndef GPC_BLOCK_TPC_IF_SVH
`define GPC_BLOCK_TPC_IF_SVH

`include "rvgpu_typedef.svh"

// Block Scheduler与TPC之间的接口，用于Block分发
interface gpc_block_tpc_if;
    // Block分发通道 (Block Scheduler -> TPC)
    logic                block_valid;     // Block有效
    logic                block_ready;     // TPC准备好接收Block
    logic [31:0]         block_id;        // Block ID
    logic [31:0]         cluster_id;      // Cluster ID
    logic [63:0]         program_addr;    // 程序地址
    logic [63:0]         arglist_ptr;     // 参数列表指针
    logic [31:0]         argument_size;   // 参数大小
    logic [255:0]        arglist_data;    // 参数列表数据
    logic [31:0]         block_x, block_y, block_z;  // Block维度
    logic [31:0]         thread_x, thread_y, thread_z;  // Thread维度
    
    // Warp分发通道 (TPC -> SM)
    logic                warp_valid;      // Warp有效
    logic                warp_ready;      // SM准备好接收Warp
    logic [31:0]         warp_id;         // Warp ID
    logic [31:0]         warp_block_id;   // Warp所属的Block ID
    logic [63:0]         warp_program_addr; // 程序地址
    logic [63:0]         warp_arglist_ptr;  // 参数列表指针
    logic [31:0]         warp_argument_size; // 参数大小
    logic [31:0]         thread_mask;     // 线程掩码
    logic [255:0]        warp_arglist_data; // 参数列表数据
    
    // 完成通道 (TPC -> Block Scheduler)
    logic                complete_valid;  // 完成信号有效
    logic                complete_ready;  // Block Scheduler准备好接收完成信号
    logic [31:0]         complete_block_id; // 完成的Block ID
    logic                complete_status; // 完成状态 (0=成功, 1=失败)
    
    // 模块端口
    modport scheduler (
        output block_valid, block_id, cluster_id, program_addr, arglist_ptr, argument_size, arglist_data, 
               block_x, block_y, block_z, thread_x, thread_y, thread_z, complete_ready,
        input  block_ready, complete_valid, complete_block_id, complete_status
    );
    
    modport tpc (
        input  block_valid, block_id, cluster_id, program_addr, arglist_ptr, argument_size, arglist_data,
               block_x, block_y, block_z, thread_x, thread_y, thread_z, complete_ready,
        output block_ready, complete_valid, complete_block_id, complete_status,
        output warp_valid, warp_id, warp_block_id, warp_program_addr, warp_arglist_ptr, warp_argument_size, 
               thread_mask, warp_arglist_data,
        input  warp_ready
    );
    
    modport sm (
        input  warp_valid, warp_id, warp_block_id, warp_program_addr, warp_arglist_ptr, warp_argument_size, 
               thread_mask, warp_arglist_data,
        output warp_ready
    );
    
endinterface : gpc_block_tpc_if

`endif // GPC_BLOCK_TPC_IF_SVH 