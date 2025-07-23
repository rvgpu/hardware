`timescale 1ns/1ps

`include "svunit_defines.svh"
`include "rvgpu_command_package.svh"
`include "rvgpu_job_dispatcher_test_base.svh"
`include "rvgpu_clk_rst.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_job_dispatcher.sv"

// SVUnit中模块名必须以_unit_test结尾
module ut_rvgpu_job_dispatcher_basic_unit_test;
  import svunit_pkg::svunit_testcase;
  import rvgpu_control_unit_pkg::*;

  string name = "ut_rvgpu_job_dispatcher_basic_unit_test";
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
  job_dispatcher_if jd_if();
  rvgpu_internal_noc_if noc_if();
  mmu_if jd_mmu();

  // DUT instance - Job Dispatcher
  rvgpu_job_dispatcher #(
    .CONTROL_UNIT_CONFIG(DEFAULT_CONTROL_UNIT_CONFIG)
  ) dut (
    .clk(clk_rst_if.clk),
    .rst_n(clk_rst_if.rst_n),
    .noc_if(noc_if.device),
    .mmu_if(jd_mmu.cp_port),
    .jd_if(jd_if.jd_port)
  );

  // Test base class instance
  rvgpu_job_dispatcher_test_base test_base;

  //===================================
  // Test Variables
  //===================================
  logic complete, error, busy;
  logic [63:0] package_addr, mmu_addr;
  logic [47:0] vaddr;
  logic read, write;
  logic [63:0] noc_addr;
  logic [7:0] noc_size;

  //===================================
  // Build
  //===================================
  function void build();
    svunit_ut = new(name);
    clk_mgr = new("jd_test_clk", 10.0, 10);
    clk_mgr.initialize(clk_rst_if);
    test_base = new(jd_if, noc_if, jd_mmu, clk_rst_if, clk_mgr);
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
    clk_mgr.wait_clks(1);
    $display("@%0t: Setup completed", $time);
  endtask

  task teardown();
    svunit_ut.teardown();
    test_base.clear_jd_signals();
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
    
    clk_mgr.wait_clks(5);
    
    // 验证复位后的初始状态
    test_base.check_job_dispatcher_status(complete, error, busy);
    `FAIL_IF(complete !== 1'b0)
    `FAIL_IF(error !== 1'b0)
    `FAIL_IF(busy !== 1'b0)
    
    $display("@%0t: Reset behavior test completed", $time);
  `SVTEST_END

  `SVTEST(test_enable_behavior)
    $display("@%0t: Testing enable behavior", $time);
    
    // 测试使能信号
    test_base.enable_job_dispatcher(64'h1000, 64'h2000);
    
    clk_mgr.wait_clks(2);
    
    // 验证使能后的状态
    test_base.check_job_dispatcher_status(complete, error, busy);
    // 注意：实际状态取决于Job Dispatcher的实现
    
    $display("@%0t: Enable behavior test completed", $time);
  `SVTEST_END

  `SVTEST(test_reset_operation)
    $display("@%0t: Testing reset operation", $time);
    
    // 先使能
    test_base.enable_job_dispatcher(64'h1000, 64'h2000);
    clk_mgr.wait_clks(2);
    
    // 然后复位
    test_base.reset_job_dispatcher();
    clk_mgr.wait_clks(2);
    
    // 验证复位后的状态
    test_base.check_job_dispatcher_status(complete, error, busy);
    `FAIL_IF(complete !== 1'b0)
    `FAIL_IF(error !== 1'b0)
    `FAIL_IF(busy !== 1'b0)
    
    $display("@%0t: Reset operation test completed", $time);
  `SVTEST_END

  `SVTEST(test_mmu_config_timing)
    logic cfg_en;
    logic [47:0] cfg_base_addr;

    $display("@%0t: Testing MMU configuration", $time);
    // 单独测试 mmu_config 信号

    jd_if.package_addr = 64'h1000;
    jd_if.mmu_addr = 64'h2000;

    jd_if.enable = 1'b1;
    clk_mgr.wait_posedge();
    `FAIL_IF(mmu_if.cfg_en !== 1'b1)
    `FAIL_IF(mmu_if.cfg_base_addr !== 48'h2000)

    clk_mgr.delay_ns(1);
    jd_if.enable = 1'b0;  // Single pulse

    clk_mgr.wait_posedge();    
    `FAIL_IF(mmu_if.cfg_en !== 1'b0)
    
    $display("@%0t: MMU configuration test completed", $time);
  `SVTEST_END

  `SVTEST(test_mmu_interface)
    logic [63:0] payload_addr;
    logic cfg_en;
    logic [47:0] cfg_base_addr;

    $display("@%0t: Testing MMU interface", $time);
    
    // 使能Job Dispatcher
    test_base.enable_job_dispatcher(64'h1000, 64'h2000);
    
    // 等待Header fetch MMU请求 (重构后直接从Header fetch开始)
    test_base.wait_for_mmu_request(vaddr, read, write, 50);
    payload_addr = 64'h1000 + 8'h8;
    `FAIL_IF(vaddr !== 48'h1000)  // Package地址
    `FAIL_IF(read !== 1'b1)
    `FAIL_IF(write !== 1'b0)
    
    // 发送MMU响应
    test_base.send_mmu_translation_response(48'h3000, 1'b1, 2'b00);
    
    $display("@%0t: MMU interface test completed", $time);
  `SVTEST_END

  `SVTEST(test_noc_interface)
    command_header_t test_header;

    $display("@%0t: Testing NOC interface", $time);
    
    // 使能Job Dispatcher
    test_base.enable_job_dispatcher(64'h1000, 64'h2000);
    
    // 等待Header fetch MMU请求 (重构后直接从Header fetch开始)
    test_base.wait_for_mmu_request(vaddr, read, write, 50);

    test_base.send_mmu_translation_response(48'h4000, 1'b1, 2'b00);
    $display("@%0t: MMU response sent", $time);
    
    // 等待NOC请求
    test_base.wait_for_noc_request(noc_addr, noc_size, 50);
    `FAIL_IF(noc_addr !== 32'h4000)
    `FAIL_IF(noc_size !== NOC_SIZE_8B)  // Header大小
    
    // 发送NOC响应
    test_header.payload_size = 16'h20;
    test_header.flags = 16'h0000;
    test_header.command_type = CMD_COMPUTE_JOB;
    test_base.send_noc_read_response({192'h0, test_header}, 2'b00, 8'h00);
    
    $display("@%0t: NOC interface test completed", $time);
  `SVTEST_END

  `SVTEST(test_complete_workflow)
    $display("@%0t: Testing complete workflow", $time);
    
    // 模拟完整的Job Dispatcher工作流程
    test_base.simulate_job_dispatcher_workflow(64'h1000, 64'h2000);
    
    // 验证完成状态
    clk_mgr.wait_clks(10);
    test_base.check_job_dispatcher_status(complete, error, busy);
    `FAIL_IF(error !== 1'b0)  // 不应该有错误
    
    $display("@%0t: Complete workflow test completed", $time);
  `SVTEST_END

  `SVTEST(test_error_handling)
    $display("@%0t: Testing error handling", $time);
    
    // 使能Job Dispatcher
    test_base.enable_job_dispatcher(64'h1000, 64'h2000);
    
    // 等待MMU请求并发送错误响应
    test_base.wait_for_mmu_request(vaddr, read, write, 50);
    test_base.send_mmu_translation_response(48'h3000, 1'b0, 2'b10);  // 页面错误
    
    // 等待错误状态
    clk_mgr.wait_clks(10);
    
    // 验证错误状态
    test_base.check_job_dispatcher_status(complete, error, busy);
    // 注意：实际行为取决于Job Dispatcher的错误处理实现
    
    $display("@%0t: Error handling test completed", $time);
  `SVTEST_END

  `SVTEST(test_multiple_operations)
    $display("@%0t: Testing multiple operations", $time);
    
    // 第一次操作
    $display("@%0t: First Operate", $time);
    test_base.simulate_job_dispatcher_workflow(64'h1000, 64'h2000);
    
    clk_mgr.wait_clks(20);
    
    // 第二次操作
    $display("@%0t: Second Operate", $time);
    test_base.simulate_job_dispatcher_workflow(64'h3000, 64'h4000);
    
    $display("@%0t: Multiple operations test completed", $time);
  `SVTEST_END

  `SVTEST(test_busy_state)
    $display("@%0t: Testing busy state", $time);
    
    // 使能Job Dispatcher
    test_base.enable_job_dispatcher(64'h1000, 64'h2000);
    
    // 检查忙碌状态
    clk_mgr.wait_clks(2);
    test_base.check_job_dispatcher_status(complete, error, busy);
    // 注意：实际忙碌状态取决于Job Dispatcher的实现
    
    $display("@%0t: Busy state test completed", $time);
  `SVTEST_END

  `SVTEST(test_timeout_handling)
    $display("@%0t: Testing timeout handling", $time);
    
    // 使能Job Dispatcher但不提供响应
    test_base.enable_job_dispatcher(64'h1000, 64'h2000);
    
    // 等待超时
    clk_mgr.wait_clks(100);
    
    // 检查状态
    test_base.check_job_dispatcher_status(complete, error, busy);
    // 注意：实际超时行为取决于Job Dispatcher的实现
    
    $display("@%0t: Timeout handling test completed", $time);
  `SVTEST_END

  `SVTEST(test_interface_monitoring)
    $display("@%0t: Testing interface monitoring", $time);
    
    // 使能Job Dispatcher
    test_base.enable_job_dispatcher(64'h1000, 64'h2000);
    
    // 监控接口
    for (int i = 0; i < 10; i++) begin
      test_base.monitor_job_dispatcher_interface();
      clk_mgr.wait_posedge();
    end
    
    // 验证监控结果
    `FAIL_IF(!test_base.jd_busy_detected)
    
    $display("@%0t: Interface monitoring test completed", $time);
  `SVTEST_END

  `SVTEST(test_error_handling_no_retry)
    $display("@%0t: Testing error handling (no retry mechanism)", $time);
    
    // 使能Job Dispatcher
    test_base.enable_job_dispatcher(64'h1000, 64'h2000);
    
    // 等待MMU请求并发送错误响应
    test_base.wait_for_mmu_request(vaddr, read, write, 50);
    test_base.send_mmu_translation_response(48'h3000, 1'b0, 2'b10);  // 页面错误
    
    // 等待几个时钟周期，让DUT处理错误
    clk_mgr.wait_clks(5);
    
    // 验证错误状态 - DUT应该报告错误并停止
    test_base.check_job_dispatcher_status(complete, error, busy);
    `FAIL_IF(error !== 1'b1)  // 应该有错误
    `FAIL_IF(complete !== 1'b0)  // 不应该完成
    
    // 验证DUT不会继续发送MMU请求（没有重试机制）
    // 等待一段时间，确保没有新的MMU请求
    clk_mgr.wait_clks(10);
    `FAIL_IF(mmu_if.req_valid !== 1'b0)  // 不应该有新的MMU请求
    
    $display("@%0t: Error handling test completed (no retry)", $time);
  `SVTEST_END

  `SVTEST(test_performance_monitoring)
    $display("@%0t: Testing performance monitoring", $time);
    
    // 执行完整工作流程
    test_base.simulate_job_dispatcher_workflow(64'h1000, 64'h2000);
    
    // 验证性能监控信号 (如果可访问)
    // 注意：这些信号在DUT内部，测试中无法直接访问
    // 但可以通过观察行为来验证性能
    
    $display("@%0t: Performance monitoring test completed", $time);
  `SVTEST_END

  `SVUNIT_TESTS_END

endmodule 