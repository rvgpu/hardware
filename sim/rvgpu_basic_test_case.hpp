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

#ifndef RVGPU_BASIC_TEST_CASE_HPP
#define RVGPU_BASIC_TEST_CASE_HPP

// 前向声明
class RVGPUHostSimulator;

//=============================================================================
// RVGPUBasicTestCase Class Declaration
//=============================================================================

class RVGPUBasicTestCase {
public:
    // 构造函数
    RVGPUBasicTestCase(RVGPUHostSimulator* sim = nullptr);
    
    // 析构函数
    ~RVGPUBasicTestCase();
    
    // 运行测试用例
    void run();
    
private:
    RVGPUHostSimulator* sim;
    
    // 禁用拷贝构造和赋值操作
    RVGPUBasicTestCase(const RVGPUBasicTestCase&) = delete;
    RVGPUBasicTestCase& operator=(const RVGPUBasicTestCase&) = delete;
};

#endif // RVGPU_BASIC_TEST_CASE_HPP 