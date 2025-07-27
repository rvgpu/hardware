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

`include "rvgpu_axi_config.svh"

//=============================================================================
// Host Interface (AXI-Lite Slave)
//=============================================================================

interface host_if #(
    parameter host_axi_config_t HOST_CONFIG     = DEFAULT_HOST_AXI_CONFIG
);
    // Write Address Channel
    logic [HOST_CONFIG.addr_width-1:0]          awaddr;
    logic [7:0]                                 awlen;
    logic [2:0]                                 awsize;
    logic [1:0]                                 awburst;
    logic                                       awvalid;
    logic                                       awready;
    
    // Write Data Channel
    logic [HOST_CONFIG.data_width-1:0]          wdata;
    logic [HOST_CONFIG.strb_width-1:0]          wstrb;
    logic                                       wlast;
    logic                                       wvalid;
    logic                                       wready;
    
    // Write Response Channel
    logic [1:0]                                 bresp;
    logic                                       bvalid;
    logic                                       bready;
    
    // Read Address Channel
    logic [HOST_CONFIG.addr_width-1:0]          araddr;
    logic [7:0]                                 arlen;
    logic [2:0]                                 arsize;
    logic [1:0]                                 arburst;
    logic                                       arvalid;
    logic                                       arready;
    
    // Read Data Channel
    logic [HOST_CONFIG.data_width-1:0]          rdata;
    logic [1:0]                                 rresp;
    logic                                       rlast;
    logic                                       rvalid;
    logic                                       rready;
    
    // Master Port (Host)
    modport master (
        // Write Address
        output awaddr, awlen, awsize, awburst, awvalid,
        input  awready,
        // Write Data
        output wdata, wstrb, wlast, wvalid,
        input  wready,
        // Write Response,
        input  bresp, bvalid,
        output bready,
        // Read Address
        output araddr, arlen, arsize, arburst, arvalid,
        input  arready,
        // Read Data
        input  rdata, rresp, rlast, rvalid,
        output rready
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
        input  rready
    );
    
endinterface : host_if

//=============================================================================
// Memory Interface (AXI Master)
//=============================================================================

interface memory_if #(
    parameter memory_axi_config_t MEMORY_CONFIG     = DEFAULT_MEMORY_AXI_CONFIG
);
    // Write Address Channel
    logic [MEMORY_CONFIG.addr_width-1:0]            awaddr;
    logic [7:0]                                     awlen;
    logic [2:0]                                     awsize;
    logic [1:0]                                     awburst;
    logic [MEMORY_CONFIG.id_width-1:0]              awid;
    logic                                           awvalid;
    logic                                           awready;
    
    // Write Data Channel
    logic [MEMORY_CONFIG.data_width-1:0]            wdata;
    logic [MEMORY_CONFIG.strb_width-1:0]            wstrb;
    logic                                           wlast;
    logic                                           wvalid;
    logic                                           wready;
    
    // Write Response Channel
    logic [1:0]                                     bresp;
    logic [MEMORY_CONFIG.id_width-1:0]              bid;
    logic                                           bvalid;
    logic                                           bready;
    
    // Read Address Channel
    logic [MEMORY_CONFIG.addr_width-1:0]            araddr;
    logic [7:0]                                     arlen;
    logic [2:0]                                     arsize;
    logic [1:0]                                     arburst;
    logic [MEMORY_CONFIG.id_width-1:0]              arid;
    logic                                           arvalid;
    logic                                           arready;
    
    // Read Data Channel
    logic [MEMORY_CONFIG.data_width-1:0]            rdata;
    logic [1:0]                                     rresp;
    logic [MEMORY_CONFIG.id_width-1:0]              rid;
    logic                                           rlast;
    logic                                           rvalid;
    logic                                           rready;
    
    // Master Port (RVGPU)
    modport master (
        output awaddr, awlen, awsize, awburst, awid, awvalid,
        input  awready,
        output wdata, wstrb, wlast, wvalid,
        input  wready,
        input  bresp, bid, bvalid,
        output bready,
        output araddr, arlen, arsize, arburst, arid, arvalid,
        input  arready,
        input  rdata, rresp, rid, rlast, rvalid,
        output rready
    );
    
    // Slave Port (Memory)
    modport slave (
        input  awaddr, awlen, awsize, awburst, awid, awvalid,
        output awready,
        input  wdata, wstrb, wlast, wvalid,
        output wready,
        output bresp, bid, bvalid,
        input  bready,
        input  araddr, arlen, arsize, arburst, arid, arvalid,
        output arready,
        output rdata, rresp, rid, rlast, rvalid,
        input  rready
    );
    
endinterface : memory_if

`endif // RVGPU_INTERFACE_AXI_SVH