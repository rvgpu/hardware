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

`ifndef RVGPU_INTERFACE_AXI_SVH
`define RVGPU_INTERFACE_AXI_SVH

`include "rvgpu_config.svh"
`include "rvgpu_interface_axi.svh"
`include "rvgpu_types_toplevel_parameter.svh"

//=============================================================================
// Host Interface (AXI Slave)
//=============================================================================

interface host_if #(
    parameter int unsigned         DATA_WIDTH = 64,
    parameter int unsigned         ADDR_WIDTH = 64
);
    // Write Address Channel
    logic [ADDR_WIDTH-1:0]         awaddr;
    logic [7:0]                    awlen;
    logic [2:0]                    awsize;
    logic [1:0]                    awburst;
    logic                          awvalid;
    logic                          awready;
    
    // Write Data Channel
    logic [DATA_WIDTH-1:0]         wdata;
    logic [DATA_WIDTH/8-1:0]       wstrb;
    logic                          wlast;
    logic                          wvalid;
    logic                          wready;
    
    // Write Response Channel
    logic [1:0]                    bresp;
    logic                          bvalid;
    logic                          bready;
    
    // Read Address Channel
    logic [ADDR_WIDTH-1:0]         araddr;
    logic [7:0]                    arlen;
    logic [2:0]                    arsize;
    logic [1:0]                    arburst;
    logic                          arvalid;
    logic                          arready;
    
    // Read Data Channel
    logic [DATA_WIDTH-1:0]         rdata;
    logic [1:0]                    rresp;
    logic                          rlast;
    logic                          rvalid;
    logic                          rready;
    
    // Clock and Reset
    logic clk;
    logic rst_n;
    
    // Master Port (Host)
    modport master (
        output awaddr, awlen, awsize, awburst, awvalid,
        input  awready,
        output wdata, wstrb, wlast, wvalid,
        input  wready,
        input  bresp, bvalid,
        output bready,
        output araddr, arlen, arsize, arburst, arvalid,
        input  arready,
        input  rdata, rresp, rlast, rvalid,
        output rready,
        input  clk, rst_n
    );
    
    // Slave Port (RVGPU)
    modport slave (
        input  awaddr, awlen, awsize, awburst, awvalid,
        output awready,
        input  wdata, wstrb, wlast, wvalid,
        output wready,
        output bresp, bvalid,
        input  bready,
        input  araddr, arlen, arsize, arburst, arvalid,
        output arready,
        output rdata, rresp, rlast, rvalid,
        input  rready,
        input  clk, rst_n
    );
    
    // Clock Generation
    modport clocking (
        input  clk, rst_n
    );
    
endinterface : host_if

//=============================================================================
// Memory Interface (AXI Master)
//=============================================================================

interface memory_if #(
    parameter int unsigned         DATA_WIDTH = 256,
    parameter int unsigned         ADDR_WIDTH = 48
);
    // Write Address Channel
    logic [ADDR_WIDTH-1:0]         awaddr;
    logic [7:0]                    awlen;
    logic [2:0]                    awsize;
    logic [1:0]                    awburst;
    logic                          awvalid;
    logic                          awready;
    
    // Write Data Channel
    logic [DATA_WIDTH-1:0]         wdata;
    logic [DATA_WIDTH/8-1:0]       wstrb;
    logic                          wlast;
    logic                          wvalid;
    logic                          wready;
    
    // Write Response Channel
    logic [1:0]                    bresp;
    logic                          bvalid;
    logic                          bready;
    
    // Read Address Channel
    logic [ADDR_WIDTH-1:0]         araddr;
    logic [7:0]                    arlen;
    logic [2:0]                    arsize;
    logic [1:0]                    arburst;
    logic                          arvalid;
    logic                          arready;
    
    // Read Data Channel
    logic [DATA_WIDTH-1:0]         rdata;
    logic [1:0]                    rresp;
    logic                          rlast;
    logic                          rvalid;
    logic                          rready;
    
    // Clock and Reset
    logic clk;
    logic rst_n;
    
    // Master Port (RVGPU)
    modport master (
        output awaddr, awlen, awsize, awburst, awvalid,
        input  awready,
        output wdata, wstrb, wlast, wvalid,
        input  wready,
        input  bresp, bvalid,
        output bready,
        output araddr, arlen, arsize, arburst, arvalid,
        input  arready,
        input  rdata, rresp, rlast, rvalid,
        output rready,
        input  clk, rst_n
    );
    
    // Slave Port (Memory)
    modport slave (
        input  awaddr, awlen, awsize, awburst, awvalid,
        output awready,
        input  wdata, wstrb, wlast, wvalid,
        output wready,
        output bresp, bvalid,
        input  bready,
        input  araddr, arlen, arsize, arburst, arvalid,
        output arready,
        output rdata, rresp, rlast, rvalid,
        input  rready,
        input  clk, rst_n
    );
    
    // Clock Generation
    modport clocking (
        input  clk, rst_n
    );
    
endinterface : memory_if

`endif // RVGPU_INTERFACE_AXI_SVH 