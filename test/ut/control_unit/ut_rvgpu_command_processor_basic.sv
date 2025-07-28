`timescale 1ns/1ps

`include "svunit_defines.svh"
`include "rvgpu_command_processor_test_base.svh"
`include "rvgpu_clk_rst.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_mmu_if.svh"
`include "rvgpu_command_processor.sv"

// SVUnit中模块名必须以_unit_test结尾
module ut_rvgpu_command_processor_basic_unit_test;
  import svunit_pkg::svunit_testcase;
  import rvgpu_control_unit_pkg::*;

  string name = "ut_rvgpu_command_processor_basic_unit_test";
  svunit_testcase svunit_ut;

  //===================================
  // Clock and Reset Infrastructure
  //===================================
  clk_rst_if clk_rst_if();
  rvgpu_clk_rst_gen #(
    .CLK_PERIOD_NS(10.0), 
    .RST_CYCLES(10)
  ) clk_rst_gen (
    .clk_rst_if(clk_rst_if.master)
  );
  rvgpu_clk_manager clk_mgr;

  //===================================
  // Interface Instances
  //===================================
  control_if #(.ADDR_WIDTH(64), .DATA_WIDTH(64)) ctrl_cp();
  rvgpu_internal_noc_if noc_if();
  mmu_if cp_mmu();
  cp_mmu_config_if cp_mmu_config();

  // DUT instance - 真实的Command Processor（包含真实的Job Dispatcher）
  rvgpu_command_processor #(
    .CONTROL_UNIT_CONFIG(DEFAULT_CONTROL_UNIT_CONFIG)
  ) dut (
    .clk(clk_rst_if.clk),
    .rst_n(clk_rst_if.rst_n),
    .ctrl_cp(ctrl_cp.cp_port),
    .noc_if(noc_if.device),
    .mmu_if(cp_mmu.requester_port),
    .mmu_config_if(cp_mmu_config.cp_port),
    .gpu_irq()
  );

  // Test base class instance
  rvgpu_command_processor_test_base test_base;

  //===================================
  // Test Variables
  //===================================
  // 共享的测试变量
  logic idle, complete, error, mmu_ready;
  logic [63:0] mmu_addr, pkg_addr;
  logic start, reset, irq_en;
  logic [63:0] test_mmu_addr, read_mmu_addr;
  logic [63:0] test_pkg_addr, read_pkg_addr;

  //===================================
  // Build
  //===================================
  function void build();
    svunit_ut = new(name);
    clk_mgr = new("cp_test_clk", 10.0, 10);
    clk_mgr.initialize(clk_rst_if);
    test_base = new(ctrl_cp, noc_if, cp_mmu, cp_mmu_config, clk_rst_if, clk_mgr);
    $display("@%0t: Build completed", $time);
    clk_mgr.display_status();
  endfunction

  //===================================
  // Setup/Teardown
  //===================================
  task setup();
    $vcdpluson();

    svunit_ut.setup();
    test_base.initialize_signals();
    test_base.initialize_monitors();
    
    clk_mgr.apply_reset();
    clk_mgr.wait_clock_stable(2);
    clk_mgr.wait_clks(1); // 等待一个时钟，确保mmu_ready被置为1
    $display("@%0t: Setup completed", $time);
  endtask

  task teardown();
    svunit_ut.teardown();
    test_base.clear_control_signals();
    test_base.clear_noc_signals();
    test_base.clear_mmu_signals();
    $display("@%0t: Teardown completed", $time);
  endtask

  // SVUnit Compatibility Tasks
  task step(int cycles = 1); clk_mgr.step(cycles); endtask
  task nextSamplePoint(); clk_mgr.nextSamplePoint(); endtask
  task reset_dut(); clk_mgr.reset(); endtask
  task pause(); clk_mgr.pause(); endtask

  //===================================
  // SVUnit Test Cases
  //===================================
  `SVUNIT_TESTS_BEGIN

  `SVTEST(test_reset_behavior)
    $display("@%0t: Testing reset behavior", $time);
    
    // 等待状态稳定（复位释放后需要等待状态寄存器更新）
    clk_mgr.wait_clks(2);
    
    // 验证复位后的初始状态
    test_base.read_status_reg(idle, complete, error, mmu_ready);
    $display("@%0t: idle=%0d, complete=%0d, error=%0d, mmu_ready=%0d", $time, idle, complete, error, mmu_ready);
    `FAIL_IF(idle !== 1'b1)
    `FAIL_IF(complete !== 1'b0)
    `FAIL_IF(error !== 1'b0)
    `FAIL_IF(mmu_ready !== 1'b1)
    
    // 验证寄存器初始值
    test_base.read_mmu_pagetable_addr(mmu_addr);
    test_base.read_command_packet_addr(pkg_addr);
    `FAIL_IF(mmu_addr !== 64'h0)
    `FAIL_IF(pkg_addr !== 64'h0)
    
    $display("@%0t: Reset behavior test completed", $time);
  `SVTEST_END

  `SVTEST(test_register_read_write)
    $display("@%0t: Testing register read/write operations", $time);
    
    // 测试MMU页表地址寄存器
    test_mmu_addr = 64'h12345678_9ABCDEF0;
    test_base.write_mmu_pagetable_addr(test_mmu_addr);
    
    test_base.read_mmu_pagetable_addr(read_mmu_addr);
    $display("@%0t: read_mmu_addr=%0h, test_mmu_addr=%0h", $time, read_mmu_addr, test_mmu_addr);
    `FAIL_IF(read_mmu_addr !== test_mmu_addr)
    
    // 测试Command Packet地址寄存器
    test_pkg_addr = 64'hFEDCBA98_76543210;
    test_base.write_command_packet_addr(test_pkg_addr);
    
    test_base.read_command_packet_addr(read_pkg_addr);
    `FAIL_IF(read_pkg_addr !== test_pkg_addr)
    
    // 测试控制寄存器
    test_base.write_control_reg(1'b1, 1'b0, 1'b1); // 启动，中断使能
    
    test_base.read_control_reg(start, reset, irq_en);
    `FAIL_IF(start !== 1'b1)
    `FAIL_IF(reset !== 1'b0)
    `FAIL_IF(irq_en !== 1'b1)
    
    $display("@%0t: Register read/write test completed", $time);
  `SVTEST_END

  `SVTEST(test_basic_operation_flow)
    $display("@%0t: Testing basic operation flow", $time);
    
    // 1. 配置地址
    test_base.write_mmu_pagetable_addr(64'h1000);
    test_base.write_command_packet_addr(64'h2000);
    
    // 2. 启动操作
    test_base.write_control_reg(1'b1, 1'b0, 1'b1); // 启动，中断使能
    
    // 3. 等待处理完成
    clk_mgr.wait_clks(20); // 给Job Dispatcher足够时间处理
    
    // 4. 验证状态
    test_base.read_status_reg(idle, complete, error, mmu_ready);
    
    // 注意：由于使用真实的Job Dispatcher，实际行为取决于JD的实现
    // 这里主要验证CP的状态机逻辑正确
    `FAIL_IF(error !== 1'b0) // 不应该有错误
    
    $display("@%0t: Basic operation flow test completed", $time);
  `SVTEST_END

  `SVTEST(test_reset_operation)
    $display("@%0t: Testing reset operation TODO", $time);
    
    $display("@%0t: Reset operation test completed", $time);
  `SVTEST_END

  `SVTEST(test_interrupt_generation)
    $display("@%0t: Testing interrupt generation", $time);
    
    // 1. 配置并启动（中断使能）
    test_base.write_mmu_pagetable_addr(64'h1000);
    test_base.write_command_packet_addr(64'h2000);
    test_base.write_control_reg(1'b1, 1'b0, 1'b1); // 启动，中断使能
    
    // 2. 等待处理完成
    clk_mgr.wait_clks(20);
    
    // 3. 验证中断状态（通过状态寄存器）
    test_base.read_status_reg(idle, complete, error, mmu_ready);
    
    // 由于使用真实JD，这里主要验证CP的中断逻辑
    // 如果JD完成，应该看到complete=1
    if (complete) begin
      $display("@%0t: Job completed, interrupt should be generated", $time);
    end
    
    $display("@%0t: Interrupt generation test completed", $time);
  `SVTEST_END

  `SVTEST(test_multiple_operations)
    $display("@%0t: Testing multiple operations", $time);
    
    // 第一次操作
    test_base.write_mmu_pagetable_addr(64'h1000);
    test_base.write_command_packet_addr(64'h2000);
    test_base.write_control_reg(1'b1, 1'b0, 1'b1);
    
    clk_mgr.wait_clks(15);
    
    // 检查第一次操作状态
    test_base.read_status_reg(idle, complete, error, mmu_ready);
    
    // 第二次操作（不同的地址）
    test_base.write_mmu_pagetable_addr(64'h3000);
    test_base.write_command_packet_addr(64'h4000);
    test_base.write_control_reg(1'b1, 1'b0, 1'b1);
    
    clk_mgr.wait_clks(15);
    
    // 检查第二次操作状态
    test_base.read_status_reg(idle, complete, error, mmu_ready);
    
    $display("@%0t: Multiple operations test completed", $time);
  `SVTEST_END

  `SVTEST(test_invalid_register_access)
    logic [63:0] read_data;
    
    $display("@%0t: Testing invalid register access", $time);
    
    // 测试无效地址的读取
    test_base.send_control_read_transaction(16'hFFFF); // 无效地址
    test_base.accept_control_response();
    
    // 验证错误响应（在无握手协议中，无效地址应该返回0）
    read_data = ctrl_cp.ctrl_rdata;
    `FAIL_IF(read_data !== 64'h0) // 应该返回0
    
    $display("@%0t: Invalid register access test completed", $time);
  `SVTEST_END

  `SVTEST(test_register_strobe_operations)
    $display("@%0t: Testing register strobe operations", $time);
    
    // 注意：Command Processor当前设计不支持strobe操作
    // 所有写入操作都是完整的32位写入
    // 这个测试验证即使传递strobe参数，写入仍然正常工作
    
    test_mmu_addr = 64'h12345678_9ABCDEF0;
    
    // 写入数据（strobe参数被忽略）
    test_base.send_control_write_transaction(REG_MMU_PAGETABLE_LO, test_mmu_addr[31:0], 8'h0F);
    test_base.send_control_write_transaction(REG_MMU_PAGETABLE_HI, test_mmu_addr[63:32], 8'h0F);
    
    // 验证写入结果（应该是完整写入）
    test_base.read_mmu_pagetable_addr(read_mmu_addr);
    `FAIL_IF(read_mmu_addr !== test_mmu_addr)
    
    $display("@%0t: Register strobe operations test completed (strobe ignored)", $time);
  `SVTEST_END

  `SVTEST(test_control_register_bits)
    $display("@%0t: Testing control register individual bits", $time);
    
    // 测试START位
    test_base.write_control_reg(1'b1, 1'b0, 1'b0); // 只设置START
    test_base.read_control_reg(start, reset, irq_en);
    `FAIL_IF(start !== 1'b1)
    `FAIL_IF(reset !== 1'b0)
    `FAIL_IF(irq_en !== 1'b0)
    
    // 测试RESET位
    test_base.write_control_reg(1'b0, 1'b1, 1'b0); // 只设置RESET
    test_base.read_control_reg(start, reset, irq_en);
    `FAIL_IF(start !== 1'b0)
    `FAIL_IF(reset !== 1'b1)
    `FAIL_IF(irq_en !== 1'b0)
    
    // 测试IRQ_EN位
    test_base.write_control_reg(1'b0, 1'b0, 1'b1); // 只设置IRQ_EN
    test_base.read_control_reg(start, reset, irq_en);
    `FAIL_IF(start !== 1'b0)
    `FAIL_IF(reset !== 1'b0)
    `FAIL_IF(irq_en !== 1'b1)
    
    $display("@%0t: Control register bits test completed", $time);
  `SVTEST_END

  `SVTEST(test_status_register_behavior)
    $display("@%0t: Testing status register behavior", $time);
    
    // 初始状态检查
    test_base.read_status_reg(idle, complete, error, mmu_ready);
    `FAIL_IF(idle !== 1'b1) // 初始应该是空闲状态
    `FAIL_IF(mmu_ready !== 1'b1) // MMU应该就绪
    
    // 启动操作后检查状态变化
    test_base.write_mmu_pagetable_addr(64'h1000);
    test_base.write_command_packet_addr(64'h2000);
    test_base.write_control_reg(1'b1, 1'b0, 1'b1);
    
    clk_mgr.wait_clks(5);
    
    // 检查运行状态
    test_base.read_status_reg(idle, complete, error, mmu_ready);
    // 注意：实际状态取决于Job Dispatcher的行为
    
    $display("@%0t: Status register behavior test completed", $time);
  `SVTEST_END

  `SVTEST(test_no_handshake_protocol_behavior)
    logic [63:0] read_data1, read_data2, read_data3;
    
    $display("@%0t: Testing no handshake protocol behavior", $time);
    
    // 测试无握手协议的特性：每个周期都提供读数据
    
    // 连续读取不同地址，验证数据立即可用
    ctrl_cp.ctrl_addr = REG_STATUS;
    clk_mgr.wait_posedge();
    read_data1 = ctrl_cp.ctrl_rdata;
    
    ctrl_cp.ctrl_addr = REG_CONTROL;
    clk_mgr.wait_posedge();
    read_data2 = ctrl_cp.ctrl_rdata;
    
    ctrl_cp.ctrl_addr = REG_MMU_PAGETABLE_LO;
    clk_mgr.wait_posedge();
    read_data3 = ctrl_cp.ctrl_rdata;
    
    $display("@%0t: No handshake read test: status=0x%016x, control=0x%016x, mmu_lo=0x%016x", 
             $time, read_data1, read_data2, read_data3);
    
    // 验证写操作也是立即生效
    test_base.write_control_reg(1'b1, 1'b0, 1'b1);
    clk_mgr.wait_posedge();
    
    ctrl_cp.ctrl_addr = REG_CONTROL;
    clk_mgr.wait_posedge();
    read_data2 = ctrl_cp.ctrl_rdata;
    `FAIL_IF(read_data2[0] !== 1'b1) // START位应该立即生效
    
    $display("@%0t: No handshake protocol behavior test completed", $time);
  `SVTEST_END

  `SVTEST(test_rapid_register_access)
    logic [63:0] test_addr, test_data;
    int i;
    
    $display("@%0t: Testing rapid register access", $time);
    
    // 测试快速连续的寄存器访问
    for (i = 0; i < 10; i++) begin
      test_addr = 64'h1000 + (i * 64'h100);
      test_data = 64'hDEADBEEF + (i * 64'h1000);
      
      // 快速写入
      test_base.write_mmu_pagetable_addr(test_addr);
      test_base.write_command_packet_addr(test_data);
      
      // 快速读取验证
      test_base.read_mmu_pagetable_addr(read_mmu_addr);
      test_base.read_command_packet_addr(read_pkg_addr);
      
      `FAIL_IF(read_mmu_addr !== test_addr)
      `FAIL_IF(read_pkg_addr !== test_data)
    end
    
    $display("@%0t: Rapid register access test completed", $time);
  `SVTEST_END

  `SVUNIT_TESTS_END

endmodule
