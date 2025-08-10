//=============================================================================
// Copyright © 2025 RVGPU Team
// Licensed under the Apache License, Version 2.0 (the "License");
//=============================================================================

`ifndef RVGPU_INTERFACE_SM_L15DATA_REQRESP_SVH
`define RVGPU_INTERFACE_SM_L15DATA_REQRESP_SVH

`include "rvgpu_typedef.svh"

// L1 Data Cache <-> L1.5 Cache 访问接口（数据侧，宽数据/掩码/ID）
interface interface_sm_l15data_reqresp #(
    parameter int REQ_DATA_W = 512,
    parameter int MASK_W     = 64,
    parameter int ID_W       = 32,
    parameter int SIZE_W     = 4
);
    // 请求
    logic                 req_valid;
    logic                 req_is_read;        // 1=read, 0=write
    logic [SIZE_W-1:0]    req_size;           // 2^n 字节
    logic [63:0]          req_paddr;
    logic [REQ_DATA_W-1:0]req_data;
    logic [MASK_W-1:0]    req_mask;
    logic [ID_W-1:0]      req_id;
    logic                 req_ready;

    // 响应
    logic                 resp_valid;
    logic [REQ_DATA_W-1:0]resp_data;
    logic                 resp_error;
    logic [ID_W-1:0]      resp_id;
    logic                 resp_ready;

    // requester视角（发请求，收响应）
    modport requester (
        output req_valid, req_is_read, req_size, req_paddr, req_data, req_mask, req_id,
        input  req_ready,
        input  resp_valid, resp_data, resp_error, resp_id,
        output resp_ready
    );

    // cache视角（收请求，发响应）
    modport cache (
        input  req_valid, req_is_read, req_size, req_paddr, req_data, req_mask, req_id,
        output req_ready,
        output resp_valid, resp_data, resp_error, resp_id,
        input  resp_ready
    );

endinterface : interface_sm_l15data_reqresp

`endif // RVGPU_INTERFACE_SM_L15DATA_REQRESP_SVH


