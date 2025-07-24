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

`ifndef RVGPU_SM_EXECUTE_STAGE_SV
`define RVGPU_SM_EXECUTE_STAGE_SV

`include "rvgpu_typedef.svh"

// SM执行阶段
// 集成CUDA核心和Tensor核心，处理寄存器读取和执行单元调度
module rvgpu_sm_execute_stage #(
    parameter int WARP_COUNT = 32,      // 支持的warp数量
    parameter int THREAD_COUNT = 32     // 每个warp的线程数
) (
    input  logic clk,
    input  logic rst_n,
    
    // 从解码阶段的输入
    input  logic                                decode_exec_valid,
    input  logic [31:0]                         decode_exec_inst,
    input  logic [63:0]                         decode_exec_pc,
    input  logic [$clog2(WARP_COUNT)-1:0]      decode_exec_warp_id,
    input  logic [THREAD_COUNT-1:0]             decode_exec_active_mask,
    input  logic [4:0]                          decode_exec_rs1,
    input  logic [4:0]                          decode_exec_rs2,
    input  logic [4:0]                          decode_exec_rs3,
    input  logic [4:0]                          decode_exec_rd,
    input  logic [31:0]                         decode_exec_imm,
    input  logic                                decode_exec_is_alu,
    input  logic                                decode_exec_is_fpu,
    input  logic                                decode_exec_is_tensor,
    input  logic                                decode_exec_is_branch,
    input  logic                                decode_exec_is_jump,
    input  logic                                decode_exec_is_load,
    input  logic                                decode_exec_is_store,
    input  logic                                decode_exec_is_barrier,
    input  logic [3:0]                          decode_exec_alu_op,
    input  logic [2:0]                          decode_exec_fpu_op,
    input  logic [2:0]                          decode_exec_tensor_op,
    input  logic [2:0]                          decode_exec_branch_op,
    input  logic                                decode_exec_reg_write,
    input  logic                                decode_exec_use_imm,
    input  logic                                decode_exec_is_32bit,
    output logic                                decode_exec_ready,
    
    // 寄存器文件读接口
    output logic                                reg_read_enable[3],
    output logic [$clog2(WARP_COUNT)-1:0]      reg_read_warp_id[3],
    output logic [4:0]                          reg_read_addr[3],
    input  logic [31:0]                         reg_read_data[3][THREAD_COUNT],
    
    // 到访存阶段的输出
    output logic                                exec_mem_valid,
    output logic [31:0]                         exec_mem_inst,
    output logic [63:0]                         exec_mem_pc,
    output logic [$clog2(WARP_COUNT)-1:0]      exec_mem_warp_id,
    output logic [THREAD_COUNT-1:0]             exec_mem_active_mask,
    output logic [4:0]                          exec_mem_rd,
    output logic [31:0]                         exec_mem_result[THREAD_COUNT],
    output logic                                exec_mem_is_load,
    output logic                                exec_mem_is_store,
    output logic                                exec_mem_is_branch,
    output logic                                exec_mem_reg_write,
    output logic [31:0]                         exec_mem_branch_target,
    output logic [THREAD_COUNT-1:0]             exec_mem_branch_mask,
    input  logic                                exec_mem_ready,
    
    // 流水线控制
    input  logic                                pipeline_stall,
    input  logic                                pipeline_flush
);

    // 寄存器操作数
    logic [31:0] src1_data[THREAD_COUNT];
    logic [31:0] src2_data[THREAD_COUNT];
    logic [31:0] src3_data[THREAD_COUNT];
    
    // CUDA核心接口
    logic        cuda_inst_valid;
    logic        cuda_result_valid;
    logic [31:0] cuda_result_data[THREAD_COUNT];
    logic [4:0]  cuda_result_rd;
    logic [31:0] cuda_result_pc;
    logic [31:0] cuda_result_warp_id;
    logic [31:0] cuda_result_active_mask;
    logic        cuda_result_is_branch;
    logic [31:0] cuda_result_branch_target;
    logic [31:0] cuda_result_branch_mask;
    logic        cuda_ready;
    
    // Tensor核心接口
    logic        tensor_inst_valid;
    logic        tensor_result_valid;
    logic [31:0] tensor_result_data[THREAD_COUNT][4][4]; // 4x4矩阵
    logic [4:0]  tensor_result_rd;
    logic [31:0] tensor_result_pc;
    logic [31:0] tensor_result_warp_id;
    logic [31:0] tensor_result_active_mask;
    logic        tensor_ready;
    
    // 矩阵数据重组 (简化处理，实际需要更复杂的矩阵管理)
    logic [15:0] matrix_a[THREAD_COUNT][4][4];
    logic [15:0] matrix_b[THREAD_COUNT][4][4];
    logic [31:0] matrix_c[THREAD_COUNT][4][4];
    logic [31:0] tensor_flattened_result[THREAD_COUNT];
    
    // 执行结果选择
    logic [31:0] final_result[THREAD_COUNT];
    logic        final_is_branch;
    logic [31:0] final_branch_target;
    logic [31:0] final_branch_mask;
    
    // 流水线寄存器
    logic                               em_valid_reg;
    logic [31:0]                        em_inst_reg;
    logic [63:0]                        em_pc_reg;
    logic [$clog2(WARP_COUNT)-1:0]     em_warp_id_reg;
    logic [THREAD_COUNT-1:0]            em_active_mask_reg;
    logic [4:0]                         em_rd_reg;
    logic [31:0]                        em_result_reg[THREAD_COUNT];
    logic                               em_is_load_reg, em_is_store_reg, em_is_branch_reg;
    logic                               em_reg_write_reg;
    logic [31:0]                        em_branch_target_reg;
    logic [THREAD_COUNT-1:0]            em_branch_mask_reg;
    
    // 寄存器读取控制
    always_comb begin
        // 读取rs1
        reg_read_enable[0] = decode_exec_valid;
        reg_read_warp_id[0] = decode_exec_warp_id;
        reg_read_addr[0] = decode_exec_rs1;
        
        // 读取rs2 (如果不使用立即数)
        reg_read_enable[1] = decode_exec_valid && !decode_exec_use_imm;
        reg_read_warp_id[1] = decode_exec_warp_id;
        reg_read_addr[1] = decode_exec_rs2;
        
        // 读取rs3 (用于Tensor指令)
        reg_read_enable[2] = decode_exec_valid && decode_exec_is_tensor;
        reg_read_warp_id[2] = decode_exec_warp_id;
        reg_read_addr[2] = decode_exec_rs3;
    end
    
    // 操作数准备
    always_comb begin
        // src1始终来自rs1
        for (int t = 0; t < THREAD_COUNT; t++) begin
            src1_data[t] = reg_read_data[0][t];
        end
        
        // src2来自rs2或立即数
        for (int t = 0; t < THREAD_COUNT; t++) begin
            if (decode_exec_use_imm) begin
                src2_data[t] = decode_exec_imm;
            end else begin
                src2_data[t] = reg_read_data[1][t];
            end
        end
        
        // src3来自rs3 (仅用于Tensor指令)
        for (int t = 0; t < THREAD_COUNT; t++) begin
            src3_data[t] = reg_read_data[2][t];
        end
    end
    
    // 矩阵数据准备 (简化实现)
    always_comb begin
        for (int t = 0; t < THREAD_COUNT; t++) begin
            // 简化：将32位数据拆分为16位矩阵元素
            for (int i = 0; i < 4; i++) begin
                for (int j = 0; j < 4; j++) begin
                    matrix_a[t][i][j] = src1_data[t][15:0];
                    matrix_b[t][i][j] = src2_data[t][15:0];
                    matrix_c[t][i][j] = src3_data[t];
                end
            end
        end
    end
    
    // Tensor结果展平 (简化实现)
    always_comb begin
        for (int t = 0; t < THREAD_COUNT; t++) begin
            // 简化：只取矩阵的第一个元素作为结果
            tensor_flattened_result[t] = tensor_result_data[t][0][0];
        end
    end
    
    // CUDA核心实例化
    rvgpu_sm_cuda_core #(
        .THREAD_COUNT(THREAD_COUNT),
        .SIMD_WIDTH(8)
    ) u_cuda_core (
        .clk(clk),
        .rst_n(rst_n),
        .inst_valid(cuda_inst_valid),
        .inst(decode_exec_inst),
        .pc(decode_exec_pc),
        .warp_id(decode_exec_warp_id),
        .active_mask(decode_exec_active_mask),
        .src1_data(src1_data),
        .src2_data(src2_data),
        .src3_data(src3_data),
        .imm_data(decode_exec_imm),
        .result_valid(cuda_result_valid),
        .result_data(cuda_result_data),
        .result_rd(cuda_result_rd),
        .result_pc(cuda_result_pc),
        .result_warp_id(cuda_result_warp_id),
        .result_active_mask(cuda_result_active_mask),
        .result_is_branch(cuda_result_is_branch),
        .result_branch_target(cuda_result_branch_target),
        .result_branch_mask(cuda_result_branch_mask),
        .stall(pipeline_stall),
        .ready(cuda_ready)
    );
    
    // Tensor核心实例化
    rvgpu_sm_tensor_core #(
        .THREAD_COUNT(THREAD_COUNT),
        .MATRIX_SIZE(4)
    ) u_tensor_core (
        .clk(clk),
        .rst_n(rst_n),
        .inst_valid(tensor_inst_valid),
        .inst(decode_exec_inst),
        .pc(decode_exec_pc),
        .warp_id(decode_exec_warp_id),
        .active_mask(decode_exec_active_mask),
        .matrix_a(matrix_a),
        .matrix_b(matrix_b),
        .matrix_c(matrix_c),
        .result_valid(tensor_result_valid),
        .result_data(tensor_result_data),
        .result_rd(tensor_result_rd),
        .result_pc(tensor_result_pc),
        .result_warp_id(tensor_result_warp_id),
        .result_active_mask(tensor_result_active_mask),
        .stall(pipeline_stall),
        .ready(tensor_ready)
    );
    
    // 执行单元选择和控制
    always_comb begin
        cuda_inst_valid = decode_exec_valid && 
                          (decode_exec_is_alu || decode_exec_is_fpu || 
                           decode_exec_is_branch || decode_exec_is_jump);
        
        tensor_inst_valid = decode_exec_valid && decode_exec_is_tensor;
    end
    
    // 结果选择
    always_comb begin
        final_is_branch = 1'b0;
        final_branch_target = '0;
        final_branch_mask = '0;
        
        if (tensor_result_valid) begin
            // Tensor核心结果
            for (int t = 0; t < THREAD_COUNT; t++) begin
                final_result[t] = tensor_flattened_result[t];
            end
        end else if (cuda_result_valid) begin
            // CUDA核心结果
            for (int t = 0; t < THREAD_COUNT; t++) begin
                final_result[t] = cuda_result_data[t];
            end
            final_is_branch = cuda_result_is_branch;
            final_branch_target = cuda_result_branch_target;
            final_branch_mask = cuda_result_branch_mask;
        end else begin
            // 默认结果
            for (int t = 0; t < THREAD_COUNT; t++) begin
                final_result[t] = '0;
            end
        end
    end
    
    // 流水线寄存器更新
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            em_valid_reg <= 1'b0;
            em_inst_reg <= '0;
            em_pc_reg <= '0;
            em_warp_id_reg <= '0;
            em_active_mask_reg <= '0;
            em_rd_reg <= '0;
            em_is_load_reg <= 1'b0;
            em_is_store_reg <= 1'b0;
            em_is_branch_reg <= 1'b0;
            em_reg_write_reg <= 1'b0;
            em_branch_target_reg <= '0;
            em_branch_mask_reg <= '0;
            
            for (int t = 0; t < THREAD_COUNT; t++) begin
                em_result_reg[t] <= '0;
            end
        end else if (pipeline_flush) begin
            em_valid_reg <= 1'b0;
        end else if (!pipeline_stall) begin
            if ((cuda_result_valid || tensor_result_valid || 
                 decode_exec_is_load || decode_exec_is_store || 
                 decode_exec_is_barrier) && exec_mem_ready) begin
                em_valid_reg <= 1'b1;
                em_inst_reg <= decode_exec_inst;
                em_pc_reg <= decode_exec_pc;
                em_warp_id_reg <= decode_exec_warp_id;
                em_active_mask_reg <= decode_exec_active_mask;
                em_rd_reg <= decode_exec_rd;
                em_is_load_reg <= decode_exec_is_load;
                em_is_store_reg <= decode_exec_is_store;
                em_is_branch_reg <= final_is_branch;
                em_reg_write_reg <= decode_exec_reg_write;
                em_branch_target_reg <= final_branch_target;
                em_branch_mask_reg <= final_branch_mask;
                
                for (int t = 0; t < THREAD_COUNT; t++) begin
                    em_result_reg[t] <= final_result[t];
                end
            end else if (exec_mem_ready) begin
                em_valid_reg <= 1'b0;
            end
        end
    end
    
    // 输出信号
    assign exec_mem_valid = em_valid_reg;
    assign exec_mem_inst = em_inst_reg;
    assign exec_mem_pc = em_pc_reg;
    assign exec_mem_warp_id = em_warp_id_reg;
    assign exec_mem_active_mask = em_active_mask_reg;
    assign exec_mem_rd = em_rd_reg;
    assign exec_mem_result = em_result_reg;
    assign exec_mem_is_load = em_is_load_reg;
    assign exec_mem_is_store = em_is_store_reg;
    assign exec_mem_is_branch = em_is_branch_reg;
    assign exec_mem_reg_write = em_reg_write_reg;
    assign exec_mem_branch_target = em_branch_target_reg;
    assign exec_mem_branch_mask = em_branch_mask_reg;
    
    // 准备信号
    assign decode_exec_ready = exec_mem_ready || !em_valid_reg;

endmodule : rvgpu_sm_execute_stage

`endif // RVGPU_SM_EXECUTE_STAGE_SV 