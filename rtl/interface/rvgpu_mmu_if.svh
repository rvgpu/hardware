//=============================================================================
// Copyright © 2025 RVGPU Team
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//   
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//=============================================================================

`ifndef RVGPU_MMU_IF_SVH
`define RVGPU_MMU_IF_SVH

`include "rvgpu_constant.svh"

//=============================================================================
// MMU Interface - 基本的MMU请求/响应接口
// 用于地址转换请求和响应，不包含配置信号
//=============================================================================
interface mmu_if;
    localparam int VA_WIDTH = `RVGPU_CONST_CU_VA_WIDTH;
    localparam int PA_WIDTH = `RVGPU_CONST_CU_PA_WIDTH;

    // Request Channel
    logic                               req_valid;
    logic [VA_WIDTH-1:0]                req_vaddr;
    logic                               req_read;
    logic                               req_write;
    logic                               req_ready;
    
    // Response Channel
    logic                               resp_valid;
    logic [PA_WIDTH-1:0]                resp_paddr;
    logic                               resp_hit;
    logic [1:0]                         resp_status;
    logic                               resp_ready;
    
    // Requestor port (发起地址转换请求)
    modport requester_port (
        output req_valid, req_vaddr, req_read, req_write,
        input  req_ready,
        input  resp_valid, resp_paddr, resp_hit, resp_status,
        output resp_ready
    );
    
    // MMU port (执行地址转换)
    modport mmu_port (
        input  req_valid, req_vaddr, req_read, req_write,
        output req_ready,
        output resp_valid, resp_paddr, resp_hit, resp_status,
        input  resp_ready
    );
endinterface : mmu_if

//=============================================================================
// CP-MMU Config Interface - CP专用的MMU配置接口
// 专门用于Command Processor配置MMU的页表基地址等参数
//=============================================================================
interface cp_mmu_config_if;
    localparam int PA_WIDTH = `RVGPU_CONST_CU_PA_WIDTH;

    // Configuration Channel
    logic                               cfg_en;         // 配置使能
    logic [PA_WIDTH-1:0]                cfg_base_addr;  // 页表基地址
    
    // CP port (配置MMU)
    modport cp_port (
        output cfg_en, cfg_base_addr
    );
    
    // MMU port (接收配置)
    modport mmu_port (
        input cfg_en, cfg_base_addr
    );
endinterface : cp_mmu_config_if

`endif // RVGPU_MMU_IF_SVH
