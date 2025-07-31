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

`ifndef RVGPU_L2CACHE_IF_SVH
`define RVGPU_L2CACHE_IF_SVH

`include "rvgpu_l2cache_common.svh"
`include "rvgpu_l2cache_common.svh"

interface l2cache_tag_if;
    // 查找请求通道
    logic                                   lookup_valid;
    logic [L2CACHE_INDEX_BITS-1:0]          lookup_index;
    logic [L2CACHE_TAG_BITS-1:0]            lookup_tag;
    logic                                   lookup_ready;
    
    // 查找响应通道
    logic                                   lookup_hit;
    logic [L2CACHE_WAYS-1:0]                hit_way;
    l2cache_tag_entry_t                     tag_entry;
    logic                                   lookup_done;
    
    // 更新请求通道
    logic                                   update_valid;
    logic [L2CACHE_INDEX_BITS-1:0]          update_index;
    logic [L2CACHE_WAYS-1:0]                update_way;
    l2cache_tag_entry_t                     update_entry;
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
endinterface : l2cache_tag_if

//=============================================================================
// Data Array Interface - Controller <-> Data Array
// 用于控制器与数据数组之间的读写操作
//=============================================================================
interface l2cache_data_if;
    // 读请求通道
    logic                               read_valid;
    logic [L2CACHE_INDEX_BITS-1:0]     read_index;
    logic [L2CACHE_WAYS-1:0]           read_way;
    logic [L2CACHE_OFFSET_BITS-1:0]    read_offset;
    logic [7:0]                        read_size;
    logic                               read_ready;
    
    // 读响应通道
    logic [255:0]                      read_data;
    logic [31:0]                       read_strb;
    logic                               read_done;
    
    // 写请求通道
    logic                               write_valid;
    logic [L2CACHE_INDEX_BITS-1:0]     write_index;
    logic [L2CACHE_WAYS-1:0]           write_way;
    logic [L2CACHE_OFFSET_BITS-1:0]    write_offset;
    logic [255:0]                      write_data;
    logic [31:0]                       write_strb;
    logic [7:0]                        write_size;
    logic                               write_ready;
    
    // 写响应通道
    logic                               write_done;
    
    // 缓存行访问通道（用于完整行操作）
    logic                               line_read_valid;
    logic [L2CACHE_INDEX_BITS-1:0]     line_read_index;
    logic [L2CACHE_WAYS-1:0]           line_read_way;
    logic                               line_read_ready;
    
    logic                               line_read_done;
    l2cache_line_t                      line_read_data;
    
    logic                               line_write_valid;
    logic [L2CACHE_INDEX_BITS-1:0]     line_write_index;
    logic [L2CACHE_WAYS-1:0]           line_write_way;
    l2cache_line_t                      line_write_data;
    logic                               line_write_ready;
    
    logic                               line_write_done;
    
    // Controller modport (发起数据操作)
    modport controller (
        output read_valid, read_index, read_way, read_offset, read_size,
        input  read_ready, read_data, read_strb, read_done,
        output write_valid, write_index, write_way, write_offset, write_data, write_strb, write_size,
        input  write_ready, write_done,
        output line_read_valid, line_read_index, line_read_way,
        input  line_read_ready, line_read_done, line_read_data,
        output line_write_valid, line_write_index, line_write_way, line_write_data,
        input  line_write_ready, line_write_done
    );
    
    // Data Array modport (执行数据操作)
    modport data_array (
        input  read_valid, read_index, read_way, read_offset, read_size,
        output read_ready, read_data, read_strb, read_done,
        input  write_valid, write_index, write_way, write_offset, write_data, write_strb, write_size,
        output write_ready, write_done,
        input  line_read_valid, line_read_index, line_read_way,
        output line_read_ready, line_read_done, line_read_data,
        input  line_write_valid, line_write_index, line_write_way, line_write_data,
        output line_write_ready, line_write_done
    );
endinterface : l2cache_data_if

