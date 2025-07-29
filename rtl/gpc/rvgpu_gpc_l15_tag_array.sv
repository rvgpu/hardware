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

`ifndef RVGPU_GPC_L1_TAG_ARRAY_SV
`define RVGPU_GPC_L1_TAG_ARRAY_SV

`include "rvgpu_typedef.svh"

// L1 Cache Tag数组模块
// 8路组相联，支持并行查找
module rvgpu_gpc_l15_tag_array #(
    parameter int CACHE_SIZE = 256 * 1024,    // 缓存大小，单位字节
    parameter int LINE_SIZE = 64,             // 缓存行大小，单位字节
    parameter int ASSOCIATIVITY = 8,          // 相联度
    parameter int ADDR_WIDTH = 40             // 物理地址宽度
) (
    input  logic clk,
    input  logic rst_n,
    
    // 查找接口
    input  logic                      lookup_valid,
    input  logic [ADDR_WIDTH-1:0]     lookup_addr,
    output logic                      lookup_ready,
    output logic                      lookup_hit,
    output logic [$clog2(ASSOCIATIVITY)-1:0] lookup_way,
    
    // 更新接口
    input  logic                      update_valid,
    input  logic [ADDR_WIDTH-1:0]     update_addr,
    input  logic [$clog2(ASSOCIATIVITY)-1:0] update_way,
    input  logic                      update_dirty,
    output logic                      update_ready,
    
    // 替换策略接口
    input  logic                      replace_valid,
    input  logic [$clog2(ASSOCIATIVITY)-1:0] replace_way,
    output logic [ADDR_WIDTH-1:0]     replace_addr,
    output logic                      replace_dirty,
    output logic                      replace_valid_out
);
    // 计算索引和标签位宽
    localparam int NUM_SETS = (CACHE_SIZE / LINE_SIZE) / ASSOCIATIVITY;
    localparam int INDEX_WIDTH = $clog2(NUM_SETS);
    localparam int TAG_WIDTH = ADDR_WIDTH - INDEX_WIDTH - $clog2(LINE_SIZE);
    
    // 地址分解
    logic [TAG_WIDTH-1:0]     lookup_tag;
    logic [INDEX_WIDTH-1:0]   lookup_index;
    logic [TAG_WIDTH-1:0]     update_tag;
    logic [INDEX_WIDTH-1:0]   update_index;
    
    // Tag表项定义
    typedef struct packed {
        logic                 valid;    // 有效位
        logic                 dirty;    // 脏位
        logic [TAG_WIDTH-1:0] tag;      // 标签
    } tag_entry_t;
    
    // Tag数组存储
    tag_entry_t tag_array[NUM_SETS][ASSOCIATIVITY];
    
    // 地址分解
    assign lookup_tag = lookup_addr[ADDR_WIDTH-1:ADDR_WIDTH-TAG_WIDTH];
    assign lookup_index = lookup_addr[ADDR_WIDTH-TAG_WIDTH-1:$clog2(LINE_SIZE)];
    assign update_tag = update_addr[ADDR_WIDTH-1:ADDR_WIDTH-TAG_WIDTH];
    assign update_index = update_addr[ADDR_WIDTH-TAG_WIDTH-1:$clog2(LINE_SIZE)];
    
    // 查找逻辑
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            lookup_hit <= 1'b0;
            lookup_way <= '0;
            lookup_ready <= 1'b0;
        end else begin
            lookup_ready <= lookup_valid;
            
            if (lookup_valid) begin
                lookup_hit <= 1'b0;
                
                // 并行比较所有路
                for (int i = 0; i < ASSOCIATIVITY; i++) begin
                    if (tag_array[lookup_index][i].valid && 
                        tag_array[lookup_index][i].tag == lookup_tag) begin
                        lookup_hit <= 1'b1;
                        lookup_way <= i[$clog2(ASSOCIATIVITY)-1:0];
                    end
                end
            end
        end
    end
    
    // 更新逻辑
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            update_ready <= 1'b0;
            
            // 初始化所有Tag表项
            for (int i = 0; i < NUM_SETS; i++) begin
                for (int j = 0; j < ASSOCIATIVITY; j++) begin
                    tag_array[i][j].valid <= 1'b0;
                    tag_array[i][j].dirty <= 1'b0;
                    tag_array[i][j].tag <= '0;
                end
            end
        end else begin
            update_ready <= update_valid;
            
            if (update_valid) begin
                tag_array[update_index][update_way].valid <= 1'b1;
                tag_array[update_index][update_way].dirty <= update_dirty;
                tag_array[update_index][update_way].tag <= update_tag;
            end
        end
    end
    
    // 替换逻辑
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            replace_addr <= '0;
            replace_dirty <= 1'b0;
            replace_valid_out <= 1'b0;
        end else begin
            if (replace_valid) begin
                // 构造被替换地址
                replace_addr <= {tag_array[update_index][replace_way].tag, 
                                update_index, 
                                {$clog2(LINE_SIZE){1'b0}}};
                replace_dirty <= tag_array[update_index][replace_way].dirty;
                replace_valid_out <= tag_array[update_index][replace_way].valid;
            end
        end
    end

endmodule : rvgpu_gpc_l15_tag_array

`endif // RVGPU_GPC_L1_TAG_ARRAY_SV 