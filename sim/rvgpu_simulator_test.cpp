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
#include "rvgpu_register.hpp"
#include "rvgpu_sim_dpi.hpp"
#include "rvgpu_parser.hpp"

#include <iostream>
#include <cstdint>
#include <sstream>
#include <iomanip>

//=============================================================================
// RVGPUSimulatorTest Class Implementation
//=============================================================================

RVGPUSimulatorTest::RVGPUSimulatorTest(bool verbose_mode) 
    : RVGPUSimulator(verbose_mode) {
}

RVGPUSimulatorTest::~RVGPUSimulatorTest() {
}

void RVGPUSimulatorTest::load_memory(const std::string& filename) {
    std::string full_path = build_tc_path(filename);
    
    RVGPUParseHex parser;
    if (!parser.open(full_path)) {
        log("Error: Failed to open memory file: " + full_path);
        return;
    }
    
    while (parser.next_line()) {
        std::vector<uint64_t> memdata = parser.get_memdata();
        
        if (memdata.size() == 5) {
            uint64_t addr = memdata[0];
            write_memory(addr + 0,  memdata[1]);
            write_memory(addr + 4,  memdata[2]);
            write_memory(addr + 8,  memdata[3]);
            write_memory(addr + 12, memdata[4]);
        } else {
            // 如果不是5个元素，跳过这一行
            continue;
        }
    }
}

void RVGPUSimulatorTest::run() {
    log("Simulator start");

    RVGPUParseCommand cmd;
    if (!cmd.parser()) {
        log("Error: Failed to open command file");
        return;
    }
    
    while (!cmd.empty()) {
        sim_command current_command = cmd.get_command();
        switch(current_command.command) {
            case RVGPU_COMMAND_WRITE_REG:
                write_reg(current_command.reg_addr, current_command.data, 0xff);
                break;
            case RVGPU_COMMAND_CHECK_REG:
                if(read_reg(current_command.reg_addr) == current_command.data) {
                    std::ostringstream oss;
                    oss << "Check Register [0x" << std::hex << current_command.reg_addr 
                        << "] = 0x" << std::hex << current_command.data << " Success";
                    log(oss.str());
                } else {
                    std::ostringstream oss;
                    oss << "Check Register [0x" << std::hex << current_command.reg_addr 
                        << "] = 0x" << std::hex << current_command.data << " Failed";
                    log(oss.str());
                }
                break;
            case RVGPU_LOAD_MEMORY:
                load_memory(current_command.filename);
                break;
            case RVGPU_WAIT_GPU_DONE:
                wait_gpu_done();
                break;
            default:
                log("Unknown Command");
                break;
        }
    }

    log("Simulator end");
} 