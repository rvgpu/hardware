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

`ifndef LDST_SM_IF_SVH
`define LDST_SM_IF_SVH

`include "rvgpu_typedef.svh"

// LDST单元与SM之间的接口，用于处理内存访问请求
interface ldst_sm_if;
    // 请求通道
    logic                req_valid;    // 请求有效信号
    logic                req_ready;    // LDST单元准备好接收请求
    logic                req_is_load;  // 1=加载请求, 0=存储请求
    logic [3:0]          req_size;     // 访问大小 (0=1B, 1=2B, 2=4B, 3=8B, 4=16B)
    logic [2:0]          req_type;     // 访问类型 (普通/原子/屏障等)
    logic [63:0]         req_addr;     // 虚拟地址
    logic [511:0]        req_data;     // 存储请求的数据
    logic [31:0]         req_warp_id;  // Warp ID
    logic [4:0]          req_lane_id;  // Lane ID
    logic [31:0]         req_mask;     // 活动线程掩码
    
    // 响应通道
    logic                resp_valid;   // 响应有效信号
    logic                resp_ready;   // SM准备好接收响应
    logic [511:0]        resp_data;    // 加载请求的返回数据
    logic [31:0]         resp_warp_id; // Warp ID
    logic [4:0]          resp_lane_id; // Lane ID
    logic                resp_error;   // 错误指示
    
    // 控制信号
    logic                flush;        // 刷新请求 (取消所有未完成的请求)
    logic [31:0]         stall_mask;   // Warp暂停掩码
    
    // 状态信号
    logic [7:0]          pending_count; // 未完成请求数量
    
    // 访问类型定义
    typedef enum logic [2:0] {
        LDST_NORMAL      = 3'b000,     // 普通加载/存储
        LDST_ATOMIC_ADD  = 3'b001,     // 原子加
        LDST_ATOMIC_CAS  = 3'b010,     // 原子比较和交换
        LDST_FENCE       = 3'b011,     // 内存屏障
        LDST_PREFETCH    = 3'b100      // 预取
    } ldst_type_e;
    
    // 模块端口
    modport ldst (
        input  req_valid, req_is_load, req_size, req_type, req_addr, req_data, req_warp_id, req_lane_id, req_mask, resp_ready, flush,
        output req_ready, resp_valid, resp_data, resp_warp_id, resp_lane_id, resp_error, pending_count, stall_mask
    );
    
    modport sm (
        output req_valid, req_is_load, req_size, req_type, req_addr, req_data, req_warp_id, req_lane_id, req_mask, resp_ready, flush,
        input  req_ready, resp_valid, resp_data, resp_warp_id, resp_lane_id, resp_error, pending_count, stall_mask
    );
    
    // 任务和函数
    // SM端使用的任务
    task sm_request_load(
        input logic [63:0]  addr,
        input logic [31:0]  warp_id,
        input logic [4:0]   lane_id,
        input logic [31:0]  mask,
        input logic [3:0]   size
    );
        req_valid    = 1'b1;
        req_is_load  = 1'b1;
        req_size     = size;
        req_type     = LDST_NORMAL;
        req_addr     = addr;
        req_warp_id  = warp_id;
        req_lane_id  = lane_id;
        req_mask     = mask;
        req_data     = 'x;  // 不关心
        
        @(posedge req_ready);
        req_valid    = 1'b0;
    endtask
    
    task sm_request_store(
        input logic [63:0]  addr,
        input logic [511:0] data,
        input logic [31:0]  warp_id,
        input logic [4:0]   lane_id,
        input logic [31:0]  mask,
        input logic [3:0]   size
    );
        req_valid    = 1'b1;
        req_is_load  = 1'b0;
        req_size     = size;
        req_type     = LDST_NORMAL;
        req_addr     = addr;
        req_data     = data;
        req_warp_id  = warp_id;
        req_lane_id  = lane_id;
        req_mask     = mask;
        
        @(posedge req_ready);
        req_valid    = 1'b0;
    endtask
    
    task sm_wait_response(
        output logic [511:0] data,
        output logic         error
    );
        resp_ready = 1'b1;
        @(posedge resp_valid);
        data  = resp_data;
        error = resp_error;
        resp_ready = 1'b0;
    endtask
    
    // LDST端使用的任务
    task ldst_accept_request();
        req_ready = 1'b1;
        @(posedge req_valid);
        req_ready = 1'b0;
    endtask
    
    task ldst_send_response(
        input logic [511:0] data,
        input logic [31:0]  warp_id,
        input logic [4:0]   lane_id,
        input logic         error
    );
        resp_valid    = 1'b1;
        resp_data     = data;
        resp_warp_id  = warp_id;
        resp_lane_id  = lane_id;
        resp_error    = error;
        
        @(posedge resp_ready);
        resp_valid    = 1'b0;
    endtask

endinterface : ldst_sm_if

`endif // LDST_SM_IF_SVH 