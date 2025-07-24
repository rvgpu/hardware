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

`ifndef GPC_NOC_ADAPTER_IF_SVH
`define GPC_NOC_ADAPTER_IF_SVH

`include "rvgpu_typedef.svh"
`include "rvgpu_job_block.svh"

// NOC Adapter接口，用于NOC Adapter和Block Scheduler之间的通信
interface gpc_noc_adapter_if;
    // Job Block通道 (NOC Adapter -> Block Scheduler)
    logic                job_valid;      // Job有效
    logic                job_ready;      // Block Scheduler准备好接收Job
    job_block_t          job_block;      // Job Block数据
    
    // 模块端口
    modport noc_adapter (
        output job_valid, job_block,
        input  job_ready
    );
    
    modport device (
        input  job_valid, job_block,
        output job_ready
    );
    
    // 任务和函数
    // NOC Adapter使用的任务
    task send_job(
        input job_block_t block
    );
        job_valid = 1'b1;
        job_block = block;
        
        @(posedge job_ready);
        job_valid = 1'b0;
    endtask
    
    // Block Scheduler使用的任务
    task receive_job(
        output job_block_t block
    );
        job_ready = 1'b1;
        @(posedge job_valid);
        block = job_block;
        job_ready = 1'b0;
    endtask

endinterface : gpc_noc_adapter_if

`endif // GPC_NOC_ADAPTER_IF_SVH 