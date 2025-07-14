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

#include "rvgpu_basic_test_case.hpp"
#include "rvgpu_sim_dpi.hpp"

#include <iostream>
#include <cstdint>

//=============================================================================
// RVGPUBasicTestCase Class Implementation
//=============================================================================

RVGPUBasicTestCase::RVGPUBasicTestCase(RVGPUHostSimulator* host_sim) 
    : host_simulator(host_sim) {
}

RVGPUBasicTestCase::~RVGPUBasicTestCase() {
}

void RVGPUBasicTestCase::run() {
    if (host_simulator != nullptr) {
        host_simulator->log("开始运行基本测试用例");
    }
    
    // 写入寄存器测试 - 添加strb参数
    cpu_axi_write(0x0000, 0x12345678, 0xFF);
    cpu_axi_write(0x0004, 0x12345678, 0xFF);
    cpu_axi_write(0x0008, 0x12345678, 0xFF);
    cpu_axi_write(0x000c, 0x12345678, 0xFF);
    cpu_axi_write(0x0010, 0x00000001, 0xFF);
    
    if (host_simulator != nullptr) {
        host_simulator->wait_gpu_done();
    }
    
    // 读取寄存器测试 - 使用正确的函数名
    uint64_t data;
    cpu_axi_read_with_data(0x0010, &data);
    
    if (data == 0x00000001) {
        if (host_simulator != nullptr) {
            host_simulator->log("GPU工作完成");
        }
    } else {
        if (host_simulator != nullptr) {
            host_simulator->log("GPU工作失败，读取值: 0x" + std::to_string(data));
        }
    }
    
    if (host_simulator != nullptr) {
        host_simulator->log("基本测试用例完成");
    }
} 