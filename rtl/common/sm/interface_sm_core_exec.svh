//=============================================================================
// Copyright © 2025 RVGPU Team
// Licensed under the Apache License, Version 2.0 (the "License");
//=============================================================================

`ifndef RVGPU_INTERFACE_SM_CORE_EXEC_SVH
`define RVGPU_INTERFACE_SM_CORE_EXEC_SVH

`include "rvgpu_typedef.svh"

// CUDA Core 执行接口（整数/浮点/分支）
interface interface_sm_core_exec #(
    parameter int THREAD_COUNT = 32
);
    // 指令与上下文
    logic        inst_valid;
    logic [31:0] inst;
    logic [31:0] pc;
    logic [31:0] warp_id;
    logic [31:0] active_mask;

    // 操作数与立即数
    logic [31:0] src1_data[THREAD_COUNT];
    logic [31:0] src2_data[THREAD_COUNT];
    logic [31:0] src3_data[THREAD_COUNT];
    logic [31:0] imm_data;

    // 流控
    logic        stall;
    logic        ready;

    // 结果
    logic        result_valid;
    logic [31:0] result_data[THREAD_COUNT];
    logic        result_is_branch;
    logic [31:0] result_branch_target;
    logic [31:0] result_branch_mask;

    // Core侧（消费者）
    modport core_sink (
        input  inst_valid, inst, pc, warp_id, active_mask,
        input  src1_data, src2_data, src3_data, imm_data,
        input  stall,
        output ready,
        output result_valid, result_data, result_is_branch, result_branch_target, result_branch_mask
    );

    // 生产侧（上游驱动）
    modport source (
        output inst_valid, inst, pc, warp_id, active_mask,
        output src1_data, src2_data, src3_data, imm_data,
        output stall,
        input  ready,
        input  result_valid, result_data, result_is_branch, result_branch_target, result_branch_mask
    );

endinterface : interface_sm_core_exec

`endif // RVGPU_INTERFACE_SM_CORE_EXEC_SVH


