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

#include "rvgpu_simulator_test.hpp"
#include "rvgpu_simulator.hpp"
#include "rvgpu_sim_dpi.hpp"

#include <iostream>
#include <cstdint>

//=============================================================================
// RVGPUSimulatorTest Class Implementation
//=============================================================================

RVGPUSimulatorTest::RVGPUSimulatorTest(bool verbose_mode) 
    : RVGPUSimulator(verbose_mode) {
}

RVGPUSimulatorTest::~RVGPUSimulatorTest() {
}

void RVGPUSimulatorTest::run() {
    log("开始运行RVGPU模拟器测试");
    
    // 写入寄存器测试 - 添加strb参数
    write_reg(0x0000, 0x12345678, 0xFF);
    write_reg(0x0004, 0x12345678, 0xFF);
    write_reg(0x0008, 0x12345678, 0xFF);
    write_reg(0x000c, 0x12345678, 0xFF);
    write_reg(0x0010, 0x00000001, 0xFF);
    
    wait_gpu_done();
    
    // 读取寄存器测试
    uint64_t data = read_reg(0x0010);
    
    if (data == 0x00000001) {
        log("GPU工作完成");
    } else {
        log("GPU工作失败，读取值: 0x" + std::to_string(data));
    }
    
    log("RVGPU模拟器测试完成");
} 