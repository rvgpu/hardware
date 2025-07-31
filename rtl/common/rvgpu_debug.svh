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

`ifndef RVGPU_DEBUG_SVH
`define RVGPU_DEBUG_SVH

`define DEBUG_CU_EN         (`CONFIG_DEBUG_EN && (`CONFIG_DEBUG_MODULE & `CONFIG_DEBUG_CU_MASK))
`define DEBUG_GPC_EN        (`CONFIG_DEBUG_EN && (`CONFIG_DEBUG_MODULE & `CONFIG_DEBUG_GPC_MASK))
`define DEBUG_L2CACHE_EN    (`CONFIG_DEBUG_EN && (`CONFIG_DEBUG_MODULE & `CONFIG_DEBUG_L2CACHE_MASK))
`define DEBUG_MMU_EN        (`CONFIG_DEBUG_EN && (`CONFIG_DEBUG_MODULE & `CONFIG_DEBUG_MMU_MASK))
`define DEBUG_NOC_EN        (`CONFIG_DEBUG_EN && (`CONFIG_DEBUG_MODULE & `CONFIG_DEBUG_NOC_MASK))

// Debug打印宏 - SystemVerilog兼容
`define DEBUG_PRINT(modulename, msg) \
    $display("@%0t: [%s] %s", $time, modulename, msg)

`define GPC_PRINT(modulename, msg) \
    $display("@%0t: [GPC.%0d.%s] : %s", $time, GPC_ID, modulename, msg)
`endif // RVGPU_DEBUG_SVH
