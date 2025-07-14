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

`ifndef RVGPU_TOPLEVEL_TB_SV
`define RVGPU_TOPLEVEL_TB_SV

`include "rvgpu_config.svh"
`include "rvgpu_interface_axi.svh"

`ifndef RVGPU_INTERNAL_NOC_PKG_IMPORTED
`define RVGPU_INTERNAL_NOC_PKG_IMPORTED
import rvgpu_internal_noc_pkg::*;
`endif // RVGPU_INTERNAL_NOC_PKG_IMPORTED

// DPI导入声明 - 从C++导入函数
import "DPI-C" context function void cpu_init();
import "DPI-C" context function void cpu_run_test_suite();
import "DPI-C" context function void cpu_test_array_add();
import "DPI-C" context function void cpu_cleanup();

module rvgpu_toplevel_tb;

    // 时钟和复位信号
    logic clk;
    logic rst_n;
    
    // 时钟周期计数
    int unsigned cycle_count;
    
    // Host接口实例
    host_if host_if_inst();
    
    // Memory接口实例数组 - 使用数组方式定义
    memory_if mem_if [`L2CACHE_SLICE_NUMBER]();
    
    // RVGPU顶层模块实例
    rvgpu_toplevel u_rvgpu_toplevel (
        .clk(clk),
        .rst_n(rst_n),
        .host_if(host_if_inst.slave),
        .mem_if(mem_if)
    );
    
    // 简单的内存模拟
    logic [63:0] memory [1024];
    logic [63:0] axi_read_data;
    
    // 时钟生成
    initial begin
        clk = 0;
        cycle_count = 0;
        
        forever begin
            #5 clk = ~clk;
            cycle_count++;
        end
    end
    
    // 复位生成
    initial begin
        rst_n = 0;
        #100;
        rst_n = 1;
    end
    
    // DPI函数实现 - 导出给C++使用
    export "DPI-C" function cpu_axi_write;
    export "DPI-C" function cpu_axi_write_done;
    export "DPI-C" function cpu_axi_read;
    export "DPI-C" function cpu_axi_read_data;
    export "DPI-C" function cpu_axi_read_done;
    export "DPI-C" task cpu_clock_cycle;
    export "DPI-C" function cpu_log;
    
    // AXI写操作
    function void cpu_axi_write(input logic [63:0] addr, input logic [63:0] data, input logic [7:0] strb);
        // 直接写入内存
        if (addr >= 64'h1000) begin
            memory[addr[15:3]] = data;
        end
        $display("[%0t] AXI写: addr=0x%h, data=0x%h", $time, addr, data);
    endfunction
    
    // AXI写完成检查
    function int cpu_axi_write_done();
        return 1; // 立即完成
    endfunction
    
    // AXI读操作
    function void cpu_axi_read(input logic [63:0] addr);
        // 读取内存
        if (addr >= 64'h1000) begin
            axi_read_data = memory[addr[15:3]];
        end else begin
            axi_read_data = 64'h0; // 寄存器默认值
        end
        $display("[%0t] AXI读: addr=0x%h, data=0x%h", $time, addr, axi_read_data);
    endfunction
    
    // AXI读数据获取
    function longint unsigned cpu_axi_read_data();
        return axi_read_data;
    endfunction
    
    // AXI读完成检查
    function int cpu_axi_read_done();
        return 1; // 立即完成
    endfunction
    
    // 时钟周期推进
    task cpu_clock_cycle();
        // 等待一个时钟周期
        @(posedge clk);
    endtask
    
    // 日志输出
    function void cpu_log(input string message);
        $display("[%0t] %s", $time, message);
    endfunction
    
    // 测试主程序
    initial begin
        // 等待复位完成
        wait (rst_n);
        #100;
        
        $display("RVGPU顶层测试开始");
        
        // 初始化CPU模拟器
        cpu_init();
        
        // 运行测试套件
        cpu_run_test_suite();
        
        // 清理
        cpu_cleanup();
        
        $display("RVGPU顶层测试完成");
        $finish;
    end
    
    // 波形输出
    initial begin
        $dumpfile("rvgpu_toplevel_tb.vcd");
        $dumpvars(0, rvgpu_toplevel_tb);
    end
    
    // 超时保护
    initial begin
        #1000000; // 1ms超时
        $display("测试超时!");
        $finish;
    end

endmodule : rvgpu_toplevel_tb

`endif // RVGPU_TOPLEVEL_TB_SV 