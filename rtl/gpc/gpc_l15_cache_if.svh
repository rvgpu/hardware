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

`ifndef GPC_L15_CACHE_IF_SVH
`define GPC_L15_CACHE_IF_SVH

`include "rvgpu_typedef.svh"

// L1.5 Cache接口 (原L1 Cache，位于GPC级别)
// 介于SM级L1 Data Cache和全局L2 Cache之间
interface gpc_l15_cache_if;
    // 请求通道
    logic                req_valid;      // 请求有效
    logic                req_ready;      // Cache准备好接收请求
    logic                req_is_read;    // 1=读请求, 0=写请求
    logic [3:0]          req_size;       // 访问大小 (0=1B, 1=2B, 2=4B, 3=8B, 4=16B, 5=32B, 6=64B, 7=128B)
    logic [3:0]          req_type;       // 访问类型 (普通/原子/屏障等)
    logic [63:0]         req_paddr;      // 物理地址
    logic [1023:0]       req_data;       // 写请求的数据 (扩展到128字节)
    logic [127:0]        req_mask;       // 写掩码 (每字节一位)
    logic [31:0]         req_id;         // 请求ID (用于匹配响应)
    
    // 响应通道
    logic                resp_valid;     // 响应有效
    logic                resp_ready;     // 请求者准备好接收响应
    logic [1023:0]       resp_data;      // 读请求的返回数据 (128字节)
    logic                resp_error;     // 错误指示
    logic [31:0]         resp_id;        // 响应ID (与请求ID匹配)
    
    // 控制信号
    logic                flush;          // 刷新请求
    
    // 状态信号
    logic [7:0]          pending_count;  // 未完成请求数量
    
    // 访问类型定义
    typedef enum logic [3:0] {
        L15_CACHE_NORMAL      = 4'b0000,     // 普通读写
        L15_CACHE_ATOMIC_ADD  = 4'b0001,     // 原子加
        L15_CACHE_ATOMIC_AND  = 4'b0010,     // 原子与
        L15_CACHE_ATOMIC_OR   = 4'b0011,     // 原子或
        L15_CACHE_ATOMIC_XOR  = 4'b0100,     // 原子异或
        L15_CACHE_ATOMIC_CAS  = 4'b0101,     // 原子比较和交换
        L15_CACHE_ATOMIC_EXCH = 4'b0110,     // 原子交换
        L15_CACHE_FENCE       = 4'b0111,     // 内存屏障
        L15_CACHE_PREFETCH    = 4'b1000,     // 预取
        L15_CACHE_FLUSH       = 4'b1001,     // 缓存刷新
        L15_CACHE_INVALIDATE  = 4'b1010      // 缓存失效
    } l15_cache_access_type_e;
    
    // 模块端口
    modport cache (
        input  req_valid, req_is_read, req_size, req_type, req_paddr, req_data, req_mask, req_id, resp_ready, flush,
        output req_ready, resp_valid, resp_data, resp_error, resp_id, pending_count
    );
    
    modport requester (
        output req_valid, req_is_read, req_size, req_type, req_paddr, req_data, req_mask, req_id, resp_ready, flush,
        input  req_ready, resp_valid, resp_data, resp_error, resp_id, pending_count
    );
    
    modport noc_adapter (
        output req_valid, req_is_read, req_size, req_type, req_paddr, req_data, req_mask, req_id, resp_ready, flush,
        input  req_ready, resp_valid, resp_data, resp_error, resp_id, pending_count
    );
    
    // 任务和函数
    // 请求者使用的任务
    task req_read(
        input  logic [63:0] paddr,
        input  logic [3:0]  size,
        input  logic [31:0] id
    );
        req_valid   = 1'b1;
        req_is_read = 1'b1;
        req_size    = size;
        req_type    = L15_CACHE_NORMAL;
        req_paddr   = paddr;
        req_id      = id;
        req_data    = 'x;  // 不关心
        req_mask    = 'x;  // 不关心
        
        @(posedge req_ready);
        req_valid   = 1'b0;
    endtask
    
    task req_write(
        input  logic [63:0]   paddr,
        input  logic [1023:0] data,
        input  logic [127:0]  mask,
        input  logic [3:0]    size,
        input  logic [31:0]   id
    );
        req_valid   = 1'b1;
        req_is_read = 1'b0;
        req_size    = size;
        req_type    = L15_CACHE_NORMAL;
        req_paddr   = paddr;
        req_data    = data;
        req_mask    = mask;
        req_id      = id;
        
        @(posedge req_ready);
        req_valid   = 1'b0;
    endtask
    
    // 等待响应任务
    task wait_resp(
        input  logic [31:0] expected_id,
        output logic [1023:0] data,
        output logic error
    );
        do begin
            @(posedge resp_valid);
        end while (resp_id != expected_id);
        
        data = resp_data;
        error = resp_error;
        resp_ready = 1'b1;
        @(posedge clk);
        resp_ready = 1'b0;
    endtask

endinterface : gpc_l15_cache_if

`endif // GPC_L15_CACHE_IF_SVH 