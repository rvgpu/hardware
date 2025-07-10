#include "../simtop/rvgpu_simulator.hpp"
#include <iostream>
#include <vector>
#include <chrono>
#include <memory>

//=============================================================================
// 示例应用程序：使用RVGPU仿真器
//=============================================================================

int main() {
    std::cout << "=== RVGPU Simulator Example ===" << std::endl;
    
    // 使用智能指针管理内存
    auto gpu = std::make_unique<rvgpu_simulator>(RVGPU_SIM_TYPE::RVGPU_RTLSIM, 256 * 1024 * 1024);  // 256MB VRAM

    // 这里准备好VRAM的数据, 暂时不实现
    // gpu->write_mem_block(0x1000, test_data, sizeof(test_data));

    gpu->write_reg(RVGPU_REG::MMU_PAGETABLE_LO, 0x10000000);
    gpu->write_reg(RVGPU_REG::MMU_PAGETABLE_HI, 0x00000000);
    gpu->write_reg(RVGPU_REG::COMMAND_PACKET_LO, 0x0000F000);
    gpu->write_reg(RVGPU_REG::COMMAND_PACKET_HI, 0x00000000);

    // 启动GPU
    gpu->write_reg(RVGPU_REG::START_REG, 1);

    // 等待完成
    if (gpu->wait_for_completion(5000)) { // 5秒超时
        std::cout << "GPU任务完成" << std::endl;
    } else {
        std::cout << "GPU任务超时" << std::endl;
    }
    
    // 工具库，暂不实现
    // tools.write_file("gpu_mem.bin", gpu->read_mem_block(0x1000, 0x1020));
    
    return 0;
} 