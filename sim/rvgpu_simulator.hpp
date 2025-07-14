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

#ifndef RVGPU_SIMULATOR_HPP
#define RVGPU_SIMULATOR_HPP

#include <iostream>
#include <cstdint>
#include <vector>
#include <string>
#include <chrono>
#include <thread>
#include "rvgpu_register.hpp"
#include "rvgpu_memory.hpp"

//=============================================================================
// RVGPU Simulator Base Class Declaration
//=============================================================================

class RVGPUSimulator {
protected:
    // 内存模拟 - 使用Memory类
    RVGPUMemory* memory;
    bool verbose;
    
public:
    // 单例模式接口
    static RVGPUSimulator* getInstance();
    static void destroyInstance();

    // 构造函数
    RVGPUSimulator(bool verbose_mode = true);
    
    // 析构函数
    virtual ~RVGPUSimulator();
    
    // 纯虚函数 - 子类必须实现
    virtual void run() = 0;
    
    // 日志输出
    void log(const std::string& message);

    // 等待GPU完成
    void wait_gpu_done(int timeout_cycles = 1000);

    // Host寄存器读写接口
    void write_reg(uint64_t addr, uint64_t data, uint8_t strb);
    uint64_t read_reg(uint64_t addr);
    
    // 内存访问接口
    void write_memory(uint64_t addr, uint64_t data);
    uint64_t read_memory(uint64_t addr);
    
protected:
    // 禁用拷贝构造和赋值操作
    RVGPUSimulator(const RVGPUSimulator&) = delete;
    RVGPUSimulator& operator=(const RVGPUSimulator&) = delete;
    
    // 静态实例指针声明
    static RVGPUSimulator* instance;
};

#endif // RVGPU_SIMULATOR_HPP 