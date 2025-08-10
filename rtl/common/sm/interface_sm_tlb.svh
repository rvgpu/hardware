//=============================================================================
// Copyright © 2025 RVGPU Team
// Licensed under the Apache License, Version 2.0 (the "License");
//=============================================================================

`ifndef RVGPU_INTERFACE_SM_TLB_SVH
`define RVGPU_INTERFACE_SM_TLB_SVH

`include "rvgpu_typedef.svh"
`include "rvgpu_mmu_if.svh"

// L0 ICache <-> TLB 访问接口（精简版，对齐现有字段）
interface interface_sm_tlb;
    // 请求
    logic                req_valid;
    logic [38:0]         req_vaddr;
    mmu_access_type_e    req_type;
    logic [31:0]         req_warp_id;
    logic                req_ready;

    // 响应
    logic                resp_valid;
    logic                resp_hit;
    logic [26:0]         resp_ppn;
    logic                resp_fault;
    logic [31:0]         resp_warp_id;

    // requester视角（发请求，收响应）
    modport requester (
        output req_valid, req_vaddr, req_type, req_warp_id,
        input  req_ready,
        input  resp_valid, resp_hit, resp_ppn, resp_fault, resp_warp_id
    );

    // TLB视角（收请求，发响应）
    modport tlb (
        input  req_valid, req_vaddr, req_type, req_warp_id,
        output req_ready,
        output resp_valid, resp_hit, resp_ppn, resp_fault, resp_warp_id
    );

endinterface : interface_sm_tlb

`endif // RVGPU_INTERFACE_SM_TLB_SVH


