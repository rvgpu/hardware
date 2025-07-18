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

#include "rvgpu_simulator.hpp"
#include "rvgpu_sim_dpi.hpp"
#include "rvgpu_simulator_test.hpp"

#include <iostream>
#include <cstdint>
#include <vector>
#include <string>
#include <chrono>
#include <thread>

//=============================================================================
// RVGPUSimulator Class Implementation
//=============================================================================

RVGPUSimulator::RVGPUSimulator(bool verbose_mode) : verbose(verbose_mode) {
    memory = new RVGPUMemory(1 * 1024 * 1024 * 1024); // 初始化内存 1GB
    log("RVGPU模拟器初始化完成");
}

RVGPUSimulator::~RVGPUSimulator() {
    if (memory != nullptr) {
        delete memory;
        memory = nullptr;
    }
    log("RVGPU模拟器析构完成");
}

// 日志输出
void RVGPUSimulator::log(const std::string& message) {
    if (verbose) {
        std::cout << "[HOST] " << message << std::endl;
    }
}

// 等待GPU完成
void RVGPUSimulator::wait_gpu_done(int timeout_cycles) {
    log("等待GPU完成...");
    // 调用DPI函数等待GPU中断信号
    wait_gpu_irq();
    log("GPU操作完成");
}

// Host寄存器写接口
void RVGPUSimulator::write_reg(uint64_t addr, uint64_t data, uint8_t strb) {
    cpu_axi_write(addr, data, strb);
}

uint64_t RVGPUSimulator::read_reg(uint64_t addr) {
    uint64_t data;
    cpu_axi_read_with_data(addr, &data);
    return data;
}

// 128位内存访问接口
void RVGPUSimulator::write_memory128(uint64_t addr, uint32_t data0, uint32_t data1, uint32_t data2, uint32_t data3) {
    if (memory != nullptr) {
        memory->write128(addr, data0, data1, data2, data3);
    }
}

void RVGPUSimulator::read_memory128(uint64_t addr, uint32_t& data0, uint32_t& data1, uint32_t& data2, uint32_t& data3) {
    if (memory != nullptr) {
        memory->read128(addr, data0, data1, data2, data3);
    } else {
        data0 = data1 = data2 = data3 = 0;
    }
}

// 特化的内存访问接口
void RVGPUSimulator::write_memory8(uint64_t addr, uint8_t data) {
    if (memory != nullptr) {
        memory->write8(addr, data);
    }
}

void RVGPUSimulator::write_memory16(uint64_t addr, uint16_t data) {
    if (memory != nullptr) {
        memory->write16(addr, data);
    }
}

void RVGPUSimulator::write_memory32(uint64_t addr, uint32_t data) {
    if (memory != nullptr) {
        memory->write32(addr, data);
    }
}

void RVGPUSimulator::write_memory64(uint64_t addr, uint64_t data) {
    if (memory != nullptr) {
        memory->write64(addr, data);
    }
}

uint8_t RVGPUSimulator::read_memory8(uint64_t addr) {
    if (memory != nullptr) {
        return memory->read8(addr);
    }
    return 0;
}

uint16_t RVGPUSimulator::read_memory16(uint64_t addr) {
    if (memory != nullptr) {
        return memory->read16(addr);
    }
    return 0;
}

uint32_t RVGPUSimulator::read_memory32(uint64_t addr) {
    if (memory != nullptr) {
        return memory->read32(addr);
    }
    return 0;
}

uint64_t RVGPUSimulator::read_memory64(uint64_t addr) {
    if (memory != nullptr) {
        return memory->read64(addr);
    }
    return 0;
}



//=============================================================================
// 单例模式实现
//=============================================================================

// 静态实例指针定义
RVGPUSimulator* RVGPUSimulator::instance = nullptr;

// 获取单例实例
RVGPUSimulator* RVGPUSimulator::getInstance() {
    if (instance == nullptr) {
        instance = new RVGPUSimulatorTest(true);
    }
    return instance;
}

// 销毁单例实例
void RVGPUSimulator::destroyInstance() {
    if (instance != nullptr) {
        delete instance;
        instance = nullptr;
    }
}
