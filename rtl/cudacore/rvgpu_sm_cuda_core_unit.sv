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
`include "interface_sm_core_exec.svh"
`include "interface_sm_cuda_core.svh"
`include "interface_sm_tensor_exec.svh"
`include "interface_sm_l1data.svh"
`include "interface_sm_warp_dispatch.svh"
`include "interface_sm_regfile_access.svh"

module rvgpu_sm_cuda_core_unit #(
    parameter int CORE_ID = 0,          // CUDA Core ID
    parameter int WARP_COUNT = 32,      // 支持的warp数量  
    parameter int THREAD_COUNT = 32     // 每个warp的线程数
) (
    input  logic clk,
    input  logic rst_n,
    
    // 来自SM Warp Scheduler的warp分发（接口）
    interface_sm_warp_dispatch.core_sink        disp_if,
    
    // 寄存器文件接口（单Core接口）
    interface_sm_regfile_access.core            rf_if,
    
    // L1 Data Cache接口（接口化）
    interface_sm_l1data.core                    l1_if,
    
    // 完成信号
    output logic                                warp_complete,
    output logic [$clog2(WARP_COUNT)-1:0]       warp_complete_id,
    
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
    interface_sm_cuda_core   #(.THREAD_COUNT(THREAD_COUNT)) cuda_core_if();
    
    logic        tensor_inst_valid;
    interface_sm_tensor_exec #(.THREAD_COUNT(THREAD_COUNT), .MATRIX_SIZE(4)) tensor_exec_if();
    
    // 矩阵数据准备 (简化)
    logic [15:0] matrix_a[THREAD_COUNT][4][4];
    logic [15:0] matrix_b[THREAD_COUNT][4][4];
    logic [31:0] matrix_c[THREAD_COUNT][4][4];
    logic [31:0] tensor_result_data[THREAD_COUNT][4][4];
    logic        tensor_result_valid;
    logic [4:0]  tensor_result_rd;
    logic [31:0] tensor_result_pc;
    logic [31:0] tensor_result_warp_id;
    logic [31:0] tensor_result_active_mask;
    logic        tensor_ready;
    
    // 寄存器读取控制
    always_comb begin
        // 读取rs1
        rf_if.read_enable[0] = (state == EXECUTE);
        rf_if.read_warp_id[0] = current_warp_id;
        rf_if.read_reg_addr[0] = current_rs1;
        
        // 读取rs2 (如果不使用立即数)
        rf_if.read_enable[1] = (state == EXECUTE) && !current_use_imm;
        rf_if.read_warp_id[1] = current_warp_id;
        rf_if.read_reg_addr[1] = current_rs2;
        
        // 读取rs3 (用于Tensor指令)
        rf_if.read_enable[2] = (state == EXECUTE) && current_is_tensor;
        rf_if.read_warp_id[2] = current_warp_id;
        rf_if.read_reg_addr[2] = current_rs3;
    end
    
    // 操作数准备
    always_comb begin
        for (int t = 0; t < THREAD_COUNT; t++) begin
            src1_data[t] = rf_if.read_data[0][t];
            
            if (current_use_imm) begin
                src2_data[t] = current_imm;
            end else begin
                src2_data[t] = rf_if.read_data[1][t];
            end
            
            src3_data[t] = rf_if.read_data[2][t];
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
    logic [31:0] tensor_flattened_result[THREAD_COUNT];
    always_comb begin
        for (int t = 0; t < THREAD_COUNT; t++) begin
            tensor_flattened_result[t] = tensor_result_data[t][0][0];
        end
    end
    
    // CUDA核心实例化
    // 准备CUDA执行接口输入
    assign cuda_core_if.inst_valid  = cuda_inst_valid;
    assign cuda_core_if.inst        = current_inst;
    assign cuda_core_if.pc          = current_pc[31:0];
    assign cuda_core_if.warp_id     = {27'b0, current_warp_id};
    assign cuda_core_if.active_mask = current_active_mask;
    assign cuda_core_if.src1_data   = src1_data;
    assign cuda_core_if.src2_data   = src2_data;
    assign cuda_core_if.src3_data   = src3_data;
    assign cuda_core_if.imm_data    = current_imm;
    assign cuda_core_if.stall       = pipeline_stall;

    rvgpu_sm_cuda_core #(
        .THREAD_COUNT(THREAD_COUNT),
        .SIMD_WIDTH(8)
    ) u_cuda_core (
        .cuda_if(cuda_core_if.core)
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
        .pc(current_pc[31:0]),
        .warp_id({27'b0, current_warp_id}),
        .active_mask(current_active_mask),
        .matrix_a(matrix_a),
        .matrix_b(matrix_b),
        .matrix_c(matrix_c),
        .stall(pipeline_stall),
        .ready(tensor_ready),
        .result_valid(tensor_result_valid),
        .result_data(tensor_result_data),
        .result_rd(tensor_result_rd),
        .result_pc(tensor_result_pc),
        .result_warp_id(tensor_result_warp_id),
        .result_active_mask(tensor_result_active_mask)
    );
    
    // 执行单元选择
    always_comb begin
        cuda_inst_valid = (state == EXECUTE) && 
                          (current_is_alu || current_is_fpu || 
                           current_is_branch || current_is_jump);
        
        tensor_inst_valid = (state == EXECUTE) && current_is_tensor;
    end
    
    // 连接时钟和复位到CUDA核心接口
    assign cuda_core_if.clk = clk;
    assign cuda_core_if.rst_n = rst_n;
    
    // 主状态机
    always_ff @(posedge clk) begin
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
                    if (disp_if.valid) begin
                        // 接收新的warp指令
                        current_inst <= disp_if.inst;
                        current_pc <= disp_if.pc;
                        current_warp_id <= disp_if.warp_id;
                        current_active_mask <= disp_if.active_mask;
                        current_rs1 <= disp_if.rs1;
                        current_rs2 <= disp_if.rs2;
                        current_rs3 <= disp_if.rs3;
                        current_rd <= disp_if.rd;
                        current_imm <= disp_if.imm;
                        current_is_alu <= disp_if.is_alu;
                        current_is_fpu <= disp_if.is_fpu;
                        current_is_tensor <= disp_if.is_tensor;
                        current_is_branch <= disp_if.is_branch;
                        current_is_jump <= disp_if.is_jump;
                        current_is_load <= disp_if.is_load;
                        current_is_store <= disp_if.is_store;
                        current_is_barrier <= disp_if.is_barrier;
                        current_alu_op <= disp_if.alu_op;
                        current_fpu_op <= disp_if.fpu_op;
                        current_tensor_op <= disp_if.tensor_op;
                        current_branch_op <= disp_if.branch_op;
                        current_reg_write <= disp_if.reg_write;
                        current_use_imm <= disp_if.use_imm;
                        current_is_32bit <= disp_if.is_32bit;
                        
                        state <= EXECUTE;
                    end
                end
                
                EXECUTE: begin
                    // 等待执行单元完成
                    if (cuda_core_if.result_valid || tensor_result_valid || 
                        current_is_load || current_is_store || current_is_barrier) begin
                        
                        // 保存执行结果
                        if (tensor_result_valid) begin
                            for (int t = 0; t < THREAD_COUNT; t++) begin
                                exec_result[t] <= tensor_flattened_result[t];
                            end
                        end else if (cuda_core_if.result_valid) begin
                            for (int t = 0; t < THREAD_COUNT; t++) begin
                                exec_result[t] <= cuda_core_if.result_data[t];
                            end
                            exec_is_branch <= cuda_core_if.result_is_branch;
                            exec_branch_target <= cuda_core_if.result_branch_target;
                            exec_branch_mask <= cuda_core_if.result_branch_mask;
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
                        if (l1_if.resp_valid && l1_if.resp_warp_id == current_warp_id) begin
                            for (int t = 0; t < THREAD_COUNT; t++) begin
                                if (l1_if.resp_mask[t]) begin
                                    exec_result[t] <= l1_if.resp_data[t];
                                end
                            end
                            state <= WRITEBACK;
                        end
                    end else if (current_is_store) begin
                        // Store指令，等待LDST接受
                        if (l1_if.req_ready) begin
                            state <= WRITEBACK;
                        end
                    end else begin
                        // 非内存指令，直接进入写回
                        state <= WRITEBACK;
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
    assign disp_if.ready = (state == IDLE);
    
    // 寄存器写回
    assign rf_if.write_enable = (state == WRITEBACK) && current_reg_write;
    assign rf_if.write_warp_id = current_warp_id;
    assign rf_if.write_reg_addr = current_rd;
    assign rf_if.write_data = exec_result;
    assign rf_if.write_mask = current_active_mask;
    
    // L1 Data Cache请求
    assign l1_if.req_valid   = (state == MEMORY) && (current_is_load || current_is_store);
    assign l1_if.req_warp_id = current_warp_id;
    assign l1_if.req_mask    = current_active_mask;
    // 简化地址计算
    always_comb begin
        for (int t = 0; t < THREAD_COUNT; t++) begin
            l1_if.req_addr[t] = exec_result[t]; // 执行阶段已计算地址
            l1_if.req_data[t] = src2_data[t];   // Store数据
        end
    end
    assign l1_if.req_size     = 3'b010; // 32位
    assign l1_if.req_is_load  = current_is_load;  // 修复：应该是current_is_load，不是current_is_store
    assign l1_if.req_is_shared= 1'b0; // 简化，非共享
    // 注意：l1_if.req_ready 是输入端口，不能驱动
    // 它由 L1 cache 驱动，表示 cache 是否准备好接受请求
    assign l1_if.resp_ready   = (state == MEMORY);
    
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