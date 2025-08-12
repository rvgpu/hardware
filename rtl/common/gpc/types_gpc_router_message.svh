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

`ifndef TYPES_GPC_ROUTER_MESSAGE_SVH
`define TYPES_GPC_ROUTER_MESSAGE_SVH

`include "rvgpu_typedef.svh"

// GPC内部路由器消息类型（同时表示方向）
typedef enum logic [3:0] {
    ROUTER_MSG_L15_REQ,      // L1.5 Cache请求 (downstream)
    ROUTER_MSG_L15_RESP,     // L1.5 Cache响应 (upstream)
    ROUTER_MSG_MMU_REQ,      // MMU请求 (downstream)
    ROUTER_MSG_MMU_RESP,     // MMU响应 (upstream)
    ROUTER_MSG_BLOCK_DISP,   // Block分发 (downstream)
    ROUTER_MSG_BLOCK_COMP,   // Block完成 (upstream)
    ROUTER_MSG_SM_STATUS,    // SM状态更新 (upstream)
    ROUTER_MSG_TLB_UPDATE    // TLB更新 (downstream)
} e_router_msg_type;

typedef enum logic [7:0] {
    ROUTER_DST_GPC      = 8'h00,  // GPC
    ROUTER_DST_TPC0_SM0 = 8'h10,  // TPC0.SM0
    ROUTER_DST_TPC0_SM1 = 8'h11,  // TPC0.SM1
    ROUTER_DST_TPC1_SM0 = 8'h20,  // TPC1.SM0
    ROUTER_DST_TPC1_SM1 = 8'h21,  // TPC1.SM1
    ROUTER_DST_TPC2_SM0 = 8'h30,  // TPC2.SM0
    ROUTER_DST_TPC2_SM1 = 8'h31,  // TPC2.SM1
    ROUTER_DST_TPC3_SM0 = 8'h40,  // TPC3.SM0
    ROUTER_DST_TPC3_SM1 = 8'h41   // TPC3.SM1
} e_router_msg_dst_id;

typedef union packed {
    logic [255:0]               raw;
} u_router_msg_data;

typedef struct packed {
    e_router_msg_type           msg_type;
    e_router_msg_dst_id         dst_id;
    u_router_msg_data           data;
} t_router_message;

`endif // TYPES_GPC_ROUTER_MESSAGE_SVH
