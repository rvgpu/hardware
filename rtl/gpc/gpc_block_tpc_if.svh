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

// Block Scheduler与TPC之间的接口，用于Warp分发
interface gpc_block_tpc_if;
    // Warp分发通道 (Block Scheduler -> TPC)
    logic                warp_valid;      // Warp有效
    logic                warp_ready;      // TPC准备好接收Warp
    logic [31:0]         warp_id;         // Warp ID
    logic [31:0]         block_id;        // Block ID
    logic [63:0]         program_addr;    // 程序地址
    logic [63:0]         arglist_ptr;     // 参数列表指针
    logic [31:0]         argument_size;   // 参数大小
    logic [31:0]         thread_mask;     // 线程掩码
    logic [255:0]        arglist_data;    // 参数列表数据
    
    // 完成通道 (TPC -> Block Scheduler)
    logic                complete_valid;  // 完成信号有效
    logic                complete_ready;  // Block Scheduler准备好接收完成信号
    logic [31:0]         complete_warp_id; // 完成的Warp ID
    logic                complete_status; // 完成状态 (0=成功, 1=失败)
    
    // 模块端口
    modport scheduler (
        output warp_valid, warp_id, block_id, program_addr, arglist_ptr, argument_size, thread_mask, arglist_data, complete_ready,
        input  warp_ready, complete_valid, complete_warp_id, complete_status
    );
    
    modport tpc (
        input  warp_valid, warp_id, block_id, program_addr, arglist_ptr, argument_size, thread_mask, arglist_data, complete_ready,
        output warp_ready, complete_valid, complete_warp_id, complete_status
    );
    
    // 任务和函数
    // Block Scheduler使用的任务
    task send_warp(
        input logic [31:0] w_id,
        input logic [31:0] b_id,
        input logic [63:0] prog_addr,
        input logic [63:0] arg_ptr,
        input logic [31:0] arg_size,
        input logic [31:0] t_mask,
        input logic [255:0] arg_data
    );
        warp_valid = 1'b1;
        warp_id = w_id;
        block_id = b_id;
        program_addr = prog_addr;
        arglist_ptr = arg_ptr;
        argument_size = arg_size;
        thread_mask = t_mask;
        arglist_data = arg_data;
        
        @(posedge warp_ready);
        warp_valid = 1'b0;
    endtask
    
    // TPC使用的任务
    task receive_warp(
        output logic [31:0] w_id,
        output logic [31:0] b_id,
        output logic [63:0] prog_addr,
        output logic [63:0] arg_ptr,
        output logic [31:0] arg_size,
        output logic [31:0] t_mask,
        output logic [255:0] arg_data
    );
        warp_ready = 1'b1;
        @(posedge warp_valid);
        w_id = warp_id;
        b_id = block_id;
        prog_addr = program_addr;
        arg_ptr = arglist_ptr;
        arg_size = argument_size;
        t_mask = thread_mask;
        arg_data = arglist_data;
        warp_ready = 1'b0;
    endtask
    
    // TPC使用的任务
    task send_complete(
        input logic [31:0] w_id,
        input logic status
    );
        complete_valid = 1'b1;
        complete_warp_id = w_id;
        complete_status = status;
        
        @(posedge complete_ready);
        complete_valid = 1'b0;
    endtask
    
    // Block Scheduler使用的任务
    task receive_complete(
        output logic [31:0] w_id,
        output logic status
    );
        complete_ready = 1'b1;
        @(posedge complete_valid);
        w_id = complete_warp_id;
        status = complete_status;
        complete_ready = 1'b0;
    endtask

endinterface : gpc_block_tpc_if

`endif // GPC_BLOCK_TPC_IF_SVH 