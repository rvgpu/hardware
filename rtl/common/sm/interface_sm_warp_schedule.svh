//=============================================================================
// Copyright © 2025 RVGPU Team
// Licensed under the Apache License, Version 2.0 (the "License");
//=============================================================================

`ifndef RVGPU_INTERFACE_SM_WARP_SCHEDULE_SVH
`define RVGPU_INTERFACE_SM_WARP_SCHEDULE_SVH

`include "rvgpu_typedef.svh"

// Warp Scheduler <-> Fetch 阶段的调度接口
interface interface_sm_warp_schedule #(
    parameter int WARP_COUNT = 32
);
    logic                        valid;
    logic [$clog2(WARP_COUNT)-1:0] scheduled_warp_id;
    logic                        ready;   // Fetch 可接受新的warp

    // 调度器侧（源）
    modport scheduler_source (
        output valid, scheduled_warp_id,
        input  ready
    );

    // 取指侧（汇）
    modport fetch_sink (
        input  valid, scheduled_warp_id,
        output ready
    );

endinterface : interface_sm_warp_schedule

`endif // RVGPU_INTERFACE_SM_WARP_SCHEDULE_SVH


