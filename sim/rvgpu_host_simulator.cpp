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

#include "rvgpu_host_simulator.hpp"
#include "rvgpu_sim_dpi.hpp"

#include <iostream>
#include <cstdint>
#include <vector>
#include <string>
#include <chrono>
#include <thread>

//=============================================================================
// RVGPUHostSimulator Class Implementation
//=============================================================================

RVGPUHostSimulator::RVGPUHostSimulator(bool verbose_mode) : verbose(verbose_mode) {
    memory = new RVGPUMemory(1 * 1024 * 1024 * 1024); // 初始化内存 1GB
    log("Host模拟器初始化完成");
}

RVGPUHostSimulator::~RVGPUHostSimulator() {
    if (memory != nullptr) {
        delete memory;
        memory = nullptr;
    }
    log("Host模拟器析构完成");
}

// 日志输出
void RVGPUHostSimulator::log(const std::string& message) {
    if (verbose) {
        std::cout << "[HOST] " << message << std::endl;
    }
}

// GPU直接内存访问 - 使用Memory类
void RVGPUHostSimulator::gpu_write_memory(uint64_t addr, uint64_t data) {
    if (memory != nullptr) {
        memory->write(addr, data);
        log("GPU写内存: addr=0x" + std::to_string(addr) + ", data=0x" + std::to_string(data));
    }
}

uint64_t RVGPUHostSimulator::gpu_read_memory(uint64_t addr) {
    if (memory != nullptr) {
        uint64_t data = memory->read(addr);
        log("GPU读内存: addr=0x" + std::to_string(addr) + ", data=0x" + std::to_string(data));
        return data;
    }
    return 0;
}

// 等待GPU完成
void RVGPUHostSimulator::wait_gpu_done(int timeout_cycles) {
    log("等待GPU完成...");
    // 简化实现，实际应该检查GPU状态
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    log("GPU操作完成");
}

// 运行测试用例
void RVGPUHostSimulator::run_test_case() {
    log("开始运行测试用例");
    
    // 写入寄存器测试 - 添加strb参数
    cpu_axi_write(0x0000, 0x12345678, 0xFF);
    cpu_axi_write(0x0004, 0x12345678, 0xFF);
    cpu_axi_write(0x0008, 0x12345678, 0xFF);
    cpu_axi_write(0x000c, 0x12345678, 0xFF);
    cpu_axi_write(0x0010, 0x00000001, 0xFF);
    
    wait_gpu_done();
    
    // 读取寄存器测试 - 使用正确的函数名
    uint64_t data;
    cpu_axi_read_with_data(0x0010, &data);
    
    if (data == 0x00000001) {
        log("GPU工作完成");
    } else {
        log("GPU工作失败，读取值: 0x" + std::to_string(data));
    }
    
    log("测试用例完成");
}

//=============================================================================
// 单例模式实现
//=============================================================================

// 静态实例指针定义
RVGPUHostSimulator* RVGPUHostSimulator::instance = nullptr;

// 获取单例实例
RVGPUHostSimulator* RVGPUHostSimulator::getInstance() {
    if (instance == nullptr) {
        instance = new RVGPUHostSimulator(true);
    }
    return instance;
}

// 销毁单例实例
void RVGPUHostSimulator::destroyInstance() {
    if (instance != nullptr) {
        delete instance;
        instance = nullptr;
    }
}
