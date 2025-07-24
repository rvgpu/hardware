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

`ifndef RVGPU_SM_L0_ICACHE_SV
`define RVGPU_SM_L0_ICACHE_SV

`include "rvgpu_typedef.svh"
`include "gpc_l0_tlb_if.svh"
`include "gpc_l1_cache_if.svh"

// SM L0 ICache模块
// 提供快速的指令获取，减少指令获取延迟
module rvgpu_sm_l0_icache #(
    parameter int CACHE_SIZE = 16 * 1024,  // 缓存大小，16KB
    parameter int LINE_SIZE = 32,          // 缓存行大小，32字节
    parameter int ASSOCIATIVITY = 4        // 4路组相联
) (
    input  logic clk,
    input  logic rst_n,
    
    // Fetch接口
    input  logic        fetch_req_valid,
    input  logic [63:0] fetch_req_vaddr,
    output logic        fetch_req_ready,
    output logic        fetch_resp_valid,
    output logic [31:0] fetch_resp_inst,
    
    // L1 Cache接口
    output logic        l1_req_valid,
    output logic [63:0] l1_req_paddr,
    output logic [3:0]  l1_req_size,
    input  logic        l1_req_ready,
    input  logic        l1_resp_valid,
    input  logic [255:0] l1_resp_data,
    output logic        l1_resp_ready,
    
    // TLB接口
    output logic        tlb_req_valid,
    output logic [38:0] tlb_req_vaddr,
    output logic [2:0]  tlb_req_type,
    output logic [31:0] tlb_req_warp_id,
    input  logic        tlb_req_ready,
    input  logic        tlb_resp_valid,
    input  logic        tlb_resp_hit,
    input  logic [26:0] tlb_resp_ppn,
    input  logic        tlb_resp_fault,
    input  logic [31:0] tlb_resp_warp_id
);
    // 缓存参数计算
    localparam int SETS = (CACHE_SIZE / LINE_SIZE) / ASSOCIATIVITY;
    localparam int SET_BITS = $clog2(SETS);
    localparam int LINE_BITS = $clog2(LINE_SIZE);
    localparam int TAG_BITS = 27;  // 39位虚拟地址的高27位
    
    // 缓存表项定义
    typedef struct packed {
        logic        valid;          // 有效位
        logic [TAG_BITS-1:0] tag;    // 标签
        logic [LINE_SIZE*8-1:0] data; // 数据
        logic [1:0]  lru;            // LRU位
    } cache_entry_t;
    
    // 缓存存储
    cache_entry_t cache[SETS][ASSOCIATIVITY];
    
    // 状态机状态
    typedef enum logic [2:0] {
        IDLE,
        TRANSLATE,
        WAIT_TLB,
        CACHE_LOOKUP,
        MEMORY_ACCESS,
        WAIT_MEMORY,
        CACHE_UPDATE
    } icache_state_t;
    
    icache_state_t state;
    
    // 内部信号
    logic [63:0] current_vaddr;
    logic [63:0] current_paddr;
    logic [TAG_BITS-1:0] current_tag;
    logic [SET_BITS-1:0] current_set;
    logic [LINE_BITS-1:0] current_offset;
    logic [31:0] current_warp_id;
    logic [31:0] current_inst;
    logic [$clog2(ASSOCIATIVITY)-1:0] hit_way;
    logic [$clog2(ASSOCIATIVITY)-1:0] replace_way;
    logic cache_hit;
    
    // 地址解析
    always_comb begin
        current_tag = fetch_req_vaddr[38:12];
        current_set = fetch_req_vaddr[LINE_BITS+SET_BITS-1:LINE_BITS];
        current_offset = fetch_req_vaddr[LINE_BITS-1:0];
    end
    
    // 缓存查找逻辑
    always_comb begin
        cache_hit = 1'b0;
        hit_way = '0;
        
        for (int i = 0; i < ASSOCIATIVITY; i++) begin
            if (cache[current_set][i].valid && cache[current_set][i].tag == current_tag) begin
                cache_hit = 1'b1;
                hit_way = i;
                break;
            end
        end
    end
    
    // 替换策略 (LRU)
    always_comb begin
        replace_way = '0;
        logic [1:0] min_lru = '1;
        
        for (int i = 0; i < ASSOCIATIVITY; i++) begin
            if (!cache[current_set][i].valid) begin
                // 优先使用无效条目
                replace_way = i;
                break;
            end else if (cache[current_set][i].lru < min_lru) begin
                min_lru = cache[current_set][i].lru;
                replace_way = i;
            end
        end
    end
    
    // 主状态机
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            fetch_req_ready <= 1'b0;
            fetch_resp_valid <= 1'b0;
            fetch_resp_inst <= '0;
            
            l1_req_valid <= 1'b0;
            l1_req_paddr <= '0;
            l1_req_size <= '0;
            l1_resp_ready <= 1'b0;
            
            tlb_req_valid <= 1'b0;
            tlb_req_vaddr <= '0;
            tlb_req_type <= '0;
            tlb_req_warp_id <= '0;
            
            current_vaddr <= '0;
            current_paddr <= '0;
            current_warp_id <= '0;
            current_inst <= '0;
            
            // 初始化缓存
            for (int i = 0; i < SETS; i++) begin
                for (int j = 0; j < ASSOCIATIVITY; j++) begin
                    cache[i][j].valid <= 1'b0;
                    cache[i][j].tag <= '0;
                    cache[i][j].data <= '0;
                    cache[i][j].lru <= j[1:0]; // 初始化LRU值
                end
            end
        end else begin
            case (state)
                IDLE: begin
                    fetch_resp_valid <= 1'b0;
                    fetch_req_ready <= 1'b1;
                    
                    if (fetch_req_valid) begin
                        fetch_req_ready <= 1'b0;
                        current_vaddr <= fetch_req_vaddr;
                        current_warp_id <= 32'h0; // 简化实现，实际应传入warp_id
                        state <= TRANSLATE;
                    end
                end
                
                TRANSLATE: begin
                    // 请求TLB进行地址转换
                    tlb_req_valid <= 1'b1;
                    tlb_req_vaddr <= current_vaddr[38:0];
                    tlb_req_type <= gpc_l0_tlb_if::TLB_EXECUTE;
                    tlb_req_warp_id <= current_warp_id;
                    
                    if (tlb_req_ready) begin
                        tlb_req_valid <= 1'b0;
                        state <= WAIT_TLB;
                    end
                end
                
                WAIT_TLB: begin
                    // 等待TLB响应
                    if (tlb_resp_valid) begin
                        if (tlb_resp_hit && !tlb_resp_fault) begin
                            // 地址转换成功
                            current_paddr <= {tlb_resp_ppn, current_vaddr[11:0]};
                            state <= CACHE_LOOKUP;
                        end else begin
                            // 地址转换失败，返回错误指令
                            fetch_resp_valid <= 1'b1;
                            fetch_resp_inst <= 32'h00000000; // 返回NOP或错误指令
                            state <= IDLE;
                        end
                    end
                end
                
                CACHE_LOOKUP: begin
                    // 缓存查找
                    if (cache_hit) begin
                        // 缓存命中，返回指令
                        fetch_resp_valid <= 1'b1;
                        
                        // 根据偏移量提取指令
                        // 假设指令是32位的，每个缓存行可以存储多条指令
                        fetch_resp_inst <= cache[current_set][hit_way].data[(current_offset*8) +: 32];
                        
                        // 更新LRU
                        for (int i = 0; i < ASSOCIATIVITY; i++) begin
                            if (cache[current_set][i].valid) begin
                                if (i == hit_way) begin
                                    cache[current_set][i].lru <= '1; // 最近使用
                                end else if (cache[current_set][i].lru > 0) begin
                                    cache[current_set][i].lru <= cache[current_set][i].lru - 1;
                                end
                            end
                        end
                        
                        state <= IDLE;
                    end else begin
                        // 缓存未命中，请求L1 Cache
                        state <= MEMORY_ACCESS;
                    end
                end
                
                MEMORY_ACCESS: begin
                    // 请求L1 Cache
                    l1_req_valid <= 1'b1;
                    l1_req_paddr <= {current_paddr[63:LINE_BITS], {LINE_BITS{1'b0}}}; // 对齐到缓存行边界
                    l1_req_size <= 4'h5; // 请求整个缓存行，32字节 = 2^5
                    
                    if (l1_req_ready) begin
                        l1_req_valid <= 1'b0;
                        state <= WAIT_MEMORY;
                    end
                end
                
                WAIT_MEMORY: begin
                    // 等待L1 Cache响应
                    l1_resp_ready <= 1'b1;
                    
                    if (l1_resp_valid) begin
                        l1_resp_ready <= 1'b0;
                        state <= CACHE_UPDATE;
                    end
                end
                
                CACHE_UPDATE: begin
                    // 更新缓存
                    cache[current_set][replace_way].valid <= 1'b1;
                    cache[current_set][replace_way].tag <= current_tag;
                    cache[current_set][replace_way].data <= l1_resp_data;
                    cache[current_set][replace_way].lru <= '1; // 最近使用
                    
                    // 更新其他路的LRU值
                    for (int i = 0; i < ASSOCIATIVITY; i++) begin
                        if (cache[current_set][i].valid && i != replace_way && cache[current_set][i].lru > 0) begin
                            cache[current_set][i].lru <= cache[current_set][i].lru - 1;
                        end
                    end
                    
                    // 返回请求的指令
                    fetch_resp_valid <= 1'b1;
                    fetch_resp_inst <= l1_resp_data[(current_offset*8) +: 32];
                    
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule : rvgpu_sm_l0_icache

`endif // RVGPU_SM_L0_ICACHE_SV 