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

`ifndef RVGPU_HOST_AXI_SVH
`define RVGPU_HOST_AXI_SVH

`include "rvgpu_interface_axi.svh"
`include "../test/common/rvgpu_clk_rst.svh"

// 简单AXI Host操作类
class rvgpu_host_axi;
    // 端口
    virtual host_if host;
    rvgpu_clk_manager clk_mgr;

    // 构造
    function new(virtual host_if host, rvgpu_clk_manager clk_mgr);
        this.host = host;
        this.clk_mgr = clk_mgr;
    endfunction

    // AXI写
    task host_write(longint unsigned addr, longint unsigned data, byte unsigned strb = 8'hFF);
        logic [1:0] bresp_status;
        clk_mgr.wait_posedge();
        host.awaddr  = addr;
        host.awlen   = 0;
        host.awsize  = 3;
        host.awburst = 2'b01;
        host.awvalid = 1;
        host.wdata   = data;
        host.wstrb   = strb;
        host.wlast   = 1;
        host.wvalid  = 1;
        host.bready  = 1;
        wait (host.awready && host.wready);
        clk_mgr.wait_posedge();
        host.awvalid = 0;
        host.wvalid  = 0;
        wait (host.bvalid);
        bresp_status = host.bresp;
        clk_mgr.wait_posedge();
        host.bready = 0;
        if (bresp_status != 2'b00)
            $display("@%0t: [HOST_AXI] WARNING: bresp=0x%h", $time, bresp_status);
    endtask

    // AXI读
    task host_read(longint unsigned addr, output longint unsigned data);
        logic [1:0] rresp_status;
        clk_mgr.wait_posedge();
        host.araddr  = addr;
        host.arlen   = 0;
        host.arsize  = 3;
        host.arburst = 2'b01;
        host.arvalid = 1;
        host.rready  = 1;
        wait (host.arready);
        clk_mgr.wait_posedge();
        host.arvalid = 0;
        wait (host.rvalid);
        data = host.rdata;
        rresp_status = host.rresp;
        clk_mgr.wait_posedge();
        host.rready = 0;
        if (rresp_status != 2'b00)
            $display("@%0t: [HOST_AXI] WARNING: rresp=0x%h", $time, rresp_status);
    endtask
endclass

`endif // RVGPU_HOST_AXI_SVH 