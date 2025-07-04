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

`ifndef RVGPU_CONTROL_UNIT_IF_SVH
`define RVGPU_CONTROL_UNIT_IF_SVH

//=============================================================================
// Control Unit Internal Interfaces
// 
// 控制单元内部模块间使用的Interface定义
// 命名规则：源模块_目标模块 (例如：adapter_cp, cp_mmu, cp_noc, mmu_noc)
//=============================================================================

//=============================================================================
// Control Interface - AXI Adapter <-> Command Processor
// 用于AXI Adapter与Command Processor之间的寄存器访问
//=============================================================================
interface control_if #(
    parameter int ADDR_WIDTH = 64,
    parameter int DATA_WIDTH = 64
);
    // Write Control Signals (AXI Adapter → Command Processor)
    logic                    ctrl_we;                   // 写使能
    logic [ADDR_WIDTH-1:0]   ctrl_addr;                 // 地址
    logic [DATA_WIDTH-1:0]   ctrl_wdata;                // 写数据
    
    // Read Data Signal (Command Processor → AXI Adapter)
    logic [DATA_WIDTH-1:0]   ctrl_rdata;                // 读数据
    
    // AXI Adapter port (initiates transactions)
    modport axiadapter_port (
        output ctrl_we, ctrl_addr, ctrl_wdata,
        input  ctrl_rdata
    );
    
    // Command Processor port (responds to transactions)
    modport cp_port (
        input  ctrl_we, ctrl_addr, ctrl_wdata,
        output ctrl_rdata
    );
endinterface : control_if

//=============================================================================
// Job Dispatcher Interface - Command Processor <-> Job Dispatcher
// 用于Command Processor与Job Dispatcher之间的控制通信
//=============================================================================
interface job_dispatcher_if;
    // Control Channel (Command Processor → Job Dispatcher)
    logic                    enable;         // 使能信号
    logic                    reset;          // 复位信号
    logic [63:0]             package_addr;   // Package基地址
    logic [63:0]             mmu_addr;       // MMU页表基地址
    
    // Status Channel (Job Dispatcher → Command Processor)
    logic                    complete;       // 完成信号
    logic                    error;          // 错误信号
    logic                    busy;           // 忙碌状态
    
    // Command Processor port (controls Job Dispatcher)
    modport cp_port (
        output enable, reset, package_addr, mmu_addr,
        input  complete, error, busy
    );
    
    // Job Dispatcher port (receives control signals)
    modport jd_port (
        input  enable, reset, package_addr, mmu_addr,
        output complete, error, busy
    );
endinterface : job_dispatcher_if

//=============================================================================
// MMU Interface - Command Processor ↔ MMU
// 用于Command Processor与MMU之间的地址转换请求
//=============================================================================
interface mmu_if #(
    parameter int VA_WIDTH = 48,
    parameter int PA_WIDTH = 48
);
    // Request Channel
    logic                    req_valid;
    logic [VA_WIDTH-1:0]     req_vaddr;
    logic                    req_read;
    logic                    req_write;
    logic                    req_ready;
    
    // Response Channel
    logic                    resp_valid;
    logic [PA_WIDTH-1:0]     resp_paddr;
    logic                    resp_hit;
    logic [1:0]              resp_status;
    logic                    resp_ready;
    
    // Command Processor port (requests address translation)
    modport cp_port (
        output req_valid, req_vaddr, req_read, req_write,
        input  req_ready,
        input  resp_valid, resp_paddr, resp_hit, resp_status,
        output resp_ready
    );
    
    // MMU port (performs address translation)
    modport mmu_port (
        input  req_valid, req_vaddr, req_read, req_write,
        output req_ready,
        output resp_valid, resp_paddr, resp_hit, resp_status,
        input  resp_ready
    );
endinterface : mmu_if

`endif // RVGPU_CONTROL_UNIT_IF_SVH 