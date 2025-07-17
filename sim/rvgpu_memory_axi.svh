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

`ifndef RVGPU_MEMORY_AXI_SVH
`define RVGPU_MEMORY_AXI_SVH

`include "rvgpu_interface_axi.svh"
`include "../test/common/rvgpu_clk_rst.svh"

// DPI导入声明 - 从C++导入GPU内存访问函数
import "DPI-C" context function void gpu_write_mem(input longint unsigned addr, input longint unsigned data);
import "DPI-C" context function longint unsigned gpu_read_mem(input longint unsigned addr);

// 单个Memory Slice AXI操作类
class rvgpu_memory_axi;

    // 端口
    virtual memory_if mem_if;
    rvgpu_clk_manager clk_mgr;
    int slice_id;  // 当前slice的ID

    // 构造
    function new(virtual memory_if mem, rvgpu_clk_manager clk_mgr, int slice_id);
        this.mem_if = mem;
        this.clk_mgr = clk_mgr;
        this.slice_id = slice_id;
    endfunction

    task init();
        mem_if.arready = 1'b1;
        mem_if.awready = 1'b1;
        mem_if.wready = 1'b1;
        mem_if.bvalid = 1'b0;
        mem_if.rvalid = 1'b0;
    endtask

    task run();
        $display("@%0t: [MEM_AXI_SLICE%0d] 开始运行", $time, slice_id);
        forever begin
            clk_mgr.wait_posedge();
            handle_write_request();
            handle_read_request();
        end
    endtask

    task handle_write_request();
        if (mem_if.awvalid && mem_if.awready) begin
            $display("@%0t: [MEM_AXI_SLICE%0d] 写请求", $time, slice_id);
        end
    endtask

    task handle_read_request();
        if (mem_if.arvalid && mem_if.arready) begin
            logic [63:0] rdata;
            $display("@%0t: [MEM_AXI_SLICE%0d] 读请求", $time, slice_id);
            rdata = gpu_read_mem(mem_if.araddr);
            $display("@%0t: [MEM_AXI_SLICE%0d] 读请求完成, raddr=0x%h, rdata=0x%h", $time, slice_id, mem_if.araddr, rdata);
        end
    endtask
endclass

`endif // RVGPU_MEMORY_AXI_SVH 