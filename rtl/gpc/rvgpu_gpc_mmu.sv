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

`ifndef RVGPU_GPC_MMU_SV
`define RVGPU_GPC_MMU_SV

`include "rvgpu_typedef.svh"
`include "gpc_mmu_if.svh"
`include "gpc_mmu_noc_if.svh"
`include "gpc_l0_tlb_if.svh"

module rvgpu_gpc_mmu #(
    parameter int TLB_ENTRIES = 128,   // L1 TLB条目数量
    parameter int MAX_REQUESTS = 16,    // 最大并发请求数
    parameter int GPC_ID = 0           // GPC ID
) (
    input  logic clk,
    input  logic rst_n,
    
    // Block Scheduler请求接口
    gpc_mmu_if.gpc_mmu bs_if,
    
    // TPC请求接口 (支持多个TPC)
    gpc_mmu_if.gpc_mmu tpc_if[4],
    
    // L0 TLB更新接口 (支持多个TPC的L0 TLB)
    gpc_l0_tlb_if.gpc_mmu l0_tlb_if[4],
    
    // NOC Adapter接口 (连接到控制单元MMU)
    gpc_mmu_noc_if.gpc_mmu noc_if
);

    // TLB表项定义
    typedef struct packed {
        logic        valid;          // 有效位
        logic [26:0] vpn;            // 虚拟页号 (39位地址的高27位)
        logic [26:0] ppn;            // 物理页号
        logic [2:0]  perm;           // 权限 (读/写/执行)
        logic        accessed;       // 访问位
        logic [3:0]  plru;           // PLRU位
    } tlb_entry_t;
    
    // 请求队列表项定义
    typedef struct packed {
        logic        valid;          // 有效位
        logic [38:0] vaddr;          // 虚拟地址
        logic [2:0]  req_type;       // 访问类型
        logic [31:0] warp_id;        // Warp ID
        logic [3:0]  source_id;      // 请求源ID
        logic [3:0]  tpc_id;         // TPC ID (0-3表示TPC, 4表示Block Scheduler)
        logic        pending;        // 请求是否正在处理中
    } req_entry_t;
    
    // 状态机状态
    typedef enum logic [2:0] {
        IDLE,
        LOOKUP,
        UPDATE_TLB,
        SEND_TO_NOC,
        WAIT_NOC,
        SEND_RESPONSE,
        UPDATE_L0_TLB
    } mmu_state_t;
    
    // L1 TLB存储
    tlb_entry_t tlb_entries[TLB_ENTRIES];
    
    // 请求队列
    req_entry_t req_queue[MAX_REQUESTS];
    logic [$clog2(MAX_REQUESTS)-1:0] req_head;
    logic [$clog2(MAX_REQUESTS)-1:0] req_tail;
    logic req_queue_full;
    logic req_queue_empty;
    
    // 内部信号
    mmu_state_t state;
    logic [$clog2(TLB_ENTRIES)-1:0] replace_index;
    logic [$clog2(TLB_ENTRIES)-1:0] hit_index;
    logic [26:0] req_vpn;
    logic tlb_hit;
    logic tlb_fault;
    
    // 当前处理的请求
    req_entry_t current_req;
    logic [26:0] current_ppn;
    
    // 仲裁器 - 简单的轮询策略
    logic [2:0] arbiter_ptr;
    logic [4:0] req_valid_array;
    logic [4:0] req_grant_array;
    
    // 将请求有效信号组合成数组，便于仲裁
    assign req_valid_array = {bs_if.req_valid, 
                             tpc_if[3].req_valid, 
                             tpc_if[2].req_valid, 
                             tpc_if[1].req_valid, 
                             tpc_if[0].req_valid};
    
    // 仲裁逻辑 - 轮询策略
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arbiter_ptr <= 3'b0;
            req_grant_array <= 5'b0;
        end else begin
            // 默认不授权
            req_grant_array <= 5'b0;
            
            if (!req_queue_full) begin
                // 从当前指针开始轮询 - 简化处理
                logic [2:0] idx0 = (arbiter_ptr + 0) % 5;
                logic [2:0] idx1 = (arbiter_ptr + 1) % 5;
                logic [2:0] idx2 = (arbiter_ptr + 2) % 5;
                logic [2:0] idx3 = (arbiter_ptr + 3) % 5;
                logic [2:0] idx4 = (arbiter_ptr + 4) % 5;
                
                if (req_valid_array[idx0]) begin
                    req_grant_array[idx0] <= 1'b1;
                    arbiter_ptr <= (idx0 + 1) % 5;
                end else if (req_valid_array[idx1]) begin
                    req_grant_array[idx1] <= 1'b1;
                    arbiter_ptr <= (idx1 + 1) % 5;
                end else if (req_valid_array[idx2]) begin
                    req_grant_array[idx2] <= 1'b1;
                    arbiter_ptr <= (idx2 + 1) % 5;
                end else if (req_valid_array[idx3]) begin
                    req_grant_array[idx3] <= 1'b1;
                    arbiter_ptr <= (idx3 + 1) % 5;
                end else if (req_valid_array[idx4]) begin
                    req_grant_array[idx4] <= 1'b1;
                    arbiter_ptr <= (idx4 + 1) % 5;
                end
            end
        end
    end
    
    // 请求队列管理
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_head <= '0;
            req_tail <= '0;
            req_queue_full <= 1'b0;
            req_queue_empty <= 1'b1;
            
            // 初始化队列 - 简化处理
            req_queue[0].valid <= 1'b0;
            req_queue[0].pending <= 1'b0;
            req_queue[1].valid <= 1'b0;
            req_queue[1].pending <= 1'b0;
            req_queue[2].valid <= 1'b0;
            req_queue[2].pending <= 1'b0;
            req_queue[3].valid <= 1'b0;
            req_queue[3].pending <= 1'b0;
            req_queue[4].valid <= 1'b0;
            req_queue[4].pending <= 1'b0;
        end else begin
            // 入队逻辑
            if (req_grant_array != 5'b0 && !req_queue_full) begin
                req_queue[req_tail].valid <= 1'b1;
                req_queue[req_tail].pending <= 1'b0;
                
                // 根据授权信号确定请求来源
                if (req_grant_array[4]) begin
                    // Block Scheduler请求
                    req_queue[req_tail].vaddr <= bs_if.req_vaddr;
                    req_queue[req_tail].req_type <= bs_if.req_type;
                    req_queue[req_tail].warp_id <= bs_if.req_warp_id;
                    req_queue[req_tail].source_id <= bs_if.req_source_id;
                    req_queue[req_tail].tpc_id <= 4; // 4表示Block Scheduler
                end else begin
                    // TPC请求 - 简化处理
                    if (req_grant_array[0]) begin
                        req_queue[req_tail].vaddr <= tpc_if[0].req_vaddr;
                        req_queue[req_tail].req_type <= tpc_if[0].req_type;
                        req_queue[req_tail].warp_id <= tpc_if[0].req_warp_id;
                        req_queue[req_tail].source_id <= tpc_if[0].req_source_id;
                        req_queue[req_tail].tpc_id <= 0;
                    end else if (req_grant_array[1]) begin
                        req_queue[req_tail].vaddr <= tpc_if[1].req_vaddr;
                        req_queue[req_tail].req_type <= tpc_if[1].req_type;
                        req_queue[req_tail].warp_id <= tpc_if[1].req_warp_id;
                        req_queue[req_tail].source_id <= tpc_if[1].req_source_id;
                        req_queue[req_tail].tpc_id <= 1;
                    end else if (req_grant_array[2]) begin
                        req_queue[req_tail].vaddr <= tpc_if[2].req_vaddr;
                        req_queue[req_tail].req_type <= tpc_if[2].req_type;
                        req_queue[req_tail].warp_id <= tpc_if[2].req_warp_id;
                        req_queue[req_tail].source_id <= tpc_if[2].req_source_id;
                        req_queue[req_tail].tpc_id <= 2;
                    end else if (req_grant_array[3]) begin
                        req_queue[req_tail].vaddr <= tpc_if[3].req_vaddr;
                        req_queue[req_tail].req_type <= tpc_if[3].req_type;
                        req_queue[req_tail].warp_id <= tpc_if[3].req_warp_id;
                        req_queue[req_tail].source_id <= tpc_if[3].req_source_id;
                        req_queue[req_tail].tpc_id <= 3;
                    end
                end
                
                // 更新队列状态
                req_tail <= (req_tail + 1) % MAX_REQUESTS;
                req_queue_empty <= 1'b0;
                req_queue_full <= ((req_tail + 1) % MAX_REQUESTS == req_head);
            end
            
            // 出队逻辑
            if (state == SEND_RESPONSE && !req_queue_empty) begin
                req_queue[req_head].valid <= 1'b0;
                req_queue[req_head].pending <= 1'b0;
                
                req_head <= (req_head + 1) % MAX_REQUESTS;
                req_queue_full <= 1'b0;
                req_queue_empty <= ((req_head + 1) % MAX_REQUESTS == req_tail);
            end
            
            // 状态机触发的pending设置
            if (state == IDLE && !req_queue_empty && !req_queue[req_head].pending) begin
                req_queue[req_head].pending <= 1'b1;
            end
        end
    end
    
    // 准备就绪信号
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bs_if.req_ready <= 1'b0;
            tpc_if[0].req_ready <= 1'b0;
            tpc_if[1].req_ready <= 1'b0;
            tpc_if[2].req_ready <= 1'b0;
            tpc_if[3].req_ready <= 1'b0;
        end else begin
            // 根据授权信号设置准备就绪
            bs_if.req_ready <= req_grant_array[4] && !req_queue_full;
            tpc_if[0].req_ready <= req_grant_array[0] && !req_queue_full;
            tpc_if[1].req_ready <= req_grant_array[1] && !req_queue_full;
            tpc_if[2].req_ready <= req_grant_array[2] && !req_queue_full;
            tpc_if[3].req_ready <= req_grant_array[3] && !req_queue_full;
        end
    end
    
    // 提取虚拟页号
    assign req_vpn = current_req.vaddr[38:12];
    
    // TLB查找逻辑
    always_comb begin
        tlb_hit = 1'b0;
        hit_index = '0;
        tlb_fault = 1'b0;
        
        // 并行比较所有TLB条目 - 简化处理
        if (tlb_entries[0].valid && tlb_entries[0].vpn == req_vpn) begin
            tlb_hit = 1'b1;
            hit_index = 0;
            
            // 检查访问权限
            case (current_req.req_type)
                MMU_READ:    tlb_fault = !(tlb_entries[0].perm[0]);
                MMU_WRITE:   tlb_fault = !(tlb_entries[0].perm[1]);
                MMU_EXECUTE: tlb_fault = !(tlb_entries[0].perm[2]);
                default:     tlb_fault = 1'b1;
            endcase
        end else if (tlb_entries[1].valid && tlb_entries[1].vpn == req_vpn) begin
            tlb_hit = 1'b1;
            hit_index = 1;
            
            // 检查访问权限
            case (current_req.req_type)
                MMU_READ:    tlb_fault = !(tlb_entries[1].perm[0]);
                MMU_WRITE:   tlb_fault = !(tlb_entries[1].perm[1]);
                MMU_EXECUTE: tlb_fault = !(tlb_entries[1].perm[2]);
                default:     tlb_fault = 1'b1;
            endcase
        end
    end
    
    // PLRU最小值
    logic [3:0] min_plru;
    
    // 替换策略 (PLRU - Pseudo-LRU)
    always_comb begin
        replace_index = '0;
        min_plru = '1;
        
        // 查找PLRU值最小的条目 - 简化处理
        if (!tlb_entries[0].valid) begin
            // 优先使用无效条目
            replace_index = 0;
        end else if (!tlb_entries[1].valid) begin
            replace_index = 1;
        end else if (tlb_entries[0].plru < min_plru) begin
            min_plru = tlb_entries[0].plru;
            replace_index = 0;
        end else if (tlb_entries[1].plru < min_plru) begin
            min_plru = tlb_entries[1].plru;
            replace_index = 1;
        end
    end
    
    // 主状态机
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            current_req <= '0;
            current_ppn <= '0;
            noc_if.req_valid <= 1'b0;
            noc_if.resp_ready <= 1'b0;
            
            // 初始化TLB条目 - 简化处理
            tlb_entries[0].valid <= 1'b0;
            tlb_entries[0].vpn <= '0;
            tlb_entries[0].ppn <= '0;
            tlb_entries[0].perm <= '0;
            tlb_entries[0].accessed <= 1'b0;
            tlb_entries[0].plru <= 4'h0;
            
            tlb_entries[1].valid <= 1'b0;
            tlb_entries[1].vpn <= '0;
            tlb_entries[1].ppn <= '0;
            tlb_entries[1].perm <= '0;
            tlb_entries[1].accessed <= 1'b0;
            tlb_entries[1].plru <= 4'h1;
            
            // 初始化响应信号
            bs_if.resp_valid <= 1'b0;
            tpc_if[0].resp_valid <= 1'b0;
            tpc_if[1].resp_valid <= 1'b0;
            tpc_if[2].resp_valid <= 1'b0;
            tpc_if[3].resp_valid <= 1'b0;
            l0_tlb_if[0].update_valid <= 1'b0;
            l0_tlb_if[1].update_valid <= 1'b0;
            l0_tlb_if[2].update_valid <= 1'b0;
            l0_tlb_if[3].update_valid <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    // 重置响应信号
                    bs_if.resp_valid <= 1'b0;
                    tpc_if[0].resp_valid <= 1'b0;
                    tpc_if[1].resp_valid <= 1'b0;
                    tpc_if[2].resp_valid <= 1'b0;
                    tpc_if[3].resp_valid <= 1'b0;
                    
                    // 检查请求队列
                    if (!req_queue_empty && !req_queue[req_head].pending) begin
                        current_req <= req_queue[req_head];
                        state <= LOOKUP;
                    end
                end
                
                LOOKUP: begin
                    if (tlb_hit) begin
                        // TLB命中，更新PLRU并准备响应
                        current_ppn <= tlb_entries[hit_index].ppn;
                        
                        // 更新命中条目的PLRU和访问位
                        tlb_entries[hit_index].accessed <= 1'b1;
                        tlb_entries[hit_index].plru <= '1; // 最近使用
                        
                        // 更新其他条目的PLRU值 - 简化处理
                        if (tlb_entries[0].valid && 0 != hit_index && tlb_entries[0].plru > 0) begin
                            tlb_entries[0].plru <= tlb_entries[0].plru - 1;
                        end
                        if (tlb_entries[1].valid && 1 != hit_index && tlb_entries[1].plru > 0) begin
                            tlb_entries[1].plru <= tlb_entries[1].plru - 1;
                        end
                        
                        state <= SEND_RESPONSE;
                    end else begin
                        // TLB未命中，需要请求控制单元MMU
                        state <= SEND_TO_NOC;
                    end
                end
                
                SEND_TO_NOC: begin
                    // 发送请求到NOC Adapter
                    noc_if.req_valid <= 1'b1;
                    noc_if.req_vaddr <= current_req.vaddr;
                    noc_if.req_type <= current_req.req_type;
                    noc_if.req_warp_id <= current_req.warp_id;
                    noc_if.req_source_id <= current_req.source_id;
                    noc_if.req_gpc_id <= GPC_ID;
                    
                    if (noc_if.req_ready) begin
                        noc_if.req_valid <= 1'b0;
                        state <= WAIT_NOC;
                    end
                end
                
                WAIT_NOC: begin
                    // 等待NOC Adapter响应
                    noc_if.resp_ready <= 1'b1;
                    
                    if (noc_if.resp_valid) begin
                        noc_if.resp_ready <= 1'b0;
                        
                        // 保存响应结果
                        current_ppn <= noc_if.resp_ppn;
                        
                        if (!noc_if.resp_fault) begin
                            // 如果没有错误，更新TLB
                            state <= UPDATE_TLB;
                        end else begin
                            // 如果有错误，直接发送响应
                            state <= SEND_RESPONSE;
                        end
                    end
                end
                
                UPDATE_TLB: begin
                    // 更新TLB
                    tlb_entries[replace_index].valid <= 1'b1;
                    tlb_entries[replace_index].vpn <= req_vpn;
                    tlb_entries[replace_index].ppn <= current_ppn;
                    tlb_entries[replace_index].perm <= current_req.req_type; // 简化实现，实际应使用MMU返回的权限
                    tlb_entries[replace_index].accessed <= 1'b1;
                    tlb_entries[replace_index].plru <= '1; // 最近使用
                    
                    // 更新其他条目的PLRU值 - 简化处理
                    if (tlb_entries[0].valid && 0 != replace_index && tlb_entries[0].plru > 0) begin
                        tlb_entries[0].plru <= tlb_entries[0].plru - 1;
                    end
                    if (tlb_entries[1].valid && 1 != replace_index && tlb_entries[1].plru > 0) begin
                        tlb_entries[1].plru <= tlb_entries[1].plru - 1;
                    end
                    
                    // 如果请求来自TPC，还需要更新L0 TLB
                    if (current_req.tpc_id < 4) begin
                        state <= UPDATE_L0_TLB;
                    end else begin
                        state <= SEND_RESPONSE;
                    end
                end
                
                UPDATE_L0_TLB: begin
                    // 更新TPC的L0 TLB
                    l0_tlb_if[current_req.tpc_id].update_valid <= 1'b1;
                    l0_tlb_if[current_req.tpc_id].update_vaddr <= current_req.vaddr;
                    l0_tlb_if[current_req.tpc_id].update_ppn <= current_ppn;
                    l0_tlb_if[current_req.tpc_id].update_perm <= current_req.req_type; // 简化实现
                    
                    if (l0_tlb_if[current_req.tpc_id].update_ready) begin
                        l0_tlb_if[current_req.tpc_id].update_valid <= 1'b0;
                        state <= SEND_RESPONSE;
                    end
                end
                
                SEND_RESPONSE: begin
                    // 根据请求源发送响应
                    if (current_req.tpc_id == 4) begin
                        // 响应Block Scheduler
                        bs_if.resp_valid <= 1'b1;
                        bs_if.resp_ppn <= current_ppn;
                        bs_if.resp_hit <= tlb_hit;
                        bs_if.resp_fault <= tlb_fault;
                        bs_if.resp_warp_id <= current_req.warp_id;
                        bs_if.resp_source_id <= current_req.source_id;
                        
                        if (bs_if.resp_ready) begin
                            bs_if.resp_valid <= 1'b0;
                            state <= IDLE;
                        end
                    end else begin
                        // 响应TPC
                        tpc_if[current_req.tpc_id].resp_valid <= 1'b1;
                        tpc_if[current_req.tpc_id].resp_ppn <= current_ppn;
                        tpc_if[current_req.tpc_id].resp_hit <= tlb_hit;
                        tpc_if[current_req.tpc_id].resp_fault <= tlb_fault;
                        tpc_if[current_req.tpc_id].resp_warp_id <= current_req.warp_id;
                        tpc_if[current_req.tpc_id].resp_source_id <= current_req.source_id;
                        
                        if (tpc_if[current_req.tpc_id].resp_ready) begin
                            tpc_if[current_req.tpc_id].resp_valid <= 1'b0;
                            state <= IDLE;
                        end
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
endmodule : rvgpu_gpc_mmu

`endif // RVGPU_GPC_MMU_SV 