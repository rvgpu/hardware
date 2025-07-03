`timescale 1ns/1ps

`include "svunit_defines.svh"
`include "rvgpu_axi_adapter_test_base.svh"
`include "rvgpu_clk_rst.svh"
`include "rvgpu_axi_adapter.sv"

module ut_rvgpu_axi_adapter_data_unit_test;
  import svunit_pkg::svunit_testcase;

  string name = "ut_rvgpu_axi_adapter_data_tests";
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

  // DUT Instance
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
  // Build
  //===================================
  function void build();
    svunit_ut = new(name);
    
    // Initialize clock manager
    clk_mgr = new("axi_adapter_data_test_clk", 10.0, 10);
    clk_mgr.initialize(clk_rst_if);
    
    // Create test base with clock manager
    test_base = new(axi_if, ctrl_if, clk_rst_if, clk_mgr);
    
    $display("@%0t: Data tests build completed", $time);
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
    
    $display("@%0t: Data tests setup completed", $time);
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
    
    $display("@%0t: Data tests teardown completed", $time);
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
  // Data Monitoring
  //===================================

  // Monitor control interface for data transmission
  always @(posedge clk) begin
    if (ctrl_if.req_valid && ctrl_if.req_ready) begin
      // Capture control request data based on operation type
      if (ctrl_if.req_we) begin
        // Write operation
        test_base.captured_write_trans.addr <= ctrl_if.req_addr;
        test_base.captured_write_trans.data <= ctrl_if.req_data;
        test_base.captured_write_trans.strb <= ctrl_if.req_strb;
        $display("@%0t: Monitor - Captured WRITE request: addr=0x%016x, data=0x%016x, strb=0x%02x", 
                 $time, ctrl_if.req_addr, ctrl_if.req_data, ctrl_if.req_strb);
      end else begin
        // Read operation
        test_base.captured_read_trans.addr <= ctrl_if.req_addr;
        test_base.captured_read_trans.data <= ctrl_if.req_data;
        test_base.captured_read_trans.strb <= ctrl_if.req_strb;
        $display("@%0t: Monitor - Captured READ request: addr=0x%016x, data=0x%016x, strb=0x%02x", 
                 $time, ctrl_if.req_addr, ctrl_if.req_data, ctrl_if.req_strb);
      end
      test_base.ctrl_req_detected <= 1'b1;
    end else begin
      test_base.ctrl_req_detected <= 1'b0;
    end

    if (ctrl_if.resp_valid && ctrl_if.resp_ready) begin
      test_base.captured_read_trans.data <= ctrl_if.resp_data;
      test_base.captured_read_trans.resp <= ctrl_if.resp_status;
      test_base.ctrl_resp_detected <= 1'b1;
    end else begin
      test_base.ctrl_resp_detected <= 1'b0;
    end
  end

  //===================================
  // Helper Tasks
  //===================================

  // Complete write transaction with data verification
  task complete_write_transaction_verify(logic [63:0] addr, logic [63:0] data, logic [7:0] strb);
    // Clear previous detection
    test_base.ctrl_req_detected = 1'b0;
    
    // Step 1: Send AXI write address
    clk_mgr.wait_clks(2);
    test_base.send_axi_write_addr(addr);
    
    // Step 2: Send AXI write data
    test_base.send_axi_write_data(data, strb);
    clk_mgr.wait_clks(1);  // Wait for state machine to update
    
    // Step 3: Accept control request (DUT should send this after receiving write data)
    test_base.accept_ctrl_request();
    
    // Step 4: Verify data integrity
    test_base.verify_ctrl_request(addr, data, strb, 1'b1);
    
    // Step 5: Send control response (this should trigger AXI write response)
    clk_mgr.wait_clks(1);
    test_base.send_ctrl_response(64'h0, 2'b00);
    
    // Step 6: Accept AXI write response
    test_base.accept_axi_write_resp();
    
    // Clear signals
    test_base.clear_axi_write();
    test_base.clear_ctrl_response();
    clk_mgr.wait_clks(1);
    
    $display("@%0t: Write transaction completed and verified: addr=0x%016x, data=0x%016x, strb=0x%02x", 
             $time, addr, data, strb);
  endtask

  // Complete read transaction with data verification
  task complete_read_transaction_verify(logic [63:0] addr, logic [63:0] expected_data);
    // Clear previous detection
    test_base.ctrl_req_detected = 1'b0;
    test_base.ctrl_resp_detected = 1'b0;
    
    // Step 1: Send AXI read address
    clk_mgr.wait_clks(2);
    test_base.send_axi_read_addr(addr);
    clk_mgr.wait_clks(1);  // Wait for state machine to update
    
    // Step 2: Accept control request (DUT should send this after receiving read address)
    test_base.accept_ctrl_request();
    
    // Step 3: Verify request address
    test_base.verify_ctrl_request(addr, 64'h0, 8'hFF, 1'b0);
    
    // Step 4: Send control response (this should trigger AXI read data)
    clk_mgr.wait_clks(1);
    test_base.send_ctrl_response(expected_data, 2'b00);
    
    // Step 5: Wait for DUT to enter R_DATA state before accepting read data
    while (dut.read_state_q !== dut.R_DATA) begin
      clk_mgr.wait_clks(1);
      nextSamplePoint();
    end
    
    // Step 6: Accept AXI read data
    test_base.accept_axi_read_data();
    
    // Step 7: Verify read data
    test_base.verify_axi_read_data(expected_data, 2'b00);
    
    // Clear signals
    test_base.clear_axi_read();
    test_base.clear_ctrl_response();
    clk_mgr.wait_clks(1);
    
    $display("@%0t: Read transaction completed and verified: addr=0x%016x, data=0x%016x", 
             $time, addr, expected_data);
  endtask

  // Test data pattern with both write and read (separate tests)
  task test_data_pattern_roundtrip(string pattern_name, logic [63:0] addr, logic [63:0] data, logic [7:0] strb);
    $display("Testing %s pattern: addr=0x%016x, data=0x%016x, strb=0x%02x", 
             pattern_name, addr, data, strb);
    
    // Write data (test write protocol conversion)
    complete_write_transaction_verify(addr, data, strb);
    step(5);
    
    // Read data (test read protocol conversion with different data)
    // Note: AXI adapter is just a protocol converter, it doesn't store data
    // So we test read with the same data that we send in control response
    complete_read_transaction_verify(addr, data);
    step(5);
    
    $display("%s pattern test completed successfully", pattern_name);
  endtask

  //===================================
  // Test Cases
  //===================================
  `SVUNIT_TESTS_BEGIN
    
    //=================================
    // Test Comprehensive Data Patterns
    //=================================
    `SVTEST(test_comprehensive_data_patterns)
      $display("============== 1. Testing Comprehensive Data Patterns ==============");
      test_base.initialize_signals();
      step(5);
      
      // Test all data patterns with different addresses and strobes
      for (int data_idx = 0; data_idx < 8; data_idx++) begin
        for (int addr_idx = 0; addr_idx < 4; addr_idx++) begin  // Test subset of addresses
          for (int strb_idx = 0; strb_idx < 4; strb_idx++) begin  // Test subset of strobes
            string pattern_name = $sformatf("data_pattern_%0d_addr_%0d_strb_%0d", data_idx, addr_idx, strb_idx);
            
            test_data_pattern_roundtrip(
              pattern_name,
              test_base.test_addr_patterns[addr_idx],
              test_base.test_data_patterns[data_idx],
              test_base.test_strb_patterns[strb_idx]
            );
          end
        end
      end
      
      $display("============== 1. Comprehensive data patterns test PASSED ==============");
    `SVTEST_END
    
    //=================================
    // Test Write Data Integrity
    //=================================
    `SVTEST(test_write_data_integrity)
      // Test specific challenging data patterns
      logic [63:0] test_addresses[4];
      logic [63:0] challenging_data[8];
      logic [7:0] challenging_strobes[8];
      
      $display("============== 2. Testing Write Data Integrity ==============");
      test_base.initialize_signals();
      step(5);
      
      // Initialize test addresses
      test_addresses[0] = 64'h0000000000000000;  // Base address
      test_addresses[1] = 64'h0000000000001000;  // 4KB aligned
      test_addresses[2] = 64'h8000000000000008;  // Unaligned with high bit
      test_addresses[3] = 64'hFFFFFFFFFFFFFFF8;  // Near max address
      
      // Initialize challenging data patterns
      challenging_data[0] = 64'h0000000000000001;  // Single bit
      challenging_data[1] = 64'h8000000000000000;  // MSB only
      challenging_data[2] = 64'h7FFFFFFFFFFFFFFF;  // All bits except MSB
      challenging_data[3] = 64'hFFFFFFFFFFFFFFFF;  // All ones
      challenging_data[4] = 64'h0123456789ABCDEF;  // Incrementing pattern
      challenging_data[5] = 64'hFEDCBA9876543210;  // Decrementing pattern
      challenging_data[6] = 64'hAAAAAAAAAAAAAAAA;  // Alternating 1010
      challenging_data[7] = 64'h5555555555555555;  // Alternating 0101
      
      // Initialize challenging strobes
      challenging_strobes[0] = 8'h01;  // Single byte
      challenging_strobes[1] = 8'h80;  // Last byte only
      challenging_strobes[2] = 8'hC0;  // Two MSBs
      challenging_strobes[3] = 8'h03;  // Two LSBs
      challenging_strobes[4] = 8'hAA;  // Alternating pattern
      challenging_strobes[5] = 8'h55;  // Inverse alternating
      challenging_strobes[6] = 8'hF0;  // Upper half
      challenging_strobes[7] = 8'h0F;  // Lower half
      
      // Test each combination
      for (int i = 0; i < 4; i++) begin
        for (int j = 0; j < 8; j++) begin
          for (int k = 0; k < 8; k++) begin
            string test_name = $sformatf("write_integrity_addr_%0d_data_%0d_strb_%0d", i, j, k);
            
            complete_write_transaction_verify(
              test_addresses[i],
              challenging_data[j], 
              challenging_strobes[k]
            );
          end
        end
      end
      
      $display("============== 2. Write data integrity test PASSED ==============");
    `SVTEST_END
    
    //=================================
    // Test Read Data Integrity
    //=================================
    `SVTEST(test_read_data_integrity)
      // Test read data integrity with various response data
      logic [63:0] response_data[8];
      
      $display("============== 3. Testing Read Data Integrity ==============");
      test_base.initialize_signals();
      step(5);
      
      // Initialize response data patterns
      response_data[0] = 64'h0000000000000000;  // Zero data
      response_data[1] = 64'hFFFFFFFFFFFFFFFF;  // Max data
      response_data[2] = 64'h0F0F0F0F0F0F0F0F;  // Nibble pattern
      response_data[3] = 64'hF0F0F0F0F0F0F0F0;  // Inverse nibble
      response_data[4] = 64'h00FF00FF00FF00FF;  // Byte pattern
      response_data[5] = 64'hFF00FF00FF00FF00;  // Inverse byte
      response_data[6] = 64'hDEADBEEFCAFEBABE;  // Known pattern 1
      response_data[7] = 64'h123456789ABCDEF0;  // Known pattern 2
      
      for (int addr_idx = 0; addr_idx < 8; addr_idx++) begin
        for (int data_idx = 0; data_idx < 8; data_idx++) begin
          string test_name = $sformatf("read_integrity_addr_%0d_data_%0d", addr_idx, data_idx);
          
          complete_read_transaction_verify(
            test_base.test_addr_patterns[addr_idx],
            response_data[data_idx]
          );
        end
      end
      
      $display("============== 3. Read data integrity test PASSED ==============");
    `SVTEST_END
    
    //=================================
    // Test Concurrent Transaction Data Integrity
    //=================================
    `SVTEST(test_concurrent_transaction_data_integrity)
      // Test data integrity when read and write operations are interleaved
      logic [63:0] write_addr;
      logic [63:0] write_data;
      logic [7:0] write_strb;
      logic [63:0] read_addr;
      logic [63:0] read_data;
      
      $display("============== 4. Testing Concurrent Transaction Data Integrity ==============");
      test_base.initialize_signals();
      step(5);
      
      // Initialize test data
      write_addr = 64'h1000;
      write_data = 64'hDEADBEEFCAFEBABE;
      write_strb = 8'hFF;
      read_addr = 64'h2000;
      read_data = 64'h123456789ABCDEF0;
      
      // Step 1: Send AXI write address and data
      test_base.send_axi_write_addr(write_addr);
      test_base.send_axi_write_data(write_data, write_strb);
      
      // Step 2: Send AXI read address (concurrent with write)
      $display("@%0t: Sending AXI read address: 0x%016x", $time, read_addr);
      
      // Set control interface ready BEFORE sending read address
      ctrl_if.req_ready = 1'b1;
      $display("@%0t: Set ctrl_if.req_ready = 1", $time);
      
      test_base.send_axi_read_addr(read_addr);
      
      // Step 3: Wait for write control request to be processed
      // First wait one clock cycle for the monitoring logic to update
      step(1);
      nextSamplePoint();
      
      // Debug: Check DUT states
      $display("@%0t: Debug - Write state: %0d, Read state: %0d", $time, dut.write_state_q, dut.read_state_q);
      $display("@%0t: Debug - ctrl_if.req_valid: %b, ctrl_if.req_ready: %b", $time, ctrl_if.req_valid, ctrl_if.req_ready);
      
      // Wait for DUT to enter W_CTRL_RESP state (indicating handshake completed)
      $display("@%0t: Starting to wait for write control request processing", $time);
      $display("@%0t: Initial check - Write state: %0d, Read state: %0d", 
               $time, dut.write_state_q, dut.read_state_q);
      
      while (dut.write_state_q !== dut.W_CTRL_RESP) begin
        step(1);
        nextSamplePoint();
        // Debug: Print state every cycle for first few cycles
        if ($time <= 88495000) begin
          $display("@%0t: Debug - Write state: %0d, Read state: %0d, ctrl_req_valid: %b, ctrl_req_ready: %b", 
                   $time, dut.write_state_q, dut.read_state_q, ctrl_if.req_valid, ctrl_if.req_ready);
        end
        // Debug: Print state every 10 cycles after that
        else if ($time % 100 == 0) begin
          $display("@%0t: Debug - Write state: %0d, Read state: %0d, ctrl_req_valid: %b, ctrl_req_ready: %b", 
                   $time, dut.write_state_q, dut.read_state_q, ctrl_if.req_valid, ctrl_if.req_ready);
        end
      end
      
      $display("@%0t: Write control request processing detected!", $time);
      $display("@%0t: Write state: %0d, Read state: %0d", $time, dut.write_state_q, dut.read_state_q);
      
      // Verify write data integrity using captured data
      `FAIL_IF(test_base.captured_write_trans.addr !== write_addr)
      `FAIL_IF(test_base.captured_write_trans.data !== write_data)
      `FAIL_IF(test_base.captured_write_trans.strb !== write_strb)
      
      // Step 5: Send control response (handshake already completed)
      test_base.send_ctrl_response(64'h0, 2'b00);
      test_base.accept_axi_write_resp();
      
      // Step 6: Wait for write completion
      $display("@%0t: Waiting for write completion", $time);
      $display("@%0t: Current write state: %0d", $time, dut.write_state_q);
      
      while (dut.write_state_q !== dut.W_IDLE) begin
        step(1);
        nextSamplePoint();
        // Debug: Print state every few cycles
        if ($time % 100 == 0) begin
          $display("@%0t: Debug - Write state: %0d, Read state: %0d", $time, dut.write_state_q, dut.read_state_q);
        end
      end
      
      $display("@%0t: Write completion detected", $time);
      
      // Step 7: Now read should get control access (after write completes)
      $display("@%0t: Waiting for read control request", $time);
      $display("@%0t: Current read state: %0d, ctrl_req_valid: %b, ctrl_req_ready: %b", 
               $time, dut.read_state_q, ctrl_if.req_valid, ctrl_if.req_ready);
      
      // Check if read control request has already been processed
      if (dut.read_state_q !== dut.R_DATA) begin
        // Wait for read to get control access (after write completes)
        while (dut.read_state_q !== dut.R_CTRL_REQ) begin
          step(1);
          nextSamplePoint();
          // Debug: Print state every few cycles
          if ($time % 100 == 0) begin
            $display("@%0t: Debug - Read state: %0d, ctrl_req_valid: %b, ctrl_req_ready: %b", 
                     $time, dut.read_state_q, ctrl_if.req_valid, ctrl_if.req_ready);
          end
        end
        
        $display("@%0t: Read control request detected", $time);
        
        // Accept the read control request
        test_base.accept_ctrl_request();
      end else begin
        $display("@%0t: Read control request already processed", $time);
      end
      
      // Step 8: Verify read address integrity
      $display("@%0t: Debug - Captured read addr: 0x%016x, Expected read addr: 0x%016x", 
               $time, test_base.captured_read_trans.addr, read_addr);
      `FAIL_IF(test_base.captured_read_trans.addr !== read_addr)
      
      // Step 9: Send control response (if needed)
      $display("@%0t: Sending control response", $time);
      $display("@%0t: Current read state: %0d, ctrl_resp_ready: %b", $time, dut.read_state_q, ctrl_if.resp_ready);
      
      // Check if DUT is ready to accept control response
      if (dut.read_state_q === dut.R_CTRL_RESP) begin
        test_base.send_ctrl_response(read_data, 2'b00);
      end else begin
        $display("@%0t: DUT not in R_CTRL_RESP state, skipping control response", $time);
      end
      
      // Step 10: Wait for read data (DUT should be in R_DATA state)
      $display("@%0t: Waiting for read data", $time);
      $display("@%0t: Current read state: %0d, rvalid: %b, rready: %b", $time, dut.read_state_q, axi_if.rvalid, axi_if.rready);
      
      // Wait for DUT to be ready to send read data
      while (dut.read_state_q !== dut.R_DATA) begin
        step(1);
        nextSamplePoint();
        // Debug: Print state every few cycles
        if ($time % 100 == 0) begin
          $display("@%0t: Debug - Read state: %0d, rvalid: %b, rready: %b", $time, dut.read_state_q, axi_if.rvalid, axi_if.rready);
        end
      end
      
      $display("@%0t: DUT ready to send read data", $time);
      
      test_base.accept_axi_read_data();
      
      // Step 11: Wait for completion
      while (dut.read_state_q !== dut.R_IDLE) begin
        step(1);
        nextSamplePoint();
      end
      
      test_base.clear_axi_write();
      test_base.clear_axi_read();
      test_base.clear_ctrl_response();
      
      $display("============== 4. Concurrent transaction data integrity test PASSED ==============");
    `SVTEST_END
    
    //=================================
    // Test Strobe Pattern Data Handling
    //=================================
    `SVTEST(test_strobe_pattern_data_handling)
      // Test that different strobe patterns are correctly transmitted
      logic [63:0] test_data;
      logic [63:0] test_addr;
      
      $display("============== 5. Testing Strobe Pattern Data Handling ==============");
      test_base.initialize_signals();
      step(5);
      
      // Initialize test data
      test_data = 64'h0123456789ABCDEF;
      test_addr = 64'h5000;
      
      for (int strb_idx = 0; strb_idx < 8; strb_idx++) begin
        string test_name = $sformatf("strobe_pattern_%0d", strb_idx);
        $display("Testing %s: strb=0x%02x", test_name, test_base.test_strb_patterns[strb_idx]);
        
        complete_write_transaction_verify(test_addr + strb_idx * 8, test_data, test_base.test_strb_patterns[strb_idx]);
      end
      
      $display("============== 5. Strobe pattern data handling test PASSED ==============");
    `SVTEST_END
    
    //=================================
    // Test Address Range Data Integrity
    //=================================
    `SVTEST(test_address_range_data_integrity)
      // Test various address ranges with specific data patterns
      typedef struct {
        logic [63:0] addr;
        logic [63:0] data;
        string name;
      } addr_data_test_t;
      
      addr_data_test_t addr_data_tests[8];
      
      $display("============== 6. Testing Address Range Data Integrity ==============");
      test_base.initialize_signals();
      step(5);
      
      // Initialize address-data test patterns
      addr_data_tests[0].addr = 64'h0000000000000000; addr_data_tests[0].data = 64'h0000000000000000; addr_data_tests[0].name = "zero_addr_zero_data";
      addr_data_tests[1].addr = 64'h0000000000000008; addr_data_tests[1].data = 64'h0123456789ABCDEF; addr_data_tests[1].name = "low_addr_pattern_data";
      addr_data_tests[2].addr = 64'h00000000FFFFFFFF; addr_data_tests[2].data = 64'hFFFFFFFF00000000; addr_data_tests[2].name = "32bit_boundary";
      addr_data_tests[3].addr = 64'h0000FFFFFFFFFFFF; addr_data_tests[3].data = 64'hAAAAAAAAAAAAAAAA; addr_data_tests[3].name = "48bit_boundary";
      addr_data_tests[4].addr = 64'h7FFFFFFFFFFFFFFF; addr_data_tests[4].data = 64'h5555555555555555; addr_data_tests[4].name = "63bit_boundary";
      addr_data_tests[5].addr = 64'hFFFFFFFFFFFFFFF8; addr_data_tests[5].data = 64'hDEADBEEFCAFEBABE; addr_data_tests[5].name = "near_max_addr";
      addr_data_tests[6].addr = 64'h8000000000000000; addr_data_tests[6].data = 64'hFEDCBA9876543210; addr_data_tests[6].name = "msb_addr_pattern";
      addr_data_tests[7].addr = 64'h123456789ABCDEF0; addr_data_tests[7].data = 64'h0F0F0F0F0F0F0F0F; addr_data_tests[7].name = "pattern_addr_nibble_data";
      
      foreach (addr_data_tests[i]) begin
        $display("Testing %s: addr=0x%016x, data=0x%016x", 
                 addr_data_tests[i].name, addr_data_tests[i].addr, addr_data_tests[i].data);
        
        test_data_pattern_roundtrip(
          addr_data_tests[i].name,
          addr_data_tests[i].addr,
          addr_data_tests[i].data,
          8'hFF  // Full strobe
        );
      end
      
      $display("============== 6. Address range data integrity test PASSED ==============");
    `SVTEST_END
    
    //=================================
    // Test Error Response Data Handling
    //=================================
    `SVTEST(test_error_response_data_handling)
      // Test that error responses preserve data correctly
      logic [63:0] error_test_data[4];
      logic [1:0] error_responses[3];
      string error_names[3];
      
      $display("============== 7. Testing Error Response Data Handling ==============");
      test_base.initialize_signals();
      step(5);
      
      // Initialize error test data patterns
      error_test_data[0] = 64'h4552524F52524F52;  // "ERRORROR" in hex
      error_test_data[1] = 64'hDEADDEADDEADDEAD;  // Dead pattern
      error_test_data[2] = 64'hBADBEEFBAD000000;  // Bad beef pattern
      error_test_data[3] = 64'hFFFFFFFFFFFFFFFF;  // All ones
      
      // Initialize error responses
      error_responses[0] = 2'b01;  // EXOKAY
      error_responses[1] = 2'b10;  // SLVERR
      error_responses[2] = 2'b11;  // DECERR
      
      // Initialize error names
      error_names[0] = "EXOKAY";
      error_names[1] = "SLVERR";
      error_names[2] = "DECERR";
      
      for (int data_idx = 0; data_idx < 4; data_idx++) begin
        for (int err_idx = 0; err_idx < 3; err_idx++) begin
          string test_name = $sformatf("error_data_%0d_%s", data_idx, error_names[err_idx]);
          $display("Testing %s with data=0x%016x", test_name, error_test_data[data_idx]);
          
          // Test error response in read transaction
          test_base.ctrl_req_detected = 1'b0;
          test_base.ctrl_resp_detected = 1'b0;
          
          test_base.send_axi_read_transaction(64'h7000 + data_idx * 8);
          
          // Wait for DUT to enter R_CTRL_REQ state (indicating control request is being sent)
          $display("@%0t: Waiting for DUT to enter R_CTRL_REQ state for error test", $time);
          $display("@%0t: Initial state - Read state: %0d, ctrl_req_valid: %b, ctrl_req_ready: %b", 
                   $time, dut.read_state_q, ctrl_if.req_valid, ctrl_if.req_ready);
          
          while (dut.read_state_q !== dut.R_CTRL_REQ) begin
            step(1);
            nextSamplePoint();
            // Debug: Print state every few cycles
            if ($time % 100 == 0) begin
              $display("@%0t: Debug - Read state: %0d, ctrl_req_valid: %b, ctrl_req_ready: %b", 
                       $time, dut.read_state_q, ctrl_if.req_valid, ctrl_if.req_ready);
            end
          end
          
          $display("@%0t: DUT entered R_CTRL_REQ state for error test", $time);
          
          // Now accept the control request
          test_base.accept_ctrl_request();
          
          // Send error response with data
          test_base.send_ctrl_response(error_test_data[data_idx], error_responses[err_idx]);
          
          // Wait for control response
          while (!test_base.ctrl_resp_detected) begin
            step(1);
            nextSamplePoint();
          end
          
          // Verify error data integrity
          `FAIL_IF(test_base.captured_read_trans.data !== error_test_data[data_idx])
          `FAIL_IF(test_base.captured_read_trans.resp !== error_responses[err_idx])
          
          test_base.accept_axi_read_data();
          
          // Wait for completion
          while (dut.read_state_q !== dut.R_IDLE) begin
            step(1);
            nextSamplePoint();
          end
          
          test_base.clear_axi_read();
          test_base.clear_ctrl_response();
          step(2);
        end
      end
      
      $display("============== 7. Error response data handling test PASSED ==============");
    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule