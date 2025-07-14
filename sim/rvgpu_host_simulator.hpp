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

#ifndef RVGPU_HOST_SIMULATOR_HPP
#define RVGPU_HOST_SIMULATOR_HPP

#include <iostream>
#include <cstdint>
#include <vector>
#include <string>
#include <chrono>
#include <thread>
#include "rvgpu_register.hpp"

//=============================================================================
// RVGPU Host Simulator Class Declaration
//=============================================================================

class RVGPUHostSimulator {
private:
    // 内存模拟 - 在C++中实现
    std::vector<uint64_t> memory;
    std::vector<std::vector<uint64_t>> slice_memory; // 支持多个内存切片
    bool verbose;
    
public:
    // 构造函数
    RVGPUHostSimulator(bool verbose_mode = true);
    
    // 日志输出
    void log(const std::string& message);
    
    // GPU直接内存访问 - 直接访问C++内存
    void gpu_write_memory(int slice_id, uint64_t addr, uint64_t data);
    uint64_t gpu_read_memory(int slice_id, uint64_t addr);

    // 等待GPU完成
    void wait_gpu_done(int timeout_cycles = 1000);
    
    void run_test_case();
    
    // 单例模式接口
    static RVGPUHostSimulator* getInstance();
    static void destroyInstance();
    
private:
    // 禁用拷贝构造和赋值操作
    RVGPUHostSimulator(const RVGPUHostSimulator&) = delete;
    RVGPUHostSimulator& operator=(const RVGPUHostSimulator&) = delete;
    
    // 静态实例指针声明
    static RVGPUHostSimulator* instance;
};

#endif // RVGPU_HOST_SIMULATOR_HPP 