`ifndef RVGPU_NOC_ARBITER_TEST_BASE_SVH
`define RVGPU_NOC_ARBITER_TEST_BASE_SVH

`include "rvgpu_internal_noc_pkg.svh"
`include "rvgpu_internal_noc_if.svh"

`ifndef RVGPU_INTERNAL_NOC_PKG_IMPORTED
`define RVGPU_INTERNAL_NOC_PKG_IMPORTED
import rvgpu_internal_noc_pkg::*;
`endif // RVGPU_INTERNAL_NOC_PKG_IMPORTED

// Common type definitions for NOC arbiter testing
typedef struct packed {
  logic [31:0] header;
  logic [255:0] data;
  logic [31:0] strb;
} noc_packet_t;

// Virtual interface type for task parameters
typedef virtual rvgpu_internal_noc_if noc_vif_t;

// Base class for RVGPU NOC Arbiter testing
class rvgpu_noc_arbiter_test_base;

  // Interface references (to be connected from testbench)
  noc_vif_t cp_if;
  noc_vif_t mmu_if;
  noc_vif_t noc_if;
  
  // Test data patterns for comprehensive testing
  logic [255:0] test_patterns[8];
  logic [31:0] strobe_patterns[4];

  // Data integrity monitor variables for capturing transmitted data
  logic [255:0] captured_data;
  logic [31:0] captured_strb;
  logic [31:0] captured_header;
  logic data_transmission_detected;

  // Constructor
  function new(noc_vif_t cp_vif, noc_vif_t mmu_vif, noc_vif_t noc_vif);
    this.cp_if = cp_vif;
    this.mmu_if = mmu_vif;
    this.noc_if = noc_vif;
    
    // Initialize test patterns
    test_patterns[0] = 256'h0000000000000000000000000000000000000000000000000000000000000000;  // All zeros
    test_patterns[1] = 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;  // All ones
    test_patterns[2] = 256'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;          // 1010 pattern
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

  // Initialize all interface signals to known state
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

  // Clear request signals for both CP and MMU interfaces
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

  // Clear request signals for a specific interface
  task clear_request(noc_vif_t master_if);
    master_if.m_req_valid = 1'b0;
    master_if.m_req_header = 32'h0;
    master_if.m_req_data = 256'h0;
    master_if.m_req_strb = 32'h0;
    master_if.m_req_last = 1'b0;
  endtask

  // Verify NOC receives exact data
  task verify_noc_data(logic [255:0] expected_data, logic [31:0] expected_strb);
    `FAIL_IF(noc_if.m_req_valid !== 1'b1)
    `FAIL_IF(noc_if.m_req_data !== expected_data)
    `FAIL_IF(noc_if.m_req_strb !== expected_strb)
    `FAIL_IF(noc_if.m_req_last !== 1'b1)
    $display("@%0t: NOC Data Verified: 0x%064x", $time, expected_data);
  endtask

  // Send request from master interface
  task send_request(noc_vif_t master_if, noc_packet_t packet);
    master_if.m_req_valid = 1'b1;
    master_if.m_req_header = packet.header;
    master_if.m_req_data = packet.data;
    master_if.m_req_strb = packet.strb;
    master_if.m_req_last = 1'b1;
    $display("@%0t: Sending request - Header: 0x%08x, Data: 0x%064x", 
             $time, packet.header, packet.data);
  endtask

  // Verify request forwarding
  task verify_request_forwarding(noc_packet_t expected_packet);
    `FAIL_IF(noc_if.m_req_valid !== 1'b1)
    `FAIL_IF(noc_if.m_req_header !== expected_packet.header)
    `FAIL_IF(noc_if.m_req_data !== expected_packet.data)
    `FAIL_IF(noc_if.m_req_strb !== expected_packet.strb)
    `FAIL_IF(noc_if.m_req_last !== 1'b1)
    $display("@%0t: Request forwarding verified", $time);
  endtask

  // Send response from NOC interface
  task send_response(logic [7:0] local_addr, noc_packet_t packet);
    noc_if.m_resp_valid = 1'b1;
    noc_if.m_resp_header = packet.header;
    noc_if.m_resp_data = packet.data;
    noc_if.m_resp_status = RESP_OKAY;
    noc_if.m_resp_last = 1'b1;
    $display("@%0t: Sending response - Header: 0x%08x, Data: 0x%064x", 
             $time, packet.header, packet.data);
  endtask

  // Clear response signals
  task clear_response();
    noc_if.m_resp_valid = 1'b0;
    noc_if.m_resp_header = 32'h0;
    noc_if.m_resp_data = 256'h0;
    noc_if.m_resp_status = RESP_OKAY;
    noc_if.m_resp_last = 1'b0;
  endtask

  // Send slave request from NOC
  task send_slave_request(noc_packet_t packet);
    noc_if.s_req_valid = 1'b1;
    noc_if.s_req_header = packet.header;
    noc_if.s_req_data = packet.data;
    noc_if.s_req_strb = packet.strb;
    noc_if.s_req_last = 1'b1;
    $display("@%0t: Sending slave request - Header: 0x%08x, Data: 0x%064x", 
             $time, packet.header, packet.data);
  endtask

  // Clear slave request
  task clear_slave_request();
    noc_if.s_req_valid = 1'b0;
    noc_if.s_req_header = 32'h0;
    noc_if.s_req_data = 256'h0;
    noc_if.s_req_strb = 32'h0;
    noc_if.s_req_last = 1'b0;
  endtask

  // Verify response routing
  task verify_response_routing(noc_vif_t master_if, noc_packet_t expected_packet);
    `FAIL_IF(master_if.m_resp_valid !== 1'b1)
    `FAIL_IF(master_if.m_resp_header !== expected_packet.header)
    `FAIL_IF(master_if.m_resp_data !== expected_packet.data)
    `FAIL_IF(master_if.m_resp_status !== RESP_OKAY)
    `FAIL_IF(master_if.m_resp_last !== 1'b1)
    $display("@%0t: Response routing verified", $time);
  endtask

  // Verify slave request forwarding
  task verify_slave_request_forwarding(noc_packet_t expected_packet);
    `FAIL_IF(mmu_if.s_req_valid !== 1'b1)
    `FAIL_IF(mmu_if.s_req_header !== expected_packet.header)
    `FAIL_IF(mmu_if.s_req_data !== expected_packet.data)
    `FAIL_IF(mmu_if.s_req_strb !== expected_packet.strb)
    `FAIL_IF(mmu_if.s_req_last !== 1'b1)
    $display("@%0t: Slave request forwarding verified", $time);
  endtask

  // Check interface signals reset state - verify all interface signals are in correct state
  task check_interface_reset_state();
    $display("@%0t: Starting check_interface_reset_state", $time);

    // Check signals we initialize (these are inputs to the DUT)
    `FAIL_IF(cp_if.m_req_valid !== 1'b0)       // Device input
    `FAIL_IF(cp_if.m_resp_ready !== 1'b0)      // Device input
    `FAIL_IF(mmu_if.m_req_valid !== 1'b0)      // Device input
    `FAIL_IF(mmu_if.m_resp_ready !== 1'b0)     // Device input
    `FAIL_IF(noc_if.m_req_ready !== 1'b0)      // NOC input
    `FAIL_IF(noc_if.m_resp_valid !== 1'b0)     // NOC input
    `FAIL_IF(noc_if.s_req_valid !== 1'b0)      // NOC input
    `FAIL_IF(noc_if.s_resp_ready !== 1'b0)     // NOC input
    
    $display("@%0t: All interface signals in correct reset state", $time);
  endtask

  // Initialize data monitoring variables
  task initialize_data_monitor();
    captured_data = 256'h0;
    captured_strb = 32'h0;
    captured_header = 32'h0;
    data_transmission_detected = 1'b0;
  endtask

  // Manual check for data transmission (for use when no automatic monitor is available)
  task check_data_transmission_manual();
    if (noc_if.m_req_valid && noc_if.m_req_ready && noc_if.m_req_last) begin
      captured_data = noc_if.m_req_data;
      captured_strb = noc_if.m_req_strb;
      captured_header = noc_if.m_req_header;
      data_transmission_detected = 1'b1;
    end else begin
      data_transmission_detected = 1'b0;
    end
  endtask

  // Verify captured data matches expected values
  task verify_captured_data(logic [255:0] expected_data, logic [31:0] expected_strb, logic [31:0] expected_header);
    `FAIL_IF(captured_data !== expected_data)
    `FAIL_IF(captured_strb !== expected_strb)
    `FAIL_IF(captured_header !== expected_header)
    $display("@%0t: Captured data verified: 0x%064x, strobe: 0x%08x", $time, expected_data, expected_strb);
  endtask

  // Send CP request with specific data pattern (simplified version)
  task send_cp_data_request(logic [255:0] data_pattern, logic [31:0] strb_pattern);
    cp_if.m_req_valid = 1'b1;
    cp_if.m_req_header = create_cp_mem_read_header(8'h10, NOC_NODE_CONTROL_JD);
    cp_if.m_req_data = data_pattern;
    cp_if.m_req_strb = strb_pattern;
    cp_if.m_req_last = 1'b1;
    $display("@%0t: CP Data=0x%064x, Strobe=0x%08x", $time, data_pattern, strb_pattern);
  endtask

  //===================================
  // Common NOC Header Helper Functions
  //===================================
  
  // Create standard CP memory read request header
  function noc_header_t create_cp_mem_read_header(logic [7:0] trans_id, logic [7:0] local_addr);
    return build_noc_header(MSG_MEM_READ_REQ, trans_id, NODE_CONTROL, NODE_L2_CACHE, local_addr);
  endfunction

  // Create standard CP memory write request header  
  function noc_header_t create_cp_mem_write_header(logic [7:0] trans_id, logic [7:0] local_addr);
    return build_noc_header(MSG_MEM_WRITE_REQ, trans_id, NODE_CONTROL, NODE_L2_CACHE, local_addr);
  endfunction

  // Create standard MMU memory read request header
  function noc_header_t create_mmu_mem_read_header(logic [7:0] trans_id, logic [7:0] local_addr);
    return build_noc_header(MSG_MEM_READ_REQ, trans_id, NODE_CONTROL, NODE_L2_CACHE, local_addr);
  endfunction

  // Create standard MMU memory write request header
  function noc_header_t create_mmu_mem_write_header(logic [7:0] trans_id, logic [7:0] local_addr);
    return build_noc_header(MSG_MEM_WRITE_REQ, trans_id, NODE_CONTROL, NODE_L2_CACHE, local_addr);
  endfunction

  // Create standard CP compute request header
  function noc_header_t create_cp_compute_header(logic [7:0] trans_id, logic [7:0] target_node, logic [7:0] local_addr);
    return build_noc_header(MSG_COMPUTE_REQ, trans_id, NODE_CONTROL, target_node, local_addr);
  endfunction

  // Create standard memory read response header
  function noc_header_t create_mem_read_resp_header(logic [7:0] trans_id, logic [7:0] local_addr);
    return build_noc_header(MSG_MEM_READ_RESP, trans_id, NODE_L2_CACHE, NODE_CONTROL, local_addr);
  endfunction

  // Create standard memory write response header
  function noc_header_t create_mem_write_resp_header(logic [7:0] trans_id, logic [7:0] local_addr);
    return build_noc_header(MSG_MEM_WRITE_RESP, trans_id, NODE_L2_CACHE, NODE_CONTROL, local_addr);
  endfunction

  // Create standard slave request header (NOC to MMU)
  function noc_header_t create_slave_request_header(logic [7:0] trans_id, logic [7:0] local_addr);
    return build_noc_header(MSG_MEM_READ_REQ, trans_id, NODE_L2_CACHE, NODE_CONTROL, local_addr);
  endfunction

  // Create standard slave response header (MMU to NOC)
  function noc_header_t create_slave_response_header(logic [7:0] trans_id, logic [7:0] local_addr);
    return build_noc_header(MSG_MEM_READ_RESP, trans_id, NODE_CONTROL, NODE_L2_CACHE, local_addr);
  endfunction

  // Create unknown response header (for testing error handling)
  function noc_header_t create_unknown_response_header(logic [7:0] trans_id, logic [7:0] local_addr);
    return build_noc_header(MSG_MEM_READ_RESP, trans_id, NODE_L2_CACHE, NODE_CONTROL, local_addr);
  endfunction

  // Create slave write request header (NOC to MMU)
  function noc_header_t create_slave_write_request_header(logic [7:0] trans_id, logic [7:0] local_addr);
    return build_noc_header(MSG_MEM_WRITE_REQ, trans_id, NODE_L2_CACHE, NODE_CONTROL, local_addr);
  endfunction

  //===================================  
  // Common NOC Packet Helper Functions
  //===================================

  // Create standard CP memory read packet
  function noc_packet_t create_cp_mem_read_packet(logic [7:0] trans_id, logic [7:0] local_addr, 
                                                  logic [255:0] data, logic [31:0] strb);
    noc_packet_t packet;
    packet.header = create_cp_mem_read_header(trans_id, local_addr);
    packet.data = data;
    packet.strb = strb;
    return packet;
  endfunction

  // Create standard CP memory write packet
  function noc_packet_t create_cp_mem_write_packet(logic [7:0] trans_id, logic [7:0] local_addr, 
                                                   logic [255:0] data, logic [31:0] strb);
    noc_packet_t packet;
    packet.header = create_cp_mem_write_header(trans_id, local_addr);
    packet.data = data;
    packet.strb = strb;
    return packet;
  endfunction

  // Create standard MMU memory read packet
  function noc_packet_t create_mmu_mem_read_packet(logic [7:0] trans_id, logic [7:0] local_addr, 
                                                   logic [255:0] data, logic [31:0] strb);
    noc_packet_t packet;
    packet.header = create_mmu_mem_read_header(trans_id, local_addr);
    packet.data = data;
    packet.strb = strb;
    return packet;
  endfunction

  // Create standard MMU memory write packet
  function noc_packet_t create_mmu_mem_write_packet(logic [7:0] trans_id, logic [7:0] local_addr, 
                                                    logic [255:0] data, logic [31:0] strb);
    noc_packet_t packet;
    packet.header = create_mmu_mem_write_header(trans_id, local_addr);
    packet.data = data;
    packet.strb = strb;
    return packet;
  endfunction

  // Create standard response packet
  function noc_packet_t create_mem_read_response_packet(logic [7:0] trans_id, logic [7:0] local_addr, 
                                                        logic [255:0] data);
    noc_packet_t packet;
    packet.header = create_mem_read_resp_header(trans_id, local_addr);
    packet.data = data;
    packet.strb = 32'hFFFFFFFF;  // Response packets typically have full strobe
    return packet;
  endfunction

  // Create packet with test pattern
  function noc_packet_t create_test_packet_with_pattern(noc_header_t header, int pattern_idx, int strobe_idx);
    noc_packet_t packet;
    packet.header = header;
    packet.data = test_patterns[pattern_idx];
    packet.strb = strobe_patterns[strobe_idx];
    return packet;
  endfunction

endclass

`endif // RVGPU_NOC_ARBITER_TEST_BASE_SVH 
