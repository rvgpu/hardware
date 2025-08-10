//=============================================================================
// Copyright © 2025 RVGPU Team
// Licensed under the Apache License, Version 2.0 (the "License");
//=============================================================================

`ifndef RVGPU_INTERFACE_SM_L1DATA_SVH
`define RVGPU_INTERFACE_SM_L1DATA_SVH

`include "rvgpu_typedef.svh"

// SM CUDA Core <-> L1 Data Cache 接口（每个Core一份）
interface interface_sm_l1data #(
    parameter int WARP_COUNT = 32,
    parameter int THREAD_COUNT = 32
);
    // 请求通道（Core -> L1）
    logic                                req_valid;
    logic [$clog2(WARP_COUNT)-1:0]       req_warp_id;
    logic [THREAD_COUNT-1:0]             req_mask;
    logic [63:0]                         req_addr[THREAD_COUNT];
    logic [31:0]                         req_data[THREAD_COUNT];
    logic [2:0]                          req_size;
    logic                                req_is_load;   // 1:load 0:store
    logic                                req_is_shared; // 1:shared 0:global
    logic                                req_ready;

    // 响应通道（L1 -> Core）
    logic                                resp_valid;
    logic [$clog2(WARP_COUNT)-1:0]       resp_warp_id;
    logic [THREAD_COUNT-1:0]             resp_mask;
    logic [31:0]                         resp_data[THREAD_COUNT];
    logic                                resp_ready;

    // 核心侧视角
    modport core (
        output req_valid, req_warp_id, req_mask, req_addr, req_data, req_size, req_is_load, req_is_shared,
        input  req_ready,
        input  resp_valid, resp_warp_id, resp_mask, resp_data,
        output resp_ready
    );

    // L1侧视角
    modport l1 (
        input  req_valid, req_warp_id, req_mask, req_addr, req_data, req_size, req_is_load, req_is_shared,
        output req_ready,
        output resp_valid, resp_warp_id, resp_mask, resp_data,
        input  resp_ready
    );

endinterface : interface_sm_l1data

`endif // RVGPU_INTERFACE_SM_L1DATA_SVH


