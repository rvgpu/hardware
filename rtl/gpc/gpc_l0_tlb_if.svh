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

`ifndef GPC_L0_TLB_IF_SVH
`define GPC_L0_TLB_IF_SVH

`include "rvgpu_typedef.svh"

// L0 TLB接口，用于虚拟地址到物理地址的转换
interface gpc_l0_tlb_if;
    // 查找请求通道
    logic                lookup_valid;    // 查找请求有效
    logic                lookup_ready;    // TLB准备好接收请求
    logic [38:0]         vaddr;           // 虚拟地址
    logic [2:0]          access_type;     // 访问类型 (读/写/执行)
    logic [31:0]         warp_id;         // 请求的Warp ID (用于跟踪)
    
    // 查找响应通道
    logic                lookup_resp_valid; // 查找响应有效
    logic                lookup_hit;        // TLB命中标志
    logic [26:0]         ppn;              // 物理页号
    logic                access_fault;      // 访问错误标志
    logic [31:0]         resp_warp_id;      // 响应的Warp ID
    
    // 更新通道 (从GPC MMU到L0 TLB)
    logic                update_valid;     // 更新请求有效
    logic                update_ready;     // TLB准备好接收更新
    logic [38:0]         update_vaddr;     // 要更新的虚拟地址
    logic [26:0]         update_ppn;       // 新的物理页号
    logic [2:0]          update_perm;      // 页权限
    
    // GPC MMU请求通道 (L0 TLB未命中时)
    logic                gpc_mmu_req_valid; // 请求GPC MMU有效
    logic                gpc_mmu_req_ready; // GPC MMU准备好接收请求
    logic [38:0]         gpc_mmu_req_vaddr; // 请求的虚拟地址
    logic [2:0]          gpc_mmu_req_type;  // 请求类型
    logic [31:0]         gpc_mmu_req_warp_id; // 请求的Warp ID
    
    // GPC MMU响应通道
    logic                gpc_mmu_resp_valid; // GPC MMU响应有效
    logic                gpc_mmu_resp_ready; // L0 TLB准备好接收响应
    logic [26:0]         gpc_mmu_resp_ppn;   // 物理页号
    logic                gpc_mmu_resp_fault; // 页错误标志
    logic [31:0]         gpc_mmu_resp_warp_id; // 响应的Warp ID
    
    // 访问类型定义
    typedef enum logic [2:0] {
        TLB_READ    = 3'b001,
        TLB_WRITE   = 3'b010,
        TLB_EXECUTE = 3'b100
    } tlb_access_type_e;
    
    // 模块端口
    modport tpc (
        input  lookup_valid, vaddr, access_type, warp_id, update_valid, update_vaddr, update_ppn, update_perm, gpc_mmu_resp_valid, gpc_mmu_resp_ppn, gpc_mmu_resp_fault, gpc_mmu_resp_warp_id,
        output lookup_ready, lookup_resp_valid, lookup_hit, ppn, access_fault, resp_warp_id, update_ready, gpc_mmu_req_valid, gpc_mmu_req_vaddr, gpc_mmu_req_type, gpc_mmu_req_warp_id, gpc_mmu_req_ready
    );
    
    modport requester (
        output lookup_valid, vaddr, access_type, warp_id, gpc_mmu_resp_ready,
        input  lookup_ready, lookup_resp_valid, lookup_hit, ppn, access_fault, resp_warp_id, gpc_mmu_req_ready
    );
    
    modport gpc_mmu (
        output update_valid, update_vaddr, update_ppn, update_perm, gpc_mmu_resp_valid, gpc_mmu_resp_ppn, gpc_mmu_resp_fault, gpc_mmu_resp_warp_id, gpc_mmu_req_ready,
        input  update_ready, gpc_mmu_req_valid, gpc_mmu_req_vaddr, gpc_mmu_req_type, gpc_mmu_req_warp_id, gpc_mmu_resp_ready
    );
    
    // 任务和函数
    // 请求者使用的任务
    task req_lookup(
        input logic [38:0] va,
        input logic [2:0]  acc_type,
        input logic [31:0] w_id
    );
        lookup_valid = 1'b1;
        vaddr = va;
        access_type = acc_type;
        warp_id = w_id;
        
        @(posedge lookup_ready);
        lookup_valid = 1'b0;
    endtask
    
    task req_wait_response(
        output logic        hit,
        output logic [26:0] phys_pn,
        output logic        fault
    );
        @(posedge lookup_resp_valid);
        hit = lookup_hit;
        phys_pn = ppn;
        fault = access_fault;
    endtask
    
    // TPC使用的任务
    task tpc_accept_lookup();
        lookup_ready = 1'b1;
        @(posedge lookup_valid);
        lookup_ready = 1'b0;
    endtask
    
    task tpc_send_response(
        input logic        hit,
        input logic [26:0] phys_pn,
        input logic        fault,
        input logic [31:0] w_id
    );
        lookup_resp_valid = 1'b1;
        lookup_hit = hit;
        ppn = phys_pn;
        access_fault = fault;
        resp_warp_id = w_id;
        
        #1; // 简单延迟，实际实现中可能需要等待接收方准备好
        lookup_resp_valid = 1'b0;
    endtask
    
    task tpc_request_gpc_mmu(
        input logic [38:0] va,
        input logic [2:0]  acc_type,
        input logic [31:0] w_id
    );
        gpc_mmu_req_valid = 1'b1;
        gpc_mmu_req_vaddr = va;
        gpc_mmu_req_type = acc_type;
        gpc_mmu_req_warp_id = w_id;
        
        @(posedge gpc_mmu_req_ready);
        gpc_mmu_req_valid = 1'b0;
    endtask
    
    // GPC MMU使用的任务
    task gpc_mmu_send_update(
        input logic [38:0] va,
        input logic [26:0] phys_pn,
        input logic [2:0]  perm
    );
        update_valid = 1'b1;
        update_vaddr = va;
        update_ppn = phys_pn;
        update_perm = perm;
        
        @(posedge update_ready);
        update_valid = 1'b0;
    endtask
    
    task gpc_mmu_send_response(
        input logic [26:0] phys_pn,
        input logic        fault,
        input logic [31:0] w_id
    );
        gpc_mmu_resp_valid = 1'b1;
        gpc_mmu_resp_ppn = phys_pn;
        gpc_mmu_resp_fault = fault;
        gpc_mmu_resp_warp_id = w_id;
        
        @(posedge gpc_mmu_resp_ready);
        gpc_mmu_resp_valid = 1'b0;
    endtask

endinterface : gpc_l0_tlb_if

`endif // GPC_L0_TLB_IF_SVH 