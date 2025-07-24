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

`ifndef RVGPU_SM_CUDA_CORE_UNIT_SV
`define RVGPU_SM_CUDA_CORE_UNIT_SV

`include "rvgpu_typedef.svh"

// SM CUDA Core单元
// 作为SM的子处理单元，执行单个warp的指令
// 不包含warp调度，由SM级调度器统一调度
module rvgpu_sm_cuda_core_unit #(
    parameter int CORE_ID = 0,          // CUDA Core ID
    parameter int WARP_COUNT = 32,      // 支持的warp数量  
    parameter int THREAD_COUNT = 32     // 每个warp的线程数
) (
    input  logic clk,
    input  logic rst_n,
    
    // 来自SM Warp Scheduler的warp分发
    input  logic                                warp_dispatch_valid,
    input  logic [31:0]                         warp_dispatch_inst,
    input  logic [63:0]                         warp_dispatch_pc,
    input  logic [$clog2(WARP_COUNT)-1:0]      warp_dispatch_warp_id,
    input  logic [THREAD_COUNT-1:0]             warp_dispatch_active_mask,
    input  logic [4:0]                          warp_dispatch_rs1,
    input  logic [4:0]                          warp_dispatch_rs2,
    input  logic [4:0]                          warp_dispatch_rs3,
    input  logic [4:0]                          warp_dispatch_rd,
    input  logic [31:0]                         warp_dispatch_imm,
    input  logic                                warp_dispatch_is_alu,
    input  logic                                warp_dispatch_is_fpu,
    input  logic                                warp_dispatch_is_tensor,
    input  logic                                warp_dispatch_is_branch,
    input  logic                                warp_dispatch_is_jump,
    input  logic                                warp_dispatch_is_load,
    input  logic                                warp_dispatch_is_store,
    input  logic                                warp_dispatch_is_barrier,
    input  logic [3:0]                          warp_dispatch_alu_op,
    input  logic [2:0]                          warp_dispatch_fpu_op,
    input  logic [2:0]                          warp_dispatch_tensor_op,
    input  logic [2:0]                          warp_dispatch_branch_op,
    input  logic                                warp_dispatch_reg_write,
    input  logic                                warp_dispatch_use_imm,
    input  logic                                warp_dispatch_is_32bit,
    output logic                                warp_dispatch_ready,
    
    // 寄存器文件读接口
    output logic                                reg_read_enable[3],
    output logic [$clog2(WARP_COUNT)-1:0]      reg_read_warp_id[3],
    output logic [4:0]                          reg_read_addr[3],
    input  logic [31:0]                         reg_read_data[3][THREAD_COUNT],
    
    // 寄存器文件写接口
    output logic                                reg_write_enable,
    output logic [$clog2(WARP_COUNT)-1:0]      reg_write_warp_id,
    output logic [4:0]                          reg_write_addr,
    output logic [31:0]                         reg_write_data[THREAD_COUNT],
    output logic [THREAD_COUNT-1:0]             reg_write_mask,
    
    // LDST单元接口
    output logic                                ldst_req_valid,
    output logic [$clog2(WARP_COUNT)-1:0]      ldst_req_warp_id,
    output logic [THREAD_COUNT-1:0]             ldst_req_mask,
    output logic [63:0]                         ldst_req_addr[THREAD_COUNT],
    output logic [31:0]                         ldst_req_data[THREAD_COUNT],
    output logic [2:0]                          ldst_req_size,
    output logic                                ldst_req_is_write,
    input  logic                                ldst_req_ready,
    
    input  logic                                ldst_resp_valid,
    input  logic [$clog2(WARP_COUNT)-1:0]      ldst_resp_warp_id,
    input  logic [THREAD_COUNT-1:0]             ldst_resp_mask,
    input  logic [31:0]                         ldst_resp_data[THREAD_COUNT],
    output logic                                ldst_resp_ready,
    
    // 完成信号
    output logic                                warp_complete,
    output logic [$clog2(WARP_COUNT)-1:0]      warp_complete_id,
    
    // 分支反馈
    output logic                                branch_feedback_valid,
    output logic [63:0]                         branch_feedback_pc,
    output logic                                branch_feedback_taken,
    output logic [63:0]                         branch_feedback_target,
    
    // 流水线控制
    input  logic                                pipeline_stall,
    input  logic                                pipeline_flush
);

    // 内部执行流水线阶段
    typedef enum logic [2:0] {
        IDLE,
        EXECUTE,
        MEMORY,
        WRITEBACK,
        COMPLETE
    } exec_state_t;
    
    exec_state_t state;
    
    // 当前执行的warp信息
    logic [31:0]                         current_inst;
    logic [63:0]                         current_pc;
    logic [$clog2(WARP_COUNT)-1:0]      current_warp_id;
    logic [THREAD_COUNT-1:0]             current_active_mask;
    logic [4:0]                          current_rs1, current_rs2, current_rs3, current_rd;
    logic [31:0]                         current_imm;
    logic                                current_is_alu, current_is_fpu, current_is_tensor;
    logic                                current_is_branch, current_is_jump;
    logic                                current_is_load, current_is_store, current_is_barrier;
    logic [3:0]                          current_alu_op;
    logic [2:0]                          current_fpu_op, current_tensor_op, current_branch_op;
    logic                                current_reg_write, current_use_imm, current_is_32bit;
    
    // 执行结果
    logic [31:0]                         exec_result[THREAD_COUNT];
    logic                                exec_is_branch;
    logic [31:0]                         exec_branch_target;
    logic [THREAD_COUNT-1:0]             exec_branch_mask;
    
    // 寄存器操作数
    logic [31:0] src1_data[THREAD_COUNT];
    logic [31:0] src2_data[THREAD_COUNT];
    logic [31:0] src3_data[THREAD_COUNT];
    
    // CUDA核心和Tensor核心接口
    logic        cuda_inst_valid;
    logic        cuda_result_valid;
    logic [31:0] cuda_result_data[THREAD_COUNT];
    logic        cuda_result_is_branch;
    logic [31:0] cuda_result_branch_target;
    logic [31:0] cuda_result_branch_mask;
    logic        cuda_ready;
    
    logic        tensor_inst_valid;
    logic        tensor_result_valid;
    logic [31:0] tensor_result_data[THREAD_COUNT][4][4];
    logic [31:0] tensor_flattened_result[THREAD_COUNT];
    logic        tensor_ready;
    
    // 矩阵数据准备 (简化)
    logic [15:0] matrix_a[THREAD_COUNT][4][4];
    logic [15:0] matrix_b[THREAD_COUNT][4][4];
    logic [31:0] matrix_c[THREAD_COUNT][4][4];
    
    // 寄存器读取控制
    always_comb begin
        // 读取rs1
        reg_read_enable[0] = (state == EXECUTE);
        reg_read_warp_id[0] = current_warp_id;
        reg_read_addr[0] = current_rs1;
        
        // 读取rs2 (如果不使用立即数)
        reg_read_enable[1] = (state == EXECUTE) && !current_use_imm;
        reg_read_warp_id[1] = current_warp_id;
        reg_read_addr[1] = current_rs2;
        
        // 读取rs3 (用于Tensor指令)
        reg_read_enable[2] = (state == EXECUTE) && current_is_tensor;
        reg_read_warp_id[2] = current_warp_id;
        reg_read_addr[2] = current_rs3;
    end
    
    // 操作数准备
    always_comb begin
        for (int t = 0; t < THREAD_COUNT; t++) begin
            src1_data[t] = reg_read_data[0][t];
            
            if (current_use_imm) begin
                src2_data[t] = current_imm;
            end else begin
                src2_data[t] = reg_read_data[1][t];
            end
            
            src3_data[t] = reg_read_data[2][t];
        end
    end
    
    // 矩阵数据准备 (简化)
    always_comb begin
        for (int t = 0; t < THREAD_COUNT; t++) begin
            for (int i = 0; i < 4; i++) begin
                for (int j = 0; j < 4; j++) begin
                    matrix_a[t][i][j] = src1_data[t][15:0];
                    matrix_b[t][i][j] = src2_data[t][15:0];
                    matrix_c[t][i][j] = src3_data[t];
                end
            end
        end
    end
    
    // Tensor结果展平
    always_comb begin
        for (int t = 0; t < THREAD_COUNT; t++) begin
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
        .inst(current_inst),
        .pc(current_pc),
        .warp_id(current_warp_id),
        .active_mask(current_active_mask),
        .src1_data(src1_data),
        .src2_data(src2_data),
        .src3_data(src3_data),
        .imm_data(current_imm),
        .result_valid(cuda_result_valid),
        .result_data(cuda_result_data),
        .result_rd(),
        .result_pc(),
        .result_warp_id(),
        .result_active_mask(),
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
        .inst(current_inst),
        .pc(current_pc),
        .warp_id(current_warp_id),
        .active_mask(current_active_mask),
        .matrix_a(matrix_a),
        .matrix_b(matrix_b),
        .matrix_c(matrix_c),
        .result_valid(tensor_result_valid),
        .result_data(tensor_result_data),
        .result_rd(),
        .result_pc(),
        .result_warp_id(),
        .result_active_mask(),
        .stall(pipeline_stall),
        .ready(tensor_ready)
    );
    
    // 执行单元选择
    always_comb begin
        cuda_inst_valid = (state == EXECUTE) && 
                          (current_is_alu || current_is_fpu || 
                           current_is_branch || current_is_jump);
        
        tensor_inst_valid = (state == EXECUTE) && current_is_tensor;
    end
    
    // 主状态机
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            current_inst <= '0;
            current_pc <= '0;
            current_warp_id <= '0;
            current_active_mask <= '0;
            current_rs1 <= '0;
            current_rs2 <= '0;
            current_rs3 <= '0;
            current_rd <= '0;
            current_imm <= '0;
            current_is_alu <= 1'b0;
            current_is_fpu <= 1'b0;
            current_is_tensor <= 1'b0;
            current_is_branch <= 1'b0;
            current_is_jump <= 1'b0;
            current_is_load <= 1'b0;
            current_is_store <= 1'b0;
            current_is_barrier <= 1'b0;
            current_alu_op <= '0;
            current_fpu_op <= '0;
            current_tensor_op <= '0;
            current_branch_op <= '0;
            current_reg_write <= 1'b0;
            current_use_imm <= 1'b0;
            current_is_32bit <= 1'b0;
            
            for (int t = 0; t < THREAD_COUNT; t++) begin
                exec_result[t] <= '0;
            end
            exec_is_branch <= 1'b0;
            exec_branch_target <= '0;
            exec_branch_mask <= '0;
        end else if (pipeline_flush) begin
            state <= IDLE;
        end else if (!pipeline_stall) begin
            case (state)
                IDLE: begin
                    if (warp_dispatch_valid) begin
                        // 接收新的warp指令
                        current_inst <= warp_dispatch_inst;
                        current_pc <= warp_dispatch_pc;
                        current_warp_id <= warp_dispatch_warp_id;
                        current_active_mask <= warp_dispatch_active_mask;
                        current_rs1 <= warp_dispatch_rs1;
                        current_rs2 <= warp_dispatch_rs2;
                        current_rs3 <= warp_dispatch_rs3;
                        current_rd <= warp_dispatch_rd;
                        current_imm <= warp_dispatch_imm;
                        current_is_alu <= warp_dispatch_is_alu;
                        current_is_fpu <= warp_dispatch_is_fpu;
                        current_is_tensor <= warp_dispatch_is_tensor;
                        current_is_branch <= warp_dispatch_is_branch;
                        current_is_jump <= warp_dispatch_is_jump;
                        current_is_load <= warp_dispatch_is_load;
                        current_is_store <= warp_dispatch_is_store;
                        current_is_barrier <= warp_dispatch_is_barrier;
                        current_alu_op <= warp_dispatch_alu_op;
                        current_fpu_op <= warp_dispatch_fpu_op;
                        current_tensor_op <= warp_dispatch_tensor_op;
                        current_branch_op <= warp_dispatch_branch_op;
                        current_reg_write <= warp_dispatch_reg_write;
                        current_use_imm <= warp_dispatch_use_imm;
                        current_is_32bit <= warp_dispatch_is_32bit;
                        
                        state <= EXECUTE;
                    end
                end
                
                EXECUTE: begin
                    // 等待执行单元完成
                    if (cuda_result_valid || tensor_result_valid || 
                        current_is_load || current_is_store || current_is_barrier) begin
                        
                        // 保存执行结果
                        if (tensor_result_valid) begin
                            for (int t = 0; t < THREAD_COUNT; t++) begin
                                exec_result[t] <= tensor_flattened_result[t];
                            end
                        end else if (cuda_result_valid) begin
                            for (int t = 0; t < THREAD_COUNT; t++) begin
                                exec_result[t] <= cuda_result_data[t];
                            end
                            exec_is_branch <= cuda_result_is_branch;
                            exec_branch_target <= cuda_result_branch_target;
                            exec_branch_mask <= cuda_result_branch_mask;
                        end
                        
                        if (current_is_load || current_is_store) begin
                            state <= MEMORY;
                        end else begin
                            state <= WRITEBACK;
                        end
                    end
                end
                
                MEMORY: begin
                    // 处理内存访问
                    if (current_is_load) begin
                        // 等待LDST响应
                        if (ldst_resp_valid && ldst_resp_warp_id == current_warp_id) begin
                            for (int t = 0; t < THREAD_COUNT; t++) begin
                                if (ldst_resp_mask[t]) begin
                                    exec_result[t] <= ldst_resp_data[t];
                                end
                            end
                            state <= WRITEBACK;
                        end
                    end else begin
                        // Store指令，等待LDST接受
                        if (ldst_req_ready) begin
                            state <= WRITEBACK;
                        end
                    end
                end
                
                WRITEBACK: begin
                    // 写回寄存器
                    state <= COMPLETE;
                end
                
                COMPLETE: begin
                    // 完成当前warp指令
                    state <= IDLE;
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
    
    // 输出信号赋值
    assign warp_dispatch_ready = (state == IDLE);
    
    // 寄存器写回
    assign reg_write_enable = (state == WRITEBACK) && current_reg_write;
    assign reg_write_warp_id = current_warp_id;
    assign reg_write_addr = current_rd;
    assign reg_write_data = exec_result;
    assign reg_write_mask = current_active_mask;
    
    // LDST请求
    assign ldst_req_valid = (state == MEMORY) && (current_is_load || current_is_store);
    assign ldst_req_warp_id = current_warp_id;
    assign ldst_req_mask = current_active_mask;
    // 简化地址计算
    always_comb begin
        for (int t = 0; t < THREAD_COUNT; t++) begin
            ldst_req_addr[t] = exec_result[t]; // 执行阶段已计算地址
            ldst_req_data[t] = src2_data[t];   // Store数据
        end
    end
    assign ldst_req_size = 3'b010; // 32位
    assign ldst_req_is_write = current_is_store;
    assign ldst_resp_ready = (state == MEMORY);
    
    // 完成信号
    assign warp_complete = (state == COMPLETE);
    assign warp_complete_id = current_warp_id;
    
    // 分支反馈
    assign branch_feedback_valid = (state == COMPLETE) && exec_is_branch;
    assign branch_feedback_pc = current_pc;
    assign branch_feedback_taken = |exec_branch_mask;
    assign branch_feedback_target = exec_branch_target;

endmodule : rvgpu_sm_cuda_core_unit

`endif // RVGPU_SM_CUDA_CORE_UNIT_SV 