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

`ifndef RVGPU_GPC_PKG_SVH
`define RVGPU_GPC_PKG_SVH

package rvgpu_gpc_pkg;
    typedef struct packed {
        int unsigned num_tpc;
        int unsigned num_sm_per_tpc;
        int unsigned num_sm_per_gpc;
        int unsigned debug;
    } gpc_parameter_t;

    localparam gpc_parameter_t DEFAULT_GPC_CONFIG = '{
        num_tpc:                `CONFIG_GPC_TPC_NUMBER,
        num_sm_per_tpc:         `CONFIG_TPC_SM_NUMBER,
        num_sm_per_gpc:         `CONFIG_GPC_TPC_NUMBER * `CONFIG_TPC_SM_NUMBER,
        debug:                  1
    };

endpackage

`endif // RVGPU_GPC_PKG_SVH