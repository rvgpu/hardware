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

#ifndef RVGPU_MEMORY_HPP
#define RVGPU_MEMORY_HPP

#include <cstdint>
#include <vector>
#include <string>

//=============================================================================
// RVGPU Memory Class Declaration
//=============================================================================

class RVGPUMemory {
private:
    std::vector<uint64_t> memory;
    size_t size;
    
public:
    // 构造函数
    RVGPUMemory(size_t mem_size = 1024 * 1024);
    
    // 析构函数
    ~RVGPUMemory();
    
    // 内存读写接口
    void write(uint64_t addr, uint64_t data);
    uint64_t read(uint64_t addr);
    
private:
    // 禁用拷贝构造和赋值操作
    RVGPUMemory(const RVGPUMemory&) = delete;
    RVGPUMemory& operator=(const RVGPUMemory&) = delete;
};

#endif // RVGPU_MEMORY_HPP 