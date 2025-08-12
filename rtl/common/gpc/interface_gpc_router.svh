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

`ifndef INTERFACE_GPC_ROUTER_SVH
`define INTERFACE_GPC_ROUTER_SVH

`include "rvgpu_typedef.svh"
`include "types_gpc_router_message.svh"

interface interface_gpc_router;
    t_router_message            gpc2sm_msg;
    logic                       gpc2sm_valid;
    logic                       gpc2sm_ready;
    
    t_router_message            sm2gpc_msg;
    logic                       sm2gpc_valid;
    logic                       sm2gpc_ready;
    
    // Modport定义
    modport up_port (
        input  gpc2sm_msg, gpc2sm_valid,
        output gpc2sm_ready,
        output sm2gpc_msg, sm2gpc_valid,
        input  sm2gpc_ready
    );
    
    modport down_port (
        output gpc2sm_msg, gpc2sm_valid,
        input  gpc2sm_ready,
        input  sm2gpc_msg, sm2gpc_valid, 
        output sm2gpc_ready         
    );
    
endinterface : interface_gpc_router

`endif // INTERFACE_GPC_ROUTER_SVH
