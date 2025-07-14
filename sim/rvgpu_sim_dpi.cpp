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
#include "rvgpu_host_simulator.hpp"

//=============================================================================
// DPI函数实现
//=============================================================================

extern "C" {
    void host_init() {
        RVGPUHostSimulator::getInstance();
    }

    void host_cleanup() {
        RVGPUHostSimulator::destroyInstance();
    }
    
    void host_run_test_case() {
        RVGPUHostSimulator* sim = RVGPUHostSimulator::getInstance();
        if (sim != nullptr) {
            sim->run_test_case();
        }
    }
    
    // GPU直接内存访问DPI函数
    void gpu_write_mem(int slice_id, uint64_t addr, uint64_t data) {
        RVGPUHostSimulator* sim = RVGPUHostSimulator::getInstance();
        if (sim != nullptr) {
            sim->gpu_write_memory(slice_id, addr, data);
        }
    }
    
    uint64_t gpu_read_mem(int slice_id, uint64_t addr) {
        RVGPUHostSimulator* sim = RVGPUHostSimulator::getInstance();
        if (sim != nullptr) {
            return sim->gpu_read_memory(slice_id, addr);
        }
        return 0;
    }
} 