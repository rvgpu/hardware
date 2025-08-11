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
} router_msg_type_t;

// 目标节点ID编码
// [7:4] - TPC ID (0-15)
// [3:2] - SM ID (0-3, 但通常只用0-1)
// [1:0] - 保留
typedef logic [7:0] router_dst_id_t;

// 特殊目标ID定义
localparam ROUTER_DST_GPC      = 8'h00;  // GPC前端
localparam ROUTER_DST_TPC0_SM0 = 8'h10;  // TPC0的SM0
localparam ROUTER_DST_TPC0_SM1 = 8'h11;  // TPC0的SM1
localparam ROUTER_DST_TPC1_SM0 = 8'h20;  // TPC1的SM0
localparam ROUTER_DST_TPC1_SM1 = 8'h21;  // TPC1的SM1
localparam ROUTER_DST_TPC2_SM0 = 8'h30;  // TPC2的SM0
localparam ROUTER_DST_TPC2_SM1 = 8'h31;  // TPC2的SM1
localparam ROUTER_DST_TPC3_SM0 = 8'h40;  // TPC3的SM0
localparam ROUTER_DST_TPC3_SM1 = 8'h41;  // TPC3的SM1

// GPC内部路由器消息头
typedef struct packed {
    router_msg_type_t msg_type;    // 消息类型（隐含方向）
    router_dst_id_t  dst_id;      // 目标节点ID
    logic [7:0]      msg_id;      // 消息ID
    logic [63:0]     addr;        // 地址
    logic [15:0]     size;        // 大小
    logic            is_read;     // 是否为读操作
    logic [3:0]      mask;        // 字节掩码
    logic [31:0]     reserved;    // 保留字段
} router_msg_header_t;

// GPC内部路由器接口 - 支持双向通信
interface interface_gpc_router;
    // GPC到SM的消息通道
    router_msg_header_t         gpc2sm_header;
    logic [255:0]               gpc2sm_data;
    logic                       gpc2sm_valid;
    logic                       gpc2sm_ready;
    
    // SM到GPC的响应消息通道
    router_msg_header_t         sm2gpc_header;
    logic [255:0]               sm2gpc_data;
    logic                       sm2gpc_valid;
    logic                       sm2gpc_ready;
    
    // Modport定义
    modport up_port (
        input  gpc2sm_header, gpc2sm_data, gpc2sm_valid,
        output gpc2sm_ready,
        output sm2gpc_header, sm2gpc_data, sm2gpc_valid,
        input  sm2gpc_ready
    );
    
    modport down_port (
        output gpc2sm_header, gpc2sm_data, gpc2sm_valid,
        input  gpc2sm_ready,
        input  sm2gpc_header, sm2gpc_data, sm2gpc_valid, 
        output sm2gpc_ready         
    );
    
endinterface : interface_gpc_router

`endif // INTERFACE_GPC_ROUTER_SVH
