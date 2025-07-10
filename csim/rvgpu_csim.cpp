#include "rvgpu_csim.hpp"
#include <iostream>
#include <cstring>
#include <chrono>
#include <thread>

//=============================================================================
// rvgpu_csim 实现
//=============================================================================

rvgpu_csim::rvgpu_csim(uint64_t vram_size) 
    : vram_size(vram_size), gpu_idle(true), task_complete(false) {
    
    // 初始化寄存器
    registers.resize(64, 0); // 假设有64个寄存器
    
    std::cout << "RVGPU CSim initialized with VRAM size: " << vram_size << " bytes" << std::endl;
}

rvgpu_csim::~rvgpu_csim() {
    std::cout << "RVGPU CSim destroyed" << std::endl;
}

//=============================================================================
// 寄存器访问接口
//=============================================================================

uint32_t rvgpu_csim::read_reg(uint32_t addr) {
    std::cout << "CSim: Read register 0x" << std::hex << addr << std::endl;
    
    if (addr < registers.size() * 4) {
        return registers[addr / 4];
    }
    
    std::cout << "CSim: Invalid register address 0x" << std::hex << addr << std::endl;
    return 0;
}

void rvgpu_csim::write_reg(uint32_t addr, uint32_t data) {
    std::cout << "CSim: Write register 0x" << std::hex << addr << " = 0x" << data << std::endl;
    
    if (addr < registers.size() * 4) {
        registers[addr / 4] = data;
        
        // 处理特殊寄存器写入
        switch (addr) {
            case 0x0000: // START_REG
                if (data & 0x00000001) { // START
                    std::cout << "CSim: GPU started" << std::endl;
                    gpu_idle = false;
                }
                break;
        }
    } else {
        std::cout << "CSim: Invalid register address 0x" << std::hex << addr << std::endl;
    }
}

//=============================================================================
// 等待完成接口
//=============================================================================

bool rvgpu_csim::wait_for_completion(uint64_t timeout_ms) {
    std::cout << "CSim: Wait for completion, timeout: " << timeout_ms << "ms" << std::endl;
    
    auto start_time = std::chrono::steady_clock::now();
    auto timeout_duration = std::chrono::milliseconds(timeout_ms);
    
    while (!task_complete) {
        auto current_time = std::chrono::steady_clock::now();
        if (current_time - start_time > timeout_duration) {
            std::cout << "CSim: Wait for completion timeout" << std::endl;
            return false;
        }
        
        // 简单的任务完成模拟
        static int step_count = 0;
        step_count++;
        
        if (step_count > 100) { // 100步后完成任务
            task_complete = true;
            gpu_idle = true;
            step_count = 0;
            std::cout << "CSim: Task completed" << std::endl;
        }
        
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    
    std::cout << "CSim: Task completed successfully" << std::endl;
    return true;
}

//=============================================================================
// 工厂函数
//=============================================================================

std::unique_ptr<rvgpu_simtop> create_rvgpu_csim(uint64_t vram_size) {
    return std::make_unique<rvgpu_csim>(vram_size);
}

 