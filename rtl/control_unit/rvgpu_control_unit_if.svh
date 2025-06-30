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

`ifndef RVGPU_CONTROL_UNIT_IF_SVH
`define RVGPU_CONTROL_UNIT_IF_SVH

//=============================================================================
// Control Unit Internal Interfaces
// 
// 控制单元内部模块间使用的Interface定义
// 命名规则：源模块_目标模块 (例如：adapter_cp, cp_mmu, cp_noc, mmu_noc)
//=============================================================================

//=============================================================================
// Control Interface - AXI Adapter ↔ Command Processor
// 用于AXI Adapter与Command Processor之间的寄存器访问
//=============================================================================
interface control_if #(
    parameter int ADDR_WIDTH = 64,
    parameter int DATA_WIDTH = 64
);
    // Request Channel
    logic                    req_valid;
    logic [ADDR_WIDTH-1:0]   req_addr;
    logic [DATA_WIDTH-1:0]   req_data;
    logic [7:0]              req_strb;
    logic                    req_we;
    logic                    req_ready;
    
    // Response Channel
    logic                    resp_valid;
    logic [DATA_WIDTH-1:0]   resp_data;
    logic [1:0]              resp_status;
    logic                    resp_ready;
    
    // Master modport (AXI Adapter side)
    modport master (
        output req_valid, req_addr, req_data, req_strb, req_we,
        input  req_ready,
        input  resp_valid, resp_data, resp_status,
        output resp_ready
    );
    
    // Slave modport (Command Processor side)
    modport slave (
        input  req_valid, req_addr, req_data, req_strb, req_we,
        output req_ready,
        output resp_valid, resp_data, resp_status,
        input  resp_ready
    );
endinterface : control_if

//=============================================================================
// MMU Interface - Command Processor ↔ MMU
// 用于Command Processor与MMU之间的地址转换请求
//=============================================================================
interface mmu_if #(
    parameter int VA_WIDTH = 48,
    parameter int PA_WIDTH = 48
);
    // Request Channel
    logic                    req_valid;
    logic [VA_WIDTH-1:0]     req_vaddr;
    logic                    req_read;
    logic                    req_write;
    logic                    req_ready;
    
    // Response Channel
    logic                    resp_valid;
    logic [PA_WIDTH-1:0]     resp_paddr;
    logic                    resp_hit;
    logic [1:0]              resp_status;
    logic                    resp_ready;
    
    // Master modport (Command Processor side)
    modport master (
        output req_valid, req_vaddr, req_read, req_write,
        input  req_ready,
        input  resp_valid, resp_paddr, resp_hit, resp_status,
        output resp_ready
    );
    
    // Slave modport (MMU side)
    modport slave (
        input  req_valid, req_vaddr, req_read, req_write,
        output req_ready,
        output resp_valid, resp_paddr, resp_hit, resp_status,
        input  resp_ready
    );
endinterface : mmu_if

`endif // RVGPU_CONTROL_UNIT_IF_SVH 