`timescale 1ns/1ps

`include "svunit_defines.svh"
`include "rvgpu_axi_adapter_test_base.svh"
`include "rvgpu_clk_rst.svh"
`include "rvgpu_axi_adapter.sv"

// SVUnit中模块名必须以_unit_test结尾
module ut_rvgpu_axi_adapter_basic_unit_test;
  import svunit_pkg::svunit_testcase;

  string name = "ut_rvgpu_axi_adapter_basic_unit_test";
  svunit_testcase svunit_ut;

  //===================================
  // Clock and Reset Infrastructure
  //===================================
  
  // Clock interface and generator
  clk_rst_if clk_rst_if();
  rvgpu_clk_rst_gen #(
    .CLK_PERIOD_NS(10.0), 
    .RST_CYCLES(10)
  ) clk_rst_gen (
    .clk_rst_if(clk_rst_if.master)
  );
  
  // Clock manager (elegant API)
  rvgpu_clk_manager clk_mgr;
  
  // Convenient signals for DUT connection
  wire clk = clk_rst_if.clk;
  wire rst_n = clk_rst_if.rst_n;

  //===================================
  // Interface Instances
  //===================================
  
  host_if #(.DATA_WIDTH(64), .ADDR_WIDTH(64)) axi_if();
  control_if #(.ADDR_WIDTH(64), .DATA_WIDTH(64)) ctrl_if();

  // DUT instance
  rvgpu_axi_adapter #(
    .ADDR_WIDTH(64),
    .DATA_WIDTH(64)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .axi_if(axi_if.slave),
    .ctrl_if(ctrl_if.axiadapter_port)
  );

  // Test base class instance
  rvgpu_axi_adapter_test_base test_base;

  //===================================
  // Test Variables (declared at module level)
  //===================================
  
  // Test data variables
  logic [63:0] test_addr;
  logic [63:0] test_data;
  
  // Clock manager test variables
  real freq_mhz;
  real period_ns;
  realtime start_time;
  realtime end_time;
  realtime elapsed_ns;

  //===================================
  // Build
  //===================================
  function void build();
    svunit_ut = new(name);
    
    // Initialize clock manager
    clk_mgr = new("axi_adapter_test_clk", 10.0, 10);
    clk_mgr.initialize(clk_rst_if);
    
    // Create test base with clock manager
    test_base = new(axi_if, ctrl_if, clk_rst_if, clk_mgr);
    
    
    $display("@%0t: Build completed", $time);
    clk_mgr.display_status();
  endfunction

  //===================================
  // Setup for running the Unit Tests
  //===================================
  task setup();
    svunit_ut.setup();
    
    // Initialize all signals
    test_base.initialize_signals();
    test_base.initialize_monitors();
    
    // Apply reset using clock manager
    clk_mgr.apply_reset();
    clk_mgr.wait_clock_stable(2);
    
    $display("@%0t: Setup completed", $time);
  endtask

  //===================================
  // Here we deconstruct anything we 
  // need after running the Unit Tests
  //===================================
  task teardown();
    svunit_ut.teardown();
    // Clear all signals
    test_base.clear_axi_write();
    test_base.clear_axi_read();
    test_base.clear_ctrl_response();
    
    $display("@%0t: Teardown completed", $time);
  endtask

  //===================================
  // SVUnit Compatibility Tasks (delegated to clock manager)
  //===================================
  
  task step(int cycles = 1);
    clk_mgr.step(cycles);
  endtask
  
  task nextSamplePoint();
    clk_mgr.nextSamplePoint();
  endtask
  
  task reset();
    clk_mgr.reset();
  endtask
  
  task pause();
    clk_mgr.pause();
  endtask

  //===================================
  // All tests are defined between the
  // SVUNIT_TESTS_BEGIN/END macros
  //
  // Each individual test must be
  // defined between `SVTEST(_NAME_)
  // and `SVTEST_END
  //
  // i.e.
  //   `SVTEST(mytest)
  //     <test code>
  //   `SVTEST_END
  //===================================
  `SVUNIT_TESTS_BEGIN

  `SVTEST(test_reset_state)
    $display("@%0t: Testing reset state", $time);
    
    // Apply reset
    reset();
    step(1);
    
    // Check that all interface signals are in reset state
    test_base.check_interface_reset_state();
    
    $display("@%0t: Reset state test completed", $time);
  `SVTEST_END

        `SVTEST(test_axi_write_basic)
     $display("@%0t: Testing basic AXI write", $time);
     
     // Test data
     test_addr = 64'h1000;
     test_data = 64'hDEADBEEFCAFEBABE;
     
     // Step 1: Send AXI write address
     clk_mgr.wait_clks(2);
     $display("@%0t: DUT write state before address: %0d", $time, dut.write_state_q);
     test_base.send_axi_write_addr(test_addr);
     $display("@%0t: DUT write state after address: %0d", $time, dut.write_state_q);
     
     // Step 2: Send AXI write data
     test_base.send_axi_write_data(test_data);
     clk_mgr.wait_clks(1);  // Wait for state machine to update
     $display("@%0t: DUT write state after data: %0d", $time, dut.write_state_q);
     
     // Step 3: Accept control request (DUT should send this after receiving write data)
     test_base.accept_ctrl_request();
     $display("@%0t: DUT write state after control request: %0d", $time, dut.write_state_q);
     
     // Step 4: Send control response (this should trigger AXI write response)
     clk_mgr.wait_clks(1);
     $display("@%0t: DUT write state before control response: %0d", $time, dut.write_state_q);
     $display("@%0t: ctrl_if.resp_ready before sending response: %b", $time, ctrl_if.resp_ready);
     $display("@%0t: ctrl_req_is_write: %b", $time, dut.ctrl_req_is_write);
     $display("@%0t: write_ctrl_req: %b", $time, dut.write_ctrl_req);
     test_base.send_ctrl_response(test_data);
     
     // Step 5: Accept AXI write response
     test_base.accept_axi_write_resp();
     
     $display("@%0t: Basic AXI write test completed", $time);
   `SVTEST_END

   `SVTEST(test_axi_read_basic)
     $display("@%0t: Testing basic AXI read", $time);
     
     // Test data
     test_addr = 64'h2000;
     test_data = 64'h123456789ABCDEF0;
     
     // Fork concurrent processes
     fork
       begin
         // Host side: Send AXI read transaction
         clk_mgr.wait_clks(2);
         test_base.send_axi_read_addr(test_addr);
         test_base.accept_axi_read_data();
       end
       
       begin
         // Control processor side: Handle the request
         test_base.accept_ctrl_request();
         clk_mgr.wait_clks(1);
         test_base.send_ctrl_response(test_data);
       end
     join
     
     $display("@%0t: Basic AXI read test completed", $time);
   `SVTEST_END

   `SVTEST(test_clock_manager_features)
     $display("@%0t: Testing clock manager features", $time);
     
     // Test clock manager utilities
     freq_mhz = clk_mgr.get_clock_freq_mhz();
     period_ns = clk_mgr.get_clock_period_ns();
     
     $display("@%0t: Clock frequency: %0.1f MHz", $time, freq_mhz);
     $display("@%0t: Clock period: %0.1f ns", $time, period_ns);
     
     // Verify expected values
     `FAIL_IF(freq_mhz != 100.0)
     `FAIL_IF(period_ns != 10.0)
     
     // Test waiting functions
     start_time = $realtime;
     clk_mgr.wait_clks(10);
     end_time = $realtime;
     elapsed_ns = end_time - start_time;
     
     $display("@%0t: Elapsed time for 10 cycles: %0.1f ns", $time, elapsed_ns);
     // Should be approximately 100ns (10 cycles * 10ns)
     `FAIL_IF(elapsed_ns < 95.0 || elapsed_ns > 105.0)
     
     // Test advanced features
     clk_mgr.measure_clock_period();
     
     // Test reset functionality
     `FAIL_IF(clk_mgr.is_in_reset())
     
     $display("@%0t: Clock manager features test completed", $time);
   `SVTEST_END

  `SVUNIT_TESTS_END

endmodule 