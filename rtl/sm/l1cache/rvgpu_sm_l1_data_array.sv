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

`ifndef RVGPU_SM_L1_DATA_ARRAY_SV
`define RVGPU_SM_L1_DATA_ARRAY_SV

`include "rvgpu_typedef.svh"
`include "rvgpu_config.svh"
`include "interface_sm_l1_data_array.svh"

module rvgpu_sm_l1_data_array #(
    parameter int SM_ID = 0
) (
    input  logic clk,
    input  logic rst_n,
    
    // Data Array接口
    interface_sm_l1_data_array.data_array data_if
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
    localparam int WAY_WIDTH = $clog2(L1_CACHE_WAYS);
    
    // ============================================================================
    // 内部信号
    // ============================================================================
    
    // 地址解析
    logic [TAG_WIDTH-1:0] req_tag;
    logic [INDEX_WIDTH-1:0] req_index;
    logic [OFFSET_WIDTH-1:0] req_offset;
    
    // Data Array存储 - 使用SRAM接口
    logic [L1_CACHE_SETS-1:0][L1_CACHE_WAYS-1:0][L1_CACHE_LINE_SIZE-1:0][7:0] data_array;
    
    // 当前处理的请求
    logic processing_req;
    logic [INDEX_WIDTH-1:0] processing_index;
    logic [WAY_WIDTH-1:0] processing_way;
    logic [OFFSET_WIDTH-1:0] processing_offset;
    logic [31:0] processing_data;
    logic [2:0] processing_size;
    logic processing_is_load;
    
    // 访问控制
    logic [L1_CACHE_SETS-1:0][L1_CACHE_WAYS-1:0] access_granted;
    logic access_complete;
    
    // ============================================================================
    // 地址解析
    // ============================================================================
    
    always_comb begin
        req_tag = data_if.data_req_addr[63:OFFSET_WIDTH+INDEX_WIDTH];
        req_index = data_if.data_req_addr[OFFSET_WIDTH+INDEX_WIDTH-1:OFFSET_WIDTH];
        req_offset = data_if.data_req_addr[OFFSET_WIDTH-1:0];
    end
    
    // ============================================================================
    // 访问控制逻辑
    // ============================================================================
    
    always_comb begin
        data_if.data_req_ready = !processing_req && !access_granted[req_index][0] && 
                            !access_granted[req_index][1] && !access_granted[req_index][2] && 
                            !access_granted[req_index][3];
    end
    
    // ============================================================================
    // 请求处理状态机和数据访问逻辑
    // ============================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            processing_req <= 1'b0;
            processing_index <= '0;
            processing_way <= '0;
            processing_offset <= '0;
            processing_data <= '0;
            processing_size <= '0;
            processing_is_load <= 1'b0;
            access_granted <= '0;
            access_complete <= 1'b0;
        end else begin
            // 处理新请求
            if (data_if.data_req_valid && data_if.data_req_ready) begin
                processing_req <= 1'b1;
                processing_index <= req_index;
                processing_way <= 2'b00; // 默认使用way 0，实际应该根据Tag Array结果选择
                processing_offset <= req_offset;
                processing_data <= data_if.data_req_data;
                processing_size <= data_if.data_req_size;
                processing_is_load <= data_if.data_req_is_load;
                
                // 设置访问权限
                access_granted[req_index][0] <= 1'b1;
            end 
            // 处理写请求
            else if (processing_req && !processing_is_load && 
                    access_granted[processing_index][processing_way]) begin
                
                case (processing_size)
                    3'b000: begin // 字节写入
                        data_array[processing_index][processing_way][processing_offset] <= processing_data[7:0];
                    end
                    3'b001: begin // 半字写入
                        data_array[processing_index][processing_way][processing_offset +: 2] <= processing_data[15:0];
                    end
                    3'b010: begin // 字写入
                        data_array[processing_index][processing_way][processing_offset +: 4] <= processing_data;
                    end
                    3'b011: begin // 双字写入
                        data_array[processing_index][processing_way][processing_offset +: 4] <= processing_data;
                        data_array[processing_index][processing_way][processing_offset + 4 +: 4] <= 32'h0;
                    end
                endcase
                
                access_complete <= 1'b1;
            end 
            // 处理读请求
            else if (processing_req && processing_is_load && 
                    access_granted[processing_index][processing_way]) begin
                // 读取操作完成
                access_complete <= 1'b1;
            end
            // 完成访问
            else if (access_complete) begin
                processing_req <= 1'b0;
                access_granted[processing_index][processing_way] <= 1'b0;
                access_complete <= 1'b0;
            end
        end
    end
    
    // ============================================================================
    // 读取数据逻辑
    // ============================================================================
    
    always_comb begin
        if (processing_req && processing_is_load && access_granted[processing_index][processing_way]) begin
            // 读取操作
            logic [31:0] read_data;
            case (processing_size)
                3'b000: read_data = {24'h0, data_array[processing_index][processing_way][processing_offset +: 1]};
                3'b001: read_data = {16'h0, data_array[processing_index][processing_way][processing_offset +: 2]};
                3'b010: read_data = data_array[processing_index][processing_way][processing_offset +: 4];
                3'b011: read_data = {data_array[processing_index][processing_way][processing_offset +: 4], 32'h0};
                default: read_data = 32'h0;
            endcase
            
            data_if.data_resp_valid = 1'b1;
            data_if.data_resp_data = read_data;
        end else begin
            data_if.data_resp_valid = 1'b0;
            data_if.data_resp_data = 32'h0;
        end
    end

endmodule : rvgpu_sm_l1_data_array

`endif // RVGPU_SM_L1_DATA_ARRAY_SV