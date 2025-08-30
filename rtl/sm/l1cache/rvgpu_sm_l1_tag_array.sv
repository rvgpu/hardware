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

`ifndef RVGPU_SM_L1_TAG_ARRAY_SV
`define RVGPU_SM_L1_TAG_ARRAY_SV

`include "rvgpu_typedef.svh"
`include "rvgpu_config.svh"
`include "interface_sm_l1_tag_array.svh"

module rvgpu_sm_l1_tag_array #(
    parameter int SM_ID = 0
) (
    input  logic clk,
    input  logic rst_n,
    
    // Tag Array接口
    interface_sm_l1_tag_array.tag_array tag_if
);

    // ============================================================================
    // 使用宏定义
    // ============================================================================
    localparam int CUDA_CORE_COUNT = `CONFIG_SM_CUDA_CORE_COUNT;
    
    // L1 Cache配置参数
    localparam int L1_CACHE_SIZE = 32 * 1024;        // 32KB
    localparam int L1_CACHE_LINE_SIZE = 64;          // 64字节缓存行
    localparam int L1_CACHE_WAYS = 4;                // 4路组相联
    localparam int L1_CACHE_SETS = L1_CACHE_SIZE / (L1_CACHE_LINE_SIZE * L1_CACHE_WAYS);
    
    localparam int TAG_WIDTH = 20;                   // 标签位宽
    localparam int INDEX_WIDTH = $clog2(L1_CACHE_SETS);
    localparam int OFFSET_WIDTH = $clog2(L1_CACHE_LINE_SIZE);
    
    // ============================================================================
    // 内部信号
    // ============================================================================
    
    // 地址解析
    logic [CUDA_CORE_COUNT-1:0][TAG_WIDTH-1:0] req_tag;
    logic [CUDA_CORE_COUNT-1:0][INDEX_WIDTH-1:0] req_index;
    logic [CUDA_CORE_COUNT-1:0][OFFSET_WIDTH-1:0] req_offset;
    
    // Tag Array存储
    logic [L1_CACHE_SETS-1:0][L1_CACHE_WAYS-1:0][TAG_WIDTH-1:0] tag_array;
    logic [L1_CACHE_SETS-1:0][L1_CACHE_WAYS-1:0] valid_array;
    logic [L1_CACHE_SETS-1:0][L1_CACHE_WAYS-1:0] dirty_array;
    
    // LRU计数器
    logic [L1_CACHE_SETS-1:0][L1_CACHE_WAYS-1:0][1:0] lru_counter;
    
    // 当前处理的请求
    logic [CUDA_CORE_COUNT-1:0] processing_req;
    logic [CUDA_CORE_COUNT-1:0][INDEX_WIDTH-1:0] processing_index;
    logic [CUDA_CORE_COUNT-1:0][TAG_WIDTH-1:0] processing_tag;
    
    // ============================================================================
    // 地址解析
    // ============================================================================
    
    always_comb begin
        for (int i = 0; i < CUDA_CORE_COUNT; i++) begin
            req_tag[i] = tag_if.tag_req_addr[63:OFFSET_WIDTH+INDEX_WIDTH];
            req_index[i] = tag_if.tag_req_addr[OFFSET_WIDTH+INDEX_WIDTH-1:OFFSET_WIDTH];
            req_offset[i] = tag_if.tag_req_addr[OFFSET_WIDTH-1:0];
        end
    end
    
    // ============================================================================
    // Tag查找逻辑
    // ============================================================================
    
    always_comb begin
        for (int i = 0; i < CUDA_CORE_COUNT; i++) begin
            tag_if.tag_req_ready = !processing_req[i];
            
            if (tag_if.tag_req_valid && !processing_req[i]) begin
                // 检查是否命中
                logic hit_found = 1'b0;
                logic [1:0] hit_way = 2'b00;
                
                for (int way = 0; way < L1_CACHE_WAYS; way++) begin
                    if (valid_array[req_index[i]][way] && 
                        tag_array[req_index[i]][way] == req_tag[i]) begin
                        hit_found = 1'b1;
                        hit_way = way[1:0];
                    end
                end
                
                // 设置响应
                tag_if.tag_resp_valid = 1'b1;
                tag_if.tag_resp_hit = hit_found;
                tag_if.tag_resp_tag = req_tag[i];
                tag_if.tag_resp_index = req_index[i];
            end else begin
                tag_if.tag_resp_valid = 1'b0;
                tag_if.tag_resp_hit = 1'b0;
                tag_if.tag_resp_tag = 20'h0;
                tag_if.tag_resp_index = 8'h0;
            end
        end
    end
    
    // ============================================================================
    // 请求处理状态机
    // ============================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            processing_req <= {CUDA_CORE_COUNT{1'b0}};
            processing_index <= '{default: '0};
            processing_tag <= '{default: '0};
        end else begin
            for (int i = 0; i < CUDA_CORE_COUNT; i++) begin
                if (tag_if.tag_req_valid && !processing_req[i]) begin
                    processing_req[i] <= 1'b1;
                    processing_index[i] <= req_index[i];
                    processing_tag[i] <= req_tag[i];
                end else if (tag_if.tag_resp_valid) begin
                    processing_req[i] <= 1'b0;
                end
            end
        end
    end
    
    // ============================================================================
    // LRU更新逻辑
    // ============================================================================
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < CUDA_CORE_COUNT; i++) begin
            if (tag_if.tag_resp_valid && tag_if.tag_resp_hit) begin
                // 更新LRU计数器
                logic [1:0] hit_way = 2'b00;
                for (int way = 0; way < L1_CACHE_WAYS; way++) begin
                    if (valid_array[req_index[i]][way] && 
                        tag_array[req_index[i]][way] == req_tag[i]) begin
                        hit_way = way[1:0];
                        break;
                    end
                end
                
                // 将命中的way设为最高优先级
                lru_counter[req_index[i]][hit_way] <= 2'b11;
                
                // 降低其他way的优先级
                for (int way = 0; way < L1_CACHE_WAYS; way++) begin
                    if (way != hit_way && valid_array[req_index[i]][way]) begin
                        if (lru_counter[req_index[i]][way] > 2'b00) begin
                            lru_counter[req_index[i]][way] <= lru_counter[req_index[i]][way] - 1;
                        end
                    end
                end
            end
        end
    end

endmodule : rvgpu_sm_l1_tag_array

`endif // RVGPU_SM_L1_TAG_ARRAY_SV
