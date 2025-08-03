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

`ifndef RVGPU_TYPES_L15CACHE_DATA_SVH
`define RVGPU_TYPES_L15CACHE_DATA_SVH

`include "types_cache_op.svh"
`include "const_l15cache.svh"
`include "types_l15cache.svh"

//=============================================================================
// L1.5 Cache Data Array Types
//=============================================================================

// Data Array访问结果类型
typedef struct packed {
    logic                      line_read_done;   // 缓存行读取完成
    logic                      line_write_done;  // 缓存行写入完成
    l15cache_line_t            line_data;        // 缓存行数据
    logic [L15CACHE_WAYS-1:0] access_way;       // 访问的way
} l15cache_data_access_result_t;

`endif // RVGPU_TYPES_L15CACHE_DATA_SVH 