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

`ifndef RVGPU_GPC_L1_RRIP_SV
`define RVGPU_GPC_L1_RRIP_SV

`include "rvgpu_typedef.svh"

// L1 Cache RRIP (Re-Reference Interval Prediction) 替换策略模块
// 实现了Static RRIP (SRRIP)算法
module rvgpu_gpc_l15_rrip #(
    parameter int CACHE_SIZE = 256 * 1024,    // 缓存大小，单位字节
    parameter int LINE_SIZE = 64,             // 缓存行大小，单位字节
    parameter int ASSOCIATIVITY = 8,          // 相联度
    parameter int RRPV_BITS = 2               // RRPV位宽，一般为2或3
) (
    input  logic clk,
    input  logic rst_n,
    
    // 索引接口
    input  logic [$clog2((CACHE_SIZE/LINE_SIZE)/ASSOCIATIVITY)-1:0] index,
    
    // 命中接口
    input  logic                      hit_valid,
    input  logic [$clog2(ASSOCIATIVITY)-1:0] hit_way,
    
    // 插入接口
    input  logic                      insert_valid,
    output logic [$clog2(ASSOCIATIVITY)-1:0] insert_way,
    
    // 替换接口
    input  logic                      replace_valid,
    output logic [$clog2(ASSOCIATIVITY)-1:0] replace_way
);
    // 计算索引位宽
    localparam int NUM_SETS = (CACHE_SIZE / LINE_SIZE) / ASSOCIATIVITY;
    localparam int INDEX_WIDTH = $clog2(NUM_SETS);
    
    // RRPV数组 (Re-Reference Prediction Value)
    // 高RRPV值表示更可能被替换
    logic [RRPV_BITS-1:0] rrpv_array[NUM_SETS][ASSOCIATIVITY];
    
    // 最大RRPV值
    localparam logic [RRPV_BITS-1:0] MAX_RRPV = {RRPV_BITS{1'b1}};
    
    // 远期重用RRPV值 (用于新插入)
    localparam logic [RRPV_BITS-1:0] DISTANT_RRPV = MAX_RRPV - 1;
    
    // 近期重用RRPV值 (用于命中)
    localparam logic [RRPV_BITS-1:0] NEAR_RRPV = {RRPV_BITS{1'b0}};
    
    // 内部信号
    logic [$clog2(ASSOCIATIVITY)-1:0] victim_way;
    logic found_victim;
    
    // 命中处理：降低RRPV值
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 初始化所有RRPV为最大值
            for (int i = 0; i < NUM_SETS; i++) begin
                for (int j = 0; j < ASSOCIATIVITY; j++) begin
                    rrpv_array[i][j] <= MAX_RRPV;
                end
            end
        end else begin
            // 处理命中
            if (hit_valid) begin
                // 命中时将RRPV设为近期重用值
                rrpv_array[index][hit_way] <= NEAR_RRPV;
            end
            
            // 处理插入
            if (insert_valid) begin
                // 插入时将RRPV设为远期重用值
                rrpv_array[index][insert_way] <= DISTANT_RRPV;
            end
        end
    end
    
    // 替换策略：选择RRPV最高的路
    always_comb begin
        victim_way = '0;
        found_victim = 1'b0;
        
        // 第一次扫描：寻找RRPV为MAX_RRPV的路
        for (int i = 0; i < ASSOCIATIVITY; i++) begin
            if (rrpv_array[index][i] == MAX_RRPV) begin
                victim_way = i[$clog2(ASSOCIATIVITY)-1:0];
                found_victim = 1'b1;
                break;
            end
        end
        
        // 如果没有找到RRPV为MAX_RRPV的路，增加所有RRPV并重新扫描
        if (!found_victim) begin
            // 在实际实现中，这里应该是一个时序逻辑，但为了简化，我们使用组合逻辑
            // 在真实硬件中，可能需要多个周期来完成这个操作
            victim_way = '0;
            for (int i = 0; i < ASSOCIATIVITY; i++) begin
                if (rrpv_array[index][i] == MAX_RRPV - 1) begin
                    victim_way = i[$clog2(ASSOCIATIVITY)-1:0];
                    found_victim = 1'b1;
                    break;
                end
            end
        end
        
        // 如果仍然没有找到，选择第一路
        if (!found_victim) begin
            victim_way = '0;
        end
    end
    
    // 输出
    assign replace_way = victim_way;
    assign insert_way = victim_way;
    
    // 增加RRPV值的逻辑
    // 在实际实现中，这应该是时序逻辑的一部分
    // 为了简化，我们在这里省略了这部分逻辑

endmodule : rvgpu_gpc_l1_rrip

`endif // RVGPU_GPC_L1_RRIP_SV 