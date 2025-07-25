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

// 访问类型定义
typedef enum logic [2:0] {
    TLB_READ    = 3'b001,
    TLB_WRITE   = 3'b010,
    TLB_EXECUTE = 3'b100
} tlb_access_type_e;

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
    
    // 模块端口
    modport tpc (
        output lookup_valid, vaddr, access_type, warp_id,
        input  lookup_ready, lookup_resp_valid, lookup_hit, ppn, access_fault, resp_warp_id,
        input  update_valid, update_vaddr, update_ppn, update_perm,
        output update_ready
    );
    
    modport requester (
        output lookup_valid, vaddr, access_type, warp_id,
        input  lookup_ready, lookup_resp_valid, lookup_hit, ppn, access_fault, resp_warp_id
    );
    
    modport gpc_mmu (
        input  lookup_valid, vaddr, access_type, warp_id,
        output lookup_ready, lookup_resp_valid, lookup_hit, ppn, access_fault, resp_warp_id,
        output update_valid, update_vaddr, update_ppn, update_perm,
        input  update_ready
    );
    
endinterface : gpc_l0_tlb_if

`endif // GPC_L0_TLB_IF_SVH 