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

`ifndef RVGPU_SM_TENSOR_CORE_SV
`define RVGPU_SM_TENSOR_CORE_SV

`include "rvgpu_typedef.svh"

// SM Tensor核心
// 负责执行矩阵乘法和深度学习相关指令
module rvgpu_sm_tensor_core #(
    parameter int THREAD_COUNT = 32,    // 每个warp的线程数
    parameter int MATRIX_SIZE = 4       // 矩阵大小 (4x4)
) (
    input  logic clk,
    input  logic rst_n,
    
    // 指令输入
    input  logic        inst_valid,
    input  logic [31:0] inst,
    input  logic [31:0] pc,
    input  logic [31:0] warp_id,
    input  logic [31:0] active_mask,
    
    // 操作数输入 (矩阵A、B和C)
    input  logic [15:0] matrix_a[THREAD_COUNT][MATRIX_SIZE][MATRIX_SIZE],
    input  logic [15:0] matrix_b[THREAD_COUNT][MATRIX_SIZE][MATRIX_SIZE],
    input  logic [31:0] matrix_c[THREAD_COUNT][MATRIX_SIZE][MATRIX_SIZE],
    
    // 执行结果输出
    output logic        result_valid,
    output logic [31:0] result_data[THREAD_COUNT][MATRIX_SIZE][MATRIX_SIZE],
    output logic [4:0]  result_rd,
    output logic [31:0] result_pc,
    output logic [31:0] result_warp_id,
    output logic [31:0] result_active_mask,
    
    // 控制信号
    input  logic        stall,
    output logic        ready
);
    // 指令类型定义
    typedef enum logic [2:0] {
        TENSOR_MMAD,       // 矩阵乘加 (D = A*B + C)
        TENSOR_CONV,       // 卷积操作
        TENSOR_RELU,       // ReLU激活函数
        TENSOR_SIGMOID,    // Sigmoid激活函数
        TENSOR_TANH,       // Tanh激活函数
        TENSOR_POOL_MAX,   // 最大池化
        TENSOR_POOL_AVG    // 平均池化
    } tensor_op_e;
    
    // 指令解码结果
    tensor_op_e tensor_op;
    logic [4:0]  rd_addr;
    logic        uses_rd;
    
    // 流水线寄存器
    logic        exec1_valid;
    logic [31:0] exec1_pc;
    logic [31:0] exec1_warp_id;
    logic [31:0] exec1_active_mask;
    logic [4:0]  exec1_rd_addr;
    
    logic        exec2_valid;
    logic [31:0] exec2_pc;
    logic [31:0] exec2_warp_id;
    logic [31:0] exec2_active_mask;
    logic [4:0]  exec2_rd_addr;
    
    // 临时计算结果
    logic [31:0] mmad_result[THREAD_COUNT][MATRIX_SIZE][MATRIX_SIZE];
    logic [31:0] conv_result[THREAD_COUNT][MATRIX_SIZE][MATRIX_SIZE];
    logic [31:0] act_result[THREAD_COUNT][MATRIX_SIZE][MATRIX_SIZE];
    logic [31:0] pool_result[THREAD_COUNT][MATRIX_SIZE][MATRIX_SIZE];
    
    // 指令解码
    always_comb begin
        // 默认值
        tensor_op = TENSOR_MMAD;
        rd_addr = inst[11:7];
        uses_rd = (rd_addr != 5'b00000);
        
        // 根据自定义指令格式解码
        // 假设使用自定义指令扩展
        case (inst[6:0])
            7'b1011011: begin // 自定义Tensor指令
                case (inst[14:12])
                    3'b000: tensor_op = TENSOR_MMAD;     // 矩阵乘加
                    3'b001: tensor_op = TENSOR_CONV;     // 卷积
                    3'b010: tensor_op = TENSOR_RELU;     // ReLU
                    3'b011: tensor_op = TENSOR_SIGMOID;  // Sigmoid
                    3'b100: tensor_op = TENSOR_TANH;     // Tanh
                    3'b101: tensor_op = TENSOR_POOL_MAX; // 最大池化
                    3'b110: tensor_op = TENSOR_POOL_AVG; // 平均池化
                    default: tensor_op = TENSOR_MMAD;
                endcase
            end
            
            default: begin
                tensor_op = TENSOR_MMAD; // 默认操作
            end
        endcase
    end
    
    // 矩阵乘加运算
    always_comb begin
        for (int t = 0; t < THREAD_COUNT; t++) begin
            // 只处理活跃线程
            if (active_mask[t]) begin
                // 执行矩阵乘法 D = A*B + C
                for (int i = 0; i < MATRIX_SIZE; i++) begin
                    for (int j = 0; j < MATRIX_SIZE; j++) begin
                        // 初始化为C矩阵的值
                        mmad_result[t][i][j] = matrix_c[t][i][j];
                        
                        // 执行矩阵乘法累加
                        for (int k = 0; k < MATRIX_SIZE; k++) begin
                            // FP16乘法转换为FP32
                            logic [31:0] a_fp32 = {16'b0, matrix_a[t][i][k]};
                            logic [31:0] b_fp32 = {16'b0, matrix_b[t][k][j]};
                            mmad_result[t][i][j] = mmad_result[t][i][j] + a_fp32 * b_fp32;
                        end
                    end
                end
            end else begin
                // 非活跃线程结果为0
                for (int i = 0; i < MATRIX_SIZE; i++) begin
                    for (int j = 0; j < MATRIX_SIZE; j++) begin
                        mmad_result[t][i][j] = '0;
                    end
                end
            end
        end
    end
    
    // 卷积运算 (简化实现)
    always_comb begin
        for (int t = 0; t < THREAD_COUNT; t++) begin
            // 只处理活跃线程
            if (active_mask[t]) begin
                // 简化实现：将卷积视为特殊的矩阵乘法
                for (int i = 0; i < MATRIX_SIZE; i++) begin
                    for (int j = 0; j < MATRIX_SIZE; j++) begin
                        conv_result[t][i][j] = mmad_result[t][i][j]; // 简化实现
                    end
                end
            end else begin
                for (int i = 0; i < MATRIX_SIZE; i++) begin
                    for (int j = 0; j < MATRIX_SIZE; j++) begin
                        conv_result[t][i][j] = '0;
                    end
                end
            end
        end
    end
    
    // 激活函数 (ReLU, Sigmoid, Tanh)
    always_comb begin
        for (int t = 0; t < THREAD_COUNT; t++) begin
            // 只处理活跃线程
            if (active_mask[t]) begin
                for (int i = 0; i < MATRIX_SIZE; i++) begin
                    for (int j = 0; j < MATRIX_SIZE; j++) begin
                        // 根据激活函数类型选择
                        case (tensor_op)
                            TENSOR_RELU: begin
                                // ReLU: max(0, x)
                                act_result[t][i][j] = ($signed(matrix_c[t][i][j]) > 0) ? 
                                                     matrix_c[t][i][j] : 32'h0;
                            end
                            
                            TENSOR_SIGMOID: begin
                                // Sigmoid: 简化实现
                                // 实际应该是 1/(1+e^(-x))
                                act_result[t][i][j] = matrix_c[t][i][j]; // 简化实现
                            end
                            
                            TENSOR_TANH: begin
                                // Tanh: 简化实现
                                // 实际应该是 (e^x - e^(-x))/(e^x + e^(-x))
                                act_result[t][i][j] = matrix_c[t][i][j]; // 简化实现
                            end
                            
                            default: begin
                                act_result[t][i][j] = matrix_c[t][i][j];
                            end
                        endcase
                    end
                end
            end else begin
                for (int i = 0; i < MATRIX_SIZE; i++) begin
                    for (int j = 0; j < MATRIX_SIZE; j++) begin
                        act_result[t][i][j] = '0;
                    end
                end
            end
        end
    end
    
    // 池化操作 (最大池化和平均池化)
    always_comb begin
        for (int t = 0; t < THREAD_COUNT; t++) begin
            // 只处理活跃线程
            if (active_mask[t]) begin
                for (int i = 0; i < MATRIX_SIZE/2; i++) begin
                    for (int j = 0; j < MATRIX_SIZE/2; j++) begin
                        // 2x2池化窗口
                        logic [31:0] val1 = matrix_c[t][i*2][j*2];
                        logic [31:0] val2 = matrix_c[t][i*2][j*2+1];
                        logic [31:0] val3 = matrix_c[t][i*2+1][j*2];
                        logic [31:0] val4 = matrix_c[t][i*2+1][j*2+1];
                        
                        if (tensor_op == TENSOR_POOL_MAX) begin
                            // 最大池化
                            logic [31:0] max12 = ($signed(val1) > $signed(val2)) ? val1 : val2;
                            logic [31:0] max34 = ($signed(val3) > $signed(val4)) ? val3 : val4;
                            pool_result[t][i][j] = ($signed(max12) > $signed(max34)) ? max12 : max34;
                        end else begin
                            // 平均池化
                            pool_result[t][i][j] = (val1 + val2 + val3 + val4) / 4;
                        end
                        
                        // 填充剩余位置为0
                        if (i*2+1 < MATRIX_SIZE && j*2+1 < MATRIX_SIZE) begin
                            pool_result[t][i*2+1][j*2] = '0;
                            pool_result[t][i*2][j*2+1] = '0;
                            pool_result[t][i*2+1][j*2+1] = '0;
                        end
                    end
                end
            end else begin
                for (int i = 0; i < MATRIX_SIZE; i++) begin
                    for (int j = 0; j < MATRIX_SIZE; j++) begin
                        pool_result[t][i][j] = '0;
                    end
                end
            end
        end
    end
    
    // 流水线阶段1 (执行)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exec1_valid <= 1'b0;
            exec1_pc <= '0;
            exec1_warp_id <= '0;
            exec1_active_mask <= '0;
            exec1_rd_addr <= '0;
        end else if (!stall) begin
            exec1_valid <= inst_valid;
            exec1_pc <= pc;
            exec1_warp_id <= warp_id;
            exec1_active_mask <= active_mask;
            exec1_rd_addr <= rd_addr;
        end
    end
    
    // 流水线阶段2 (写回)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exec2_valid <= 1'b0;
            exec2_pc <= '0;
            exec2_warp_id <= '0;
            exec2_active_mask <= '0;
            exec2_rd_addr <= '0;
            
            for (int t = 0; t < THREAD_COUNT; t++) begin
                for (int i = 0; i < MATRIX_SIZE; i++) begin
                    for (int j = 0; j < MATRIX_SIZE; j++) begin
                        result_data[t][i][j] <= '0;
                    end
                end
            end
        end else if (!stall) begin
            exec2_valid <= exec1_valid;
            exec2_pc <= exec1_pc;
            exec2_warp_id <= exec1_warp_id;
            exec2_active_mask <= exec1_active_mask;
            exec2_rd_addr <= exec1_rd_addr;
            
            // 选择结果
            for (int t = 0; t < THREAD_COUNT; t++) begin
                for (int i = 0; i < MATRIX_SIZE; i++) begin
                    for (int j = 0; j < MATRIX_SIZE; j++) begin
                        case (tensor_op)
                            TENSOR_MMAD:     result_data[t][i][j] <= mmad_result[t][i][j];
                            TENSOR_CONV:     result_data[t][i][j] <= conv_result[t][i][j];
                            TENSOR_RELU,
                            TENSOR_SIGMOID,
                            TENSOR_TANH:     result_data[t][i][j] <= act_result[t][i][j];
                            TENSOR_POOL_MAX,
                            TENSOR_POOL_AVG: result_data[t][i][j] <= pool_result[t][i][j];
                            default:         result_data[t][i][j] <= mmad_result[t][i][j];
                        endcase
                    end
                end
            end
        end
    end
    
    // 输出赋值
    assign result_valid = exec2_valid;
    assign result_rd = exec2_rd_addr;
    assign result_pc = exec2_pc;
    assign result_warp_id = exec2_warp_id;
    assign result_active_mask = exec2_active_mask;
    
    // 总是准备好接收新指令
    assign ready = 1'b1;

endmodule : rvgpu_sm_tensor_core

`endif // RVGPU_SM_TENSOR_CORE_SV 