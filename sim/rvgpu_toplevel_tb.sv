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
`include "rvgpu_host_axi.svh"
`include "../test/common/rvgpu_clk_rst.svh"

`ifndef RVGPU_INTERNAL_NOC_PKG_IMPORTED
`define RVGPU_INTERNAL_NOC_PKG_IMPORTED
import rvgpu_internal_noc_pkg::*;
`endif // RVGPU_INTERNAL_NOC_PKG_IMPORTED

// DPI导入声明 - 从C++导入函数
import "DPI-C" context function void host_init();
import "DPI-C" context task host_run_test_case();
import "DPI-C" context function void host_cleanup();

// DPI导入声明 - 从C++导入GPU内存访问函数
import "DPI-C" context function void gpu_write_mem(input longint unsigned addr, input longint unsigned data);
import "DPI-C" context function longint unsigned gpu_read_mem(input longint unsigned addr);

module rvgpu_toplevel_tb;

    // 时钟和复位
    clk_rst_if clk_rst_if_inst();
    rvgpu_clk_manager clk_mgr;
    
    // GPU中断信号
    logic gpu_irq;

    rvgpu_host_axi host_axi;
    
    // Host接口实例
    host_if host_if_inst();
    
    // Memory接口实例数组
    memory_if mem_if [`L2CACHE_SLICE_NUMBER]();
    
    // 时钟生成器实例
    rvgpu_clk_rst_gen #(
        .CLK_PERIOD_NS(10), // 10ns周期=100MHz
        .RST_CYCLES(10)
    ) u_clk_gen (
        .clk_rst_if(clk_rst_if_inst)
    );
    
    // RVGPU顶层模块实例
    rvgpu_toplevel u_rvgpu_toplevel (
        .clk(clk_rst_if_inst.clk),
        .rst_n(clk_rst_if_inst.rst_n),
        .host_if(host_if_inst),
        .mem_if(mem_if),
        .gpu_irq(gpu_irq)
    );
    
    // 启动时钟周期计数
    initial begin
        fork
            clk_mgr.start_cycle_counting();
        join_none
    end

    task setup();
        clk_mgr = new("rvgpu_toplevel_tb", 100, 10);
        clk_mgr.initialize(clk_rst_if_inst);
        $display("@%0t: [TB] 时钟管理器初始化完成", $time);
        clk_mgr.display_status();

        host_axi = new(host_if_inst, clk_mgr);
    endtask
    
    initial begin
        setup();
    end
    
    // Host接口AXI写操作 - 通过host_if与RVGPU通信
    task cpu_axi_write(input longint unsigned addr, input longint unsigned data, input byte unsigned strb);
        host_axi.host_write(addr, data, strb);
    endtask
    
    // Host接口AXI读操作 - 通过host_if与RVGPU通信
    task cpu_axi_read_with_data(input longint unsigned addr, output longint unsigned data);
        host_axi.host_read(addr, data);
    endtask
    
    // DPI导出声明 - 导出给C++使用的host control接口
    export "DPI-C" task cpu_axi_write;
    export "DPI-C" task cpu_axi_read_with_data;
    export "DPI-C" task wait_gpu_irq;
    
    // GPU中断等待任务
    task wait_gpu_irq();
        @(posedge gpu_irq);
        $display("@%0t: [TB] 检测到GPU中断，等待完成", $time);
    endtask
    
    // GPU中断监控
    always @(posedge gpu_irq) begin
        $display("@%0t: [TB] GPU中断触发!", $time);
    end
    
    // GPU内存访问监控和处理
    genvar i;
    generate
        for (i = 0; i < `L2CACHE_SLICE_NUMBER; i = i + 1) begin : gpu_mem_monitor
            // GPU内存访问监控 - 简化版本，直接在响应处理中调用DPI
            always @(posedge clk_rst_if_inst.clk) begin
                // 监控GPU写请求
                if (mem_if[i].awvalid && mem_if[i].awready) begin
                    $display("@%0t: [TB] GPU写请求: slice=%0d, addr=0x%h", $time, i, mem_if[i].awaddr);
                end
                
                if (mem_if[i].wvalid && mem_if[i].wready) begin
                    // 调用C++接口写入内存
                    gpu_write_mem(mem_if[i].awaddr, mem_if[i].wdata[63:0]);
                    $display("@%0t: [TB] GPU写完成: slice=%0d, addr=0x%h, data=0x%h", $time, i, mem_if[i].awaddr, mem_if[i].wdata[63:0]);
                end
                
                // 监控GPU读请求
                if (mem_if[i].arvalid && mem_if[i].arready) begin
                    $display("@%0t: [TB] GPU读请求: slice=%0d, addr=0x%h", $time, i, mem_if[i].araddr);
                end
            end
            
            // AXI接口响应处理
            always @(posedge clk_rst_if_inst.clk) begin
                // 写地址通道
                mem_if[i].awready = 1'b1;
                
                // 写数据通道
                mem_if[i].wready = 1'b1;
                
                // 写响应通道 - 当检测到写请求时立即响应
                if (mem_if[i].awvalid && mem_if[i].wvalid && mem_if[i].bready) begin
                    mem_if[i].bresp = 2'b00; // OKAY
                    mem_if[i].bid = mem_if[i].awid;
                    mem_if[i].bvalid = 1'b1;
                end else begin
                    mem_if[i].bvalid = 1'b0;
                end
                
                // 读地址通道
                mem_if[i].arready = 1'b1;
                
                // 读数据通道 - 当检测到读请求时立即响应
                if (mem_if[i].arvalid && mem_if[i].rready) begin
                    // 调用C++接口读取内存并立即返回
                    mem_if[i].rdata = {192'h0, gpu_read_mem(mem_if[i].araddr)};
                    mem_if[i].rresp = 2'b00; // OKAY
                    mem_if[i].rid = mem_if[i].arid;
                    mem_if[i].rlast = 1'b1;
                    mem_if[i].rvalid = 1'b1;
                end else begin
                    mem_if[i].rvalid = 1'b0;
                end
            end
        end
    endgenerate
    
    // 测试主程序
    initial begin
        // 等待复位完成并确保时钟稳定
        clk_mgr.wait_clock_stable(5);
        
        $display("RVGPU顶层测试开始");
        
        // 初始化CPU模拟器
        host_init();
        
        // 运行测试套件
        host_run_test_case();
        
        // 清理
        host_cleanup();
        
        $display("RVGPU顶层测试完成");
        $finish;
    end
    
    // 波形输出
    initial begin
        $vcdpluson;
    end
    
    // 超时保护
    initial begin
        #1000000; // 1ms超时
        $display("测试超时!");
        $finish;
    end

endmodule : rvgpu_toplevel_tb

`endif // RVGPU_TOPLEVEL_TB_SV 