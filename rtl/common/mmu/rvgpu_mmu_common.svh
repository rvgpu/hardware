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

`ifndef RVGPU_MMU_COMMON_SVH
`define RVGPU_MMU_COMMON_SVH

`include "rvgpu_constant.svh"

//=============================================================================
// 1. 常量定义 - 使用公共宏
//=============================================================================

// 公共MMU配置 - 所有MMU类型共用
localparam int VA_WIDTH = `RVGPU_CONST_MMU_VA_WIDTH;
localparam int PA_WIDTH = `RVGPU_CONST_MMU_PA_WIDTH;
localparam int PAGE_OFFSET_BITS = `RVGPU_CONST_MMU_PAGE_OFFSET_BITS;
localparam int PPN_BITS = `RVGPU_CONST_MMU_PPN_BITS;
localparam int VPN_BITS = `RVGPU_CONST_MMU_VPN_BITS;
localparam int PAGE_SIZE = `RVGPU_CONST_MMU_PAGE_SIZE;

// 页表级别常量
localparam int L1_LEVEL = 2'b00;       // L1页表级别
localparam int L2_LEVEL = 2'b01;       // L2页表级别
localparam int L3_LEVEL = 2'b10;       // L3页表级别

// 页表索引位宽
localparam int PAGE_INDEX_BITS = $clog2(PAGE_SIZE / 8);

// CU TLB特定配置
localparam int CU_TLB_ENTRIES = `RVGPU_CONST_CU_TLB_ENTRIES;
localparam int CU_TLB_INDEX_BITS = `RVGPU_CONST_CU_TLB_INDEX_BITS;
localparam int CU_TLB_TAG_BITS = `RVGPU_CONST_CU_TLB_TAG_BITS;

// GPC TLB特定配置
localparam int GPC_TLB_ENTRIES = `RVGPU_CONST_GPC_MMU_TLB_ENTRIES;
localparam int GPC_TLB_INDEX_BITS = `RVGPU_CONST_GPC_MMU_TLB_INDEX_BITS;
localparam int GPC_TLB_TAG_BITS = `RVGPU_CONST_GPC_MMU_TLB_TAG_BITS;

//=============================================================================
// 2. 共用TLB结构定义
//=============================================================================

// 公共TLB条目字段 - 所有TLB类型共用
typedef struct packed {
    logic [PPN_BITS-1:0] ppn;        // 物理页号 (27位) - 公共
    logic [1:0]          permission;  // 权限位 (00:无, 01:读, 10:写, 11:读写)
    logic                accessed;    // 访问位
    logic                dirty;       // 脏位
    logic                valid;       // 有效位
} tlb_common_entry_t;

// CU TLB条目 - 包含20位标签
typedef struct packed {
    tlb_common_entry_t common;    // 公共部分
    logic [CU_TLB_TAG_BITS-1:0] tag;        // CU特定标签 (20位)
} cu_tlb_entry_t;

// GPC TLB条目 - 包含21位标签
typedef struct packed {
    tlb_common_entry_t common;    // 公共部分
    logic [GPC_TLB_TAG_BITS-1:0] tag;       // GPC特定标签 (21位)
} gpc_tlb_entry_t;

//=============================================================================
// 3. 共用TLB函数定义
//=============================================================================

// 构建公共TLB条目函数
function automatic tlb_common_entry_t build_common_tlb_entry(
    input logic [PA_WIDTH-1:0] paddr,      // 物理地址
    input logic [1:0]          perm        // 权限
);
    tlb_common_entry_t entry;
    entry.ppn = paddr[PA_WIDTH-1:PAGE_OFFSET_BITS];      // 物理页号
    entry.permission = perm;
    entry.accessed = 1'b1;
    entry.dirty = 1'b0;
    entry.valid = 1'b1;
    return entry;
endfunction

// CU TLB地址计算函数
function automatic logic [CU_TLB_TAG_BITS+CU_TLB_INDEX_BITS-1:0] calc_cu_tlb_addr(
    input logic [VA_WIDTH-1:0] vaddr       // 虚拟地址
);
    // CU TLB: 128条目，7位索引，20位标签
    logic [CU_TLB_TAG_BITS-1:0] tag = vaddr[VA_WIDTH-1:PAGE_OFFSET_BITS+CU_TLB_INDEX_BITS];
    logic [CU_TLB_INDEX_BITS-1:0] index = vaddr[PAGE_OFFSET_BITS+CU_TLB_INDEX_BITS-1:PAGE_OFFSET_BITS];
    return {tag, index};
endfunction

// GPC TLB地址计算函数
function automatic logic [GPC_TLB_TAG_BITS+GPC_TLB_INDEX_BITS-1:0] calc_gpc_tlb_addr(
    input logic [VA_WIDTH-1:0] vaddr       // 虚拟地址
);
    // GPC TLB: 64条目，6位索引，21位标签
    logic [GPC_TLB_TAG_BITS-1:0] tag = vaddr[VA_WIDTH-1:PAGE_OFFSET_BITS+GPC_TLB_INDEX_BITS];
    logic [GPC_TLB_INDEX_BITS-1:0] index = vaddr[PAGE_OFFSET_BITS+GPC_TLB_INDEX_BITS-1:PAGE_OFFSET_BITS];
    return {tag, index};
endfunction

// 构建CU TLB条目函数
function automatic cu_tlb_entry_t build_cu_tlb_entry(
    input logic [VA_WIDTH-1:0] vaddr,      // 虚拟地址
    input logic [PA_WIDTH-1:0] paddr       // 物理地址
);
    cu_tlb_entry_t entry;
    entry.common = build_common_tlb_entry(paddr, 2'b11);  // 读写权限
    entry.tag = vaddr[VA_WIDTH-1:PAGE_OFFSET_BITS+CU_TLB_INDEX_BITS];  // CU标签位
    return entry;
endfunction

// 构建GPC TLB条目函数
function automatic gpc_tlb_entry_t build_gpc_tlb_entry(
    input logic [VA_WIDTH-1:0] vaddr,      // 虚拟地址
    input logic [PA_WIDTH-1:0] paddr       // 物理地址
);
    gpc_tlb_entry_t entry;
    entry.common = build_common_tlb_entry(paddr, 2'b11);  // 读写权限
    entry.tag = vaddr[VA_WIDTH-1:PAGE_OFFSET_BITS+GPC_TLB_INDEX_BITS];  // GPC标签位
    return entry;
endfunction

//=============================================================================
// 4. 页表相关函数定义
//=============================================================================

// 多级页表地址计算函数
function automatic logic [PA_WIDTH-1:0] calc_page_table_addr(
    input logic [VA_WIDTH-1:0] vaddr,
    input logic [PA_WIDTH-1:0] base_addr,
    input logic [1:0] level
);
    logic [PAGE_INDEX_BITS-1:0] page_index;
    case (level)
        L1_LEVEL: page_index = vaddr[38:30];  // L1索引
        L2_LEVEL: page_index = vaddr[29:21];  // L2索引
        L3_LEVEL: page_index = vaddr[20:12];  // L3索引
        default: page_index = '0;
    endcase
    // 页表条目是8字节，所以索引需要左移3位
    return base_addr + {page_index, 3'b0};
endfunction

`endif // RVGPU_MMU_COMMON_SVH 