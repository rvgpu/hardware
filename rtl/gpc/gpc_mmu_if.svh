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

`ifndef GPC_MMU_IF_SVH
`define GPC_MMU_IF_SVH

`include "rvgpu_typedef.svh"

// GPC MMU接口，用于处理L0 TLB未命中的地址转换请求
interface gpc_mmu_if;
    // 请求通道
    logic                req_valid;      // 请求有效
    logic                req_ready;      // MMU准备好接收请求
    logic [38:0]         req_vaddr;      // 虚拟地址
    logic [2:0]          req_type;       // 访问类型 (读/写/执行)
    logic [31:0]         req_warp_id;    // Warp ID (用于跟踪)
    logic [3:0]          req_source_id;  // 请求源ID (用于区分不同的请求者)
    
    // 响应通道
    logic                resp_valid;     // 响应有效
    logic                resp_ready;     // 请求者准备好接收响应
    logic [26:0]         resp_ppn;       // 物理页号
    logic                resp_hit;       // TLB命中标志
    logic                resp_fault;     // 访问错误标志
    logic [31:0]         resp_warp_id;   // Warp ID
    logic [3:0]          resp_source_id; // 请求源ID
    
    // 访问类型定义 (与L0 TLB保持一致)
    typedef enum logic [2:0] {
        MMU_READ    = 3'b001,
        MMU_WRITE   = 3'b010,
        MMU_EXECUTE = 3'b100
    } mmu_access_type_e;
    
    // 模块端口
    modport gpc_mmu (
        input  req_valid, req_vaddr, req_type, req_warp_id, req_source_id, resp_ready,
        output req_ready, resp_valid, resp_ppn, resp_hit, resp_fault, resp_warp_id, resp_source_id
    );
    
    modport requester (
        output req_valid, req_vaddr, req_type, req_warp_id, req_source_id, resp_ready,
        input  req_ready, resp_valid, resp_ppn, resp_hit, resp_fault, resp_warp_id, resp_source_id
    );
    
    // 任务和函数
    // 请求者使用的任务
    task req_translate(
        input logic [38:0] vaddr,
        input logic [2:0]  type,
        input logic [31:0] warp_id,
        input logic [3:0]  source_id
    );
        req_valid <= 1'b1;
        req_vaddr <= vaddr;
        req_type <= type;
        req_warp_id <= warp_id;
        req_source_id <= source_id;
        
        @(posedge req_ready);
        req_valid <= 1'b0;
    endtask
    
    task req_wait_response(
        output logic [26:0] ppn,
        output logic        hit,
        output logic        fault,
        output logic [31:0] warp_id,
        output logic [3:0]  source_id
    );
        resp_ready <= 1'b1;
        @(posedge resp_valid);
        ppn <= resp_ppn;
        hit <= resp_hit;
        fault <= resp_fault;
        warp_id <= resp_warp_id;
        source_id <= resp_source_id;
        resp_ready <= 1'b0;
    endtask
    
    // GPC MMU使用的任务
    task mmu_accept_request();
        req_ready <= 1'b1;
        @(posedge req_valid);
        req_ready <= 1'b0;
    endtask
    
    task mmu_send_response(
        input logic [26:0] ppn,
        input logic        hit,
        input logic        fault,
        input logic [31:0] warp_id,
        input logic [3:0]  source_id
    );
        resp_valid <= 1'b1;
        resp_ppn <= ppn;
        resp_hit <= hit;
        resp_fault <= fault;
        resp_warp_id <= warp_id;
        resp_source_id <= source_id;
        
        @(posedge resp_ready);
        resp_valid <= 1'b0;
    endtask
    
endinterface : gpc_mmu_if

`endif // GPC_MMU_IF_SVH 