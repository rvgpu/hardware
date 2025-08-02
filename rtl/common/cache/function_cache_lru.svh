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

`ifndef RVGPU_FUNCTION_CACHE_LRU_SVH
`define RVGPU_FUNCTION_CACHE_LRU_SVH

//=============================================================================
// LRU管理函数（通用8路）
//=============================================================================

// 更新LRU计数器
function automatic logic [7:0] update_lru(
    input logic [7:0] current_lru,
    input logic [2:0] accessed_way
);
    logic [7:0] new_lru;
    new_lru = current_lru;
    new_lru[accessed_way] = 1'b0;  // 访问的way设为最新
    // 其他way的LRU位递增
    for (int i = 0; i < 8; i++) begin
        if (i != accessed_way && current_lru[i]) begin
            new_lru[i] = 1'b1;
        end
    end
    return new_lru;
endfunction

// 选择LRU way进行替换
function automatic logic [2:0] select_lru_way(
    input logic [7:0] lru_bits
);
    logic [2:0] selected_way;
    selected_way = 3'b000;
    for (int i = 0; i < 8; i++) begin
        if (lru_bits[i]) begin
            selected_way = i[2:0];
        end
    end
    return selected_way;
endfunction

`endif // RVGPU_FUNCTION_CACHE_LRU_SVH 