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

`ifndef RVGPU_INTERNAL_NOC_PKG_SVH
`define RVGPU_INTERNAL_NOC_PKG_SVH

`include "rvgpu_config.svh"
`include "rvgpu_constant.svh"

package rvgpu_internal_noc_pkg;

    //=============================================================================
    // 配置结构体定义
    //=============================================================================
    typedef struct packed {
        int unsigned data_width;        // 数据位宽
        int unsigned header_width;      // Header位宽
        int unsigned num_shader_cores;  // Shader Core数量：1-8
        logic        debug_enable;      // 调试功能使能
    } noc_config_t;
    
    // 默认配置
    localparam noc_config_t DEFAULT_NOC_CONFIG = '{
        data_width: `MEMORY_INTERFACE_DATA_WIDTH,
        header_width: `RVGPU_CONST_NOC_HEADER_WIDTH,
        num_shader_cores: `SHADER_CORE_NUMBER,
        debug_enable: 1'b1
    };

    `include "rvgpu_noc_message.svh"

    `include "rvgpu_noc_debug.svh"

endpackage : rvgpu_internal_noc_pkg

`endif // RVGPU_INTERNAL_NOC_PKG_SVH