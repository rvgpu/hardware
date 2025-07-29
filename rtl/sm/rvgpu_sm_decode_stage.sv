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

`ifndef RVGPU_SM_DECODE_STAGE_SV
`define RVGPU_SM_DECODE_STAGE_SV

`include "rvgpu_typedef.svh"

// SM解码阶段
// 负责指令解码、寄存器地址提取和控制信号生成
module rvgpu_sm_decode_stage #(
    parameter int WARP_COUNT = 32,      // 支持的warp数量
    parameter int THREAD_COUNT = 32     // 每个warp的线程数
) (
    input  logic clk,
    input  logic rst_n,
    
    // 从取指阶段的输入
    input  logic                                fetch_decode_valid,
    input  logic [31:0]                         fetch_decode_inst,
    input  logic [63:0]                         fetch_decode_pc,
    input  logic [$clog2(WARP_COUNT)-1:0]      fetch_decode_warp_id,
    input  logic [THREAD_COUNT-1:0]             fetch_decode_active_mask,
    output logic                                fetch_decode_ready,
    
    // 到执行阶段的输出
    output logic                                decode_exec_valid,
    output logic [31:0]                         decode_exec_inst,
    output logic [63:0]                         decode_exec_pc,
    output logic [$clog2(WARP_COUNT)-1:0]      decode_exec_warp_id,
    output logic [THREAD_COUNT-1:0]             decode_exec_active_mask,
    
    // 解码控制信号
    output logic [4:0]                          decode_exec_rs1,
    output logic [4:0]                          decode_exec_rs2,
    output logic [4:0]                          decode_exec_rs3,
    output logic [4:0]                          decode_exec_rd,
    output logic [31:0]                         decode_exec_imm,
    
    // 指令类型信号
    output logic                                decode_exec_is_alu,
    output logic                                decode_exec_is_fpu,
    output logic                                decode_exec_is_tensor,
    output logic                                decode_exec_is_branch,
    output logic                                decode_exec_is_jump,
    output logic                                decode_exec_is_load,
    output logic                                decode_exec_is_store,
    output logic                                decode_exec_is_barrier,
    
    // ALU操作码
    output logic [3:0]                          decode_exec_alu_op,
    output logic [2:0]                          decode_exec_fpu_op,
    output logic [2:0]                          decode_exec_tensor_op,
    output logic [2:0]                          decode_exec_branch_op,
    
    // 控制信号
    output logic                                decode_exec_reg_write,
    output logic                                decode_exec_use_imm,
    output logic                                decode_exec_is_32bit,
    
    input  logic                                decode_exec_ready,
    
    // 流水线控制
    input  logic                                pipeline_stall,
    input  logic                                pipeline_flush
);

    // 指令格式类型
    typedef enum logic [2:0] {
        R_TYPE,     // Register-Register
        I_TYPE,     // Immediate
        S_TYPE,     // Store
        B_TYPE,     // Branch
        U_TYPE,     // Upper immediate
        J_TYPE,     // Jump
        F_TYPE      // Float/Tensor
    } inst_format_t;
    
    // 解码后的信号
    logic [6:0]  opcode;
    logic [4:0]  rd, rs1, rs2, rs3;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
    logic [31:0] selected_imm;
    
    inst_format_t inst_format;
    
    // 控制信号
    logic is_alu, is_fpu, is_tensor, is_branch, is_jump, is_load, is_store, is_barrier;
    logic reg_write, use_imm, is_32bit;
    logic [3:0] alu_op;
    logic [2:0] fpu_op, tensor_op, branch_op;
    
    // 流水线寄存器
    logic                               de_valid_reg;
    logic [31:0]                        de_inst_reg;
    logic [63:0]                        de_pc_reg;
    logic [$clog2(WARP_COUNT)-1:0]     de_warp_id_reg;
    logic [THREAD_COUNT-1:0]            de_active_mask_reg;
    
    logic [4:0]                         de_rs1_reg, de_rs2_reg, de_rs3_reg, de_rd_reg;
    logic [31:0]                        de_imm_reg;
    logic                               de_is_alu_reg, de_is_fpu_reg, de_is_tensor_reg;
    logic                               de_is_branch_reg, de_is_jump_reg;
    logic                               de_is_load_reg, de_is_store_reg, de_is_barrier_reg;
    logic [3:0]                         de_alu_op_reg;
    logic [2:0]                         de_fpu_op_reg, de_tensor_op_reg, de_branch_op_reg;
    logic                               de_reg_write_reg, de_use_imm_reg, de_is_32bit_reg;
    
    // 指令字段提取
    assign opcode = fetch_decode_inst[6:0];
    assign rd = fetch_decode_inst[11:7];
    assign funct3 = fetch_decode_inst[14:12];
    assign rs1 = fetch_decode_inst[19:15];
    assign rs2 = fetch_decode_inst[24:20];
    assign rs3 = fetch_decode_inst[31:27];  // 用于Tensor指令
    assign funct7 = fetch_decode_inst[31:25];
    
    // 立即数提取
    assign imm_i = {{20{fetch_decode_inst[31]}}, fetch_decode_inst[31:20]};
    assign imm_s = {{20{fetch_decode_inst[31]}}, fetch_decode_inst[31:25], fetch_decode_inst[11:7]};
    assign imm_b = {{19{fetch_decode_inst[31]}}, fetch_decode_inst[31], fetch_decode_inst[7], 
                    fetch_decode_inst[30:25], fetch_decode_inst[11:8], 1'b0};
    assign imm_u = {fetch_decode_inst[31:12], 12'b0};
    assign imm_j = {{11{fetch_decode_inst[31]}}, fetch_decode_inst[31], fetch_decode_inst[19:12], 
                    fetch_decode_inst[20], fetch_decode_inst[30:21], 1'b0};
    
    // 指令格式识别
    always_comb begin
        case (opcode)
            7'b0110011, 7'b0111011: inst_format = R_TYPE;  // R-type, R32-type
            7'b0010011, 7'b0011011, 7'b0000011, 7'b1100111, 7'b1110011: inst_format = I_TYPE;  // I-type, I32-type, Load, JALR, System
            7'b0100011: inst_format = S_TYPE;  // Store
            7'b1100011: inst_format = B_TYPE;  // Branch
            7'b0110111, 7'b0010111: inst_format = U_TYPE;  // LUI, AUIPC
            7'b1101111: inst_format = J_TYPE;  // JAL
            7'b1010011, 7'b1011011: inst_format = F_TYPE;  // Float, Tensor
            default: inst_format = R_TYPE;
        endcase
    end
    
    // 立即数选择
    always_comb begin
        case (inst_format)
            I_TYPE: selected_imm = imm_i;
            S_TYPE: selected_imm = imm_s;
            B_TYPE: selected_imm = imm_b;
            U_TYPE: selected_imm = imm_u;
            J_TYPE: selected_imm = imm_j;
            default: selected_imm = 32'h0;
        endcase
    end
    
    // 主解码逻辑
    always_comb begin
        // 默认值
        is_alu = 1'b0;
        is_fpu = 1'b0;
        is_tensor = 1'b0;
        is_branch = 1'b0;
        is_jump = 1'b0;
        is_load = 1'b0;
        is_store = 1'b0;
        is_barrier = 1'b0;
        reg_write = 1'b0;
        use_imm = 1'b0;
        is_32bit = 1'b0;
        alu_op = 4'b0000;
        fpu_op = 3'b000;
        tensor_op = 3'b000;
        branch_op = 3'b000;
        
        case (opcode)
            7'b0110011: begin // R-type ALU
                is_alu = 1'b1;
                reg_write = 1'b1;
                case ({funct7, funct3})
                    10'b0000000000: alu_op = 4'b0000; // ADD
                    10'b0100000000: alu_op = 4'b0001; // SUB
                    10'b0000000001: alu_op = 4'b0010; // SLL
                    10'b0000000010: alu_op = 4'b0011; // SLT
                    10'b0000000011: alu_op = 4'b0100; // SLTU
                    10'b0000000100: alu_op = 4'b0101; // XOR
                    10'b0000000101: alu_op = 4'b0110; // SRL
                    10'b0100000101: alu_op = 4'b0111; // SRA
                    10'b0000000110: alu_op = 4'b1000; // OR
                    10'b0000000111: alu_op = 4'b1001; // AND
                    10'b0000001000: alu_op = 4'b1010; // MUL
                    10'b0000001100: alu_op = 4'b1011; // DIV
                    10'b0000001110: alu_op = 4'b1100; // REM
                    default: alu_op = 4'b0000;
                endcase
            end
            
            7'b0010011: begin // I-type ALU
                is_alu = 1'b1;
                reg_write = 1'b1;
                use_imm = 1'b1;
                case (funct3)
                    3'b000: alu_op = 4'b0000; // ADDI
                    3'b010: alu_op = 4'b0011; // SLTI
                    3'b011: alu_op = 4'b0100; // SLTIU
                    3'b100: alu_op = 4'b0101; // XORI
                    3'b110: alu_op = 4'b1000; // ORI
                    3'b111: alu_op = 4'b1001; // ANDI
                    3'b001: alu_op = 4'b0010; // SLLI
                    3'b101: alu_op = funct7[5] ? 4'b0111 : 4'b0110; // SRAI/SRLI
                    default: alu_op = 4'b0000;
                endcase
            end
            
            7'b0000011: begin // Load
                is_load = 1'b1;
                reg_write = 1'b1;
                use_imm = 1'b1;
            end
            
            7'b0100011: begin // Store
                is_store = 1'b1;
                use_imm = 1'b1;
            end
            
            7'b1100011: begin // Branch
                is_branch = 1'b1;
                use_imm = 1'b1;
                branch_op = funct3;
            end
            
            7'b1101111: begin // JAL
                is_jump = 1'b1;
                reg_write = 1'b1;
                use_imm = 1'b1;
            end
            
            7'b1100111: begin // JALR
                is_jump = 1'b1;
                reg_write = 1'b1;
                use_imm = 1'b1;
            end
            
            7'b0110111: begin // LUI
                is_alu = 1'b1;
                reg_write = 1'b1;
                use_imm = 1'b1;
                alu_op = 4'b1101; // 特殊操作码用于LUI
            end
            
            7'b0010111: begin // AUIPC
                is_alu = 1'b1;
                reg_write = 1'b1;
                use_imm = 1'b1;
                alu_op = 4'b1110; // 特殊操作码用于AUIPC
            end
            
            7'b1010011: begin // Float
                is_fpu = 1'b1;
                reg_write = 1'b1;
                case (funct7)
                    7'b0000000: fpu_op = 3'b000; // FADD.S
                    7'b0000100: fpu_op = 3'b001; // FSUB.S
                    7'b0001000: fpu_op = 3'b010; // FMUL.S
                    7'b0001100: fpu_op = 3'b011; // FDIV.S
                    7'b0101100: fpu_op = 3'b100; // FSQRT.S
                    7'b1000000: fpu_op = 3'b101; // FMADD.S
                    7'b1000100: fpu_op = 3'b110; // FMSUB.S
                    default: fpu_op = 3'b000;
                endcase
            end
            
            7'b1011011: begin // Tensor (自定义)
                is_tensor = 1'b1;
                reg_write = 1'b1;
                tensor_op = funct3;
            end
            
            7'b1110011: begin // System
                if (funct3 == 3'b000 && imm_i == 32'h0) begin
                    is_barrier = 1'b1; // ECALL作为barrier
                end
            end
            
            default: begin
                // NOP或未知指令
                is_alu = 1'b1;
                alu_op = 4'b0000;
            end
        endcase
        
        // 32位操作检测
        is_32bit = (opcode == 7'b0111011) || (opcode == 7'b0011011);
    end
    
    // 流水线寄存器更新
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            de_valid_reg <= 1'b0;
            de_inst_reg <= '0;
            de_pc_reg <= '0;
            de_warp_id_reg <= '0;
            de_active_mask_reg <= '0;
            de_rs1_reg <= '0;
            de_rs2_reg <= '0;
            de_rs3_reg <= '0;
            de_rd_reg <= '0;
            de_imm_reg <= '0;
            de_is_alu_reg <= 1'b0;
            de_is_fpu_reg <= 1'b0;
            de_is_tensor_reg <= 1'b0;
            de_is_branch_reg <= 1'b0;
            de_is_jump_reg <= 1'b0;
            de_is_load_reg <= 1'b0;
            de_is_store_reg <= 1'b0;
            de_is_barrier_reg <= 1'b0;
            de_alu_op_reg <= '0;
            de_fpu_op_reg <= '0;
            de_tensor_op_reg <= '0;
            de_branch_op_reg <= '0;
            de_reg_write_reg <= 1'b0;
            de_use_imm_reg <= 1'b0;
            de_is_32bit_reg <= 1'b0;
        end else if (pipeline_flush) begin
            de_valid_reg <= 1'b0;
        end else if (!pipeline_stall) begin
            if (fetch_decode_valid && decode_exec_ready) begin
                de_valid_reg <= 1'b1;
                de_inst_reg <= fetch_decode_inst;
                de_pc_reg <= fetch_decode_pc;
                de_warp_id_reg <= fetch_decode_warp_id;
                de_active_mask_reg <= fetch_decode_active_mask;
                de_rs1_reg <= rs1;
                de_rs2_reg <= rs2;
                de_rs3_reg <= rs3;
                de_rd_reg <= rd;
                de_imm_reg <= selected_imm;
                de_is_alu_reg <= is_alu;
                de_is_fpu_reg <= is_fpu;
                de_is_tensor_reg <= is_tensor;
                de_is_branch_reg <= is_branch;
                de_is_jump_reg <= is_jump;
                de_is_load_reg <= is_load;
                de_is_store_reg <= is_store;
                de_is_barrier_reg <= is_barrier;
                de_alu_op_reg <= alu_op;
                de_fpu_op_reg <= fpu_op;
                de_tensor_op_reg <= tensor_op;
                de_branch_op_reg <= branch_op;
                de_reg_write_reg <= reg_write;
                de_use_imm_reg <= use_imm;
                de_is_32bit_reg <= is_32bit;
            end else if (decode_exec_ready) begin
                de_valid_reg <= 1'b0;
            end
        end
    end
    
    // 输出信号
    assign decode_exec_valid = de_valid_reg;
    assign decode_exec_inst = de_inst_reg;
    assign decode_exec_pc = de_pc_reg;
    assign decode_exec_warp_id = de_warp_id_reg;
    assign decode_exec_active_mask = de_active_mask_reg;
    assign decode_exec_rs1 = de_rs1_reg;
    assign decode_exec_rs2 = de_rs2_reg;
    assign decode_exec_rs3 = de_rs3_reg;
    assign decode_exec_rd = de_rd_reg;
    assign decode_exec_imm = de_imm_reg;
    assign decode_exec_is_alu = de_is_alu_reg;
    assign decode_exec_is_fpu = de_is_fpu_reg;
    assign decode_exec_is_tensor = de_is_tensor_reg;
    assign decode_exec_is_branch = de_is_branch_reg;
    assign decode_exec_is_jump = de_is_jump_reg;
    assign decode_exec_is_load = de_is_load_reg;
    assign decode_exec_is_store = de_is_store_reg;
    assign decode_exec_is_barrier = de_is_barrier_reg;
    assign decode_exec_alu_op = de_alu_op_reg;
    assign decode_exec_fpu_op = de_fpu_op_reg;
    assign decode_exec_tensor_op = de_tensor_op_reg;
    assign decode_exec_branch_op = de_branch_op_reg;
    assign decode_exec_reg_write = de_reg_write_reg;
    assign decode_exec_use_imm = de_use_imm_reg;
    assign decode_exec_is_32bit = de_is_32bit_reg;
    
    // 准备信号
    assign fetch_decode_ready = decode_exec_ready || !de_valid_reg;

endmodule : rvgpu_sm_decode_stage

`endif // RVGPU_SM_DECODE_STAGE_SV 