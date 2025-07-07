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

`ifndef RVGPU_CONTROL_UNIT_SV
`define RVGPU_CONTROL_UNIT_SV

`include "rvgpu_control_unit_pkg.svh"
`include "rvgpu_control_unit_if.svh"

`ifndef RVGPU_CONTROL_UNIT_PKG_IMPORTED
`define RVGPU_CONTROL_UNIT_PKG_IMPORTED
import rvgpu_control_unit_pkg::*;
`endif // RVGPU_CONTROL_UNIT_PKG_IMPORTED

module rvgpu_control_unit #(
    parameter control_unit_config_t CU_CONFIG = DEFAULT_CONTROL_UNIT_CONFIG
) (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // Host Interface (AXI4 Slave) - CPU控制接口
    host_if.slave                       host_axi_if,
    
    // NOC Interface - GPU内部网络接口
    rvgpu_internal_noc_if.device        noc_if,

    // Interrupt Output
    output logic                        gpu_irq
);
    //=============================================================================
    // Internal Signals
    //=============================================================================
    // adapter_cp: AXI Adapter <-> Command Processor
    // cp_mmu: Command Processor <-> MMU
    // cp_noc: Command Processor <-> NOC Arbiter
    // mmu_noc: MMU <-> NOC Arbiter
    control_if #(.CU_CONFIG = CU_CONFIG) adapter_cp();
    
    mmu_if #(.CU_CONFIG = CU_CONFIG) cp_mmu();
    
    rvgpu_internal_noc_if.device cp_noc();
    
    rvgpu_internal_noc_if.device mmu_noc();
    
    //=============================================================================
    // AXI Adapter Instance - AXI interface to control interface
    //=============================================================================
    rvgpu_axi_adapter #(.CU_CONFIG = CU_CONFIG) u_axi_adapter (
        .clk(clk),
        .rst_n(rst_n),
        .axi_if(host_axi_if),
        .ctrl_if(adapter_cp.master)
    );
    
    //=============================================================================
    // Command Processor Instance
    //=============================================================================
    rvgpu_command_processor #(.CU_CONFIG = CU_CONFIG) u_command_processor (
        .clk(clk),
        .rst_n(rst_n),
        .ctrl_if(adapter_cp.slave),
        .noc_if(cp_noc),
        .mmu_if(cp_mmu.master),
        .gpu_irq(gpu_irq)
    );
    
    //=============================================================================
    // MMU Instance - Memory Management Unit
    //=============================================================================
    
    rvgpu_mmu #(.CU_CONFIG = CU_CONFIG) u_mmu (
        .clk(clk),
        .rst_n(rst_n),
        .mmu_if(cp_mmu.slave),
        .noc_if(mmu_noc)
    );
    
    //=============================================================================
    // NOC Arbiter Instance - 将noc_if连接到cp_noc和mmu_noc
    //=============================================================================
    
    rvgpu_noc_arbiter u_noc_arbiter (
        .clk(clk),
        .rst_n(rst_n),

        // Port 0: cp_noc Interface (Command Processor → NOC)
        .m0_if(cp_noc),

        // Port 1: mmu_noc Interface (MMU → NOC)
        .m1_if(mmu_noc),

        // NOC Interface
        .noc_if(noc_if)
    );

endmodule : rvgpu_control_unit

`endif // RVGPU_CONTROL_UNIT_SV 