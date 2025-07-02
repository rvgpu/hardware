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

`ifndef RVGPU_CONTROL_UNIT_PKG_SV
`define RVGPU_CONTROL_UNIT_PKG_SV

`include "rvgpu_constant.svh"
`include "rvgpu_internal_noc_pkg.sv"
`include "rvgpu_internal_noc_if.svh"
`include "../gpu_top/rvgpu_interface_axi.svh"

package rvgpu_control_unit_pkg;
    //=============================================================================
    // Control Unit Configuration Parameters
    //=============================================================================
    
    typedef struct packed {
        int unsigned max_payload_size;       // 最大Payload大小(字节)
        int unsigned page_size;              // 页面大小(字节)
        int unsigned tlb_entries;            // TLB条目数量
        int unsigned va_width;               // 虚拟地址位宽(位)
        int unsigned pa_width;               // 物理地址位宽(位)
        int unsigned axi_addr_width;         // AXI地址位宽(位)
        int unsigned axi_data_width;         // AXI数据位宽(位)
    } control_unit_config_t;
    
    // 默认配置参数
    localparam control_unit_config_t DEFAULT_CONTROL_UNIT_CONFIG = '{
        max_payload_size: `RVGPU_CONST_CONTROL_UNIT_CONFIG_MAX_PAYLOAD_SIZE,
        page_size: `RVGPU_CONST_CONTROL_UNIT_CONFIG_PAGE_SIZE,
        tlb_entries: `RVGPU_CONST_CONTROL_UNIT_CONFIG_TLB_ENTRIES,
        va_width: `RVGPU_CONST_CONTROL_UNIT_CONFIG_VA_WIDTH,
        pa_width: `RVGPU_CONST_CONTROL_UNIT_CONFIG_PA_WIDTH,
        axi_addr_width: `RVGPU_CONST_CONTROL_UNIT_CONFIG_AXI_ADDR_WIDTH,
        axi_data_width: `RVGPU_CONST_CONTROL_UNIT_CONFIG_AXI_DATA_WIDTH
    };

    //=============================================================================
    // Command Package Data Structures: Define the data structures of command package
    //=============================================================================
    `include "rvgpu_command_package.svh"

    //=============================================================================
    // Register Space: Define the register space which host can access
    //=============================================================================
    `include "rvgpu_register_space.svh"

endpackage : rvgpu_control_unit_pkg

`endif // RVGPU_CONTROL_UNIT_PKG_SV