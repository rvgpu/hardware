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

// Router结构如下:
//     GPC               TPC0.router           TPC1.router
// +-----------+        +------------+        +------------+
// | up_fifo   +r <--- l+            +r <--- l+            + <---  ... 
// | down_fifo +r ---> l+            +r ---> l+            + --->  ...
// +-----------+        +--+-----+---+        +--+-----+---+
//                         |     |               |     |
//                        SM0   SM1             SM0   SM1

interface interface_gpc_router;
    t_router_message            down_msg;
    logic                       down_valid;
    logic                       down_ready;
    
    t_router_message            up_msg;
    logic                       up_valid;
    logic                       up_ready;
    
    // Modport定义
    modport left_port (
        input  down_msg, down_valid,
        output down_ready,
        output up_msg, up_valid,
        input  up_ready
    );
    
    modport right_port (
        output down_msg, down_valid,
        input  down_ready,
        input  up_msg, up_valid, 
        output up_ready         
    );
    
endinterface : interface_gpc_router

`endif // INTERFACE_GPC_ROUTER_SVH
