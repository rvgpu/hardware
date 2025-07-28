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

`include "rvgpu_sram_if.svh"
`include "rvgpu_control_unit_pkg.svh"
`include "rvgpu_axi_config.svh"
`include "rvgpu_mmu_if.svh"

`ifndef RVGPU_CONTROL_UNIT_PKG_IMPORTED
`define RVGPU_CONTROL_UNIT_PKG_IMPORTED
import rvgpu_control_unit_pkg::*;
`endif // RVGPU_CONTROL_UNIT_PKG_IMPORTED

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
    parameter control_unit_config_t CU_CONFIG = DEFAULT_CONTROL_UNIT_CONFIG
);
    // Write Control Signals (AXI Adapter → Command Processor)
    logic                                            ctrl_we;    // 写使能
    logic [DEFAULT_HOST_AXI_CONFIG.addr_width-1:0]   ctrl_addr;  // 地址
    logic [DEFAULT_HOST_AXI_CONFIG.data_width-1:0]   ctrl_wdata; // 写数据
    
    // Read Data Signal (Command Processor → AXI Adapter)
    logic [DEFAULT_HOST_AXI_CONFIG.data_width-1:0]   ctrl_rdata; // 读数据
    
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

// 错误状态位定义
// error_status[7:0] 详细错误状态位，支持多种错误类型
// error_status[0] - MMU页面错误
// error_status[1] - NOC通信错误  
// error_status[2] - 非法命令类型
// error_status[3] - Payload大小超限
// error_status[4] - 地址未对齐
// error_status[5] - 阶段错误
// error_status[6] - 超时错误（预留）
// error_status[7] - 未知错误（预留）

interface job_dispatcher_if;
    // Control Channel (Command Processor → Job Dispatcher)
    logic                    enable;         // 使能信号
    logic                    reset;          // 复位信号
    logic [63:0]             package_addr;   // Package基地址
    logic [63:0]             mmu_addr;       // MMU页表基地址
    
    // Status Channel (Job Dispatcher → Command Processor)
    logic                    complete;       // 完成信号
    logic                    error;          // 错误信号（综合错误状态）
    logic [7:0]              error_status;   // 详细错误状态位
    logic                    busy;           // 忙碌状态
    
    // Command Processor port (controls Job Dispatcher)
    modport cp_port (
        output enable, reset, package_addr, mmu_addr,
        input  complete, error, error_status, busy
    );
    
    // Job Dispatcher port (receives control signals)
    modport jd_port (
        input  enable, reset, package_addr, mmu_addr,
        output complete, error, error_status, busy
    );
endinterface : job_dispatcher_if



//=============================================================================
// TLB Interface - MMU <-> TLB SRAM
// 用于MMU与TLB SRAM之间的查找和更新操作
//=============================================================================
interface tlb_if #(
    parameter int TLB_ENTRIES = 128,
    parameter int TLB_TAG_BITS = 29,
    parameter int PPN_BITS = 36
);
    // tlb_entry_t 类型现在在 rvgpu_control_unit_pkg 中定义
    
    // TLB专用控制信号
    logic                               tlb_lookup_valid;
    logic [TLB_TAG_BITS+$clog2(TLB_ENTRIES)-1:0] tlb_lookup_addr;  // {标签, 索引}
    logic [69:0]                        tlb_lookup_data;
    logic                               tlb_lookup_hit;
    logic                               tlb_lookup_ready;
    
    logic                               tlb_update_valid;
    logic [TLB_TAG_BITS+$clog2(TLB_ENTRIES)-1:0] tlb_update_addr;  // {标签, 索引}
    logic [69:0]                        tlb_update_data;
    logic                               tlb_update_ready;
    
    // Master modport (MMU控制器)
    modport mmu_port (
        output tlb_lookup_valid, tlb_lookup_addr,
        input  tlb_lookup_data, tlb_lookup_hit, tlb_lookup_ready,
        output tlb_update_valid, tlb_update_addr, tlb_update_data,
        input  tlb_update_ready
    );
    
    // Slave modport (TLB SRAM)
    modport tlb_port (
        input  tlb_lookup_valid, tlb_lookup_addr,
        output tlb_lookup_data, tlb_lookup_hit, tlb_lookup_ready,
        input  tlb_update_valid, tlb_update_addr, tlb_update_data,
        output tlb_update_ready
    );
    
    // 时钟绑定
    modport clk_mp (
        input  tlb_lookup_valid, tlb_lookup_addr,
        output tlb_lookup_data, tlb_lookup_hit, tlb_lookup_ready,
        input  tlb_update_valid, tlb_update_addr, tlb_update_data,
        output tlb_update_ready
    );
    
endinterface : tlb_if

`endif // RVGPU_CONTROL_UNIT_IF_SVH 