//=============================================================================
// Copyright © 2025 RVGPU Team
// Licensed under the Apache License, Version 2.0 (the "License");
//=============================================================================

`ifndef RVGPU_INTERFACE_SM_WARP_STATE_SVH
`define RVGPU_INTERFACE_SM_WARP_STATE_SVH

`include "rvgpu_typedef.svh"

// Warp 状态接口：提供每个 warp 的 PC、活跃掩码与有效位
interface interface_sm_warp_state #(
    parameter int WARP_COUNT   = 32,
    parameter int THREAD_COUNT = 32
);
    logic [63:0]                 warp_pc[WARP_COUNT];
    logic [THREAD_COUNT-1:0]     warp_active_mask[WARP_COUNT];
    logic [WARP_COUNT-1:0]       warp_valid;
    logic [WARP_COUNT-1:0]       warp_stalled;
    logic [WARP_COUNT-1:0]       warp_barrier;
    logic [WARP_COUNT-1:0]       warp_waiting;

    // 顶层侧（源）
    modport source (
        output warp_pc, warp_active_mask, warp_valid, warp_stalled, warp_barrier, warp_waiting
    );

    // 取指侧（只读）
    modport fetch_view (
        input  warp_pc, warp_active_mask, warp_valid, warp_stalled, warp_barrier, warp_waiting
    );

endinterface : interface_sm_warp_state

`endif // RVGPU_INTERFACE_SM_WARP_STATE_SVH


