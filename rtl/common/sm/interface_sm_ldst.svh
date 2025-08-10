//=============================================================================
// Copyright © 2025 RVGPU Team
// Licensed under the the Apache License, Version 2.0
//=============================================================================

`ifndef RVGPU_INTERFACE_SM_LDST_SVH
`define RVGPU_INTERFACE_SM_LDST_SVH

`include "rvgpu_typedef.svh"

// SM <-> LDST 简化接口（与现有 ldst_sm_if 保持兼容可替换）
interface interface_sm_ldst #(
    parameter int WARP_COUNT = 32,
    parameter int THREAD_COUNT = 32
);
    // 请求
    logic                                req_valid;
    logic [$clog2(WARP_COUNT)-1:0]       req_warp_id;
    logic [THREAD_COUNT-1:0]             req_mask;
    logic [63:0]                         req_addr[THREAD_COUNT];
    logic [31:0]                         req_data[THREAD_COUNT];
    logic [2:0]                          req_size;
    logic                                req_is_load;
    logic                                req_ready;

    // 响应
    logic                                resp_valid;
    logic [$clog2(WARP_COUNT)-1:0]       resp_warp_id;
    logic [THREAD_COUNT-1:0]             resp_mask;
    logic [31:0]                         resp_data[THREAD_COUNT];
    logic                                resp_ready;

    modport sm (
        output req_valid, req_warp_id, req_mask, req_addr, req_data, req_size, req_is_load,
        input  req_ready,
        input  resp_valid, resp_warp_id, resp_mask, resp_data,
        output resp_ready
    );

    modport ldst (
        input  req_valid, req_warp_id, req_mask, req_addr, req_data, req_size, req_is_load,
        output req_ready,
        output resp_valid, resp_warp_id, resp_mask, resp_data,
        input  resp_ready
    );

endinterface : interface_sm_ldst

`endif // RVGPU_INTERFACE_SM_LDST_SVH


