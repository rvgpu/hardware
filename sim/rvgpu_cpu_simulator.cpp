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

#include <iostream>
#include <cstdint>
#include <vector>
#include <string>
#include <cstring>
#include <chrono>
#include <thread>

// DPI接口声明
extern "C" {
    // AXI写操作
    void cpu_axi_write(uint64_t addr, uint64_t data, uint8_t strb);
    int cpu_axi_write_done();
    
    // AXI读操作
    void cpu_axi_read(uint64_t addr);
    uint64_t cpu_axi_read_data();
    int cpu_axi_read_done();
    
    // 时钟控制
    void cpu_clock_cycle();
    
    // 日志输出
    void cpu_log(const char* message);
}

// CPU模拟器类
class RVGPUCPUSimulator {
private:
    // GPU寄存器地址定义
    static const uint64_t GPU_CTRL_REG_ADDR = 0x1000;
    static const uint64_t GPU_STATUS_REG_ADDR = 0x1008;
    static const uint64_t GPU_MMU_PT_ADDR = 0x1010;
    static const uint64_t GPU_CMD_PKT_ADDR = 0x1020;
    static const uint64_t GPU_CMD_DATA_ADDR = 0x1030;
    
    // 控制寄存器位定义
    static const uint64_t GPU_CTRL_START = 0x1;
    static const uint64_t GPU_CTRL_RESET = 0x2;
    static const uint64_t GPU_CTRL_ENABLE = 0x4;
    
    // 状态寄存器位定义
    static const uint64_t GPU_STATUS_BUSY = 0x1;
    static const uint64_t GPU_STATUS_DONE = 0x2;
    static const uint64_t GPU_STATUS_ERROR = 0x4;
    
    std::vector<uint64_t> memory;
    bool verbose;
    
public:
    RVGPUCPUSimulator(bool verbose_mode = true) : verbose(verbose_mode) {
        memory.resize(1024, 0); // 初始化内存
        log("CPU模拟器初始化完成");
    }
    
    // 日志输出
    void log(const std::string& message) {
        if (verbose) {
            std::cout << "[CPU] " << message << std::endl;
            cpu_log(message.c_str());
        }
    }
    
    // 等待指定时钟周期
    void wait_cycles(int cycles) {
        for (int i = 0; i < cycles; i++) {
            cpu_clock_cycle();
        }
    }
    
    // AXI写操作封装
    void write_reg(uint64_t addr, uint64_t data) {
        log("写寄存器: 0x" + std::to_string(addr) + " = 0x" + std::to_string(data));
        cpu_axi_write(addr, data, 0xFF);
        
        // 等待写完成
        while (!cpu_axi_write_done()) {
            wait_cycles(1);
        }
    }
    
    // AXI读操作封装
    uint64_t read_reg(uint64_t addr) {
        log("读寄存器: 0x" + std::to_string(addr));
        cpu_axi_read(addr);
        
        // 等待读完成
        while (!cpu_axi_read_done()) {
            wait_cycles(1);
        }
        
        uint64_t data = cpu_axi_read_data();
        log("读寄存器结果: 0x" + std::to_string(data));
        return data;
    }
    
    // GPU控制函数
    void gpu_reset() {
        log("GPU复位");
        write_reg(GPU_CTRL_REG_ADDR, GPU_CTRL_RESET);
        wait_cycles(10);
        write_reg(GPU_CTRL_REG_ADDR, 0);
    }
    
    void gpu_enable() {
        log("GPU使能");
        write_reg(GPU_CTRL_REG_ADDR, GPU_CTRL_ENABLE);
    }
    
    void gpu_start() {
        log("GPU启动");
        write_reg(GPU_CTRL_REG_ADDR, GPU_CTRL_ENABLE | GPU_CTRL_START);
    }
    
    bool gpu_is_busy() {
        uint64_t status = read_reg(GPU_STATUS_REG_ADDR);
        return (status & GPU_STATUS_BUSY) != 0;
    }
    
    bool gpu_is_done() {
        uint64_t status = read_reg(GPU_STATUS_REG_ADDR);
        return (status & GPU_STATUS_DONE) != 0;
    }
    
    bool gpu_has_error() {
        uint64_t status = read_reg(GPU_STATUS_REG_ADDR);
        return (status & GPU_STATUS_ERROR) != 0;
    }
    
