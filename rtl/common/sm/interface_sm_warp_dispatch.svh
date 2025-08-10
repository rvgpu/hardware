//=============================================================================
// Copyright © 2025 RVGPU Team
// Licensed under the Apache License, Version 2.0 (the "License");
//=============================================================================

`ifndef RVGPU_INTERFACE_SM_WARP_DISPATCH_SVH
`define RVGPU_INTERFACE_SM_WARP_DISPATCH_SVH

`include "rvgpu_typedef.svh"

// SM -> CUDA Core Warp Dispatch 接口
interface interface_sm_warp_dispatch #(
    parameter int WARP_COUNT = 32,
    parameter int THREAD_COUNT = 32
);
    // 握手
    logic                                valid;
    logic                                ready;

    // 指令与线程上下文
    logic [31:0]                         inst;
    logic [63:0]                         pc;
    logic [$clog2(WARP_COUNT)-1:0]       warp_id;
    logic [THREAD_COUNT-1:0]             active_mask;

    // 源/目的寄存器与立即数
    logic [4:0]                          rs1;
    logic [4:0]                          rs2;
    logic [4:0]                          rs3;
    logic [4:0]                          rd;
    logic [31:0]                         imm;

    // 指令类型与控制
    logic                                is_alu;
    logic                                is_fpu;
    logic                                is_tensor;
    logic                                is_branch;
    logic                                is_jump;
    logic                                is_load;
    logic                                is_store;
    logic                                is_barrier;
    logic [3:0]                          alu_op;
    logic [2:0]                          fpu_op;
    logic [2:0]                          tensor_op;
    logic [2:0]                          branch_op;
    logic                                reg_write;
    logic                                use_imm;
    logic                                is_32bit;

    // SM侧（生产者）
    modport sm_source (
        output valid, inst, pc, warp_id, active_mask,
        output rs1, rs2, rs3, rd, imm,
        output is_alu, is_fpu, is_tensor, is_branch, is_jump, is_load, is_store, is_barrier,
        output alu_op, fpu_op, tensor_op, branch_op,
        output reg_write, use_imm, is_32bit,
        input  ready
    );

    // Core侧（消费者）
    modport core_sink (
        input  valid, inst, pc, warp_id, active_mask,
        input  rs1, rs2, rs3, rd, imm,
        input  is_alu, is_fpu, is_tensor, is_branch, is_jump, is_load, is_store, is_barrier,
        input  alu_op, fpu_op, tensor_op, branch_op,
        input  reg_write, use_imm, is_32bit,
        output ready
    );

endinterface : interface_sm_warp_dispatch

`endif // RVGPU_INTERFACE_SM_WARP_DISPATCH_SVH


