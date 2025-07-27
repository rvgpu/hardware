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
`include "rvgpu_internal_noc_pkg.svh"
`include "rvgpu_internal_noc_if.svh"
`include "../gpu_top/rvgpu_axi_config.svh"
`include "../gpu_top/rvgpu_interface_axi.svh"

package rvgpu_control_unit_pkg;
    //=============================================================================
    // Control Unit Configuration Parameters
    //=============================================================================
    
    typedef struct packed {
        int unsigned page_size;              // 页面大小(字节)
        int unsigned tlb_entries;            // TLB条目数量
        int unsigned va_width;               // 虚拟地址位宽(位)
        int unsigned pa_width;               // 物理地址位宽(位)
    } cu_parameter_t;
    
    // 默认配置参数
    localparam cu_parameter_t DEFAULT_CONTROL_UNIT_PARAMETER = '{
        page_size: `RVGPU_CONST_CU_PAGE_SIZE,
        tlb_entries: `RVGPU_CONST_CU_TLB_ENTRIES,
        va_width: `RVGPU_CONST_CU_VA_WIDTH,
        pa_width: `RVGPU_CONST_CU_PA_WIDTH
    };

    typedef struct packed {
        int unsigned va_width;               // 虚拟地址位宽(位)
        int unsigned pa_width;               // 物理地址位宽(位)
        int unsigned page_size;              // 页面大小(字节)
        int unsigned page_offset_bits;       // 页面偏移位宽(位)
        int unsigned page_index_bits;        // 页表索引位宽(位)
        int unsigned tlb_entries;            // TLB条目数量
        int unsigned tlb_index_bits;         // TLB索引位宽(位)
        int unsigned tlb_tag_bits;           // TLB标签位宽(位)
        int unsigned tlb_ppn_bits;           // TLB物理页号位宽(位)
    } mmu_parameter_t;

    localparam mmu_parameter_t DEFAULT_MMU_PARAMETER = '{
        va_width: `RVGPU_CONST_CU_VA_WIDTH,
        pa_width: `RVGPU_CONST_CU_PA_WIDTH,
        page_size: `RVGPU_CONST_CU_PAGE_SIZE,
        page_offset_bits: `RVGPU_CONST_CU_PAGE_OFFSET_BITS,
        page_index_bits: `RVGPU_CONST_CU_PAGE_INDEX_BITS,
        tlb_entries: `RVGPU_CONST_CU_TLB_ENTRIES,
        tlb_index_bits: `RVGPU_CONST_CU_TLB_INDEX_BITS,
        tlb_tag_bits: `RVGPU_CONST_CU_TLB_TAG_BITS,
        tlb_ppn_bits: `RVGPU_CONST_CU_TLB_PPN_BITS
    };

    typedef struct packed {
        int unsigned max_payload_size;       // 最大Payload大小(字节)
    } job_dispatcher_parameter_t;

    localparam job_dispatcher_parameter_t DEFAULT_JOB_DISPATCHER_PARAMETER = '{
        max_payload_size: `RVGPU_CONST_CU_MAX_PAYLOAD_SIZE
    };

    typedef struct packed {
        cu_parameter_t cu_parameter;
        mmu_parameter_t mmu_parameter;
        job_dispatcher_parameter_t job_dispatcher_parameter;
        int unsigned debug;
    } control_unit_config_t;

    localparam control_unit_config_t DEFAULT_CONTROL_UNIT_CONFIG = '{
        cu_parameter: DEFAULT_CONTROL_UNIT_PARAMETER,
        mmu_parameter: DEFAULT_MMU_PARAMETER,
        job_dispatcher_parameter: DEFAULT_JOB_DISPATCHER_PARAMETER,
        debug: `RVGPU_CONFIG_DEBUG_ENABLE
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
