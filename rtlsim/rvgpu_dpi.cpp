#include "../simtop/rvgpu_simulator.hpp"
#include "../csim/rvgpu_csim.hpp"
#include <iostream>
#include <memory>

//=============================================================================
// DPI全局变量
//=============================================================================

static std::unique_ptr<rvgpu_simulator> g_rvgpu_sim = nullptr;

//=============================================================================
// DPI函数实现
//=============================================================================

extern "C" {

// 初始化
void rvgpu_dpi_init(long long vram_size) {
    try {
        // 使用 rvgpu_simulator 来支持不同的模拟器类型
        // 默认使用 CSIM，但可以通过环境变量或其他方式选择
        g_rvgpu_sim = std::make_unique<rvgpu_simulator>(RVGPU_SIM_TYPE::RVGPU_CSIM, vram_size);
        std::cout << "RVGPU DPI initialized with " << vram_size / (1024*1024) << "MB VRAM" << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Error initializing RVGPU DPI: " << e.what() << std::endl;
    }
}

// 清理
void rvgpu_dpi_cleanup() {
    g_rvgpu_sim.reset();
    std::cout << "RVGPU DPI cleaned up" << std::endl;
}

// 寄存器访问
unsigned int rvgpu_dpi_read_reg(unsigned int addr) {
    if (!g_rvgpu_sim) {
        std::cerr << "Error: RVGPU SIM not initialized" << std::endl;
        return 0;
    }
    return g_rvgpu_sim->read_reg(addr);
}

void rvgpu_dpi_write_reg(unsigned int addr, unsigned int data) {
    if (!g_rvgpu_sim) {
        std::cerr << "Error: RVGPU SIM not initialized" << std::endl;
        return;
    }
    g_rvgpu_sim->write_reg(addr, data);
}

} // extern "C" 