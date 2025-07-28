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
`include "rvgpu_mmu_if.svh"  // 包含通用的MMU接口定义，包括mmu_access_type_e

// GPC MMU查询接口，用于地址翻译请求/响应
interface gpc_mmu_if;
    // 请求通道 (用于MMU地址转换请求)
    logic                req_valid;      // 请求有效
    logic                req_ready;      // MMU准备好接收请求
    logic [38:0]         req_vaddr;      // 虚拟地址
    mmu_access_type_e    req_type;       // 访问类型 (读/写/执行)
    logic [31:0]         req_warp_id;    // Warp ID (用于跟踪)
    logic [3:0]          req_source_id;  // 请求源ID (用于区分不同的请求者)
    
    // 响应通道 (用于MMU地址转换响应)
    logic                resp_valid;     // 响应有效
    logic                resp_ready;     // 请求者准备好接收响应
    logic [26:0]         resp_ppn;       // 物理页号
    logic                resp_hit;       // TLB命中标志
    logic                resp_fault;     // 访问错误标志
    logic [31:0]         resp_warp_id;   // Warp ID
    logic [3:0]          resp_source_id; // 请求源ID
    
    // 模块端口定义
    // 服务提供者端口 (MMU/TLB)
    modport provider (
        input  req_valid, req_vaddr, req_type, req_warp_id, req_source_id,
        output resp_ready,
        output req_ready, resp_valid, resp_ppn, resp_hit, resp_fault, resp_warp_id, resp_source_id
    );
    
    // 服务使用者端口 (TPC/SM)
    modport requester (
        output req_valid, req_vaddr, req_type, req_warp_id, req_source_id,
        input  resp_ready,
        input  req_ready, resp_valid, resp_ppn, resp_hit, resp_fault, resp_warp_id, resp_source_id
    );
    
endinterface : gpc_mmu_if

// GPC TLB更新接口，用于L0 TLB更新
interface gpc_tlb_update_if;
    // TLB更新通道
    logic                update_valid;     // 更新请求有效
    logic                update_ready;     // TLB准备好接收更新
    logic [38:0]         update_vaddr;     // 要更新的虚拟地址
    logic [26:0]         update_ppn;       // 新的物理页号
    logic [2:0]          update_perm;      // 页权限
    
    // 模块端口定义
    // 更新发起者端口 (MMU)
    modport initiator (
        output update_valid, update_vaddr, update_ppn, update_perm,
        input  update_ready
    );
    
    // 更新接收者端口 (TLB)
    modport receiver (
        input  update_valid, update_vaddr, update_ppn, update_perm,
        output update_ready
    );
    
endinterface : gpc_tlb_update_if

`endif // GPC_MMU_IF_SVH 