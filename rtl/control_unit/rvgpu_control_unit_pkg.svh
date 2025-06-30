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

`ifndef RVGPU_CONTROL_UNIT_PKG_SV
`define RVGPU_CONTROL_UNIT_PKG_SV

`include "rvgpu_constant.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_interface_axi.svh"

package rvgpu_control_unit_pkg;

    //=============================================================================
    // Control Unit Configuration Parameters
    //=============================================================================
    
    typedef struct packed {
        int unsigned max_payload_size;       // 最大Payload大小(字节)
        int unsigned page_size;              // 页面大小(字节)
        int unsigned tlb_entries;            // TLB条目数量
        int unsigned va_width;               // 虚拟地址位宽(位)
        int unsigned pa_width;               // 物理地址位宽(位)
        int unsigned axi_addr_width;         // AXI地址位宽(位)
        int unsigned axi_data_width;         // AXI数据位宽(位)
    } control_unit_config_t;
    
    // 默认配置参数
    localparam control_unit_config_t DEFAULT_CONTROL_UNIT_CONFIG = '{
        max_payload_size: `RVGPU_CONST_CONTROL_UNIT_CONFIG_MAX_PAYLOAD_SIZE,
        page_size: `RVGPU_CONST_CONTROL_UNIT_CONFIG_PAGE_SIZE,
        tlb_entries: `RVGPU_CONST_CONTROL_UNIT_CONFIG_TLB_ENTRIES,
        va_width: `RVGPU_CONST_CONTROL_UNIT_CONFIG_VA_WIDTH,
        pa_width: `RVGPU_CONST_CONTROL_UNIT_CONFIG_PA_WIDTH,
        axi_addr_width: `RVGPU_CONST_CONTROL_UNIT_CONFIG_AXI_ADDR_WIDTH,
        axi_data_width: `RVGPU_CONST_CONTROL_UNIT_CONFIG_AXI_DATA_WIDTH,
    };

    //=============================================================================
    // Command Package Data Structures  
    //=============================================================================
    
    // Command Package Header (64位/8字节) - 与C语言结构体字节序一致
    typedef struct packed {
        logic [15:0] payload_size;   // [63:48] 负载数据大小(字节)
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

    //=============================================================================
    // State Machine Definitions
    //=============================================================================
    
    // Command Processor主状态机
    typedef enum logic [3:0] {
        CP_IDLE             = 4'b0000,   // 空闲状态，等待START命令
        CP_MMU_CONFIG       = 4'b0001,   // 配置MMU页表
        CP_HEADER_FETCH     = 4'b0010,   // 读取Package Header
        CP_PAYLOAD_FETCH    = 4'b0011,   // 读取Package Payload  
        CP_TASK_DISPATCH    = 4'b0100,   // 向Shader Core分发任务
        CP_EXECUTION_MONITOR = 4'b0101,  // 监控任务执行状态
        CP_PACKAGE_CHECK    = 4'b0110,   // 检查是否还有更多Package
        CP_IRQ_TRIGGER      = 4'b0111,   // 触发中断
        CP_ERROR_HANDLER    = 4'b1000    // 错误处理状态
    } cp_state_t;

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

endpackage : rvgpu_control_unit_pkg

`endif // RVGPU_CONTROL_UNIT_PKG_SV