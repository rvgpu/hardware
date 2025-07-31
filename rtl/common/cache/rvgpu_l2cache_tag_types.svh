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

`ifndef RVGPU_L2CACHE_TAG_TYPES_SVH
`define RVGPU_L2CACHE_TAG_TYPES_SVH

// Tag条目结构
typedef struct packed {
    logic [7:0][31:0] tag;           // 每个way的地址标签（最多8路）
    logic [7:0] valid;                // 每个way的有效位
    logic [7:0] dirty;                // 每个way的脏位
    logic [7:0][1:0] mesi_state;     // 每个way的MESI状态
    logic [7:0] lru;                  // LRU计数器（8位对应8路）
} l2cache_tag_entry_t;


`endif // RVGPU_L2CACHE_TAG_TYPES_SVH