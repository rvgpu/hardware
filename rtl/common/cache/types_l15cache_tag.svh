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

`ifndef RVGPU_TYPES_L15CACHE_TAG_SVH
`define RVGPU_TYPES_L15CACHE_TAG_SVH



`include "types_cache_op.svh"
`include "const_l15cache.svh"
`include "types_l15cache.svh"

//=============================================================================
// L1.5 Cache Tag Array Types
//=============================================================================

// Tag Array状态机状态定义
typedef enum logic [3:0] {
    TAG_CLEAR = 4'b0000,            // SRAM初始化状态
    TAG_IDLE = 4'b0001,             // 空闲状态
    TAG_LOOKUP = 4'b0010,           // 发起Tag查找
    TAG_LOOKUP_WAIT = 4'b0011,      // 等待Tag查找完成
    TAG_UPDATE = 4'b0100,           // 发起Tag更新
    TAG_UPDATE_WAIT = 4'b0101       // 等待Tag更新完成
} tag_state_t;

// Tag比较结果类型
typedef struct packed {
    logic [L15CACHE_WAYS-1:0]       way_hit;        // 每个way的命中情况
    logic                           any_hit;        // 是否有任何命中
    logic                           multiple_hit;   // 是否多个命中（错误）
    logic [2:0]                     hit_way_index;  // 命中way的索引
} tag_lookup_result_t;

`endif // RVGPU_TYPES_L15CACHE_TAG_SVH 