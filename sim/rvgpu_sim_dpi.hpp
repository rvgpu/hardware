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

#ifndef RVGPU_SIM_DPI_HPP
#define RVGPU_SIM_DPI_HPP   

#include <cstdint>

extern "C" {
    // SystemVerilog导出的AXI接口函数
    void cpu_axi_write(uint64_t addr, uint64_t data, uint8_t strb);
    void cpu_axi_read_with_data(uint64_t addr, uint64_t* data);
    
    // GPU直接内存访问接口
    void gpu_write_mem(uint64_t addr, uint64_t data);
    uint64_t gpu_read_mem(uint64_t addr);
    
    // 测试控制接口
    void host_init();
    void host_cleanup();
    void host_run_test_case();
}

#endif // RVGPU_SIM_DPI_HPP