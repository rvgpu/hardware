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

`ifndef RVGPU_GPC_L1_MSHR_SV
`define RVGPU_GPC_L1_MSHR_SV

`include "rvgpu_typedef.svh"

// L1 Cache MSHR (Miss Status Handling Register) 模块
// 用于跟踪未完成的内存请求，支持请求合并
module rvgpu_gpc_l15_mshr #(
    parameter int MSHR_ENTRIES = 16,     // MSHR条目数
    parameter int MAX_REQUESTS = 4,      // 每个条目最大请求数
    parameter int ADDR_WIDTH = 40,       // 地址宽度
    parameter int LINE_SIZE = 64,        // 缓存行大小，单位字节
    parameter int ID_WIDTH = 8           // 请求ID宽度
) (
    input  logic clk,
    input  logic rst_n,
    
    // 分配接口
    input  logic                      alloc_valid,
    input  logic [ADDR_WIDTH-1:0]     alloc_addr,
    input  logic [ID_WIDTH-1:0]       alloc_id,
    input  logic [3:0]                alloc_size,
    input  logic                      alloc_is_read,
    input  logic [63:0]               alloc_mask,
    input  logic [511:0]              alloc_data,
    output logic                      alloc_ready,
    output logic                      alloc_hit,
    output logic [$clog2(MSHR_ENTRIES)-1:0] alloc_hit_index,
    
    // 完成接口
    input  logic                      complete_valid,
    input  logic [$clog2(MSHR_ENTRIES)-1:0] complete_index,
    input  logic [511:0]              complete_data,
    output logic                      complete_ready,
    
    // 响应接口
    output logic                      resp_valid,
    output logic [ID_WIDTH-1:0]       resp_id,
    output logic [511:0]              resp_data,
    output logic                      resp_error,
    input  logic                      resp_ready,
    
    // 请求接口
    output logic                      req_valid,
    output logic [ADDR_WIDTH-1:0]     req_addr,
    output logic                      req_is_read,
    output logic [$clog2(MSHR_ENTRIES)-1:0] req_index,
    input  logic                      req_ready,
    
    // 状态接口
    output logic [$clog2(MSHR_ENTRIES):0] used_entries,
    output logic                      full
);
    // MSHR表项定义
    typedef struct packed {
        logic                 valid;
        logic [ADDR_WIDTH-1:0] addr;
        logic                 is_read;
        logic                 pending;
        logic [MAX_REQUESTS-1:0] valid_reqs;
        logic [MAX_REQUESTS-1:0][ID_WIDTH-1:0]   req_ids;
        logic [MAX_REQUESTS-1:0][3:0]            req_sizes;
        logic [MAX_REQUESTS-1:0][63:0]           req_masks;
        logic [MAX_REQUESTS-1:0][511:0]          req_data;
    } mshr_entry_t;
    
    // MSHR表
    mshr_entry_t mshr[MSHR_ENTRIES];
    
    // 内部计数器
    logic [$clog2(MSHR_ENTRIES):0] entry_count;
    
    // 内部状态
    logic [$clog2(MSHR_ENTRIES)-1:0] next_alloc_index;
    logic [$clog2(MSHR_ENTRIES)-1:0] next_req_index;
    logic [MAX_REQUESTS-1:0] next_req_slot[MSHR_ENTRIES];
    
    // 状态输出
    assign used_entries = entry_count;
    assign full = (entry_count == MSHR_ENTRIES);
    
    // 地址匹配逻辑
    function automatic logic addr_match(logic [ADDR_WIDTH-1:0] addr1, logic [ADDR_WIDTH-1:0] addr2);
        // 比较缓存行地址
        return (addr1[ADDR_WIDTH-1:$clog2(LINE_SIZE)] == addr2[ADDR_WIDTH-1:$clog2(LINE_SIZE)]);
    endfunction
    
    // MSHR查找逻辑
    always_comb begin
        alloc_hit = 1'b0;
        alloc_hit_index = '0;
        
        for (int i = 0; i < MSHR_ENTRIES; i++) begin : alloc_search
            if (mshr[i].valid && addr_match(mshr[i].addr, alloc_addr)) begin
                alloc_hit = 1'b1;
                alloc_hit_index = i[$clog2(MSHR_ENTRIES)-1:0];
                break;
            end
        end
    end
    
    // 查找可用请求槽位
    always_comb begin
        for (int i = 0; i < MSHR_ENTRIES; i++) begin : slot_search
            next_req_slot[i] = '0;
            for (int j = 0; j < MAX_REQUESTS; j++) begin : slot_find
                if (!mshr[i].valid_reqs[j]) begin
                    next_req_slot[i] = (1 << j);
                    break;
                end
            end
        end
    end
    
    // MSHR分配逻辑
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < MSHR_ENTRIES; i++) begin : mshr_init
                mshr[i].valid <= 1'b0;
                mshr[i].pending <= 1'b0;
                mshr[i].valid_reqs <= '0;
            end
            
            entry_count <= '0;
            next_alloc_index <= '0;
            next_req_index <= '0;
            alloc_ready <= 1'b0;
        end else begin
            // 默认值
            alloc_ready <= !full || alloc_hit;
            
            // 处理分配请求
            if (alloc_valid && alloc_ready) begin
                if (alloc_hit) begin
                    // 命中现有MSHR条目，添加到请求列表
                    if (|next_req_slot[alloc_hit_index]) begin
                        // 找到第一个空闲槽位
                        for (int j = 0; j < MAX_REQUESTS; j++) begin : slot_alloc
                            if (next_req_slot[alloc_hit_index][j]) begin
                                mshr[alloc_hit_index].valid_reqs[j] <= 1'b1;
                                mshr[alloc_hit_index].req_ids[j] <= alloc_id;
                                mshr[alloc_hit_index].req_sizes[j] <= alloc_size;
                                mshr[alloc_hit_index].req_masks[j] <= alloc_mask;
                                mshr[alloc_hit_index].req_data[j] <= alloc_data;
                                break;
                            end
                        end
                    end
                end else if (!full) begin
                    // 分配新MSHR条目
                    mshr[next_alloc_index].valid <= 1'b1;
                    mshr[next_alloc_index].addr <= alloc_addr;
                    mshr[next_alloc_index].is_read <= alloc_is_read;
                    mshr[next_alloc_index].pending <= 1'b0;
                    mshr[next_alloc_index].valid_reqs <= 4'b0001;
                    mshr[next_alloc_index].req_ids[0] <= alloc_id;
                    mshr[next_alloc_index].req_sizes[0] <= alloc_size;
                    mshr[next_alloc_index].req_masks[0] <= alloc_mask;
                    mshr[next_alloc_index].req_data[0] <= alloc_data;
                    
                    // 更新分配索引和计数
                    next_alloc_index <= (next_alloc_index + 1) % MSHR_ENTRIES;
                    entry_count <= entry_count + 1;
                end
            end
            
            // 处理完成请求
            if (complete_valid && complete_ready) begin
                mshr[complete_index].pending <= 1'b0;
            end
            
            // 处理响应发送
            if (resp_valid && resp_ready) begin
                // 找到第一个有效请求
                for (int j = 0; j < MAX_REQUESTS; j++) begin : resp_send
                    if (mshr[req_index].valid_reqs[j]) begin
                        mshr[req_index].valid_reqs[j] <= 1'b0;
                        break;
                    end
                end
                
                // 如果没有更多请求，释放MSHR条目
                if (mshr[req_index].valid_reqs == '0) begin
                    mshr[req_index].valid <= 1'b0;
                    entry_count <= entry_count - 1;
                end
            end
            
            // 处理请求发送
            if (req_valid && req_ready) begin
                mshr[req_index].pending <= 1'b1;
                
                // 更新请求索引
                next_req_index <= (next_req_index + 1) % MSHR_ENTRIES;
            end
        end
    end
    
    // 完成接口控制
    assign complete_ready = 1'b1;
    
    // 请求接口控制
    always_comb begin
        req_valid = 1'b0;
        req_addr = '0;
        req_is_read = 1'b0;
        req_index = next_req_index;
        
        // 寻找有效但未处理的MSHR条目
        for (int i = 0; i < MSHR_ENTRIES; i++) begin : req_search
            int idx = (next_req_index + i) % MSHR_ENTRIES;
            if (mshr[idx].valid && !mshr[idx].pending) begin
                req_valid = 1'b1;
                req_addr = mshr[idx].addr;
                req_is_read = mshr[idx].is_read;
                req_index = idx[$clog2(MSHR_ENTRIES)-1:0];
                break;
            end
        end
    end
    
    // 响应接口控制
    always_comb begin
        resp_valid = 1'b0;
        resp_id = '0;
        resp_data = '0;
        resp_error = 1'b0;
        
        // 寻找完成的MSHR条目
        for (int i = 0; i < MSHR_ENTRIES; i++) begin : resp_search
            if (mshr[i].valid && !mshr[i].pending) begin
                // 找到第一个有效请求
                for (int j = 0; j < MAX_REQUESTS; j++) begin : req_find
                    if (mshr[i].valid_reqs[j]) begin
                        resp_valid = 1'b1;
                        resp_id = mshr[i].req_ids[j];
                        
                        // 根据请求大小和掩码提取数据
                        // 这里简化处理，直接返回完整数据
                        resp_data = complete_data;
                        break;
                    end
                end
                
                if (resp_valid) break;
            end
        end
    end

endmodule : rvgpu_gpc_l15_mshr

`endif // RVGPU_GPC_L1_MSHR_SV 