//=============================================================================
// AXI Adapter Interface - Controller <-> AXI Adapter
// 用于控制器与AXI适配器之间的内存访问
//=============================================================================
interface l2cache_axi_if;
    // 读请求通道
    logic                               read_req_valid;
    logic [L2CACHE_AXI_ADDR_WIDTH-1:0] read_req_addr;
    logic [7:0]                        read_req_len;
    logic [2:0]                        read_req_size;
    logic [7:0]                        read_req_id;
    logic                               read_req_ready;
    
    // 读响应通道
    logic                               read_resp_valid;
    logic [L2CACHE_AXI_DATA_WIDTH-1:0] read_resp_data;
    logic [1:0]                        read_resp_status;
    logic                               read_resp_last;
    logic [7:0]                        read_resp_id;
    logic                               read_resp_ready;
    
    // 写请求通道
    logic                               write_req_valid;
    logic [L2CACHE_AXI_ADDR_WIDTH-1:0] write_req_addr;
    logic [7:0]                        write_req_len;
    logic [2:0]                        write_req_size;
    logic [7:0]                        write_req_id;
    logic                               write_req_ready;
    
    // 写数据通道
    logic                               write_data_valid;
    logic [L2CACHE_AXI_DATA_WIDTH-1:0] write_data;
    logic [L2CACHE_AXI_DATA_WIDTH/8-1:0] write_strb;
    logic                               write_last;
    logic                               write_data_ready;
    
    // 写响应通道
    logic                               write_resp_valid;
    logic [1:0]                        write_resp_status;
    logic [7:0]                        write_resp_id;
    logic                               write_resp_ready;
    
    // Controller modport (发起内存访问)
    modport controller (
        output read_req_valid, read_req_addr, read_req_len, read_req_size, read_req_id,
        input  read_req_ready,
        input  read_resp_valid, read_resp_data, read_resp_status, read_resp_last, read_resp_id,
        output read_resp_ready,
        output write_req_valid, write_req_addr, write_req_len, write_req_size, write_req_id,
        input  write_req_ready,
        output write_data_valid, write_data, write_strb, write_last,
        input  write_data_ready,
        input  write_resp_valid, write_resp_status, write_resp_id,
        output write_resp_ready
    );
    
    // AXI Adapter modport (执行内存访问)
    modport axi_adapter (
        input  read_req_valid, read_req_addr, read_req_len, read_req_size, read_req_id,
        output read_req_ready,
        output read_resp_valid, read_resp_data, read_resp_status, read_resp_last, read_resp_id,
        input  read_resp_ready,
        input  write_req_valid, write_req_addr, write_req_len, write_req_size, write_req_id,
        output write_req_ready,
        input  write_data_valid, write_data, write_strb, write_last,
        output write_data_ready,
        output write_resp_valid, write_resp_status, write_resp_id,
        input  write_resp_ready
    );
endinterface : l2cache_axi_if

//=============================================================================
// NOC Adapter Interface - Controller <-> NOC Adapter
// 用于控制器与NOC适配器之间的请求处理
//=============================================================================
interface l2cache_noc_if;
    // 请求接收通道
    logic                               req_valid;
    logic [L2CACHE_NOC_HEADER_WIDTH-1:0] req_header;
    logic [L2CACHE_NOC_DATA_WIDTH-1:0] req_data;
    logic [L2CACHE_NOC_DATA_WIDTH/8-1:0] req_strb;
    logic                               req_last;
    logic                               req_ready;
    
    // 响应发送通道
    logic                               resp_valid;
    logic [L2CACHE_NOC_HEADER_WIDTH-1:0] resp_header;
    logic [L2CACHE_NOC_DATA_WIDTH-1:0] resp_data;
    logic [1:0]                        resp_status;
    logic                               resp_last;
    logic                               resp_ready;
    
    // 请求发送通道（用于向其他节点发送请求）
    logic                               out_req_valid;
    logic [L2CACHE_NOC_HEADER_WIDTH-1:0] out_req_header;
    logic [L2CACHE_NOC_DATA_WIDTH-1:0] out_req_data;
    logic [L2CACHE_NOC_DATA_WIDTH/8-1:0] out_req_strb;
    logic                               out_req_last;
    logic                               out_req_ready;
    
    // 响应接收通道
    logic                               out_resp_valid;
    logic [L2CACHE_NOC_HEADER_WIDTH-1:0] out_resp_header;
    logic [L2CACHE_NOC_DATA_WIDTH-1:0] out_resp_data;
    logic [1:0]                        out_resp_status;
    logic                               out_resp_last;
    logic                               out_resp_ready;
    
    // Controller modport (处理NOC请求)
    modport controller (
        input  req_valid, req_header, req_data, req_strb, req_last,
        output req_ready,
        output resp_valid, resp_header, resp_data, resp_status, resp_last,
        input  resp_ready,
        output out_req_valid, out_req_header, out_req_data, out_req_strb, out_req_last,
        input  out_req_ready,
        input  out_resp_valid, out_resp_header, out_resp_data, out_resp_status, out_resp_last,
        output out_resp_ready
    );
    
    // NOC Adapter modport (适配NOC接口)
    modport noc_adapter (
        output req_valid, req_header, req_data, req_strb, req_last,
        input  req_ready,
        input  resp_valid, resp_header, resp_data, resp_status, resp_last,
        output resp_ready,
        input  out_req_valid, out_req_header, out_req_data, out_req_strb, out_req_last,
        output out_req_ready,
        output out_resp_valid, out_resp_header, out_resp_data, out_resp_status, out_resp_last,
        input  out_resp_ready
    );
endinterface : l2cache_noc_if

`endif // RVGPU_L2CACHE_IF_SVH 