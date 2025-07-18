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

#include "rvgpu_sim_dpi.hpp"
#include "rvgpu_simulator.hpp"
#include "rvgpu_simulator_test.hpp"

//=============================================================================
// DPI函数实现
//=============================================================================

extern "C" {
    void host_init() {
        RVGPUSimulator::getInstance();
    }

    void host_cleanup() {
        RVGPUSimulator::destroyInstance();
    }
    
    void host_run_test_case() {
        RVGPUSimulator* sim = RVGPUSimulator::getInstance();
        if (sim != nullptr) {
            sim->run();
        }
    }
    
    // GPU直接内存访问DPI函数
    void gpu_write_mem(uint64_t addr, uint64_t data) {
        RVGPUSimulator* sim = RVGPUSimulator::getInstance();
        if (sim != nullptr) {
            sim->write_memory64(addr, data);
        }
    }
    
    uint64_t gpu_read_mem(uint64_t addr) {
        RVGPUSimulator* sim = RVGPUSimulator::getInstance();
        if (sim != nullptr) {
            return sim->read_memory64(addr);
        }
        return 0;
    }
} 