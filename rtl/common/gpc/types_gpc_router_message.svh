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

// 路由器消息状态枚举
typedef enum logic [1:0] {
    ROUTER_MSG_IDLE,     // 空闲状态
    ROUTER_MSG_ACTIVE,   // 活跃状态
    ROUTER_MSG_COMPLETE, // 完成状态
    ROUTER_MSG_ERROR     // 错误状态
} router_msg_status_t;

// 路由器优先级枚举
typedef enum logic [2:0] {
    ROUTER_PRIO_LOW,     // 低优先级
    ROUTER_PRIO_NORMAL,  // 正常优先级
    ROUTER_PRIO_HIGH,    // 高优先级
    ROUTER_PRIO_URGENT,  // 紧急优先级
    ROUTER_PRIO_CRITICAL // 关键优先级
} router_priority_t;

// 路由器配置参数
typedef struct packed {
    logic [7:0]  max_msg_size;      // 最大消息大小
    logic [7:0]  fifo_depth;        // FIFO深度
    logic [3:0]  timeout_cycles;    // 超时周期数
    logic        enable_arbitration; // 启用仲裁
    logic        enable_flow_control; // 启用流控制
    logic [15:0] reserved;          // 保留字段
} router_config_t;

// 路由器统计信息
typedef struct packed {
    logic [31:0] msg_sent;          // 发送消息数
    logic [31:0] msg_received;      // 接收消息数
    logic [31:0] msg_dropped;       // 丢弃消息数
    logic [31:0] msg_timeout;       // 超时消息数
    logic [31:0] arbitration_wins;  // 仲裁获胜次数
    logic [31:0] reserved;          // 保留字段
} router_stats_t;

// 路由器错误代码
typedef enum logic [3:0] {
    ROUTER_ERR_NONE,        // 无错误
    ROUTER_ERR_INVALID_DST, // 无效目标
    ROUTER_ERR_FIFO_FULL,   // FIFO满
    ROUTER_ERR_TIMEOUT,     // 超时
    ROUTER_ERR_INVALID_MSG, // 无效消息
    ROUTER_ERR_BUSY,        // 忙状态
    ROUTER_ERR_RESET,       // 复位状态
    ROUTER_ERR_UNKNOWN      // 未知错误
} router_error_t;

`endif // TYPES_GPC_ROUTER_MESSAGE_SVH
