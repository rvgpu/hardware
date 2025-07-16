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

`ifndef RVGPU_MMU_PKG_SVH
`define RVGPU_MMU_PKG_SVH

`include "rvgpu_constant.svh"

package rvgpu_mmu_pkg;
    
    // 地址位宽参数 - 使用已定义的常量
    localparam int VA_WIDTH = `RVGPU_CONST_CU_VA_WIDTH;  // 虚拟地址位宽
    localparam int PA_WIDTH = `RVGPU_CONST_CU_PA_WIDTH;  // 物理地址位宽
    localparam int TLB_ENTRIES = `RVGPU_CONST_CU_TLB_ENTRIES;  // TLB条目数
    localparam int TLB_INDEX_BITS = `RVGPU_CONST_CU_TLB_INDEX_BITS;  // TLB索引位数
    localparam int PPN_BITS = `RVGPU_CONST_CU_TLB_PPN_BITS;  // 物理页号位数
   
    // 页表相关常量 - 使用已定义的常量
    localparam int PAGE_OFFSET_BITS = `RVGPU_CONST_CU_PAGE_OFFSET_BITS;  // 页内偏移位数
    localparam int PAGE_INDEX_BITS = `RVGPU_CONST_CU_PAGE_INDEX_BITS;  // 页表索引位数
    localparam int TLB_TAG_BITS = `RVGPU_CONST_CU_TLB_TAG_BITS;  // TLB标签位数
    
    // TLB地址计算常量
    localparam int TLB_TAG_START_BIT = VA_WIDTH - 1;
    localparam int TLB_TAG_END_BIT = PAGE_OFFSET_BITS + TLB_INDEX_BITS;
    localparam int TLB_INDEX_START_BIT = PAGE_OFFSET_BITS + TLB_INDEX_BITS - 1;
    localparam int TLB_INDEX_END_BIT = PAGE_OFFSET_BITS;
    
    // 页表级别常量
    localparam int MAX_PAGE_LEVELS = 3;    // 最大页表级别
    localparam int L1_LEVEL = 2'b00;       // L1页表级别
    localparam int L2_LEVEL = 2'b01;       // L2页表级别
    localparam int L3_LEVEL = 2'b10;       // L3页表级别

    //=============================================================================
    // TLB 相关参数和位域定义
    //=============================================================================
    
    // TLB条目位宽参数
    localparam int TLB_ENTRY_WIDTH = 103;  // TLB条目实际宽度：52+46+2+1+1+1=103位
    localparam int TLB_ADDR_WIDTH = $clog2(TLB_ENTRIES);
    localparam int TLB_DATA_WIDTH = TLB_ENTRY_WIDTH;  // TLB条目数据宽度
    
    // TLB条目位域定义 - 与struct packed定义保持一致
    // struct packed: {ppn, tag, permission, accessed, dirty, valid}
    // 最后声明的字段在最低位，所以valid在最低位
    localparam int PPN_START = 69;        // ppn位[69:34] (最高位)
    localparam int PPN_END = 34;
    localparam int TAG_START = 33;        // tag位[33:5]
    localparam int TAG_END = 5;
    localparam int PERM_START = 4;        // permission位[4:3]
    localparam int PERM_END = 3;
    localparam int ACCESSED_BIT = 2;      // accessed位
    localparam int DIRTY_BIT = 1;         // dirty位
    localparam int VALID_BIT = 0;         // valid位 (最低位)

    //=============================================================================
    // MMU 功能函数
    //=============================================================================

    // TLB地址计算函数
    function automatic logic [TLB_TAG_BITS + TLB_INDEX_BITS - 1:0] calc_tlb_addr(
        input logic [VA_WIDTH-1:0] vaddr
    );
        // TLB地址格式：{标签, 索引}
        // 标签：虚拟地址的高位（除去页内偏移和索引位）
        // 索引：虚拟地址的中间位（用于SRAM地址）

        logic [TLB_TAG_BITS-1:0] tag = vaddr[VA_WIDTH-1:PAGE_OFFSET_BITS+TLB_INDEX_BITS];
        logic [TLB_INDEX_BITS-1:0] index = vaddr[TLB_INDEX_START_BIT:TLB_INDEX_END_BIT];

        return {tag, index};
    endfunction

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

endpackage : rvgpu_mmu_pkg

`endif // RVGPU_MMU_PKG_SVH