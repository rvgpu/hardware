//=============================================================================
// Copyright © 2025 RVGPU Team
// Licensed under the Apache License, Version 2.0 (the "License");
//=============================================================================

`ifndef RVGPU_INTERFACE_SM_ICACHE_FETCH_SVH
`define RVGPU_INTERFACE_SM_ICACHE_FETCH_SVH

`include "rvgpu_typedef.svh"

// Fetch <-> L0 ICache 取指接口
interface interface_sm_icache_fetch;
    // 请求
    logic        req_valid;
    logic [63:0] req_vaddr;
    logic        req_ready;

    // 响应
    logic        resp_valid;
    logic [31:0] resp_inst;

    // Fetch侧（发请求、收响应）
    modport fetch (
        output req_valid, req_vaddr,
        input  req_ready,
        input  resp_valid, resp_inst
    );

    // ICache侧（收请求、发响应）
    modport icache (
        input  req_valid, req_vaddr,
        output req_ready,
        output resp_valid, resp_inst
    );

endinterface : interface_sm_icache_fetch

`endif // RVGPU_INTERFACE_SM_ICACHE_FETCH_SVH


