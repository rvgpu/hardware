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

`ifndef RVGPU_SRAM_IF_SVH
`define RVGPU_SRAM_IF_SVH

//=============================================================================
// RVGPU SRAM Interface
//=============================================================================

interface rvgpu_sram_if #(
    parameter int WIDTH             = 64,
    parameter int HEIGHT            = 64
);
    // 输出信号
    logic [WIDTH-1:0]               rdata;
    
    // 输入信号
    logic                           clk;
    logic                           ce;
    logic                           we;
    logic [$clog2(HEIGHT)-1:0]      addr;
    logic [WIDTH-1:0]               wdata;
    
    // Master modport
    modport access_port (
        input  clk, ce, we, addr, wdata,
        output rdata
    );
    
    // Slave modport
    modport sram_port (
        input  clk, ce, we, addr, wdata,
        output rdata
    );
    
    // 时钟绑定
    modport clk_mp (
        input  clk,
        input  ce, we, addr, wdata,
        output rdata
    );
    
endinterface : rvgpu_sram_if

`endif // RVGPU_SRAM_IF_SVH 