    // 设置MMU页表基地址
    void set_mmu_pagetable(uint64_t pt_addr) {
        log("设置MMU页表基地址: 0x" + std::to_string(pt_addr));
        write_reg(GPU_MMU_PT_ADDR, pt_addr);
    }
    
    // 设置命令包地址
    void set_command_packet(uint64_t cmd_addr) {
        log("设置命令包地址: 0x" + std::to_string(cmd_addr));
        write_reg(GPU_CMD_PKT_ADDR, cmd_addr);
    }
    
    // 写入命令数据
    void write_command_data(uint64_t offset, uint64_t data) {
        uint64_t addr = GPU_CMD_DATA_ADDR + offset;
        log("写入命令数据: 0x" + std::to_string(addr) + " = 0x" + std::to_string(data));
        write_reg(addr, data);
    }
    
    // 等待GPU完成
    void wait_gpu_done(int timeout_cycles = 1000) {
        log("等待GPU完成...");
        int cycles = 0;
        
        while (!gpu_is_done() && cycles < timeout_cycles) {
            wait_cycles(1);
            cycles++;
            
            if (gpu_has_error()) {
                log("GPU报告错误!");
                break;
            }
        }
        
        if (cycles >= timeout_cycles) {
            log("GPU操作超时!");
        } else {
            log("GPU操作完成，耗时 " + std::to_string(cycles) + " 个时钟周期");
        }
    }
    
    // 数组加法测试
    void test_array_add() {
        log("开始数组加法测试");
        
        // 准备测试数据
        uint64_t array_a_addr = 0x2000;
        uint64_t array_b_addr = 0x3000;
        uint64_t array_c_addr = 0x4000;
        uint64_t array_size = 64; // 64个元素
        
        // 初始化数组A
        for (int i = 0; i < array_size; i++) {
            memory[array_a_addr/8 + i] = i;
        }
        
        // 初始化数组B
        for (int i = 0; i < array_size; i++) {
            memory[array_b_addr/8 + i] = i * 2;
        }
        
        // 设置命令包
        uint64_t cmd_packet[4];
        cmd_packet[0] = 0x01; // 命令类型：数组加法
        cmd_packet[1] = array_a_addr; // 源数组A地址
        cmd_packet[2] = array_b_addr; // 源数组B地址
        cmd_packet[3] = array_c_addr; // 目标数组C地址
        
        // 写入命令包
        for (int i = 0; i < 4; i++) {
            write_command_data(i * 8, cmd_packet[i]);
        }
        
        // 设置命令包地址
        set_command_packet(0x5000);
        
        // 启动GPU
        gpu_start();
        
        // 等待完成
        wait_gpu_done();
        
        // 验证结果
        log("验证计算结果...");
        for (int i = 0; i < array_size; i++) {
            uint64_t expected = i + i * 2; // A[i] + B[i]
            uint64_t actual = memory[array_c_addr/8 + i];
            
            if (expected != actual) {
                log("错误: 索引 " + std::to_string(i) + 
                    " 期望 " + std::to_string(expected) + 
                    " 实际 " + std::to_string(actual));
            }
        }
        
        log("数组加法测试完成");
    }
    
    // 运行完整测试套件
    void run_test_suite() {
        log("开始RVGPU测试套件");
        
        // 复位GPU
        gpu_reset();
        
        // 使能GPU
        gpu_enable();
        
        // 设置MMU页表
        set_mmu_pagetable(0x10000);
        
        // 运行各种测试
        test_array_add();
        
        log("RVGPU测试套件完成");
    }
};

// 全局CPU模拟器实例
static RVGPUCPUSimulator* cpu_sim = nullptr;

// DPI函数实现
extern "C" {
    void cpu_init() {
        if (cpu_sim == nullptr) {
            cpu_sim = new RVGPUCPUSimulator(true);
        }
    }
    
    void cpu_run_test_suite() {
        if (cpu_sim != nullptr) {
            cpu_sim->run_test_suite();
        }
    }
    
    void cpu_test_array_add() {
        if (cpu_sim != nullptr) {
            cpu_sim->test_array_add();
        }
    }
    
    void cpu_cleanup() {
        if (cpu_sim != nullptr) {
            delete cpu_sim;
            cpu_sim = nullptr;
        }
    }
} 