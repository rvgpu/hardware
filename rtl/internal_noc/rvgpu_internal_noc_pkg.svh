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
        int unsigned header_width;      // Header位宽
        int unsigned data_width;        // 数据位宽
        int unsigned strb_width;        // Strb位宽
        int unsigned status_width;      // Status位宽
    } noc_if_config_t;

    typedef struct packed {
        noc_if_config_t if_config;
        int unsigned num_shader_cores;  // Shader Core数量：1-8
        logic        debug_enable;      // 调试功能使能
    } noc_config_t;
    
    // 默认配置
    localparam noc_if_config_t DEFAULT_NOC_IF_CONFIG = '{
        header_width: `RVGPU_CONST_NOC_HEADER_WIDTH,
        data_width: `RVGPU_CONST_NOC_DATA_WIDTH,
        strb_width: `RVGPU_CONST_NOC_DATA_WIDTH / 8,
        status_width: 2
    };

    localparam noc_config_t DEFAULT_NOC_CONFIG = '{
        if_config: DEFAULT_NOC_IF_CONFIG,
        num_shader_cores: `CONFIG_GPC_NUMBER,
        debug_enable: 1'b1
    };

    `include "rvgpu_noc_message.svh"

    `include "rvgpu_noc_debug.svh"

endpackage : rvgpu_internal_noc_pkg

`endif // RVGPU_INTERNAL_NOC_PKG_SVH