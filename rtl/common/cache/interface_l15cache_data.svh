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

`ifndef RVGPU_INTERFACE_L15CACHE_DATA_SVH
`define RVGPU_INTERFACE_L15CACHE_DATA_SVH


`include "types_cache_op.svh"
`include "const_l15cache.svh"
`include "types_l15cache.svh"

//=============================================================================
// Data Array Interface - Controller <-> Data Array
//=============================================================================
interface l15cache_data_if;
    // 缓存行读请求通道
    logic                              line_read_valid;
    logic [L15CACHE_INDEX_BITS-1:0]     line_read_index;
    logic [L15CACHE_WAYS-1:0]           line_read_way;
    logic                              line_read_ready;
    
    // 缓存行读响应通道
    logic                              line_read_done;
    l15cache_line_t                     line_read_data;
    
    // 缓存行写请求通道
    logic                              line_write_valid;
    logic [L15CACHE_INDEX_BITS-1:0]     line_write_index;
    logic [L15CACHE_WAYS-1:0]           line_write_way;
    l15cache_line_t                     line_write_data;
    logic                              line_write_ready;
    
    // 缓存行写响应通道
    logic                              line_write_done;
    
    // Controller modport (发起数据操作)
    modport controller (
        output line_read_valid, line_read_index, line_read_way,
        input  line_read_ready, line_read_done, line_read_data,
        output line_write_valid, line_write_index, line_write_way, line_write_data,
        input  line_write_ready, line_write_done
    );
    
    // Data Array modport (执行数据操作)
    modport data_array (
        input  line_read_valid, line_read_index, line_read_way,
        output line_read_ready, line_read_done, line_read_data,
        input  line_write_valid, line_write_index, line_write_way, line_write_data,
        output line_write_ready, line_write_done
    );
endinterface : l15cache_data_if

`endif // RVGPU_INTERFACE_L15CACHE_DATA_SVH 