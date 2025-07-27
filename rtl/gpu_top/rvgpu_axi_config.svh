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

`ifndef RVGPU_AXI_CONFIG_SVH
`define RVGPU_AXI_CONFIG_SVH

`include "rvgpu_config.svh"

typedef struct packed {
    int unsigned addr_width;           // 地址位宽(位)
    int unsigned data_width;           // 数据位宽(位)
    int unsigned strb_width;           // 字节使能位宽(位)
} host_axi_config_t;

localparam host_axi_config_t DEFAULT_HOST_AXI_CONFIG = '{
    addr_width: `HOST_INTERFACE_ADDR_WIDTH,
    data_width: `HOST_INTERFACE_DATA_WIDTH,
    strb_width: `HOST_INTERFACE_DATA_WIDTH/8
};

typedef struct packed {
    int unsigned addr_width;           // 地址位宽(位)
    int unsigned data_width;           // 数据位宽(位)
    int unsigned strb_width;           // 字节使能位宽(位)
    int unsigned id_width;             // ID位宽(位)
} memory_axi_config_t;

localparam memory_axi_config_t DEFAULT_MEMORY_AXI_CONFIG = '{
    addr_width: `MEMORY_INTERFACE_ADDR_WIDTH,
    data_width: `MEMORY_INTERFACE_DATA_WIDTH,
    strb_width: `MEMORY_INTERFACE_DATA_WIDTH/8,
    id_width: 8
};


`endif