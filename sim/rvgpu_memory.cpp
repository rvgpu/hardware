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
#include <cstring>

//=============================================================================
// RVGPUMemory Class Implementation
//=============================================================================

RVGPUMemory::RVGPUMemory(size_t mem_size) 
    : size(mem_size), capacity(mem_size) {
    // 分配内存并初始化为0
    memory_ptr = new uint8_t[capacity];
    std::memset(memory_ptr, 0, capacity);
}

RVGPUMemory::~RVGPUMemory() {
    if (memory_ptr != nullptr) {
        delete[] memory_ptr;
        memory_ptr = nullptr;
    }
}



// 128位写接口 - 接受4个32位参数
void RVGPUMemory::write128(uint64_t addr, uint32_t data0, uint32_t data1, uint32_t data2, uint32_t data3) {
    // 边界检查 - 128位需要16字节
    if (addr + 16 > capacity) {
        return; // 超出边界，静默失败
    }
    
    // 直接写入4个32位数据
    std::memcpy(&memory_ptr[addr + 0], &data0, sizeof(uint32_t));
    std::memcpy(&memory_ptr[addr + 4], &data1, sizeof(uint32_t));
    std::memcpy(&memory_ptr[addr + 8], &data2, sizeof(uint32_t));
    std::memcpy(&memory_ptr[addr + 12], &data3, sizeof(uint32_t));
}

// 128位读接口 - 返回4个32位参数
void RVGPUMemory::read128(uint64_t addr, uint32_t& data0, uint32_t& data1, uint32_t& data2, uint32_t& data3) {
    // 边界检查 - 128位需要16字节
    if (addr + 16 > capacity) {
        // 如果地址超出范围，返回0
        data0 = data1 = data2 = data3 = 0;
        return;
    }
    
    // 直接读取4个32位数据
    std::memcpy(&data0, &memory_ptr[addr + 0], sizeof(uint32_t));
    std::memcpy(&data1, &memory_ptr[addr + 4], sizeof(uint32_t));
    std::memcpy(&data2, &memory_ptr[addr + 8], sizeof(uint32_t));
    std::memcpy(&data3, &memory_ptr[addr + 12], sizeof(uint32_t));
}

// 特化的8位读写接口 - 调用私有模板接口
void RVGPUMemory::write8(uint64_t addr, uint8_t data) {
    write_template<uint8_t>(addr, data);
}

uint8_t RVGPUMemory::read8(uint64_t addr) {
    return read_template<uint8_t>(addr);
}

// 特化的16位读写接口 - 调用私有模板接口
void RVGPUMemory::write16(uint64_t addr, uint16_t data) {
    write_template<uint16_t>(addr, data);
}

uint16_t RVGPUMemory::read16(uint64_t addr) {
    return read_template<uint16_t>(addr);
}

// 特化的32位读写接口 - 调用私有模板接口
void RVGPUMemory::write32(uint64_t addr, uint32_t data) {
    write_template<uint32_t>(addr, data);
}

uint32_t RVGPUMemory::read32(uint64_t addr) {
    return read_template<uint32_t>(addr);
}

// 特化的64位读写接口 - 调用私有模板接口
void RVGPUMemory::write64(uint64_t addr, uint64_t data) {
    write_template<uint64_t>(addr, data);
}

uint64_t RVGPUMemory::read64(uint64_t addr) {
    return read_template<uint64_t>(addr);
}

 