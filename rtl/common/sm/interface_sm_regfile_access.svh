//=============================================================================
// Copyright © 2025 RVGPU Team
// Licensed under the Apache License, Version 2.0 (the "License");
//=============================================================================

`ifndef RVGPU_INTERFACE_SM_REGFILE_ACCESS_SVH
`define RVGPU_INTERFACE_SM_REGFILE_ACCESS_SVH

`include "rvgpu_typedef.svh"

// CUDA Core <-> RegFile 端口接口（单Core视角）
interface interface_sm_regfile_access #(
    parameter int WARP_COUNT = 32,
    parameter int THREAD_COUNT = 32
);
    // 读端口（每Core固定3个）
    logic                                read_enable[3];
    logic [$clog2(WARP_COUNT)-1:0]       read_warp_id[3];
    logic [4:0]                          read_reg_addr[3];
    logic [31:0]                         read_data[3][THREAD_COUNT];

    // 写端口（每Core 1个）
    logic                                write_enable;
    logic [$clog2(WARP_COUNT)-1:0]       write_warp_id;
    logic [4:0]                          write_reg_addr;
    logic [31:0]                         write_data[THREAD_COUNT];
    logic [THREAD_COUNT-1:0]             write_mask;

    // Core侧
    modport core (
        output read_enable, read_warp_id, read_reg_addr,
        input  read_data,
        output write_enable, write_warp_id, write_reg_addr, write_data, write_mask
    );

    // 汇聚到 regfile 扁平端口的适配侧（由 sm_top 使用）
    modport adapter (
        input  read_enable, read_warp_id, read_reg_addr,
        output read_data,
        input  write_enable, write_warp_id, write_reg_addr, write_data, write_mask
    );

endinterface : interface_sm_regfile_access

`endif // RVGPU_INTERFACE_SM_REGFILE_ACCESS_SVH


