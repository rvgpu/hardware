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

`ifndef INTERFACE_SM_BLOCK_SCHEDULER_SVH
`define INTERFACE_SM_BLOCK_SCHEDULER_SVH

`include "rvgpu_typedef.svh"
`include "rvgpu_config.svh"
`include "types_job_cluster.svh"

// Block Scheduler接口
// 用于router_arbiter与block_scheduler之间的通信
interface interface_sm_block_scheduler;
    // Block任务信号
    logic valid;
    t_job_cluster data;
    logic ready;
    
    // Block完成信号
    logic block_complete;
    t_job_cluster completed_job_cluster;
    
    // Router端口 - 发送Block任务，接收Block完成信号
    modport router_port (
        output valid, data,
        input  ready,
        input  block_complete, completed_job_cluster
    );
    
    // Scheduler端口 - 接收Block任务，发送Block完成信号
    modport scheduler_port (
        input  valid, data,
        output ready,
        output block_complete, completed_job_cluster
    );
endinterface

`endif // INTERFACE_SM_BLOCK_SCHEDULER_SVH