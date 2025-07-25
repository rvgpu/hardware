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

`ifndef GPC_MMU_NOC_IF_SVH
`define GPC_MMU_NOC_IF_SVH

`include "rvgpu_typedef.svh"
`include "rvgpu_internal_noc_pkg.svh"

// GPC MMU与NOC Adapter之间的接口，用于与控制单元MMU通信
interface gpc_mmu_noc_if;
    // 请求通道
    logic                req_valid;      // 请求有效
    logic                req_ready;      // NOC Adapter准备好接收请求
    logic [38:0]         req_vaddr;      // 虚拟地址
    logic [2:0]          req_type;       // 访问类型 (读/写/执行)
    logic [31:0]         req_warp_id;    // Warp ID (用于跟踪)
    logic [3:0]          req_source_id;  // 请求源ID
    logic [7:0]          req_gpc_id;     // GPC ID
    
    // 响应通道
    logic                resp_valid;     // 响应有效
    logic                resp_ready;     // GPC MMU准备好接收响应
    logic [26:0]         resp_ppn;       // 物理页号
    logic                resp_hit;       // TLB命中标志
    logic                resp_fault;     // 访问错误标志
    logic [31:0]         resp_warp_id;   // Warp ID
    logic [3:0]          resp_source_id; // 请求源ID
    
    // 模块端口
    modport gpc_mmu (
        output req_valid, req_vaddr, req_type, req_warp_id, req_source_id, req_gpc_id,
        output resp_ready,
        input  req_ready, resp_valid, resp_ppn, resp_hit, resp_fault, resp_warp_id, resp_source_id
    );
    
    modport noc_adapter (
        input  resp_ready,
        output req_valid, req_vaddr, req_type, req_warp_id, req_source_id, req_gpc_id,
        input  req_ready, resp_valid, resp_ppn, resp_hit, resp_fault, resp_warp_id, resp_source_id
    );
    
endinterface : gpc_mmu_noc_if

`endif // GPC_MMU_NOC_IF_SVH 