`include "svunit_defines.svh"
`include "clk_and_reset.svh"
`include "rvgpu_internal_noc_pkg.sv"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_noc_arbiter.sv"
`include "rvgpu_noc_arbiter_test_base.svh"
`include "project.v"

module rvgpu_noc_arbiter_baisc_unit_test;
  import svunit_pkg::svunit_testcase;
  import rvgpu_internal_noc_pkg::*;

  string name = "ut_rvgpu_noc_arbiter_basic";
  svunit_testcase svunit_ut;

  //===================================
  // Clock and Reset
  //===================================
  `CLK_RESET_FIXTURE(5, 10)        

  // Interface instances
  rvgpu_internal_noc_if #(.NOC_CONFIG(DEFAULT_NOC_CONFIG)) cp_if();  // Command Processor
  rvgpu_internal_noc_if #(.NOC_CONFIG(DEFAULT_NOC_CONFIG)) mmu_if();  // MMU
  rvgpu_internal_noc_if #(.NOC_CONFIG(DEFAULT_NOC_CONFIG)) noc_if(); // NOC output

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

  // Test data structures (now defined in test_base)
  noc_packet_t test_packet;
  noc_packet_t test_packet_cp, test_packet_mmu;
  noc_packet_t resp_packet;
  noc_packet_t slave_req_packet;
  noc_packet_t slave_resp_packet;
  noc_packet_t unknown_resp_packet;

  //===================================
  // Build
  //===================================
  function void build();
    svunit_ut = new(name);
    
    // Create test base instance
    test_base = new(cp_if, mmu_if, noc_if);
  endfunction

  //===================================
  // Signal Initialization (now provided by test_base)
  //===================================
  // initialize_signals() is now provided by test_base

  //===================================
  // Setup
  //===================================
  task setup();
    svunit_ut.setup();
    $vcdpluson();
    
    $display("@%0t: Setup starting", $time);
    test_base.initialize_signals();
    $display("@%0t: initialize_signals completed", $time);
    reset();
    $display("@%0t: reset completed", $time);
  endtask

  //===================================
  // Teardown
  //===================================
  task teardown();
    svunit_ut.teardown();
  endtask

  //===================================
  // Helper Tasks and Functions
  //===================================
  
  // Check reset state - uses test_base for interface signals and adds DUT internal state checks
  task check_reset_state();
    $display("@%0t: Starting check_reset_state", $time);

    // Check interface signals using test_base
    test_base.check_interface_reset_state();
    
    // Check arbiter internal state (specific to this test)
    `FAIL_IF(dut.arb_state !== dut.REQ_ARB_IDLE)
    `FAIL_IF(dut.route_state !== dut.RESP_ROUTE_IDLE)
    `FAIL_IF(dut.arb_priority !== 1'b0)
    
    $display("@%0t: All signals and DUT internal state in correct reset state", $time);
  endtask

  // send_request() is now provided by test_base

  // ✅ AXI-compliant request with automatic handshake completion
  task send_request_and_wait_handshake(noc_vif_t master_if, noc_packet_t packet);
    // Start request
    master_if.m_req_valid = 1'b1;
    master_if.m_req_header = packet.header;
    master_if.m_req_data = packet.data;
    master_if.m_req_strb = packet.strb;
    master_if.m_req_last = 1'b1;
    $display("@%0t: Sending request - Header: 0x%08x", $time, packet.header);
    
    // Wait for handshake completion
    while (!(master_if.m_req_valid && master_if.m_req_ready)) begin
      @(posedge clk);
    end
    
    // Handshake completed, clear on next cycle (AXI compliant)
    @(posedge clk);
    master_if.m_req_valid = 1'b0;
    master_if.m_req_header = 32'h0;
    master_if.m_req_data = 256'h0;
    master_if.m_req_strb = 32'h0;
    master_if.m_req_last = 1'b0;
    $display("@%0t: Request completed and cleared", $time);
  endtask

  // send_response(), clear_response(), send_slave_request(), clear_slave_request(),
  // verify_response_routing(), and verify_slave_request_forwarding() are now provided by test_base

  //===================================
  // Test Cases
  //===================================
  `SVUNIT_TESTS_BEGIN
    
    //=================================
    // Test Basic Reset and Initialization
    //=================================
    `SVTEST(test_basic_reset_initialization)
      $display("============== 1. Testing Basic Reset and Initialization ==============");
      test_base.initialize_signals();
      step(10);
      
      // Verify reset state
      check_reset_state();
      
      // Test multiple resets
      for (int i = 0; i < 3; i++) begin
        reset();
        check_reset_state();
        $display("Reset cycle %0d passed", i+1);
      end
      
      // Test signal stability
      step(10);
      check_reset_state();
      
      $display("============== 1. Basic reset and initialization test passed ==============");
    `SVTEST_END
    
    //=================================
    // Test Request Arbitration - Single Master
    //=================================
    `SVTEST(test_single_master_arbitration)
      $display("============== 2. Testing Single Master Arbitration ==============");
      test_base.initialize_signals();
      step(5);
      
      test_packet = test_base.create_cp_mem_read_packet(8'h10, 8'h00, 
                      256'hDEADBEEF_CAFEBABE_12345678_9ABCDEF0_FEDCBA98_76543210_ABCDEF01_23456789, 
                      32'hFFFFFFFF);
      
      // Control timing to observe intermediate states
      // Step 1: Send request first, but keep NOC not ready
      $display("@%0t: Step 1 - Send CP request (NOC not ready)", $time);
      test_base.send_request(cp_if, test_packet);
      step(1);
      nextSamplePoint();
      
      // State should transition to REQ_ARB_CP, and valid should be forwarded immediately
      // but ready stays 0 because NOC is not ready
      $display("@%0t: Check state transition with valid forwarding", $time);
      `FAIL_IF(dut.arb_state !== dut.REQ_ARB_CP)
      `FAIL_IF(cp_if.m_req_ready !== 1'b0)      // NOC not ready, so CP not ready
      `FAIL_IF(noc_if.m_req_valid !== 1'b1)     // ✅ Valid should be forwarded immediately!
      `FAIL_IF(noc_if.m_req_header !== test_packet.header)  // Header should be forwarded
      
      // Step 2: Now make NOC ready to complete the handshake
      $display("@%0t: Step 2 - Make NOC ready", $time);
      noc_if.m_req_ready = 1'b1;
      step(1);
      nextSamplePoint();
      
      // because all conditions (valid && ready && last) are satisfied
      $display("@%0t: Check transaction completion", $time);
      `FAIL_IF(dut.arb_state !== dut.REQ_ARB_IDLE)  // Transaction completed, back to IDLE
      
      // Step 3: Clear request signals for cleanup
      $display("@%0t: Step 3 - Clear CP request signals", $time);
      test_base.clear_request(cp_if);
      
      // Reset NOC ready for next test
      noc_if.m_req_ready = 1'b0;
      step(1);
      
      // Test MMU with same controlled timing
      $display("@%0t: Step 4 - Test MMU request", $time);
      test_packet = test_base.create_mmu_mem_write_packet(8'h20, 8'h10, test_packet.data, test_packet.strb);
      test_base.send_request(mmu_if, test_packet);
      step(1);
      nextSamplePoint();
      
      // MMU state with valid forwarding but ready = 0
      `FAIL_IF(dut.arb_state !== dut.REQ_ARB_MMU)
      `FAIL_IF(mmu_if.m_req_ready !== 1'b0)     // NOC not ready
      `FAIL_IF(noc_if.m_req_valid !== 1'b1)     // Valid should be forwarded
      
      // Enable NOC for MMU
      noc_if.m_req_ready = 1'b1;
      step(1);
      nextSamplePoint();
      
      // After MMU handshake completion, state should return to IDLE
      $display("@%0t: Check MMU transaction completion", $time);
      `FAIL_IF(dut.arb_state !== dut.REQ_ARB_IDLE)  // Transaction completed, back to IDLE
      
      test_base.clear_request(mmu_if);
      
      $display("============== 2. Single master arbitration test passed ==============");
    `SVTEST_END
    
    //=================================
    // Test Priority Rotation Arbitration
    //=================================
    `SVTEST(test_priority_rotation_arbitration)
      $display("============== 3. Testing Priority Rotation Arbitration ==============");
      test_base.initialize_signals();
      step(5);
            
      test_packet_cp.header = test_base.create_cp_compute_header(8'h30, NODE_SHADER_0, 8'h00);
      test_packet_cp.data = 256'hA5A5A5A5_5A5A5A5A_F0F0F0F0_0F0F0F0F_CCCCCCCC_33333333_AAAAAAAA_55555555;
      test_packet_cp.strb = 32'hFFFFFFFF;
      
      test_packet_mmu = test_base.create_mmu_mem_read_packet(8'h40, 8'h10,
                          256'h12345678_9ABCDEF0_FEDCBA98_76543210_ABCDEF01_23456789_DEADBEEF_CAFEBABE,
                          32'hFFFFFFFF);
      
      // **Round 1**: Test initial priority (priority=0, CP has higher priority)
      $display("@%0t: Round 1 - Initial priority=0, CP should win", $time);
      
      // Send both requests simultaneously (NOC not ready)
      test_base.send_request(cp_if, test_packet_cp);
      test_base.send_request(mmu_if, test_packet_mmu);
      step(1);
      nextSamplePoint();
      
      // CP should be selected (priority 0), valid forwarded immediately but ready = 0
      $display("@%0t: Check CP wins arbitration", $time);
      `FAIL_IF(dut.arb_state !== dut.REQ_ARB_CP)
      `FAIL_IF(cp_if.m_req_ready !== 1'b0)       // NOC not ready
      `FAIL_IF(mmu_if.m_req_ready !== 1'b0)      // MMU not selected, so not ready
      `FAIL_IF(noc_if.m_req_valid !== 1'b1)      // ✅ CP's valid should be forwarded
      `FAIL_IF(noc_if.m_req_header !== test_packet_cp.header)  // CP's header forwarded
      
      // Enable NOC to complete CP handshake
      noc_if.m_req_ready = 1'b1;
      step(1);
      nextSamplePoint();
      
      // CP transaction completes, returns to IDLE first
      $display("@%0t: Check CP transaction completion", $time);
      // CP transaction completes, state returns to IDLE
      `FAIL_IF(dut.arb_state !== dut.REQ_ARB_IDLE)
      
      // Clear CP request BEFORE MMU arbitration to avoid double flip
      // This prevents second priority flip when IDLE → REQ_ARB_MMU
      test_base.clear_request(cp_if);
      
      // Wait one more cycle for MMU arbitration
      step(1);
      nextSamplePoint();
      
      // Now state should transition to MMU since MMU request is still pending
      $display("@%0t: Check MMU arbitration after CP completion", $time);
      `FAIL_IF(dut.arb_state !== dut.REQ_ARB_MMU)
      `FAIL_IF(mmu_if.m_req_ready !== 1'b1)      // NOC ready, so MMU ready
      
      // Verify MMU request is being forwarded
      test_base.verify_request_forwarding(test_packet_mmu);
      step(1);
      nextSamplePoint();
      
      // MMU transaction should be complete now, state should return to IDLE
      $display("@%0t: Check MMU transaction completion", $time);
      `FAIL_IF(dut.arb_state !== dut.REQ_ARB_IDLE)
      
      // Now safe to clear MMU request
      test_base.clear_request(mmu_if);
      
      // Check priority flip
      $display("@%0t: Check priority flip", $time);
      `FAIL_IF(dut.arb_priority !== 1'b1)        // Priority should flip
      
      // **Round 2**: Test flipped priority (priority=1, MMU has higher priority)
      $display("@%0t: Round 2 - Flipped priority=1, MMU should win", $time);
      
      // Reset NOC ready for controlled timing
      noc_if.m_req_ready = 1'b0;
      step(1);
      
      // Send both requests again
      test_base.send_request(cp_if, test_packet_cp);
      test_base.send_request(mmu_if, test_packet_mmu);
      step(1);
      nextSamplePoint();
      
      // MMU should be selected first now (priority 1), valid forwarded but ready = 0
      $display("@%0t: Check MMU wins arbitration", $time);
      `FAIL_IF(dut.arb_state !== dut.REQ_ARB_MMU)
      `FAIL_IF(mmu_if.m_req_ready !== 1'b0)      // NOC not ready yet
      `FAIL_IF(cp_if.m_req_ready !== 1'b0)       // CP should not be selected
      `FAIL_IF(noc_if.m_req_valid !== 1'b1)      // ✅ MMU's valid should be forwarded
      `FAIL_IF(noc_if.m_req_header !== test_packet_mmu.header)  // MMU's header forwarded
      
      // Enable NOC to complete MMU handshake
      noc_if.m_req_ready = 1'b1;
      step(1);
      nextSamplePoint();
      
      // MMU transaction completes, returns to IDLE first
      $display("@%0t: Check MMU transaction completion", $time);
      // MMU transaction completes, state returns to IDLE
      `FAIL_IF(dut.arb_state !== dut.REQ_ARB_IDLE)
      
      // Wait one more cycle for CP arbitration
      step(1);
      nextSamplePoint();
      
      // Now state should transition to CP since CP request is still pending
      $display("@%0t: Check CP arbitration after MMU completion", $time);
      `FAIL_IF(dut.arb_state !== dut.REQ_ARB_CP)
      `FAIL_IF(cp_if.m_req_ready !== 1'b1)       // NOC ready, so CP ready
      test_base.verify_request_forwarding(test_packet_cp);
      
      // Let CP transaction complete, then clean up
      // Clear MMU first since it's already done
      test_base.clear_request(mmu_if);
      step(1);
      nextSamplePoint();
      
      // CP transaction should be complete now
      $display("@%0t: Check final CP transaction completion", $time);
      `FAIL_IF(dut.arb_state !== dut.REQ_ARB_IDLE)
      
      // Now safe to clear CP request
      test_base.clear_request(cp_if);
      
      $display("============== 3. Priority rotation arbitration test passed ==============");
    `SVTEST_END
    
    //=================================
    // Test Response Routing
    //=================================
    `SVTEST(test_response_routing)
      $display("============== 4. Testing Response Routing ==============");
      test_base.initialize_signals();
      step(5);
            
      // Test response routing to Command Processor - local_addr 0x0x
      resp_packet = test_base.create_mem_read_response_packet(8'h50, 8'h05, 
                     256'h87654321_FEDCBA98_76543210_ABCDEF01_23456789_DEADBEEF_CAFEBABE_12345678);
      
      cp_if.m_resp_ready = 1'b0;  // Start with CP not ready
      test_base.send_response(8'h05, resp_packet);
      step(1);
      nextSamplePoint();
      
      // Verify routing state and response forwarding
      `FAIL_IF(dut.route_state !== dut.RESP_ROUTE_CP)
      test_base.verify_response_routing(cp_if, resp_packet);
      
      // Now make CP ready to complete the handshake
      cp_if.m_resp_ready = 1'b1;
      step(1);
      nextSamplePoint();
      
      // Should return to idle after handshake
      `FAIL_IF(dut.route_state !== dut.RESP_ROUTE_IDLE)
      
      test_base.clear_response();
      cp_if.m_resp_ready = 1'b0;
      
      // Test response routing to MMU - local_addr 0x1x
      resp_packet.header = test_base.create_mem_write_resp_header(8'h60, 8'h15);
      mmu_if.m_resp_ready = 1'b0;  // Start with MMU not ready
      cp_if.m_resp_ready = 1'b0;
      
      test_base.send_response(8'h15, resp_packet);
      step(1);
      nextSamplePoint();
      
      // Verify routing state and response forwarding
      `FAIL_IF(dut.route_state !== dut.RESP_ROUTE_MMU)
      test_base.verify_response_routing(mmu_if, resp_packet);
      
      // Now make MMU ready to complete the handshake
      mmu_if.m_resp_ready = 1'b1;
      step(1);
      nextSamplePoint();
      
      // Should return to idle after handshake
      `FAIL_IF(dut.route_state !== dut.RESP_ROUTE_IDLE)
      
      test_base.clear_response();
      mmu_if.m_resp_ready = 1'b0;
      
      $display("============== 4. Response routing test passed ==============");
    `SVTEST_END
    
    //=================================
    // Test Slave Interface Direct Connection to MMU
    //=================================
    `SVTEST(test_slave_interface_direct_connection)
      $display("============== 5. Testing Slave Interface Direct Connection to MMU ==============");
      test_base.initialize_signals();
      step(5);
      
      // **CRITICAL**: All NOC slave requests are forwarded to MMU ONLY
      // CP slave interface is unused (CP only acts as master)
      
      // Test slave request forwarding (NOC -> MMU)
      slave_req_packet.header = test_base.create_slave_request_header(8'h70, 8'h10);
      slave_req_packet.data = 256'hAABBCCDD_EEFF0011_22334455_66778899_AABBCCDD_EEFF0011_22334455_66778899;
      slave_req_packet.strb = 32'hFFFFFFFF;
      
      // Set MMU ready to accept slave requests
      mmu_if.s_req_ready = 1'b1;
      
      // Send slave request from NOC
      test_base.send_slave_request(slave_req_packet);
      step(1);
      nextSamplePoint();
      
      // Verify: NOC slave request is directly forwarded to MMU
      test_base.verify_slave_request_forwarding(slave_req_packet);
      `FAIL_IF(noc_if.s_req_ready !== 1'b1)  // NOC should be ready when MMU is ready
      
      // Verify: CP slave interface remains unused
      `FAIL_IF(cp_if.s_req_valid !== 1'b0)   // CP should never receive slave requests
      `FAIL_IF(cp_if.s_req_ready !== 1'b0)   // CP slave interface should be tied off
      
      test_base.clear_slave_request();
      
      // Test slave response forwarding (MMU -> NOC)
      slave_resp_packet.header = test_base.create_slave_response_header(8'h80, 8'h00);
      slave_resp_packet.data = 256'h11223344_55667788_99AABBCC_DDEEFF00_11223344_55667788_99AABBCC_DDEEFF00;
      slave_resp_packet.strb = 32'hFFFFFFFF;
      
      // Set NOC ready to accept slave responses
      noc_if.s_resp_ready = 1'b1;
      
      // Send slave response from MMU
      mmu_if.s_resp_valid = 1'b1;
      mmu_if.s_resp_header = slave_resp_packet.header;
      mmu_if.s_resp_data = slave_resp_packet.data;
      mmu_if.s_resp_status = RESP_OKAY;
      mmu_if.s_resp_last = 1'b1;
      
      step(1);
      nextSamplePoint();
      
      // Verify: MMU slave response is directly forwarded to NOC
      `FAIL_IF(noc_if.s_resp_valid !== 1'b1)
      `FAIL_IF(noc_if.s_resp_header !== slave_resp_packet.header)
      `FAIL_IF(noc_if.s_resp_data !== slave_resp_packet.data)
      `FAIL_IF(noc_if.s_resp_status !== RESP_OKAY)
      `FAIL_IF(noc_if.s_resp_last !== 1'b1)
      `FAIL_IF(mmu_if.s_resp_ready !== 1'b1)  // MMU should be ready when NOC is ready
      
      // Verify: CP slave interface remains unused for responses too
      `FAIL_IF(cp_if.s_resp_valid !== 1'b0)   // CP should never send slave responses
      
      // Clear slave response
      mmu_if.s_resp_valid = 1'b0;
      mmu_if.s_resp_header = 32'h0;
      mmu_if.s_resp_data = 256'h0;
      mmu_if.s_resp_status = RESP_OKAY;
      mmu_if.s_resp_last = 1'b0;
      
      $display("============== 5. Slave interface direct connection to MMU test passed ==============");
    `SVTEST_END
    
    //=================================
    // Test Command Processor Slave Interface (Should be Unused)
    //=================================
    `SVTEST(test_command_processor_slave_unused)
      $display("============== 6. Testing Command Processor Slave Interface (Unused) ==============");
      test_base.initialize_signals();
      step(5);
      
      // Verify that Command Processor slave interface is completely unused
      // This is by design - CP only acts as master, never as slave
      
      // Test various slave request scenarios to confirm CP is never involved
      
      // Scenario 1: Send slave request from NOC
      slave_req_packet.header = test_base.create_slave_write_request_header(8'h90, 8'h10);
      slave_req_packet.data = 256'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
      slave_req_packet.strb = 32'hFFFFFFFF;
      
      mmu_if.s_req_ready = 1'b1;
      test_base.send_slave_request(slave_req_packet);
      step(3);  // Wait a few cycles
      
      // CP slave interface should remain completely inactive
      `FAIL_IF(cp_if.s_req_valid !== 1'b0)    // Never receives requests
      `FAIL_IF(cp_if.s_req_ready !== 1'b0)    // Never ready (tied off)
      `FAIL_IF(cp_if.s_resp_valid !== 1'b0)   // Never sends responses
      `FAIL_IF(cp_if.s_resp_header !== 32'h0) // Always zero
      `FAIL_IF(cp_if.s_resp_data !== 256'h0)  // Always zero
      `FAIL_IF(cp_if.s_resp_status !== 2'b00) // Always zero
      `FAIL_IF(cp_if.s_resp_last !== 1'b0)    // Always zero
      
      test_base.clear_slave_request();
      
      // Scenario 2: Even when MMU responds, CP slave interface stays inactive
      mmu_if.s_resp_valid = 1'b1;
      mmu_if.s_resp_header = 32'hDEADBEEF;
      mmu_if.s_resp_data = 256'hCAFEBABE;
      mmu_if.s_resp_status = RESP_OKAY;
      mmu_if.s_resp_last = 1'b1;
      noc_if.s_resp_ready = 1'b1;
      
      step(3);
      
      // CP slave interface should still be completely inactive
      `FAIL_IF(cp_if.s_req_valid !== 1'b0)
      `FAIL_IF(cp_if.s_req_ready !== 1'b0)  
      `FAIL_IF(cp_if.s_resp_valid !== 1'b0)
      `FAIL_IF(cp_if.s_resp_header !== 32'h0)
      `FAIL_IF(cp_if.s_resp_data !== 256'h0)
      `FAIL_IF(cp_if.s_resp_status !== 2'b00)
      `FAIL_IF(cp_if.s_resp_last !== 1'b0)
      
      // Clean up
      mmu_if.s_resp_valid = 1'b0;
      mmu_if.s_resp_header = 32'h0;
      mmu_if.s_resp_data = 256'h0;
      mmu_if.s_resp_status = RESP_OKAY;
      mmu_if.s_resp_last = 1'b0;
      
      $display("============== 6. Command Processor slave interface unused test passed ==============");
    `SVTEST_END
    
    //=================================
    // Test Unknown Address Range Response Handling
    //=================================
    `SVTEST(test_unknown_address_response)
      $display("============== 7. Testing Unknown Address Range Response Handling ==============");
      test_base.initialize_signals();
      step(5);      
      // Test response with unknown local_addr (0x2x range)
      unknown_resp_packet.header = test_base.create_unknown_response_header(8'h90, 8'h25);
      unknown_resp_packet.data = 256'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
      unknown_resp_packet.strb = 32'hFFFFFFFF;
      
      test_base.send_response(8'h25, unknown_resp_packet);
      step(1);
      nextSamplePoint();
      
      // Should remain in IDLE state and drop the response
      `FAIL_IF(dut.route_state !== dut.RESP_ROUTE_IDLE)
      `FAIL_IF(noc_if.m_resp_ready !== 1'b1)  // Should be ready to drop unknown responses
      
      test_base.clear_response();
      
      $display("============== 7. Unknown address response handling test passed ==============");
    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule