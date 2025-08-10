//=============================================================================
// Copyright © 2025 RVGPU Team
// Licensed under the Apache License, Version 2.0 (the "License");
//=============================================================================

`ifndef RVGPU_INTERFACE_SM_PC_UPDATE_SVH
`define RVGPU_INTERFACE_SM_PC_UPDATE_SVH

`include "rvgpu_typedef.svh"

// PC Update 接口：写回阶段产生，取指阶段消费
interface interface_sm_pc_update #(
    parameter int WARP_COUNT = 32
);
    logic                        valid;
    logic [$clog2(WARP_COUNT)-1:0] warp_id;
    logic [63:0]                 pc;

    // 源（写回）
    modport source (
        output valid, warp_id, pc
    );

    // 汇（取指）
    modport sink (
        input  valid, warp_id, pc
    );

endinterface : interface_sm_pc_update

`endif // RVGPU_INTERFACE_SM_PC_UPDATE_SVH


