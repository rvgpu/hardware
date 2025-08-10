//=============================================================================
// Copyright © 2025 RVGPU Team
// Licensed under the Apache License, Version 2.0 (the "License");
//=============================================================================

`ifndef RVGPU_INTERFACE_SM_CUDA_CORE_SVH
`define RVGPU_INTERFACE_SM_CUDA_CORE_SVH

`include "rvgpu_typedef.svh"

// CUDA核心接口
interface interface_sm_cuda_core #(
    parameter int THREAD_COUNT = 32
);
    // 时钟和复位
    logic clk;
    logic rst_n;
    
    // 指令输入
    logic        inst_valid;
    logic [31:0] inst;
    logic [31:0] pc;
    logic [31:0] warp_id;
    logic [31:0] active_mask;
    
    // 操作数输入
    logic [31:0] src1_data[THREAD_COUNT];
    logic [31:0] src2_data[THREAD_COUNT];
    logic [31:0] src3_data[THREAD_COUNT];
    logic [31:0] imm_data;
    
    // 执行结果输出
    logic        result_valid;
    logic [31:0] result_data[THREAD_COUNT];
    logic [4:0]  result_rd;
    logic [31:0] result_pc;
    logic [31:0] result_warp_id;
    logic [31:0] result_active_mask;
    logic        result_is_branch;
    logic [31:0] result_branch_target;
    logic [31:0] result_branch_mask;
    
    // 控制信号
    logic        stall;
    logic        ready;

    // 核心侧（消费者）modport
    modport core (
        input  clk, rst_n,
        input  inst_valid, inst, pc, warp_id, active_mask,
        input  src1_data, src2_data, src3_data, imm_data,
        input  stall,
        output ready,
        output result_valid, result_data, result_rd, result_pc, 
               result_warp_id, result_active_mask, result_is_branch, 
               result_branch_target, result_branch_mask
    );

    // 外部侧（驱动者）modport
    modport external (
        output clk, rst_n,
        output inst_valid, inst, pc, warp_id, active_mask,
        output src1_data, src2_data, src3_data, imm_data,
        output stall,
        input  ready,
        input  result_valid, result_data, result_rd, result_pc, 
               result_warp_id, result_active_mask, result_is_branch, 
               result_branch_target, result_branch_mask
    );

endinterface : interface_sm_cuda_core

`endif // RVGPU_INTERFACE_SM_CUDA_CORE_SVH
