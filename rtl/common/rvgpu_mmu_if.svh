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

`ifndef RVGPU_MMU_IF_SVH
`define RVGPU_MMU_IF_SVH

`include "rvgpu_constant.svh"

//=============================================================================
// MMU访问类型定义
//=============================================================================
typedef enum logic [2:0] {
    MMU_READ    = 3'b001,
    MMU_WRITE   = 3'b010,
    MMU_EXECUTE = 3'b100
} mmu_access_type_e;

//=============================================================================
// MMU响应状态码定义
//=============================================================================
typedef enum logic [1:0] {
    MMU_RESP_OKAY      = 2'b00,    // 地址转换成功
    MMU_RESP_TLB_MISS  = 2'b01,    // TLB未命中
    MMU_RESP_FAULT     = 2'b10,    // 页错误（权限错误、无效地址等）
    MMU_RESP_ERROR     = 2'b11     // 其他错误
} mmu_resp_status_e;

//=============================================================================
// MMU Interface - 基本的MMU请求/响应接口
// 用于地址转换请求和响应，不包含配置信号
//=============================================================================
interface mmu_if;
    localparam int VA_WIDTH = `RVGPU_CONST_CU_VA_WIDTH;
    localparam int PA_WIDTH = `RVGPU_CONST_CU_PA_WIDTH;

    // Request Channel
    logic                               req_valid;
    logic [VA_WIDTH-1:0]                req_vaddr;
    mmu_access_type_e                   req_type;
    logic                               req_ready;
    
    // Response Channel
    logic                               resp_valid;
    logic [PA_WIDTH-1:0]                resp_paddr;
    logic                               resp_hit;
    mmu_resp_status_e                   resp_status;
    logic                               resp_ready;
    
    // Requestor port (发起地址转换请求)
    modport requester_port (
        output req_valid, req_vaddr, req_type,
        input  req_ready,
        input  resp_valid, resp_paddr, resp_hit, resp_status,
        output resp_ready
    );
    
    // MMU port (执行地址转换)
    modport mmu_port (
        input  req_valid, req_vaddr, req_type,
        output req_ready,
        output resp_valid, resp_paddr, resp_hit, resp_status,
        input  resp_ready
    );
endinterface : mmu_if

//=============================================================================
// MMU TLB Lookup Interface - MMU <-> TLB
// 用于MMU向TLB发送查找请求
//=============================================================================
interface mmu_tlb_if;
    localparam int VA_WIDTH = `RVGPU_CONST_CU_VA_WIDTH;
    localparam int PA_WIDTH = `RVGPU_CONST_CU_PA_WIDTH;

    // 请求通道 (MMU -> TLB)
    logic                               req_valid;
    logic [VA_WIDTH-1:0]                req_vaddr;
    logic                               req_ready;

    // 响应通道 (TLB -> MMU)
    logic                               resp_valid;
    logic [PA_WIDTH-1:0]                resp_paddr;
    logic                               resp_hit;
    logic                               resp_ready;

    // 更新通道 (MMU -> TLB)
    logic                               update_valid;
    logic [VA_WIDTH-1:0]                update_vaddr;
    logic [PA_WIDTH-1:0]                update_paddr;
    logic                               update_ready;

    modport mmu_port (
        // 请求端口
        output req_valid, req_vaddr,
        input  req_ready,
        // 响应端口
        input  resp_valid, resp_paddr, resp_hit,
        output resp_ready,
        // 更新端口
        output update_valid, update_vaddr, update_paddr,
        input  update_ready
    );

    modport tlb_port (
        // 请求端口
        input  req_valid, req_vaddr,
        output req_ready,
        // 响应端口
        output resp_valid, resp_paddr, resp_hit,
        input  resp_ready,
        // 更新端口
        input  update_valid, update_vaddr, update_paddr,
        output update_ready
    );
endinterface : mmu_tlb_if

//=============================================================================
// CP-MMU Config Interface - CP专用的MMU配置接口
// 专门用于Command Processor配置MMU的页表基地址等参数
//=============================================================================
interface cp_mmu_config_if;
    localparam int PA_WIDTH = `RVGPU_CONST_CU_PA_WIDTH;

    // Configuration Channel
    logic                               cfg_en;         // 配置使能
    logic [PA_WIDTH-1:0]                cfg_base_addr;  // 页表基地址
    
    // CP port (配置MMU)
    modport cp_port (
        output cfg_en, cfg_base_addr
    );
    
    // MMU port (接收配置)
    modport mmu_port (
        input cfg_en, cfg_base_addr
    );
endinterface : cp_mmu_config_if

//=============================================================================
// GPC TLB Update Interface - GPC MMU -> L0 TLB
// 用于MMU向TLB发送更新请求
//=============================================================================
interface gpc_tlb_update_if;
    localparam int VA_WIDTH = `RVGPU_CONST_CU_VA_WIDTH;
    localparam int PA_WIDTH = `RVGPU_CONST_CU_PA_WIDTH;

    // TLB更新通道
    logic                               update_valid;     // 更新请求有效
    logic                               update_ready;     // TLB准备好接收更新
    logic [VA_WIDTH-1:0]                update_vaddr;     // 要更新的虚拟地址
    logic [PA_WIDTH-1:0]                update_paddr;     // 新的物理地址
    logic [2:0]                         update_perm;      // 页权限
    
    // 更新发起者端口 (MMU)
    modport initiator (
        output update_valid, update_vaddr, update_paddr, update_perm,
        input  update_ready
    );
    
    // 更新接收者端口 (TLB)
    modport receiver (
        input  update_valid, update_vaddr, update_paddr, update_perm,
        output update_ready
    );
endinterface : gpc_tlb_update_if

`endif // RVGPU_MMU_IF_SVH 