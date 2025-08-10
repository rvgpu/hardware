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
`include "interface_sm_decode_exec.svh"
`include "interface_sm_exec_mem.svh"
`include "interface_sm_core_exec.svh"
`include "interface_sm_cuda_core.svh"
`include "interface_sm_tensor_exec.svh"
`include "interface_sm_regfile_access.svh"

// SM执行阶段
// 集成CUDA核心和Tensor核心，处理寄存器读取和执行单元调度
module rvgpu_sm_execute_stage #(
    parameter int WARP_COUNT = 32,      // 支持的warp数量
    parameter int THREAD_COUNT = 32     // 每个warp的线程数
) (
    input  logic clk,
    input  logic rst_n,
    
    // 从解码阶段的输入（接口）
    interface_sm_decode_exec.exec_sink          de_if,
    
    // 寄存器文件读接口（接口化）
    interface_sm_regfile_access.core            rf_if,
    
    // 到访存阶段的输出（接口）
    interface_sm_exec_mem.exec_source           em_if,
    
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
    interface_sm_core_exec   #(.THREAD_COUNT(THREAD_COUNT)) core_exec_if();
    interface_sm_cuda_core   #(.THREAD_COUNT(THREAD_COUNT)) cuda_core_if();
    
    // Tensor核心接口
    logic        tensor_inst_valid;
    interface_sm_tensor_exec #(.THREAD_COUNT(THREAD_COUNT), .MATRIX_SIZE(4)) tensor_exec_if();
    
    // 矩阵数据重组 (简化处理，实际需要更复杂的矩阵管理)
    logic [15:0] matrix_a[THREAD_COUNT][4][4];
    logic [15:0] matrix_b[THREAD_COUNT][4][4];
    logic [31:0] matrix_c[THREAD_COUNT][4][4];
    logic [31:0] tensor_result_data[THREAD_COUNT][4][4];
    logic [31:0] tensor_flattened_result[THREAD_COUNT];
    
    // 执行结果选择
    logic [31:0] final_result[THREAD_COUNT];
    logic        final_is_branch;
    logic [31:0] final_branch_target;
    logic [31:0] final_branch_mask;
    
    // 当前指令上下文（用于传递给tensor core）
    logic [4:0]  current_rd;
    logic [31:0] current_pc;
    logic [$clog2(WARP_COUNT)-1:0] current_warp_id;
    logic [THREAD_COUNT-1:0] current_active_mask;
    
    // Tensor core输出结果信号
    logic [4:0]  tensor_result_rd;
    logic [31:0] tensor_result_pc;
    logic [31:0] tensor_result_warp_id;
    logic [31:0] tensor_result_active_mask;
    
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
        rf_if.read_enable[0]  = de_if.valid;
        rf_if.read_warp_id[0] = de_if.warp_id;
        rf_if.read_reg_addr[0]= de_if.rs1;
        
        // 读取rs2 (如果不使用立即数)
        rf_if.read_enable[1]  = de_if.valid && !de_if.use_imm;
        rf_if.read_warp_id[1] = de_if.warp_id;
        rf_if.read_reg_addr[1]= de_if.rs2;
        
        // 读取rs3 (用于Tensor指令)
        rf_if.read_enable[2]  = de_if.valid && de_if.is_tensor;
        rf_if.read_warp_id[2] = de_if.warp_id;
        rf_if.read_reg_addr[2]= de_if.rs3;
    end
    
    // 操作数准备
    always_comb begin
        // src1始终来自rs1
        for (int t = 0; t < THREAD_COUNT; t++) begin
            src1_data[t] = rf_if.read_data[0][t];
        end
        
        // src2来自rs2或立即数
        for (int t = 0; t < THREAD_COUNT; t++) begin
            if (de_if.use_imm) begin
                src2_data[t] = de_if.imm;
            end else begin
                src2_data[t] = rf_if.read_data[1][t];
            end
        end
        
        // src3来自rs3 (仅用于Tensor指令)
        for (int t = 0; t < THREAD_COUNT; t++) begin
            src3_data[t] = rf_if.read_data[2][t];
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
    
    // 准备CUDA执行接口输入
    assign core_exec_if.inst_valid  = cuda_inst_valid;
    assign core_exec_if.inst        = de_if.inst;
    assign core_exec_if.pc          = de_if.pc[31:0];
    assign core_exec_if.warp_id     = {27'b0, de_if.warp_id};
    assign core_exec_if.active_mask = de_if.active_mask;
    assign core_exec_if.src1_data   = src1_data;
    assign core_exec_if.src2_data   = src2_data;
    assign core_exec_if.src3_data   = src3_data;
    assign core_exec_if.imm_data    = de_if.imm;
    assign core_exec_if.stall       = pipeline_stall;
    
    // 更新当前指令上下文
    assign current_rd = de_if.rd;
    assign current_pc = de_if.pc[31:0];
    assign current_warp_id = de_if.warp_id;
    assign current_active_mask = de_if.active_mask;
    
    // 连接CUDA核心接口
    assign cuda_core_if.clk = clk;
    assign cuda_core_if.rst_n = rst_n;
    assign cuda_core_if.inst_valid = core_exec_if.inst_valid;
    assign cuda_core_if.inst = core_exec_if.inst;
    assign cuda_core_if.pc = core_exec_if.pc;
    assign cuda_core_if.warp_id = core_exec_if.warp_id;
    assign cuda_core_if.active_mask = core_exec_if.active_mask;
    assign cuda_core_if.src1_data = core_exec_if.src1_data;
    assign cuda_core_if.src2_data = core_exec_if.src2_data;
    assign cuda_core_if.src3_data = core_exec_if.src3_data;
    assign cuda_core_if.imm_data = core_exec_if.imm_data;
    assign cuda_core_if.stall = core_exec_if.stall;
    assign core_exec_if.ready = cuda_core_if.ready;
    assign core_exec_if.result_valid = cuda_core_if.result_valid;
    assign core_exec_if.result_data = cuda_core_if.result_data;
    assign core_exec_if.result_is_branch = cuda_core_if.result_is_branch;
    assign core_exec_if.result_branch_target = cuda_core_if.result_branch_target;
    assign core_exec_if.result_branch_mask = cuda_core_if.result_branch_mask;

    // CUDA核心实例化（接口化）
    rvgpu_sm_cuda_core #(
        .THREAD_COUNT(THREAD_COUNT),
        .SIMD_WIDTH(8)
    ) u_cuda_core (
        .cuda_if(cuda_core_if)
    );
    
    // 准备Tensor执行接口输入
    assign tensor_exec_if.inst_valid  = tensor_inst_valid;
    assign tensor_exec_if.inst        = de_if.inst;
    assign tensor_exec_if.pc          = de_if.pc[31:0];
    assign tensor_exec_if.warp_id     = {27'b0, de_if.warp_id};
    assign tensor_exec_if.active_mask = de_if.active_mask;
    assign tensor_exec_if.matrix_a    = matrix_a;
    assign tensor_exec_if.matrix_b    = matrix_b;
    assign tensor_exec_if.matrix_c    = matrix_c;
    assign tensor_exec_if.stall       = pipeline_stall;

    // Tensor核心实例化
    rvgpu_sm_tensor_core #(
        .THREAD_COUNT(THREAD_COUNT),
        .MATRIX_SIZE(4)
    ) u_tensor_core (
        .clk(clk),
        .rst_n(rst_n),
        .inst_valid(tensor_exec_if.inst_valid),
        .inst(tensor_exec_if.inst),
        .pc(tensor_exec_if.pc),
        .warp_id(tensor_exec_if.warp_id),
        .active_mask(tensor_exec_if.active_mask),
        .matrix_a(matrix_a),
        .matrix_b(matrix_b),
        .matrix_c(matrix_c),
        .stall(tensor_exec_if.stall),
        .ready(tensor_exec_if.ready),
        .result_valid(tensor_exec_if.result_valid),
        .result_data(tensor_result_data),
        .result_rd(tensor_result_rd),
        .result_pc(tensor_result_pc),
        .result_warp_id(tensor_result_warp_id),
        .result_active_mask(tensor_result_active_mask)
    );
    
    // 执行单元选择和控制
    always_comb begin
        cuda_inst_valid = de_if.valid && 
                          (de_if.is_alu || de_if.is_fpu || 
                           de_if.is_branch || de_if.is_jump);
        
        tensor_inst_valid = de_if.valid && de_if.is_tensor;
    end
    
    // 结果选择
    always_comb begin
        final_is_branch = 1'b0;
        final_branch_target = '0;
        final_branch_mask = '0;
        
        if (tensor_exec_if.result_valid) begin
            // Tensor核心结果
            for (int t = 0; t < THREAD_COUNT; t++) begin
                final_result[t] = tensor_flattened_result[t];
            end
        end else if (core_exec_if.result_valid) begin
            // CUDA核心结果
            for (int t = 0; t < THREAD_COUNT; t++) begin
                final_result[t] = core_exec_if.result_data[t];
            end
            final_is_branch = core_exec_if.result_is_branch;
            final_branch_target = core_exec_if.result_branch_target;
            final_branch_mask = core_exec_if.result_branch_mask;
        end else begin
            // 默认结果
            for (int t = 0; t < THREAD_COUNT; t++) begin
                final_result[t] = '0;
            end
        end
    end
    
    // 流水线寄存器更新
    always_ff @(posedge clk) begin
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
            if ((core_exec_if.result_valid || tensor_exec_if.result_valid || 
                 de_if.is_load || de_if.is_store || 
                 de_if.is_barrier) && em_if.ready) begin
                em_valid_reg <= 1'b1;
                em_inst_reg <= de_if.inst;
                em_pc_reg <= de_if.pc;
                em_warp_id_reg <= de_if.warp_id;
                em_active_mask_reg <= de_if.active_mask;
                em_rd_reg <= de_if.rd;
                em_is_load_reg <= de_if.is_load;
                em_is_store_reg <= de_if.is_store;
                em_is_branch_reg <= final_is_branch;
                em_reg_write_reg <= de_if.reg_write;
                em_branch_target_reg <= final_branch_target;
                em_branch_mask_reg <= final_branch_mask;
                
                for (int t = 0; t < THREAD_COUNT; t++) begin
                    em_result_reg[t] <= final_result[t];
                end
            end else if (em_if.ready) begin
                em_valid_reg <= 1'b0;
            end
        end
    end
    
    // 输出信号
    assign em_if.valid          = em_valid_reg;
    assign em_if.inst           = em_inst_reg;
    assign em_if.pc             = em_pc_reg;
    assign em_if.warp_id        = em_warp_id_reg;
    assign em_if.active_mask    = em_active_mask_reg;
    assign em_if.rd             = em_rd_reg;
    assign em_if.result         = em_result_reg;
    assign em_if.is_load        = em_is_load_reg;
    assign em_if.is_store       = em_is_store_reg;
    assign em_if.is_branch      = em_is_branch_reg;
    assign em_if.reg_write      = em_reg_write_reg;
    assign em_if.branch_target  = em_branch_target_reg;
    assign em_if.branch_mask    = em_branch_mask_reg;
    
    // 准备信号
    assign de_if.ready = em_if.ready || !em_valid_reg;

endmodule : rvgpu_sm_execute_stage

`endif // RVGPU_SM_EXECUTE_STAGE_SV 