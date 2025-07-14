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

#ifndef RVGPU_REGISTER_HPP
#define RVGPU_REGISTER_HPP

#include <cstdint>

//=============================================================================
// Register Addresses
//=============================================================================

// Command Processor寄存器地址映射
constexpr uint16_t REG_MMU_PAGETABLE_LO    = 0x0000;  // 页表基地址低32位
constexpr uint16_t REG_MMU_PAGETABLE_HI    = 0x0004;  // 页表基地址高32位
constexpr uint16_t REG_COMMAND_PACKET_LO   = 0x0008;  // Package数组虚拟地址低32位
constexpr uint16_t REG_COMMAND_PACKET_HI   = 0x000C;  // Package数组虚拟地址高32位
constexpr uint16_t REG_CONTROL             = 0x0010;  // 控制寄存器
constexpr uint16_t REG_STATUS              = 0x0014;  // 状态寄存器
constexpr uint16_t REG_IRQ_STATUS          = 0x0018;  // 中断状态寄存器

//=============================================================================
// Register Bit Field Definitions
//=============================================================================

// 控制寄存器位域定义
struct control_reg_t {
    uint32_t reserved : 29;  // [31:3] 保留位
    uint32_t irq_en   : 1;  // [2] 中断使能  
    uint32_t reset    : 1;  // [1] 复位Command Processor
    uint32_t start    : 1;  // [0] 启动GPU工作
};

// 状态寄存器位域定义
struct status_reg_t {
    uint32_t reserved  : 28;  // [31:4] 保留位
    uint32_t mmu_ready : 1;   // [3] MMU配置完成
    uint32_t error     : 1;   // [2] 发生错误
    uint32_t complete  : 1;   // [1] 任务完成
    uint32_t idle      : 1;   // [0] GPU空闲
};

// 中断状态寄存器位域定义
struct irq_status_reg_t {
    uint32_t reserved    : 30;  // [31:2] 保留位
    uint32_t error_irq   : 1;   // [1] 错误中断状态 (写1清除)
    uint32_t complete_irq : 1;  // [0] 完成中断状态 (写1清除)
};

//=============================================================================
// Register Bit Masks
//=============================================================================

// 控制寄存器位掩码
constexpr uint32_t CTRL_IRQ_EN_MASK  = 0x00000004;  // [2] 中断使能
constexpr uint32_t CTRL_RESET_MASK    = 0x00000002;  // [1] 复位
constexpr uint32_t CTRL_START_MASK    = 0x00000001;  // [0] 启动

// 状态寄存器位掩码
constexpr uint32_t STATUS_MMU_READY_MASK = 0x00000008;  // [3] MMU就绪
constexpr uint32_t STATUS_ERROR_MASK     = 0x00000004;  // [2] 错误
constexpr uint32_t STATUS_COMPLETE_MASK  = 0x00000002;  // [1] 完成
constexpr uint32_t STATUS_IDLE_MASK      = 0x00000001;  // [0] 空闲

// 中断状态寄存器位掩码
constexpr uint32_t IRQ_ERROR_MASK    = 0x00000002;  // [1] 错误中断
constexpr uint32_t IRQ_COMPLETE_MASK = 0x00000001;  // [0] 完成中断

#endif // RVGPU_REGISTER_HPP 