#ifndef RVGPU_REGISTERS_HPP
#define RVGPU_REGISTERS_HPP

#include <cstdint>

//=============================================================================
// RVGPU寄存器定义
//=============================================================================

enum class RVGPU_REG : uint32_t {
    // 控制寄存器
    START_REG = 0x0000,           // 启动寄存器
    STATUS_REG = 0x0004,          // 状态寄存器
    IRQ_STATUS_REG = 0x0008,      // 中断状态寄存器
    IRQ_MASK_REG = 0x000C,        // 中断掩码寄存器
    
    // MMU寄存器
    MMU_PAGETABLE_LO = 0x0010,    // MMU页表低32位
    MMU_PAGETABLE_HI = 0x0014,    // MMU页表高32位
    MMU_CONFIG_REG = 0x0018,      // MMU配置寄存器
    
    // 命令寄存器
    COMMAND_PACKET_LO = 0x0020,   // 命令包低32位
    COMMAND_PACKET_HI = 0x0024,   // 命令包高32位
    COMMAND_STATUS_REG = 0x0028,  // 命令状态寄存器
    
    // 内存寄存器
    VRAM_BASE_LO = 0x0030,        // VRAM基地址低32位
    VRAM_BASE_HI = 0x0034,        // VRAM基地址高32位
    VRAM_SIZE_REG = 0x0038,       // VRAM大小寄存器
    
    // 调试寄存器
    DEBUG_REG = 0x0040,           // 调试寄存器
    DEBUG_MODE_REG = 0x0044,      // 调试模式寄存器
};

// 寄存器地址转换为整数
inline uint32_t reg_addr(RVGPU_REG reg) {
    return static_cast<uint32_t>(reg);
}

#endif // RVGPU_REGISTERS_HPP 