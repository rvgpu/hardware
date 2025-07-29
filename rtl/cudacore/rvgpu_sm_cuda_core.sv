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

`ifndef RVGPU_SM_CUDA_CORE_SV
`define RVGPU_SM_CUDA_CORE_SV

`include "rvgpu_typedef.svh"

// SM CUDA核心
// 负责执行整数和浮点运算指令
module rvgpu_sm_cuda_core #(
    parameter int THREAD_COUNT = 32,    // 每个warp的线程数
    parameter int SIMD_WIDTH = 8        // SIMD宽度（每个周期处理的线程数）
) (
    input  logic clk,
    input  logic rst_n,
    
    // 指令输入
    input  logic        inst_valid,
    input  logic [31:0] inst,
    input  logic [31:0] pc,
    input  logic [31:0] warp_id,
    input  logic [31:0] active_mask,
    
    // 操作数输入
    input  logic [31:0] src1_data[THREAD_COUNT],
    input  logic [31:0] src2_data[THREAD_COUNT],
    input  logic [31:0] src3_data[THREAD_COUNT],
    input  logic [31:0] imm_data,
    
    // 执行结果输出
    output logic        result_valid,
    output logic [31:0] result_data[THREAD_COUNT],
    output logic [4:0]  result_rd,
    output logic [31:0] result_pc,
    output logic [31:0] result_warp_id,
    output logic [31:0] result_active_mask,
    output logic        result_is_branch,
    output logic [31:0] result_branch_target,
    output logic [31:0] result_branch_mask,
    
    // 控制信号
    input  logic        stall,
    output logic        ready
);
    // 指令类型定义
    typedef enum logic [3:0] {
        ALU_ADD,
        ALU_SUB,
        ALU_AND,
        ALU_OR,
        ALU_XOR,
        ALU_SLL,
        ALU_SRL,
        ALU_SRA,
        ALU_SLT,
        ALU_SLTU,
        ALU_MUL,
        ALU_DIV,
        ALU_REM
    } alu_op_e;
    
    typedef enum logic [2:0] {
        FPU_ADD,
        FPU_SUB,
        FPU_MUL,
        FPU_DIV,
        FPU_SQRT,
        FPU_FMADD,
        FPU_FMSUB
    } fpu_op_e;
    
    // 指令解码结果
    logic        is_int_op;
    logic        is_float_op;
    logic        is_branch_op;
    alu_op_e     alu_op;
    fpu_op_e     fpu_op;
    logic [4:0]  rd_addr;
    logic        uses_rd;
    
    // 流水线寄存器
    logic        exec1_valid;
    logic [31:0] exec1_pc;
    logic [31:0] exec1_warp_id;
    logic [31:0] exec1_active_mask;
    logic [4:0]  exec1_rd_addr;
    logic        exec1_uses_rd;
    logic        exec1_is_branch;
    
    logic        exec2_valid;
    logic [31:0] exec2_pc;
    logic [31:0] exec2_warp_id;
    logic [31:0] exec2_active_mask;
    logic [4:0]  exec2_rd_addr;
    logic        exec2_uses_rd;
    logic        exec2_is_branch;
    
    // 临时计算结果
    logic [31:0] int_result[THREAD_COUNT];
    logic [31:0] float_result[THREAD_COUNT];
    logic [31:0] branch_target;
    logic [31:0] branch_mask;
    
    // 指令解码
    always_comb begin
        // 默认值
        is_int_op = 1'b0;
        is_float_op = 1'b0;
        is_branch_op = 1'b0;
        alu_op = ALU_ADD;
        fpu_op = FPU_ADD;
        rd_addr = inst[11:7];
        uses_rd = (rd_addr != 5'b00000);
        
        // 根据RISC-V指令格式解码
        case (inst[6:0])
            7'b0110011: begin // R-type
                is_int_op = 1'b1;
                case ({inst[31:25], inst[14:12]})
                    10'b0000000000: alu_op = ALU_ADD;  // ADD
                    10'b0100000000: alu_op = ALU_SUB;  // SUB
                    10'b0000000111: alu_op = ALU_AND;  // AND
                    10'b0000000110: alu_op = ALU_OR;   // OR
                    10'b0000000100: alu_op = ALU_XOR;  // XOR
                    10'b0000000001: alu_op = ALU_SLL;  // SLL
                    10'b0000000101: alu_op = ALU_SRL;  // SRL
                    10'b0100000101: alu_op = ALU_SRA;  // SRA
                    10'b0000000010: alu_op = ALU_SLT;  // SLT
                    10'b0000000011: alu_op = ALU_SLTU; // SLTU
                    10'b0000001000: alu_op = ALU_MUL;  // MUL
                    10'b0000001100: alu_op = ALU_DIV;  // DIV
                    10'b0000001110: alu_op = ALU_REM;  // REM
                    default: alu_op = ALU_ADD;
                endcase
            end
            
            7'b0010011: begin // I-type
                is_int_op = 1'b1;
                case (inst[14:12])
                    3'b000: alu_op = ALU_ADD;  // ADDI
                    3'b111: alu_op = ALU_AND;  // ANDI
                    3'b110: alu_op = ALU_OR;   // ORI
                    3'b100: alu_op = ALU_XOR;  // XORI
                    3'b001: alu_op = ALU_SLL;  // SLLI
                    3'b101: alu_op = inst[30] ? ALU_SRA : ALU_SRL; // SRAI/SRLI
                    3'b010: alu_op = ALU_SLT;  // SLTI
                    3'b011: alu_op = ALU_SLTU; // SLTIU
                    default: alu_op = ALU_ADD;
                endcase
            end
            
            7'b1100011: begin // B-type
                is_branch_op = 1'b1;
                uses_rd = 1'b0;
            end
            
            7'b1010011: begin // F-type
                is_float_op = 1'b1;
                case (inst[31:25])
                    7'b0000000: fpu_op = FPU_ADD;   // FADD.S
                    7'b0000100: fpu_op = FPU_SUB;   // FSUB.S
                    7'b0001000: fpu_op = FPU_MUL;   // FMUL.S
                    7'b0001100: fpu_op = FPU_DIV;   // FDIV.S
                    7'b0101100: fpu_op = FPU_SQRT;  // FSQRT.S
                    7'b1000000: fpu_op = FPU_FMADD; // FMADD.S
                    7'b1000100: fpu_op = FPU_FMSUB; // FMSUB.S
                    default: fpu_op = FPU_ADD;
                endcase
            end
            
            default: begin
                is_int_op = 1'b1; // 默认当作整数操作
                alu_op = ALU_ADD;
            end
        endcase
    end
    
    // 整数ALU
    always_comb begin
        for (int t = 0; t < THREAD_COUNT; t++) begin
            // 默认结果
            int_result[t] = '0;
            
            // 只处理活跃线程
            if (active_mask[t]) begin
                case (alu_op)
                    ALU_ADD:  int_result[t] = src1_data[t] + src2_data[t];
                    ALU_SUB:  int_result[t] = src1_data[t] - src2_data[t];
                    ALU_AND:  int_result[t] = src1_data[t] & src2_data[t];
                    ALU_OR:   int_result[t] = src1_data[t] | src2_data[t];
                    ALU_XOR:  int_result[t] = src1_data[t] ^ src2_data[t];
                    ALU_SLL:  int_result[t] = src1_data[t] << src2_data[t][4:0];
                    ALU_SRL:  int_result[t] = src1_data[t] >> src2_data[t][4:0];
                    ALU_SRA:  int_result[t] = $signed(src1_data[t]) >>> src2_data[t][4:0];
                    ALU_SLT:  int_result[t] = ($signed(src1_data[t]) < $signed(src2_data[t])) ? 32'h1 : 32'h0;
                    ALU_SLTU: int_result[t] = (src1_data[t] < src2_data[t]) ? 32'h1 : 32'h0;
                    ALU_MUL:  int_result[t] = src1_data[t] * src2_data[t];
                    ALU_DIV:  int_result[t] = (src2_data[t] == '0) ? '1 : (src1_data[t] / src2_data[t]);
                    ALU_REM:  int_result[t] = (src2_data[t] == '0) ? src1_data[t] : (src1_data[t] % src2_data[t]);
                    default:  int_result[t] = src1_data[t] + src2_data[t];
                endcase
            end
        end
    end
    
    // 浮点单元 (简化实现)
    always_comb begin
        for (int t = 0; t < THREAD_COUNT; t++) begin
            // 默认结果
            float_result[t] = '0;
            
            // 只处理活跃线程
            if (active_mask[t]) begin
                // 简化实现：实际应使用IEEE-754浮点运算
                case (fpu_op)
                    FPU_ADD:   float_result[t] = src1_data[t] + src2_data[t];
                    FPU_SUB:   float_result[t] = src1_data[t] - src2_data[t];
                    FPU_MUL:   float_result[t] = src1_data[t] * src2_data[t];
                    FPU_DIV:   float_result[t] = (src2_data[t] == '0) ? '1 : (src1_data[t] / src2_data[t]);
                    FPU_SQRT:  float_result[t] = src1_data[t]; // 简化实现，实际需要平方根计算
                    FPU_FMADD: float_result[t] = src1_data[t] * src2_data[t] + src3_data[t];
                    FPU_FMSUB: float_result[t] = src1_data[t] * src2_data[t] - src3_data[t];
                    default:   float_result[t] = src1_data[t];
                endcase
            end
        end
    end
    
    // 分支处理
    always_comb begin
        branch_target = pc + imm_data; // 简化实现，实际需要根据指令类型计算目标地址
        branch_mask = '0;
        
        for (int t = 0; t < THREAD_COUNT; t++) begin
            if (active_mask[t]) begin
                case (inst[14:12])
                    3'b000: branch_mask[t] = (src1_data[t] == src2_data[t]); // BEQ
                    3'b001: branch_mask[t] = (src1_data[t] != src2_data[t]); // BNE
                    3'b100: branch_mask[t] = ($signed(src1_data[t]) < $signed(src2_data[t])); // BLT
                    3'b101: branch_mask[t] = ($signed(src1_data[t]) >= $signed(src2_data[t])); // BGE
                    3'b110: branch_mask[t] = (src1_data[t] < src2_data[t]); // BLTU
                    3'b111: branch_mask[t] = (src1_data[t] >= src2_data[t]); // BGEU
                    default: branch_mask[t] = 1'b0;
                endcase
            end
        end
    end
    
    // 流水线阶段1 (执行)
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            exec1_valid <= 1'b0;
            exec1_pc <= '0;
            exec1_warp_id <= '0;
            exec1_active_mask <= '0;
            exec1_rd_addr <= '0;
            exec1_uses_rd <= 1'b0;
            exec1_is_branch <= 1'b0;
        end else if (!stall) begin
            exec1_valid <= inst_valid;
            exec1_pc <= pc;
            exec1_warp_id <= warp_id;
            exec1_active_mask <= active_mask;
            exec1_rd_addr <= rd_addr;
            exec1_uses_rd <= uses_rd;
            exec1_is_branch <= is_branch_op;
        end
    end
    
    // 流水线阶段2 (写回)
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            exec2_valid <= 1'b0;
            exec2_pc <= '0;
            exec2_warp_id <= '0;
            exec2_active_mask <= '0;
            exec2_rd_addr <= '0;
            exec2_uses_rd <= 1'b0;
            exec2_is_branch <= 1'b0;
            
            for (int t = 0; t < THREAD_COUNT; t++) begin
                result_data[t] <= '0;
            end
            
            result_branch_target <= '0;
            result_branch_mask <= '0;
        end else if (!stall) begin
            exec2_valid <= exec1_valid;
            exec2_pc <= exec1_pc;
            exec2_warp_id <= exec1_warp_id;
            exec2_active_mask <= exec1_active_mask;
            exec2_rd_addr <= exec1_rd_addr;
            exec2_uses_rd <= exec1_uses_rd;
            exec2_is_branch <= exec1_is_branch;
            
            // 选择结果
            for (int t = 0; t < THREAD_COUNT; t++) begin
                if (is_int_op) begin
                    result_data[t] <= int_result[t];
                end else if (is_float_op) begin
                    result_data[t] <= float_result[t];
                end else begin
                    result_data[t] <= '0;
                end
            end
            
            if (is_branch_op) begin
                result_branch_target <= branch_target;
                result_branch_mask <= branch_mask;
            end else begin
                result_branch_target <= '0;
                result_branch_mask <= '0;
            end
        end
    end
    
    // 输出赋值
    assign result_valid = exec2_valid;
    assign result_rd = exec2_rd_addr;
    assign result_pc = exec2_pc;
    assign result_warp_id = exec2_warp_id;
    assign result_active_mask = exec2_active_mask;
    assign result_is_branch = exec2_is_branch;
    
    // 总是准备好接收新指令
    assign ready = 1'b1;

endmodule : rvgpu_sm_cuda_core

`endif // RVGPU_SM_CUDA_CORE_SV 