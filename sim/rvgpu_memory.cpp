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

#include "rvgpu_memory.hpp"
#include <iostream>
#include <iomanip>

//=============================================================================
// RVGPUMemory Class Implementation
//=============================================================================

RVGPUMemory::RVGPUMemory(size_t mem_size) 
    : size(mem_size) {
    memory.resize(size, 0); // 初始化内存，所有值设为0
}

RVGPUMemory::~RVGPUMemory() {
}

void RVGPUMemory::write(uint64_t addr, uint64_t data) {
    uint64_t mem_addr = addr / 8; // 64位对齐
    if (mem_addr < size) {
        memory[mem_addr] = data;
    }
}

uint64_t RVGPUMemory::read(uint64_t addr) {
    uint64_t mem_addr = addr / 8; // 64位对齐
    if (mem_addr < size) {
        return memory[mem_addr];
    }
    return 0;
}

 