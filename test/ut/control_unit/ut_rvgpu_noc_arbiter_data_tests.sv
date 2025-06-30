`include "svunit_defines.svh"
`include "clk_and_reset.svh"
`include "rvgpu_internal_noc_pkg.sv"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_noc_arbiter.sv"
`include "rvgpu_noc_arbiter_test_base.svh"
`include "project.v"

module rvgpu_noc_arbiter_data_tests_unit_test;
  import svunit_pkg::svunit_testcase;
  import rvgpu_internal_noc_pkg::*;

  string name = "ut_rvgpu_noc_arbiter_data_tests";
  svunit_testcase svunit_ut;

  //===================================
  // Clock and Reset
  //===================================
  `CLK_RESET_FIXTURE(5, 10)        

  // Interface instances
  rvgpu_internal_noc_if #(.NOC_CONFIG(DEFAULT_NOC_CONFIG)) cp_if();
  rvgpu_internal_noc_if #(.NOC_CONFIG(DEFAULT_NOC_CONFIG)) mmu_if();
  rvgpu_internal_noc_if #(.NOC_CONFIG(DEFAULT_NOC_CONFIG)) noc_if();

  // DUT Instance
  rvgpu_noc_arbiter dut (
    .clk(clk),
    .rst_n(rst_n),
    .cp_if(cp_if.noc),
    .mmu_if(mmu_if.noc),
    .noc_if(noc_if.device)
  );

  // Test base class instance
  rvgpu_noc_arbiter_test_base test_base;

  // Test data patterns are now provided by test_base

  function void build();
    svunit_ut = new(name);
    
    // Create test base instance
    test_base = new(cp_if, mmu_if, noc_if);
  endfunction

  // initialize_signals() is now provided by test_base

  task setup();
    svunit_ut.setup();
    $vcdpluson();
    test_base.initialize_signals();
    test_base.initialize_data_monitor();
    reset();
  endtask

  task teardown();
    svunit_ut.teardown();
  endtask

  // send_cp_data_request() is now provided by test_base

  // Data integrity monitor variables are now provided by test_base
  // But we still need the always block here because it requires clock access

  // Monitor NOC interface for data transmissions
  always @(posedge clk) begin
    if (noc_if.m_req_valid && noc_if.m_req_ready && noc_if.m_req_last) begin
      test_base.captured_data <= noc_if.m_req_data;
      test_base.captured_strb <= noc_if.m_req_strb;
      test_base.captured_header <= noc_if.m_req_header;
      test_base.data_transmission_detected <= 1'b1;
    end else begin
      test_base.data_transmission_detected <= 1'b0;
    end
  end

  // Send CP request and verify data transmission (works for both pre-ready and controlled scenarios)
  task send_cp_request_and_verify_transmission(logic [255:0] expected_data, logic [31:0] expected_strb);
    logic [31:0] expected_header;
    expected_header = test_base.create_cp_mem_read_header(8'h10, 8'h00);
    
    // Clear previous capture
    test_base.data_transmission_detected = 1'b0;
    
    // Send request using test_base function
    test_base.send_cp_data_request(expected_data, expected_strb);
    
    // Wait for transmission to be captured
    while (!test_base.data_transmission_detected) begin
      step(1);
      nextSamplePoint();
    end
    
    // Verify data integrity using test_base function
    test_base.verify_captured_data(expected_data, expected_strb, expected_header);
  endtask

  // Test data transmission with simulated backpressure
  task test_transmission_with_backpressure(logic [255:0] test_data, logic [31:0] test_strb, int delay_cycles);
    fork
      begin
        // Send request and verify data transmission
        send_cp_request_and_verify_transmission(test_data, test_strb);
      end
      begin
        // Simulate backpressure by delaying ready signal
        step(delay_cycles);
        noc_if.m_req_ready = 1'b1;
      end
    join
    $display("@%0t: Backpressure test completed with %0d cycle delay", $time, delay_cycles);
  endtask

  // Test immediate data transmission (pre-ready scenario)
  task test_immediate_transmission(logic [255:0] test_data, logic [31:0] test_strb);
    // Ready is already set to 1 before calling this function
    send_cp_request_and_verify_transmission(test_data, test_strb);
    $display("@%0t: Immediate transmission test completed", $time);
  endtask

  // Test edge case data with both immediate and delayed scenarios
  task test_edge_case_data(string test_name, logic [255:0] test_data, logic [31:0] test_strb);
    $display("Testing %s", test_name);
    
    // Test immediate transmission
    test_base.initialize_signals();
    noc_if.m_req_ready = 1'b1;
    step(2);
    test_immediate_transmission(test_data, test_strb);
    test_base.clear_requests();
    noc_if.m_req_ready = 1'b0;
    step(1);
    
    // Test with backpressure
    test_base.initialize_signals();
    noc_if.m_req_ready = 1'b0;
    step(2);
    test_transmission_with_backpressure(test_data, test_strb, 2);
    test_base.clear_requests();
    noc_if.m_req_ready = 1'b0;
    step(1);
    
    $display("%s test completed", test_name);
  endtask

  //===================================
  // Enhanced Data Integrity Tests
  //===================================
  `SVUNIT_TESTS_BEGIN
    
    //=================================
    // Test Immediate Data Transmission (Pre-ready Scenarios)
    //=================================
    `SVTEST(test_immediate_data_transmission)
      $display("============== 1. Testing Immediate Data Transmission ==============");
      
      for (int pattern_idx = 0; pattern_idx < 8; pattern_idx++) begin
        for (int strobe_idx = 0; strobe_idx < 4; strobe_idx++) begin
          $display("Testing immediate transmission: pattern %0d, strobe %0d", pattern_idx, strobe_idx);
          
          test_base.initialize_signals();
          noc_if.m_req_ready = 1'b1;  // Pre-set ready for immediate transmission
          step(2);
          
          test_immediate_transmission(test_base.test_patterns[pattern_idx], test_base.strobe_patterns[strobe_idx]);
          
          test_base.clear_requests();
          noc_if.m_req_ready = 1'b0;
          step(1);
        end
      end
      
      $display("============== 1. Immediate data transmission test PASSED ==============");
    `SVTEST_END
    
    //=================================
    // Test Backpressure Data Transmission
    //=================================
    `SVTEST(test_backpressure_data_transmission)
      $display("============== 2. Testing Backpressure Data Transmission ==============");
      
      for (int pattern_idx = 0; pattern_idx < 8; pattern_idx++) begin
        for (int strobe_idx = 0; strobe_idx < 4; strobe_idx++) begin
          $display("Testing backpressure transmission: pattern %0d, strobe %0d", pattern_idx, strobe_idx);
          
          test_base.initialize_signals();
          noc_if.m_req_ready = 1'b0;  // Start with ready = 0 for backpressure
          step(2);
          
          // Test with 3-cycle backpressure delay
          test_transmission_with_backpressure(test_base.test_patterns[pattern_idx], test_base.strobe_patterns[strobe_idx], 3);
          
          test_base.clear_requests();
          noc_if.m_req_ready = 1'b0;
          step(1);
        end
      end
      
      $display("============== 2. Backpressure data transmission test PASSED ==============");
    `SVTEST_END
    
    //=================================
    // Test Data Integrity During Arbitration
    //=================================
    `SVTEST(test_arbitration_data_integrity)
      $display("============== 3. Testing Data Integrity During Arbitration ==============");
      
      // Test sequential requests to ensure no data mixing
      test_base.initialize_signals();
      step(2);
      
      // Test 1: Send CP request first
      $display("Testing CP request with AAAA pattern");
      cp_if.m_req_valid = 1'b1;
      cp_if.m_req_header = test_base.create_cp_mem_read_header(8'h10, 8'h00);
      cp_if.m_req_data = test_base.test_patterns[2];    // AAAA pattern
      cp_if.m_req_strb = test_base.strobe_patterns[1];  // F0F0 strobe
      cp_if.m_req_last = 1'b1;
      
      step(1);
      nextSamplePoint();
      
      // Verify CP data transmitted correctly before completing handshake
      `FAIL_IF(dut.arb_state !== dut.REQ_ARB_CP)
      test_base.verify_noc_data(test_base.test_patterns[2], test_base.strobe_patterns[1]);
      
      // Complete CP handshake
      noc_if.m_req_ready = 1'b1;
      step(1);
      nextSamplePoint();
      `FAIL_IF(dut.arb_state !== dut.REQ_ARB_IDLE)
      
      // Clear CP and send MMU request
      cp_if.m_req_valid = 1'b0;
      noc_if.m_req_ready = 1'b0;  // Reset ready for MMU test
      step(1);
      
      $display("Testing MMU request with 5555 pattern");
      mmu_if.m_req_valid = 1'b1;
      mmu_if.m_req_header = test_base.create_mmu_mem_write_header(8'h20, 8'h10);
      mmu_if.m_req_data = test_base.test_patterns[3];   // 5555 pattern
      mmu_if.m_req_strb = test_base.strobe_patterns[2]; // Lower half strobe
      mmu_if.m_req_last = 1'b1;
      
      step(1);
      nextSamplePoint();
      
      // Verify MMU data transmitted correctly before completing handshake
      `FAIL_IF(dut.arb_state !== dut.REQ_ARB_MMU)
      test_base.verify_noc_data(test_base.test_patterns[3], test_base.strobe_patterns[2]);
      
      // Complete MMU handshake
      noc_if.m_req_ready = 1'b1;
      step(1);
      nextSamplePoint();
      `FAIL_IF(dut.arb_state !== dut.REQ_ARB_IDLE)
      
      test_base.clear_requests();
      step(1);
      
      $display("============== 3. Arbitration data integrity test PASSED ==============");
    `SVTEST_END
    
    //=================================
    // Test Response Data Routing
    //=================================
    `SVTEST(test_response_data_integrity)
      $display("============== 4. Testing Response Data Integrity ==============");
      
      for (int i = 0; i < 4; i++) begin
        $display("Testing response data pattern %0d", i);
        
        test_base.initialize_signals();
        step(2);
        
        // Send response from NOC with specific pattern (CP not ready initially)
        cp_if.m_resp_ready = 1'b0;
        noc_if.m_resp_valid = 1'b1;
        noc_if.m_resp_header = test_base.create_mem_read_resp_header(8'h50, 8'h05);
        noc_if.m_resp_data = test_base.test_patterns[i];
        noc_if.m_resp_status = RESP_OKAY;
        noc_if.m_resp_last = 1'b1;
        
        step(1);
        nextSamplePoint();
        
        // Verify response routing and data before completing handshake
        `FAIL_IF(dut.route_state !== dut.RESP_ROUTE_CP)
        `FAIL_IF(cp_if.m_resp_valid !== 1'b1)
        `FAIL_IF(cp_if.m_resp_data !== test_base.test_patterns[i])
        `FAIL_IF(cp_if.m_resp_status !== RESP_OKAY)
        
        // Complete handshake
        cp_if.m_resp_ready = 1'b1;
        step(1);
        nextSamplePoint();
        
        // Should return to idle after handshake
        `FAIL_IF(dut.route_state !== dut.RESP_ROUTE_IDLE)
        
        // Clear response
        noc_if.m_resp_valid = 1'b0;
        noc_if.m_resp_header = 32'h0;
        noc_if.m_resp_data = 256'h0;
        noc_if.m_resp_status = RESP_OKAY;
        noc_if.m_resp_last = 1'b0;
        step(1);
      end
      
      $display("============== 4. Response data integrity test PASSED ==============");
    `SVTEST_END
    
    //=================================
    // Test Edge Cases and Corner Data
    //=================================
    `SVTEST(test_edge_case_data_handling)
      $display("============== 5. Testing Edge Case Data Handling ==============");
      
      // Test various edge case data patterns
      test_edge_case_data("all zeros with minimal strobe", 256'h0, 32'h00000001);
      test_edge_case_data("all ones with maximal strobe", 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 32'hFFFFFFFF);
      test_edge_case_data("single bit patterns", 256'h1, 32'h80000000);
      
      $display("============== 5. Edge case data handling test PASSED ==============");
    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule 