`timescale 1ns/1ps

`include "svunit_defines.svh"
`include "rvgpu_mmu_test_base.svh"
`include "rvgpu_clk_rst.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_mmu.sv"

// SVUnit中模块名必须以_unit_test结尾
module ut_rvgpu_mmu_basic_unit_test;
  import svunit_pkg::svunit_testcase;
  import rvgpu_control_unit_pkg::*;

  string name = "ut_rvgpu_mmu_basic_unit_test";
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
  mmu_if #(.VA_WIDTH(48), .PA_WIDTH(48)) mmu_if();
  rvgpu_internal_noc_if noc_if();

  // DUT instance - MMU
  rvgpu_mmu #(
    .CONTROL_UNIT_CONFIG(DEFAULT_CONTROL_UNIT_CONFIG)
  ) dut (
    .clk(clk_rst_if.clk),
    .rst_n(clk_rst_if.rst_n),
    .mmu_if(mmu_if.mmu_port),
    .noc_if(noc_if.device)
  );

  // Test base class instance
  rvgpu_mmu_test_base test_base;

  //===================================
  // Test Variables
  //===================================
  logic [47:0] vaddr, paddr;
  logic hit;
  logic [1:0] status;
  logic [47:0] page_table_base;
  logic [63:0] noc_addr;
  logic [15:0] noc_size;

  //===================================
  // Build
  //===================================
  function void build();
    svunit_ut = new(name);
    clk_mgr = new("mmu_test_clk", 10.0, 10);
    clk_mgr.initialize(clk_rst_if);
    test_base = new(mmu_if, noc_if, clk_rst_if, clk_mgr);
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
    test_base.clear_mmu_signals();
    test_base.clear_noc_signals();
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
    test_base.check_mmu_interface_reset_state();
    
    $display("@%0t: Reset behavior test completed", $time);
  `SVTEST_END

  `SVTEST(test_mmu_configuration)
    $display("@%0t: Testing MMU configuration", $time);
    
    // 测试MMU页表基地址配置
    page_table_base = 48'h100000000000;
    test_base.configure_mmu_page_table(page_table_base);
    
    clk_mgr.wait_clks(2);
    
    // 验证配置是否生效
    `FAIL_IF(mmu_if.cfg_en !== 1'b0)  // 配置信号应该已经清除
    
    $display("@%0t: MMU configuration test completed", $time);
  `SVTEST_END

  `SVTEST(test_basic_translation_request)
    $display("@%0t: Testing basic translation request", $time);
    
    // 配置MMU
    test_base.configure_mmu_page_table(39'h10000000);
    clk_mgr.wait_clks(2);
    
    // 发送翻译请求
    vaddr = 48'h000000001000;
    test_base.send_mmu_request(vaddr, 1'b1, 1'b0);
    
    // 启动线程等待MMU响应（在后台运行）
    fork
        test_base.wait_for_mmu_response(paddr, hit, status, 100);  // 增加到100个周期
    join_none
    
    // 第一次NOC请求（L1页表访问）
    test_base.wait_for_noc_request(noc_addr, noc_size, 100);  // 增加到100个周期
    test_base.send_noc_response({208'h0, 39'h20000000}, 2'b00, 8'h00);  // L2页表基地址
    
    // 第二次NOC请求（L2页表访问）
    test_base.wait_for_noc_request(noc_addr, noc_size, 100);  // 增加到100个周期
    test_base.send_noc_response({208'h0, 39'h30000000}, 2'b00, 8'h00);  // L3页表基地址
    
    // 第三次NOC请求（L3页表访问）
    test_base.wait_for_noc_request(noc_addr, noc_size, 100);  // 增加到100个周期
    test_base.send_noc_response({208'h0, 39'h40000000}, 2'b00, 8'h00);  // 物理页号
    
    // 等待MMU响应线程完成
    wait fork;
    
    // 验证响应
    `FAIL_IF(status !== 2'b00)  // 应该没有错误
    `FAIL_IF(paddr !== 48'h40000000)  // 验证物理地址
    
    $display("@%0t: Basic translation request test completed", $time);
  `SVTEST_END

  `SVTEST(test_tlb_hit_scenario)
    $display("@%0t: Testing TLB hit scenario", $time);
    
    // 配置MMU
    test_base.configure_mmu_page_table(39'h10000000);
    clk_mgr.wait_clks(2);
    
    // 第一次访问（TLB miss，会更新TLB）
    vaddr = 48'h000000002000;
    test_base.send_mmu_request(vaddr, 1'b1, 1'b0);
    
    // 启动线程等待MMU响应（在后台运行）
    fork
        test_base.wait_for_mmu_response(paddr, hit, status, 100);
    join_none
    
    // 等待NOC请求（页表访问）
    test_base.wait_for_noc_request(noc_addr, noc_size, 100);
    
    // 发送L1页表条目（包含L2页表基地址）
    // 64位页表条目格式：[63:12] = 下一级页表基地址, [11:0] = 标志位
    test_base.send_noc_response({208'h0, 39'h20000000}, 2'b00, 8'h00);
    
    // 等待第二次NOC请求（L2页表访问）
    test_base.wait_for_noc_request(noc_addr, noc_size, 100);
    
    // 发送L2页表条目（包含L3页表基地址）
    test_base.send_noc_response({208'h0, 39'h30000000}, 2'b00, 8'h00);
    
    // 等待第三次NOC请求（L3页表访问）
    test_base.wait_for_noc_request(noc_addr, noc_size, 100);
    
    // 发送L3页表条目（包含物理页号）
    test_base.send_noc_response({208'h0, 39'h40000000}, 2'b00, 8'h00);
    
    // 等待MMU响应线程完成
    wait fork;
    
    // 第二次访问相同地址（TLB hit）
    test_base.send_mmu_request(vaddr, 1'b1, 1'b0);
    test_base.wait_for_mmu_response(paddr, hit, status, 10);
    
    // 验证TLB hit
    `FAIL_IF(!hit)  // 应该是hit
    `FAIL_IF(paddr !== 39'h40000000)
    
    $display("@%0t: TLB hit scenario test completed", $time);
  `SVTEST_END

  `SVTEST(test_read_write_requests)
    $display("@%0t: Testing read/write requests", $time);
    
    // 配置MMU
    test_base.configure_mmu_page_table(39'h10000000);
    clk_mgr.wait_clks(2);
    
    // 测试读请求
    vaddr = 48'h000000003000;
    test_base.send_mmu_request(vaddr, 1'b1, 1'b0);
    
    // 启动线程等待MMU响应（在后台运行）
    fork
        test_base.wait_for_mmu_response(paddr, hit, status, 100);
    join_none
    
    // 第一次NOC请求（L1页表访问）
    test_base.wait_for_noc_request(noc_addr, noc_size, 100);
    test_base.send_noc_response({208'h0, 39'h20000000}, 2'b00, 8'h00);  // L2页表基地址
    
    // 第二次NOC请求（L2页表访问）
    test_base.wait_for_noc_request(noc_addr, noc_size, 100);
    test_base.send_noc_response({208'h0, 39'h30000000}, 2'b00, 8'h00);  // L3页表基地址
    
    // 第三次NOC请求（L3页表访问）
    test_base.wait_for_noc_request(noc_addr, noc_size, 100);
    test_base.send_noc_response({208'h0, 39'h40000000}, 2'b00, 8'h00);  // 物理页号
    
    // 等待MMU响应线程完成
    wait fork;
    
    // 验证读请求响应
    `FAIL_IF(status !== 2'b00)
    `FAIL_IF(paddr !== 39'h40000000)
    
    // 测试写请求
    vaddr = 48'h000000004000;
    test_base.send_mmu_request(vaddr, 1'b0, 1'b1);
    
    // 启动线程等待MMU响应（在后台运行）
    fork
        test_base.wait_for_mmu_response(paddr, hit, status, 100);
    join_none
    
    // 第一次NOC请求（L1页表访问）
    test_base.wait_for_noc_request(noc_addr, noc_size, 100);
    test_base.send_noc_response({208'h0, 39'h20000000}, 2'b00, 8'h00);  // L2页表基地址
    
    // 第二次NOC请求（L2页表访问）
    test_base.wait_for_noc_request(noc_addr, noc_size, 100);
    test_base.send_noc_response({208'h0, 39'h30000000}, 2'b00, 8'h00);  // L3页表基地址
    
    // 第三次NOC请求（L3页表访问）
    test_base.wait_for_noc_request(noc_addr, noc_size, 100);
    test_base.send_noc_response({208'h0, 39'h40000000}, 2'b00, 8'h00);  // 物理页号
    
    // 等待MMU响应线程完成
    wait fork;
    
    // 验证写请求响应
    `FAIL_IF(status !== 2'b00)
    `FAIL_IF(paddr !== 39'h40000000)
    
    $display("@%0t: Read/write requests test completed", $time);
  `SVTEST_END

  `SVTEST(test_multiple_requests)
    $display("@%0t: Testing multiple requests", $time);
    
    // 配置MMU
    test_base.configure_mmu_page_table(39'h10000000);
    clk_mgr.wait_clks(2);
    
    // 发送多个请求
    for (int i = 0; i < 4; i++) begin
      vaddr = 39'h000000010000 + (i * 39'h1000);
      test_base.send_mmu_request(vaddr, 1'b1, 1'b0);
      
      // 启动线程等待MMU响应（在后台运行）
      fork
          test_base.wait_for_mmu_response(paddr, hit, status, 100);
      join_none
      
      // 第一次NOC请求（L1页表访问）
      test_base.wait_for_noc_request(noc_addr, noc_size, 100);
      test_base.send_noc_response({208'h0, 39'h20000000}, 2'b00, 8'h00);  // L2页表基地址
      
      // 第二次NOC请求（L2页表访问）
      test_base.wait_for_noc_request(noc_addr, noc_size, 100);
      test_base.send_noc_response({208'h0, 39'h30000000}, 2'b00, 8'h00);  // L3页表基地址
      
      // 第三次NOC请求（L3页表访问）
      test_base.wait_for_noc_request(noc_addr, noc_size, 100);
      test_base.send_noc_response({208'h0, 39'h40000000}, 2'b00, 8'h00);  // 物理页号
      
      // 等待MMU响应线程完成
      wait fork;
      
      // 验证响应
      `FAIL_IF(status !== 2'b00)
      `FAIL_IF(paddr !== 39'h40000000)
    end
    
    $display("@%0t: Multiple requests test completed", $time);
  `SVTEST_END

  `SVTEST(test_error_handling)
    $display("@%0t: Testing error handling", $time);
    
    // 配置MMU
    test_base.configure_mmu_page_table(39'h10000000);
    clk_mgr.wait_clks(2);
    
    // 发送请求
    vaddr = 48'h000000005000;
    test_base.send_mmu_request(vaddr, 1'b1, 1'b0);
    
    // 等待NOC请求
    test_base.wait_for_noc_request(noc_addr, noc_size, 50);
    
    // 发送错误响应
    test_base.send_noc_response(256'h0, 2'b10, 8'h00);  // SLVERR
    
    // 等待MMU响应
    test_base.wait_for_mmu_response(paddr, hit, status, 50);
    
    // 验证错误状态
    `FAIL_IF(status !== 2'b10)  // 应该传播错误
    
    $display("@%0t: Error handling test completed", $time);
  `SVTEST_END

  `SVUNIT_TESTS_END

endmodule 