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

`ifndef RVGPU_REGISTER_SPACE_SVH
`define RVGPU_REGISTER_SPACE_SVH
//=============================================================================
// Register Addresses
//=============================================================================
    
// Command Processor寄存器地址映射
localparam logic [15:0] REG_MMU_PAGETABLE_LO    = 16'h0000;  // 页表基地址低32位
localparam logic [15:0] REG_MMU_PAGETABLE_HI    = 16'h0004;  // 页表基地址高32位
localparam logic [15:0] REG_COMMAND_PACKET_LO   = 16'h0008;  // Package数组虚拟地址低32位
localparam logic [15:0] REG_COMMAND_PACKET_HI   = 16'h000C;  // Package数组虚拟地址高32位
localparam logic [15:0] REG_CONTROL             = 16'h0010;  // 控制寄存器
localparam logic [15:0] REG_STATUS              = 16'h0014;  // 状态寄存器
localparam logic [15:0] REG_IRQ_STATUS          = 16'h0018;  // 中断状态寄存器
    
// 控制寄存器位域定义
typedef struct packed {
    logic [28:0] reserved;      // [31:3] 保留位
    logic        irq_en;        // [2] 中断使能  
    logic        reset;         // [1] 复位Command Processor
    logic        start;         // [0] 启动GPU工作
} control_reg_t;
    
// 状态寄存器位域定义
typedef struct packed {
    logic [27:0] reserved;      // [31:4] 保留位
    logic        mmu_ready;     // [3] MMU配置完成
    logic        error;         // [2] 发生错误
    logic        complete;      // [1] 任务完成
    logic        idle;          // [0] GPU空闲
} status_reg_t;
    
// 中断状态寄存器位域定义
typedef struct packed {
    logic [29:0] reserved;      // [31:2] 保留位
    logic        error_irq;     // [1] 错误中断状态 (写1清除)
    logic        complete_irq;  // [0] 完成中断状态 (写1清除)
} irq_status_reg_t;

`endif // RVGPU_REGISTER_SPACE_SVH