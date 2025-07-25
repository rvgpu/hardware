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

`ifndef RVGPU_GPC_L1_WRITE_BUFFER_SV
`define RVGPU_GPC_L1_WRITE_BUFFER_SV

`include "rvgpu_typedef.svh"

// L1 Cache写缓冲模块
// 用于缓存写请求，支持写合并
module rvgpu_gpc_l15_write_buffer #(
    parameter int BUFFER_ENTRIES = 8,    // 缓冲条目数
    parameter int ADDR_WIDTH = 40,       // 地址宽度
    parameter int LINE_SIZE = 64,        // 缓存行大小，单位字节
    parameter int ID_WIDTH = 8           // 请求ID宽度
) (
    input  logic clk,
    input  logic rst_n,
    
    // 入队接口
    input  logic                      enq_valid,
    input  logic [ADDR_WIDTH-1:0]     enq_addr,
    input  logic [ID_WIDTH-1:0]       enq_id,
    input  logic [LINE_SIZE*8-1:0]    enq_data,
    input  logic [LINE_SIZE-1:0]      enq_mask,
    output logic                      enq_ready,
    output logic                      enq_hit,
    output logic [$clog2(BUFFER_ENTRIES)-1:0] enq_hit_index,
    
    // 查找接口
    input  logic                      lookup_valid,
    input  logic [ADDR_WIDTH-1:0]     lookup_addr,
    output logic                      lookup_hit,
    output logic [LINE_SIZE*8-1:0]    lookup_data,
    output logic [LINE_SIZE-1:0]      lookup_mask,
    
    // 写回接口
    output logic                      wb_valid,
    output logic [ADDR_WIDTH-1:0]     wb_addr,
    output logic [LINE_SIZE*8-1:0]    wb_data,
    output logic [LINE_SIZE-1:0]      wb_mask,
    input  logic                      wb_ready,
    
    // 完成接口
    input  logic                      complete_valid,
    input  logic [$clog2(BUFFER_ENTRIES)-1:0] complete_index,
    output logic                      complete_ready,
    
    // 响应接口
    output logic                      resp_valid,
    output logic [ID_WIDTH-1:0]       resp_id,
    input  logic                      resp_ready,
    
    // 状态接口
    output logic [$clog2(BUFFER_ENTRIES):0] used_entries,
    output logic                      full,
    input  logic                      flush
);
    // 写缓冲表项定义
    typedef struct packed {
        logic                 valid;
        logic [ADDR_WIDTH-1:0] addr;
        logic [LINE_SIZE*8-1:0] data;
        logic [LINE_SIZE-1:0]  mask;
        logic                 pending;
        logic                 dirty;
        logic [ID_WIDTH-1:0]   last_id;
    } wb_entry_t;
    
    // 写缓冲表
    wb_entry_t wb[BUFFER_ENTRIES];
    
    // 内部计数器
    logic [$clog2(BUFFER_ENTRIES):0] entry_count;
    
    // 内部状态
    logic [$clog2(BUFFER_ENTRIES)-1:0] next_alloc_index;
    logic [$clog2(BUFFER_ENTRIES)-1:0] next_wb_index;
    
    // 状态输出
    assign used_entries = entry_count;
    assign full = (entry_count == BUFFER_ENTRIES);
    
    // 地址匹配逻辑
    function automatic logic addr_match(logic [ADDR_WIDTH-1:0] addr1, logic [ADDR_WIDTH-1:0] addr2);
        // 比较缓存行地址
        return (addr1[ADDR_WIDTH-1:$clog2(LINE_SIZE)] == addr2[ADDR_WIDTH-1:$clog2(LINE_SIZE)]);
    endfunction
    
    // 写缓冲查找逻辑
    always_comb begin
        enq_hit = 1'b0;
        enq_hit_index = '0;
        
        for (int i = 0; i < BUFFER_ENTRIES; i++) begin : enq_search
            if (wb[i].valid && addr_match(wb[i].addr, enq_addr)) begin
                enq_hit = 1'b1;
                enq_hit_index = i[$clog2(BUFFER_ENTRIES)-1:0];
                break;
            end
        end
    end
    
    // 查找接口逻辑
    always_comb begin
        lookup_hit = 1'b0;
        lookup_data = '0;
        lookup_mask = '0;
        
        for (int i = 0; i < BUFFER_ENTRIES; i++) begin : lookup_search
            if (wb[i].valid && addr_match(wb[i].addr, lookup_addr)) begin
                lookup_hit = 1'b1;
                lookup_data = wb[i].data;
                lookup_mask = wb[i].mask;
                break;
            end
        end
    end
    
    // 写缓冲分配逻辑
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < BUFFER_ENTRIES; i++) begin : wb_init
                wb[i].valid <= 1'b0;
                wb[i].pending <= 1'b0;
                wb[i].dirty <= 1'b0;
            end
            
            entry_count <= '0;
            next_alloc_index <= '0;
            next_wb_index <= '0;
            enq_ready <= 1'b0;
        end else begin
            // 默认值
            enq_ready <= !full || enq_hit;
            
            // 处理入队请求
            if (enq_valid && enq_ready) begin
                if (enq_hit) begin
                    // 命中现有写缓冲条目，合并写请求
                    for (int i = 0; i < LINE_SIZE; i++) begin : data_merge
                        if (enq_mask[i]) begin
                            wb[enq_hit_index].data[i*8 +: 8] <= enq_data[i*8 +: 8];
                            wb[enq_hit_index].mask[i] <= 1'b1;
                        end
                    end
                    wb[enq_hit_index].dirty <= 1'b1;
                    wb[enq_hit_index].last_id <= enq_id;
                end else if (!full) begin
                    // 分配新写缓冲条目
                    wb[next_alloc_index].valid <= 1'b1;
                    wb[next_alloc_index].addr <= enq_addr;
                    wb[next_alloc_index].data <= enq_data;
                    wb[next_alloc_index].mask <= enq_mask;
                    wb[next_alloc_index].pending <= 1'b0;
                    wb[next_alloc_index].dirty <= 1'b1;
                    wb[next_alloc_index].last_id <= enq_id;
                    
                    // 更新分配索引和计数
                    next_alloc_index <= (next_alloc_index + 1) % BUFFER_ENTRIES;
                    entry_count <= entry_count + 1;
                end
            end
            
            // 处理完成请求
            if (complete_valid && complete_ready) begin
                wb[complete_index].pending <= 1'b0;
                wb[complete_index].dirty <= 1'b0;
            end
            
            // 处理响应发送
            if (resp_valid && resp_ready) begin
                // 找到已完成的写缓冲条目
                for (int i = 0; i < BUFFER_ENTRIES; i++) begin : resp_cleanup
                    if (wb[i].valid && !wb[i].pending && !wb[i].dirty) begin
                        wb[i].valid <= 1'b0;
                        entry_count <= entry_count - 1;
                        break;
                    end
                end
            end
            
            // 处理写回发送
            if (wb_valid && wb_ready) begin
                wb[next_wb_index].pending <= 1'b1;
                
                // 更新写回索引
                next_wb_index <= (next_wb_index + 1) % BUFFER_ENTRIES;
            end
            
            // 处理刷新请求
            if (flush) begin
                // 将所有非挂起的脏条目标记为待写回
                for (int i = 0; i < BUFFER_ENTRIES; i++) begin : flush_mark
                    if (wb[i].valid && !wb[i].pending && wb[i].dirty) begin
                        wb[i].pending <= 1'b1;
                    end
                end
            end
        end
    end
    
    // 完成接口控制
    assign complete_ready = 1'b1;
    
    // 写回接口控制
    always_comb begin
        wb_valid = 1'b0;
        wb_addr = '0;
        wb_data = '0;
        wb_mask = '0;
        
        // 寻找脏且未挂起的写缓冲条目
        for (int i = 0; i < BUFFER_ENTRIES; i++) begin : wb_search
            int idx = (next_wb_index + i) % BUFFER_ENTRIES;
            if (wb[idx].valid && !wb[idx].pending && wb[idx].dirty) begin
                wb_valid = 1'b1;
                wb_addr = wb[idx].addr;
                wb_data = wb[idx].data;
                wb_mask = wb[idx].mask;
                next_wb_index = idx[$clog2(BUFFER_ENTRIES)-1:0];
                break;
            end
        end
    end
    
    // 响应接口控制
    always_comb begin
        resp_valid = 1'b0;
        resp_id = '0;
        
        // 寻找已完成的写缓冲条目
        for (int i = 0; i < BUFFER_ENTRIES; i++) begin : resp_search
            if (wb[i].valid && !wb[i].pending && !wb[i].dirty) begin
                resp_valid = 1'b1;
                resp_id = wb[i].last_id;
                break;
            end
        end
    end

endmodule : rvgpu_gpc_l15_write_buffer

`endif // RVGPU_GPC_L1_WRITE_BUFFER_SV 