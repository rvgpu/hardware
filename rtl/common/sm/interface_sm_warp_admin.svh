//=============================================================================
// Copyright © 2025 RVGPU Team
// Licensed under the Apache License, Version 2.0 (the "License");
//=============================================================================

`ifndef RVGPU_INTERFACE_SM_WARP_ADMIN_SVH
`define RVGPU_INTERFACE_SM_WARP_ADMIN_SVH

`include "rvgpu_typedef.svh"

// Warp 管理接口：分配/释放握手与状态
interface interface_sm_warp_admin #(
    parameter int WARP_COUNT = 32
);
    // 分配请求/应答
    logic                        alloc_valid;
    logic [$clog2(WARP_COUNT)-1:0] alloc_id;
    logic                        alloc_ready;

    // 释放请求
    logic                        dealloc_valid;
    logic [$clog2(WARP_COUNT)-1:0] dealloc_id;

    // 状态
    logic [WARP_COUNT-1:0]       allocated_bitmap;
    logic [$clog2(WARP_COUNT):0] allocated_count;

    // 顶层侧（源/管理者）
    modport manager (
        output alloc_valid, alloc_id,
        input  alloc_ready,
        output dealloc_valid, dealloc_id,
        input  allocated_bitmap, allocated_count
    );

    // 寄存器文件侧（存储/执行者）
    modport storage (
        input  alloc_valid, alloc_id,
        output alloc_ready,
        input  dealloc_valid, dealloc_id,
        output allocated_bitmap, allocated_count
    );

endinterface : interface_sm_warp_admin

`endif // RVGPU_INTERFACE_SM_WARP_ADMIN_SVH


