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

`ifndef RVGPU_INTERFACE_L15CACHE_TAG_SVH
`define RVGPU_INTERFACE_L15CACHE_TAG_SVH


`include "types_cache_op.svh"
`include "const_l15cache.svh"
`include "types_l15cache.svh"

//=============================================================================
// Tag Array Interface - Controller <-> Tag Array
//=============================================================================
interface l15cache_tag_if;
    // 查找请求通道
    logic                                   lookup_valid;
    logic [L15CACHE_INDEX_BITS-1:0]          lookup_index;
    logic [L15CACHE_TAG_BITS-1:0]            lookup_tag;
    logic                                   lookup_ready;
    
    // 查找响应通道
    logic                                   lookup_hit;
    logic [L15CACHE_WAYS-1:0]                hit_way;
    l15cache_tag_entry_t                     tag_entry;
    logic                                   lookup_done;
    
    // 更新请求通道
    logic                                   update_valid;
    logic [L15CACHE_INDEX_BITS-1:0]          update_index;
    logic [L15CACHE_WAYS-1:0]                update_way;
    l15cache_tag_entry_t                     update_entry;
    logic                                   update_ready;
    
    // 更新响应通道
    logic                                   update_done;
    
    // Controller modport (发起Tag操作)
    modport controller (
        output lookup_valid, lookup_index, lookup_tag,
        input  lookup_ready, lookup_hit, hit_way, tag_entry, lookup_done,
        output update_valid, update_index, update_way, update_entry,
        input  update_ready, update_done
    );
    
    // Tag Array modport (执行Tag操作)
    modport tag_array (
        input  lookup_valid, lookup_index, lookup_tag,
        output lookup_ready, lookup_hit, hit_way, tag_entry, lookup_done,
        input  update_valid, update_index, update_way, update_entry,
        output update_ready, update_done
    );
endinterface : l15cache_tag_if

`endif // RVGPU_INTERFACE_L15CACHE_TAG_SVH 