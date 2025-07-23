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

`ifndef RVGPU_GPC_TOP_SV
`define RVGPU_GPC_TOP_SV

`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_internal_noc_pkg.svh"

module rvgpu_gpc_top #(
    parameter noc_config_t NOC_CONFIG = DEFAULT_NOC_CONFIG
) (
    input  logic clk,
    input  logic rst_n,
    rvgpu_internal_noc_if.device noc_if
);
    // 空实现
endmodule : rvgpu_gpc_top

`endif // RVGPU_GPC_TOP_SV 