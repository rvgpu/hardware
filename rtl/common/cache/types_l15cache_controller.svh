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

`ifndef RVGPU_TYPES_L15CACHE_CONTROLLER_SVH
`define RVGPU_TYPES_L15CACHE_CONTROLLER_SVH



`include "types_cache_op.svh"
`include "const_l15cache.svh"
`include "types_l15cache.svh"

//=============================================================================
// L1.5 Cache Controller Types
//=============================================================================

// 控制器状态机状态定义
typedef enum logic [3:0] {
    L15_STATE_IDLE          = 4'h0,    // 空闲状态
    L15_STATE_TAG_LOOKUP    = 4'h1,    // Tag查找
    L15_STATE_TAG_WAIT      = 4'h2,    // Tag等待
    L15_STATE_DATA_READ     = 4'h3,    // 数据读操作
    L15_STATE_MISS_HANDLE   = 4'h4,    // 未命中处理
    L15_STATE_MEMORY_ACCESS = 4'h5,    // 内存访问
    L15_STATE_TAG_UPDATE    = 4'h6,    // Tag更新
    L15_STATE_DATA_WRITE    = 4'h7,    // 数据写操作
    L15_STATE_RESPONSE      = 4'h8,    // 响应
    L15_STATE_WRITE_BACK    = 4'h9,    // 写回
    L15_STATE_EVICT         = 4'ha,    // 驱逐
    L15_STATE_SYNC          = 4'hb,    // 同步
    L15_STATE_ERROR         = 4'hc     // 错误状态
} l15cache_state_t;

// 控制器内部信号类型
typedef struct packed {
    logic [L15CACHE_WAYS-1:0] hit_way;      // 命中way
    logic [L15CACHE_WAYS-1:0] selected_way;  // 选择的way
    logic                      cache_hit;     // 缓存命中标志
    logic                      line_dirty;    // 缓存行脏标志
} l15cache_access_result_t;

`endif // RVGPU_TYPES_L15CACHE_CONTROLLER_SVH 