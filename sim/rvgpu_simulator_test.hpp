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

#ifndef RVGPU_SIMULATOR_TEST_HPP
#define RVGPU_SIMULATOR_TEST_HPP

#include "rvgpu_simulator.hpp"

//=============================================================================
// RVGPU Simulator Test Class Declaration
//=============================================================================

class RVGPUSimulatorTest : public RVGPUSimulator {
public:
    // 构造函数
    RVGPUSimulatorTest(bool verbose_mode = true);
    
    // 析构函数
    ~RVGPUSimulatorTest();
    
    // 实现纯虚函数
    void run() override;
    
private:
    // 加载内存数据
    void load_memory(const std::string& filename);
    
    // 禁用拷贝构造和赋值操作
    RVGPUSimulatorTest(const RVGPUSimulatorTest&) = delete;
    RVGPUSimulatorTest& operator=(const RVGPUSimulatorTest&) = delete;
};

#endif // RVGPU_SIMULATOR_TEST_HPP 