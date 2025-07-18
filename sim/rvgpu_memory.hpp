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
#include <type_traits>
#include <cassert>
#include <cstring>

//=============================================================================
// RVGPU Memory Class Declaration
//=============================================================================

class RVGPUMemory {
private:
    uint8_t* memory_ptr;  // 改为uint8_t指针访问
    size_t size;
    size_t capacity;
    
    // 私有的模板化内存读写接口
    template<typename T>
    void write_template(uint64_t addr, T data) {
        static_assert(std::is_integral<T>::value, "T must be integral type");
        static_assert(sizeof(T) <= 16, "T size must be <= 16 bytes");
        
        // 边界检查
        if (addr + sizeof(T) > capacity) {
            return; // 超出边界，静默失败
        }
        
        // 直接内存拷贝，更简单高效
        std::memcpy(&memory_ptr[addr], &data, sizeof(T));
    }
    
    template<typename T>
    T read_template(uint64_t addr) {
        static_assert(std::is_integral<T>::value, "T must be integral type");
        static_assert(sizeof(T) <= 16, "T size must be <= 16 bytes");
        
        // 边界检查
        if (addr + sizeof(T) > capacity) {
            return 0; // 超出边界，返回0
        }
        
        T result = 0;
        // 直接内存拷贝，更简单高效
        std::memcpy(&result, &memory_ptr[addr], sizeof(T));
        return result;
    }
    
public:
    // 构造函数
    RVGPUMemory(size_t mem_size = 1024 * 1024);
    
    // 析构函数
    ~RVGPUMemory();
    

    
    // 128位接口 - 接受4个32位参数
    void write128(uint64_t addr, uint32_t data0, uint32_t data1, uint32_t data2, uint32_t data3);
    void read128(uint64_t addr, uint32_t& data0, uint32_t& data1, uint32_t& data2, uint32_t& data3);
    
    // 特化的读写接口，用于不同位宽 - 公共接口
    void write8(uint64_t addr, uint8_t data);
    void write16(uint64_t addr, uint16_t data);
    void write32(uint64_t addr, uint32_t data);
    void write64(uint64_t addr, uint64_t data);
    
    uint8_t read8(uint64_t addr);
    uint16_t read16(uint64_t addr);
    uint32_t read32(uint64_t addr);
    uint64_t read64(uint64_t addr);
    

    
private:
    // 禁用拷贝构造和赋值操作
    RVGPUMemory(const RVGPUMemory&) = delete;
    RVGPUMemory& operator=(const RVGPUMemory&) = delete;
};

#endif // RVGPU_MEMORY_HPP 