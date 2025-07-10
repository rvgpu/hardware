//=============================================================================
// RVGPU DPI接口
// 用于C++与SystemVerilog仿真器的通信
//=============================================================================

`ifndef RVGPU_DPI_SV
`define RVGPU_DPI_SV

// DPI导入声明
import "DPI-C" function void rvgpu_dpi_init(input longint vram_size);
import "DPI-C" function void rvgpu_dpi_cleanup();
import "DPI-C" function int unsigned rvgpu_dpi_read_reg(input int unsigned addr);
import "DPI-C" function void rvgpu_dpi_write_reg(input int unsigned addr, input int unsigned data);
import "DPI-C" function byte rvgpu_dpi_read_mem(input longint addr);
import "DPI-C" function void rvgpu_dpi_write_mem(input longint addr, input byte data);
import "DPI-C" function void rvgpu_dpi_read_mem_block(input longint addr, output byte data[], input int unsigned size);
import "DPI-C" function void rvgpu_dpi_write_mem_block(input longint addr, input byte data[], input int unsigned size);
import "DPI-C" function bit rvgpu_dpi_get_irq_status();
import "DPI-C" function void rvgpu_dpi_clear_irq();
import "DPI-C" function void rvgpu_dpi_step(input int unsigned cycles);
import "DPI-C" function void rvgpu_dpi_run_until_idle();
import "DPI-C" function void rvgpu_dpi_reset();
import "DPI-C" function void rvgpu_dpi_set_debug_mode(input bit enable);

//=============================================================================
// RVGPU DPI包装器模块
//=============================================================================

module rvgpu_dpi_wrapper #(
    parameter longint VRAM_SIZE = 256 * 1024 * 1024  // 256MB
) (
    input  logic        clk,
    input  logic        rst_n,
    
    // 寄存器接口
    input  logic [31:0] reg_addr,
    input  logic [31:0] reg_wdata,
    input  logic        reg_wen,
    output logic [31:0] reg_rdata,
    input  logic        reg_ren,
    
    // 内存接口
    input  logic [63:0] mem_addr,
    input  logic [7:0]  mem_wdata,
    input  logic        mem_wen,
    output logic [7:0]  mem_rdata,
    input  logic        mem_ren,
    
    // 中断接口
    output logic        irq,
    
    // 调试接口
    input  logic        debug_enable
);

    // 内部状态
    logic initialized = 0;
    
    // 初始化
    initial begin
        rvgpu_dpi_init(VRAM_SIZE);
        initialized = 1;
        $display("RVGPU DPI wrapper initialized with %0d MB VRAM", VRAM_SIZE / (1024*1024));
    end
    
    // 清理
    final begin
        rvgpu_dpi_cleanup();
        $display("RVGPU DPI wrapper cleaned up");
    end
    
    // 寄存器访问
    always_ff @(posedge clk) begin
        if (reg_wen && initialized) begin
            rvgpu_dpi_write_reg(reg_addr, reg_wdata);
        end
    end
    
    always_comb begin
        if (reg_ren && initialized) begin
            reg_rdata = rvgpu_dpi_read_reg(reg_addr);
        end else begin
            reg_rdata = 32'h0;
        end
    end
    
    // 内存访问
    always_ff @(posedge clk) begin
        if (mem_wen && initialized) begin
            rvgpu_dpi_write_mem(mem_addr, mem_wdata);
        end
    end
    
    always_comb begin
        if (mem_ren && initialized) begin
            mem_rdata = rvgpu_dpi_read_mem(mem_addr);
        end else begin
            mem_rdata = 8'h0;
        end
    end
    
    // 中断状态
    always_comb begin
        if (initialized) begin
            irq = rvgpu_dpi_get_irq_status();
        end else begin
            irq = 1'b0;
        end
    end
    
    // 调试模式设置
    always_ff @(posedge clk) begin
        if (debug_enable) begin
            rvgpu_dpi_set_debug_mode(1'b1);
        end
    end
    
    // 仿真控制
    always_ff @(posedge clk) begin
        if (!rst_n && initialized) begin
            rvgpu_dpi_reset();
        end
    end

endmodule : rvgpu_dpi_wrapper

//=============================================================================
// RVGPU DPI测试模块
//=============================================================================

module rvgpu_dpi_test #(
    parameter longint VRAM_SIZE = 256 * 1024 * 1024
) (
    input  logic clk,
    input  logic rst_n
);

    // 测试信号
    logic [31:0] test_reg_addr;
    logic [31:0] test_reg_wdata;
    logic        test_reg_wen;
    logic [31:0] test_reg_rdata;
    logic        test_reg_ren;
    
    logic [63:0] test_mem_addr;
    logic [7:0]  test_mem_wdata;
    logic        test_mem_wen;
    logic [7:0]  test_mem_rdata;
    logic        test_mem_ren;
    
    logic        test_irq;
    logic        test_debug_enable;
    
    // 实例化DPI包装器
    rvgpu_dpi_wrapper #(
        .VRAM_SIZE(VRAM_SIZE)
    ) u_rvgpu_dpi_wrapper (
        .clk(clk),
        .rst_n(rst_n),
        .reg_addr(test_reg_addr),
        .reg_wdata(test_reg_wdata),
        .reg_wen(test_reg_wen),
        .reg_rdata(test_reg_rdata),
        .reg_ren(test_reg_ren),
        .mem_addr(test_mem_addr),
        .mem_wdata(test_mem_wdata),
        .mem_wen(test_mem_wen),
        .mem_rdata(test_mem_rdata),
        .mem_ren(test_mem_ren),
        .irq(test_irq),
        .debug_enable(test_debug_enable)
    );
    
    // 测试序列
    initial begin
        // 等待初始化
        wait(u_rvgpu_dpi_wrapper.initialized);
        
        // 测试寄存器写入
        @(posedge clk);
        test_reg_addr = 32'h0010;  // CONTROL寄存器
        test_reg_wdata = 32'h00000001;  // START位
        test_reg_wen = 1'b1;
        @(posedge clk);
        test_reg_wen = 1'b0;
        
        // 测试寄存器读取
        @(posedge clk);
        test_reg_addr = 32'h0014;  // STATUS寄存器
        test_reg_ren = 1'b1;
        @(posedge clk);
        test_reg_ren = 1'b0;
        
        // 测试内存写入
        @(posedge clk);
        test_mem_addr = 64'h1000;
        test_mem_wdata = 8'hAB;
        test_mem_wen = 1'b1;
        @(posedge clk);
        test_mem_wen = 1'b0;
        
        // 测试内存读取
        @(posedge clk);
        test_mem_addr = 64'h1000;
        test_mem_ren = 1'b1;
        @(posedge clk);
        test_mem_ren = 1'b0;
        
        // 等待一段时间
        repeat(100) @(posedge clk);
        
        $display("RVGPU DPI test completed");
        $finish;
    end

endmodule : rvgpu_dpi_test

`endif // RVGPU_DPI_SV 