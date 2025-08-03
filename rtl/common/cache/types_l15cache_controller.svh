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

// 控制器内部信号类型
typedef struct packed {
    logic [L15CACHE_WAYS-1:0]  hit_way;      // 命中way
    logic [L15CACHE_WAYS-1:0]  selected_way;  // 选择的way
    logic                      cache_hit;     // 缓存命中标志
    logic                      line_dirty;    // 缓存行脏标志
} l15cache_access_result_t;

`endif // RVGPU_TYPES_L15CACHE_CONTROLLER_SVH 