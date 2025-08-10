//=============================================================================
// Copyright © 2025 RVGPU Team
// Licensed under the Apache License, Version 2.0 (the "License");
//=============================================================================

`ifndef RVGPU_INTERFACE_SM_TENSOR_EXEC_SVH
`define RVGPU_INTERFACE_SM_TENSOR_EXEC_SVH

`include "rvgpu_typedef.svh"

// Tensor Core 执行接口
interface interface_sm_tensor_exec #(
    parameter int THREAD_COUNT = 32,
    parameter int MATRIX_SIZE = 4
);
    // 指令与上下文
    logic        inst_valid;
    logic [31:0] inst;
    logic [31:0] pc;
    logic [31:0] warp_id;
    logic [31:0] active_mask;

    // 操作数（矩阵）
    logic [15:0] matrix_a[THREAD_COUNT][MATRIX_SIZE][MATRIX_SIZE];
    logic [15:0] matrix_b[THREAD_COUNT][MATRIX_SIZE][MATRIX_SIZE];
    logic [31:0] matrix_c[THREAD_COUNT][MATRIX_SIZE][MATRIX_SIZE];

    // 流控
    logic        stall;
    logic        ready;

    // 结果
    logic        result_valid;
    logic [31:0] result_data[THREAD_COUNT][MATRIX_SIZE][MATRIX_SIZE];

    // Core侧（消费者）
    modport core_sink (
        input  inst_valid, inst, pc, warp_id, active_mask,
        input  matrix_a, matrix_b, matrix_c,
        input  stall,
        output ready,
        output result_valid, result_data
    );

    // 生产侧（上游驱动）
    modport source (
        output inst_valid, inst, pc, warp_id, active_mask,
        output matrix_a, matrix_b, matrix_c,
        output stall,
        input  ready,
        input  result_valid, result_data
    );

endinterface : interface_sm_tensor_exec

`endif // RVGPU_INTERFACE_SM_TENSOR_EXEC_SVH


