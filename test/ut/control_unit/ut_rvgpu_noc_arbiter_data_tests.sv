`include "svunit_defines.svh"
`include "clk_and_reset.svh"
`include "rvgpu_internal_noc_pkg.sv"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_noc_arbiter.sv"
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

  // Test data patterns for comprehensive testing
  logic [255:0] test_patterns[8];
  logic [31:0] strobe_patterns[4];

  function void build();
    svunit_ut = new(name);
    
    // Initialize test patterns
    test_patterns[0] = 256'h0000000000000000000000000000000000000000000000000000000000000000;  // All zeros
    test_patterns[1] = 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;  // All ones
    test_patterns[2] = 256'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;  // 1010 pattern
    test_patterns[3] = 256'h5555555555555555555555555555555555555555555555555555555555555555;  // 0101 pattern
    test_patterns[4] = 256'hDEADBEEFCAFEBABE123456789ABCDEF0FEDCBA9876543210ABCDEF0123456789;  // Random 1
    test_patterns[5] = 256'h123456789ABCDEF0FEDCBA9876543210ABCDEF0123456789DEADBEEFCAFEBABE;  // Random 2
    test_patterns[6] = 256'hF0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0;  // Byte pattern
    test_patterns[7] = 256'h0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F;  // Inverse byte

    // Initialize strobe patterns
    strobe_patterns[0] = 32'hFFFFFFFF;  // Full transfer
    strobe_patterns[1] = 32'hF0F0F0F0;  // Alternating bytes
    strobe_patterns[2] = 32'h0000FFFF;  // Lower half
    strobe_patterns[3] = 32'hFFFF0000;  // Upper half
  endfunction

  task initialize_signals();
    // CP interface - device side (test acts as device, DUT acts as NOC)
    cp_if.m_req_valid = 0;
    cp_if.m_req_header = 0;
    cp_if.m_req_data = 0;
    cp_if.m_req_strb = 0;
    cp_if.m_req_last = 0;
    cp_if.m_resp_ready = 0;
    cp_if.s_req_ready = 0;
    cp_if.s_resp_valid = 0;
    cp_if.s_resp_header = 0;
    cp_if.s_resp_data = 0;
    cp_if.s_resp_status = RESP_OKAY;
    cp_if.s_resp_last = 0;

    // MMU interface - device side (test acts as device, DUT acts as NOC)
    mmu_if.m_req_valid = 0;
    mmu_if.m_req_header = 0;
    mmu_if.m_req_data = 0;
    mmu_if.m_req_strb = 0;
    mmu_if.m_req_last = 0;
    mmu_if.m_resp_ready = 0;
    mmu_if.s_req_ready = 0;
    mmu_if.s_resp_valid = 0;
    mmu_if.s_resp_header = 0;
    mmu_if.s_resp_data = 0;
    mmu_if.s_resp_status = RESP_OKAY;
    mmu_if.s_resp_last = 0;

    // NOC interface - NOC side (test acts as NOC, DUT acts as device)
    noc_if.m_req_ready = 0;      // NOC ready to accept requests (controlled by test)
    noc_if.m_resp_valid = 0;     // NOC sends responses
    noc_if.m_resp_header = 0;
    noc_if.m_resp_data = 0;
    noc_if.m_resp_status = RESP_OKAY;
    noc_if.m_resp_last = 0;
    noc_if.s_req_valid = 0;      // NOC sends slave requests
    noc_if.s_req_header = 0;
    noc_if.s_req_data = 0;
    noc_if.s_req_strb = 0;
    noc_if.s_req_last = 0;
    noc_if.s_resp_ready = 0;     // NOC ready to accept slave responses
  endtask

  task setup();
    svunit_ut.setup();
    $vcdpluson();
    initialize_signals();
    reset();
  endtask

  task teardown();
    svunit_ut.teardown();
  endtask

  // Send CP request with specific data pattern
  task send_cp_data_request(logic [255:0] data_pattern, logic [31:0] strb_pattern);
    cp_if.m_req_valid = 1'b1;
    cp_if.m_req_header = build_noc_header(MSG_MEM_READ_REQ, 8'h10, NODE_CONTROL, NODE_L2_CACHE, 8'h00);
    cp_if.m_req_data = data_pattern;
    cp_if.m_req_strb = strb_pattern;
    cp_if.m_req_last = 1'b1;
    $display("@%0t: CP Data=0x%064x, Strobe=0x%08x", $time, data_pattern, strb_pattern);
  endtask

  // Data integrity monitor for capturing transmitted data
  logic [255:0] captured_data;
  logic [31:0] captured_strb;
  logic [31:0] captured_header;
  logic data_transmission_detected;

  // Monitor NOC interface for data transmissions
  always @(posedge clk) begin
    if (noc_if.m_req_valid && noc_if.m_req_ready && noc_if.m_req_last) begin
      captured_data <= noc_if.m_req_data;
      captured_strb <= noc_if.m_req_strb;
      captured_header <= noc_if.m_req_header;
      data_transmission_detected <= 1'b1;
    end else begin
      data_transmission_detected <= 1'b0;
    end
  end

  // Send CP request and verify data transmission (works for both pre-ready and controlled scenarios)
  task send_cp_request_and_verify_transmission(logic [255:0] expected_data, logic [31:0] expected_strb);
    logic [31:0] expected_header;
    expected_header = build_noc_header(MSG_MEM_READ_REQ, 8'h10, NODE_CONTROL, NODE_L2_CACHE, 8'h00);
    
    // Clear previous capture
    data_transmission_detected = 1'b0;
    
    // Send request
    cp_if.m_req_valid = 1'b1;
    cp_if.m_req_header = expected_header;
    cp_if.m_req_data = expected_data;
    cp_if.m_req_strb = expected_strb;
    cp_if.m_req_last = 1'b1;
    
    // Wait for transmission to be captured
    while (!data_transmission_detected) begin
      step(1);
      nextSamplePoint();
    end
    
    // Verify data integrity
    `FAIL_IF(captured_data !== expected_data)
    `FAIL_IF(captured_strb !== expected_strb)
    `FAIL_IF(captured_header !== expected_header)
    
    $display("@%0t: Data transmission verified: 0x%064x, strobe: 0x%08x", $time, expected_data, expected_strb);
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
    initialize_signals();
    noc_if.m_req_ready = 1'b1;
    step(2);
    test_immediate_transmission(test_data, test_strb);
    clear_requests();
    noc_if.m_req_ready = 1'b0;
    step(1);
    
    // Test with backpressure
    initialize_signals();
    noc_if.m_req_ready = 1'b0;
    step(2);
    test_transmission_with_backpressure(test_data, test_strb, 2);
    clear_requests();
    noc_if.m_req_ready = 1'b0;
    step(1);
    
    $display("%s test completed", test_name);
  endtask

  // Verify NOC receives exact data
  task verify_noc_data(logic [255:0] expected_data, logic [31:0] expected_strb);
    `FAIL_IF(noc_if.m_req_valid !== 1'b1)
    `FAIL_IF(noc_if.m_req_data !== expected_data)
    `FAIL_IF(noc_if.m_req_strb !== expected_strb)
    `FAIL_IF(noc_if.m_req_last !== 1'b1)
    $display("@%0t: NOC Data Verified: 0x%064x", $time, expected_data);
  endtask

  // Clear request signals
  task clear_requests();
    cp_if.m_req_valid = 1'b0;
    cp_if.m_req_header = 32'h0;
    cp_if.m_req_data = 256'h0;
    cp_if.m_req_strb = 32'h0;
    cp_if.m_req_last = 1'b0;
    
    mmu_if.m_req_valid = 1'b0;
    mmu_if.m_req_header = 32'h0;
    mmu_if.m_req_data = 256'h0;
    mmu_if.m_req_strb = 32'h0;
    mmu_if.m_req_last = 1'b0;
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
          
          initialize_signals();
          noc_if.m_req_ready = 1'b1;  // Pre-set ready for immediate transmission
          step(2);
          
          test_immediate_transmission(test_patterns[pattern_idx], strobe_patterns[strobe_idx]);
          
          clear_requests();
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
          
          initialize_signals();
          noc_if.m_req_ready = 1'b0;  // Start with ready = 0 for backpressure
          step(2);
          
          // Test with 3-cycle backpressure delay
          test_transmission_with_backpressure(test_patterns[pattern_idx], strobe_patterns[strobe_idx], 3);
          
          clear_requests();
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
      initialize_signals();
      step(2);
      
      // Test 1: Send CP request first
      $display("Testing CP request with AAAA pattern");
      cp_if.m_req_valid = 1'b1;
      cp_if.m_req_header = build_noc_header(MSG_MEM_READ_REQ, 8'h10, NODE_CONTROL, NODE_L2_CACHE, 8'h00);
      cp_if.m_req_data = test_patterns[2];    // AAAA pattern
      cp_if.m_req_strb = strobe_patterns[1];  // F0F0 strobe
      cp_if.m_req_last = 1'b1;
      
      step(1);
      nextSamplePoint();
      
      // Verify CP data transmitted correctly before completing handshake
      `FAIL_IF(dut.arb_state !== dut.REQ_ARB_CP)
      verify_noc_data(test_patterns[2], strobe_patterns[1]);
      
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
      mmu_if.m_req_header = build_noc_header(MSG_MEM_WRITE_REQ, 8'h20, NODE_CONTROL, NODE_L2_CACHE, 8'h10);
      mmu_if.m_req_data = test_patterns[3];   // 5555 pattern
      mmu_if.m_req_strb = strobe_patterns[2]; // Lower half strobe
      mmu_if.m_req_last = 1'b1;
      
      step(1);
      nextSamplePoint();
      
      // Verify MMU data transmitted correctly before completing handshake
      `FAIL_IF(dut.arb_state !== dut.REQ_ARB_MMU)
      verify_noc_data(test_patterns[3], strobe_patterns[2]);
      
      // Complete MMU handshake
      noc_if.m_req_ready = 1'b1;
      step(1);
      nextSamplePoint();
      `FAIL_IF(dut.arb_state !== dut.REQ_ARB_IDLE)
      
      clear_requests();
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
        
        initialize_signals();
        step(2);
        
        // Send response from NOC with specific pattern (CP not ready initially)
        cp_if.m_resp_ready = 1'b0;
        noc_if.m_resp_valid = 1'b1;
        noc_if.m_resp_header = build_noc_header(MSG_MEM_READ_RESP, 8'h50, NODE_L2_CACHE, NODE_CONTROL, 8'h05);
        noc_if.m_resp_data = test_patterns[i];
        noc_if.m_resp_status = RESP_OKAY;
        noc_if.m_resp_last = 1'b1;
        
        step(1);
        nextSamplePoint();
        
        // Verify response routing and data before completing handshake
        `FAIL_IF(dut.route_state !== dut.RESP_ROUTE_CP)
        `FAIL_IF(cp_if.m_resp_valid !== 1'b1)
        `FAIL_IF(cp_if.m_resp_data !== test_patterns[i])
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