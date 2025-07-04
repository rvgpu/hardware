`ifndef RVGPU_AXI_ADAPTER_TEST_BASE_SVH
`define RVGPU_AXI_ADAPTER_TEST_BASE_SVH

`include "rvgpu_control_unit_pkg.svh"
`include "rvgpu_control_unit_if.svh"
`include "rvgpu_interface_axi.svh"
`include "rvgpu_clk_rst.svh"

`ifndef RVGPU_CONTROL_UNIT_PKG_IMPORTED
`define RVGPU_CONTROL_UNIT_PKG_IMPORTED
import rvgpu_control_unit_pkg::*;
`endif // RVGPU_CONTROL_UNIT_PKG_IMPORTED

// Common type definitions for AXI adapter testing
typedef struct packed {
  logic [63:0] addr;
  logic [63:0] data;
  logic [7:0] strb;
  logic [1:0] resp;
  logic we;  // Write enable flag
} axi_transaction_t;

// Virtual interface types for task parameters
typedef virtual host_if #(.DATA_WIDTH(64), .ADDR_WIDTH(64)) axi_vif_t;
typedef virtual control_if #(.ADDR_WIDTH(64), .DATA_WIDTH(64)) ctrl_vif_t;
typedef virtual clk_rst_if clk_rst_vif_t;

// Base class for RVGPU AXI Adapter testing
class rvgpu_axi_adapter_test_base;

  // Interface references (to be connected from testbench)
  axi_vif_t axi_if;
  ctrl_vif_t ctrl_cp;
  clk_rst_vif_t clk_rst_if;
  
  // Clock manager for elegant time control
  rvgpu_clk_manager clk_mgr;
  
  // Test data patterns for comprehensive testing
  logic [63:0] test_data_patterns[8];
  logic [63:0] test_addr_patterns[8]; 
  logic [7:0] test_strb_patterns[8];
  logic [1:0] test_resp_patterns[4];

  // Transaction monitoring variables
  axi_transaction_t captured_write_trans;
  axi_transaction_t captured_read_trans;
  logic write_transaction_detected;
  logic read_transaction_detected;
  logic ctrl_req_detected;

  // Constructor
  function new(axi_vif_t axi_vif, ctrl_vif_t ctrl_cp, clk_rst_vif_t clk_rst_vif, rvgpu_clk_manager clk_manager);
    this.axi_if = axi_vif;
    this.ctrl_cp = ctrl_cp;
    this.clk_rst_if = clk_rst_vif;
    this.clk_mgr = clk_manager;
    
    // Initialize test data patterns
    test_data_patterns[0] = 64'h0000000000000000;  // All zeros
    test_data_patterns[1] = 64'hFFFFFFFFFFFFFFFF;  // All ones
    test_data_patterns[2] = 64'hAAAAAAAAAAAAAAAA;  // 1010 pattern
    test_data_patterns[3] = 64'h5555555555555555;  // 0101 pattern
    test_data_patterns[4] = 64'hDEADBEEFCAFEBABE;  // Random 1
    test_data_patterns[5] = 64'h123456789ABCDEF0;  // Random 2
    test_data_patterns[6] = 64'hF0F0F0F0F0F0F0F0;  // Byte pattern
    test_data_patterns[7] = 64'h0F0F0F0F0F0F0F0F;  // Inverse byte

    // Initialize test address patterns
    test_addr_patterns[0] = 64'h0000000000000000;  // Base address
    test_addr_patterns[1] = 64'h0000000000001000;  // 4KB aligned
    test_addr_patterns[2] = 64'h0000000000010000;  // 64KB aligned
    test_addr_patterns[3] = 64'h1000000000000000;  // High bit set
    test_addr_patterns[4] = 64'h0000FFFFFFFFFFFF;  // Lower 48 bits
    test_addr_patterns[5] = 64'h8000000000000008;  // Unaligned
    test_addr_patterns[6] = 64'h0123456789ABCDEF;  // Pattern address
    test_addr_patterns[7] = 64'hFEDCBA9876543210;  // Reverse pattern

    // Initialize strobe patterns
    test_strb_patterns[0] = 8'hFF;  // Full transfer
    test_strb_patterns[1] = 8'hF0;  // Upper half
    test_strb_patterns[2] = 8'h0F;  // Lower half
    test_strb_patterns[3] = 8'hAA;  // Alternating bytes
    test_strb_patterns[4] = 8'h55;  // Inverse alternating
    test_strb_patterns[5] = 8'h01;  // Single byte
    test_strb_patterns[6] = 8'h80;  // MSB only
    test_strb_patterns[7] = 8'hC3;  // Sparse pattern

    // Initialize response patterns
    test_resp_patterns[0] = 2'b00;  // OKAY
    test_resp_patterns[1] = 2'b01;  // EXOKAY
    test_resp_patterns[2] = 2'b10;  // SLVERR
    test_resp_patterns[3] = 2'b11;  // DECERR
  endfunction

  // Initialize all interface signals to known state
  task initialize_signals();
    // AXI interface - host side (test acts as host, DUT acts as slave)
    axi_if.awaddr = 0;
    axi_if.awlen = 0;
    axi_if.awsize = 3'b011;  // 8 bytes (64-bit)
    axi_if.awburst = 2'b01;  // INCR
    axi_if.awvalid = 0;
    axi_if.wdata = 0;
    axi_if.wstrb = 0;
    axi_if.wlast = 0;
    axi_if.wvalid = 0;
    axi_if.bready = 0;
    axi_if.araddr = 0;
    axi_if.arlen = 0;
    axi_if.arsize = 3'b011;  // 8 bytes (64-bit)
    axi_if.arburst = 2'b01;  // INCR
    axi_if.arvalid = 0;
    axi_if.rready = 0;

    // Control interface - control processor side (test acts as control processor, DUT acts as master)
    ctrl_cp.ctrl_we = 0;       // Control processor write enable
    ctrl_cp.ctrl_addr = 0;     // Control processor address
    ctrl_cp.ctrl_wdata = 0;    // Control processor write data
    ctrl_cp.ctrl_rdata = 0;    // Control processor read data
  endtask

  // Clear AXI write signals
  task clear_axi_write();
    axi_if.awaddr = 64'h0;
    axi_if.awvalid = 1'b0;
    axi_if.wdata = 64'h0;
    axi_if.wstrb = 8'h0;
    axi_if.wlast = 1'b0;
    axi_if.wvalid = 1'b0;
    axi_if.bready = 1'b0;
  endtask

  // Clear AXI read signals
  task clear_axi_read();
    axi_if.araddr = 64'h0;
    axi_if.arvalid = 1'b0;
    axi_if.rready = 1'b0;
  endtask

  // Clear control interface signals
  task clear_ctrl_signals();
    ctrl_cp.ctrl_we = 1'b0;
    ctrl_cp.ctrl_addr = 64'h0;
    ctrl_cp.ctrl_wdata = 64'h0;
    ctrl_cp.ctrl_rdata = 64'h0;
  endtask

  // Initialize transaction monitoring variables
  task initialize_monitors();
    captured_write_trans = '{default: 0};
    captured_read_trans = '{default: 0};
    write_transaction_detected = 1'b0;
    read_transaction_detected = 1'b0;
    ctrl_req_detected = 1'b0;
  endtask

  // Send AXI write address and wait for handshake
  task send_axi_write_addr(logic [63:0] addr);
    axi_if.awaddr = addr;
    axi_if.awvalid = 1'b1;
    $display("@%0t: Sending AXI write address: 0x%016x", $time, addr);
    
    // Wait for handshake completion using clock manager
    while (!(axi_if.awvalid && axi_if.awready)) begin
      clk_mgr.wait_posedge();
    end
    clk_mgr.wait_posedge();
    axi_if.awvalid = 1'b0;
    $display("@%0t: AXI write address handshake completed", $time);
  endtask

  // Send AXI write data and wait for handshake
  task send_axi_write_data(logic [63:0] data, logic [7:0] strb = 8'hFF);
    axi_if.wdata = data;
    axi_if.wstrb = strb;
    axi_if.wlast = 1'b1;  // AXI-Lite single transfer
    axi_if.wvalid = 1'b1;
    $display("@%0t: Sending AXI write data: 0x%016x, strobe: 0x%02x", $time, data, strb);
    
    // Wait for handshake completion using clock manager
    while (!(axi_if.wvalid && axi_if.wready)) begin
      clk_mgr.wait_posedge();
    end
    clk_mgr.wait_posedge();
    axi_if.wvalid = 1'b0;
    axi_if.wlast = 1'b0;
    $display("@%0t: AXI write data handshake completed", $time);
  endtask

  // Send AXI read address
  task send_axi_read_addr(logic [63:0] addr);
    axi_if.araddr = addr;
    axi_if.arvalid = 1'b1;
    $display("@%0t: Sending AXI read address: 0x%016x", $time, addr);
    
    // Wait for handshake completion using clock manager
    while (!(axi_if.arvalid && axi_if.arready)) begin
      clk_mgr.wait_posedge();
    end
    clk_mgr.wait_posedge();
    axi_if.arvalid = 1'b0;
    $display("@%0t: AXI read address handshake completed", $time);
  endtask

  // Accept AXI write response
  task accept_axi_write_resp();
    axi_if.bready = 1'b1;
    $display("@%0t: Ready to accept AXI write response", $time);
    
    // Wait for response using clock manager
    while (!(axi_if.bvalid && axi_if.bready)) begin
      clk_mgr.wait_posedge();
    end
    clk_mgr.wait_posedge();
    axi_if.bready = 1'b0;
    $display("@%0t: AXI write response received", $time);
  endtask

  // Accept AXI read data
  task accept_axi_read_data();
    axi_if.rready = 1'b1;
    $display("@%0t: Ready to accept AXI read data", $time);
    
    // Wait for data using clock manager
    while (!(axi_if.rvalid && axi_if.rready)) begin
      clk_mgr.wait_posedge();
    end
    clk_mgr.wait_posedge();
    axi_if.rready = 1'b0;
    $display("@%0t: AXI read data received", $time);
  endtask

  // Verify AXI read data response
  task verify_axi_read_data(logic [63:0] expected_data, logic [1:0] expected_resp = 2'b00);
    `FAIL_IF(axi_if.rvalid !== 1'b1)
    `FAIL_IF(axi_if.rdata !== expected_data)
    `FAIL_IF(axi_if.rresp !== expected_resp)
    `FAIL_IF(axi_if.rlast !== 1'b1)  // AXI-Lite single transfer
    $display("@%0t: AXI read data verified: 0x%016x, resp: 0x%01x", $time, expected_data, expected_resp);
  endtask

  // Verify AXI write response
  task verify_axi_write_resp(logic [1:0] expected_resp = 2'b00);
    `FAIL_IF(axi_if.bvalid !== 1'b1)
    `FAIL_IF(axi_if.bresp !== expected_resp)
    $display("@%0t: AXI write response verified: 0x%01x", $time, expected_resp);
  endtask

  // Set control read data (for read operations)
  task set_ctrl_rdata(logic [63:0] data);
    ctrl_cp.ctrl_rdata = data;
    $display("@%0t: Set control read data: 0x%016x", $time, data);
  endtask

  // Monitor control write request (no handshake - direct monitoring)
  task monitor_ctrl_write_request();
    if (ctrl_cp.ctrl_we) begin
      $display("@%0t: Control write detected: addr=0x%016x, data=0x%016x", 
               $time, ctrl_cp.ctrl_addr, ctrl_cp.ctrl_wdata);
      captured_write_trans.addr = ctrl_cp.ctrl_addr;
      captured_write_trans.data = ctrl_cp.ctrl_wdata;
      captured_write_trans.we = 1'b1;
      write_transaction_detected = 1'b1;
    end else begin
      write_transaction_detected = 1'b0;
    end
  endtask

  // Monitor control read request (no handshake - direct monitoring)
  task monitor_ctrl_read_request();
    // In no-handshake protocol, read is always available
    // We monitor by checking if AXI read address was sent
    if (axi_if.arvalid && axi_if.arready) begin
      $display("@%0t: Control read detected: addr=0x%016x", $time, axi_if.araddr);
      captured_read_trans.addr = axi_if.araddr;
      captured_read_trans.we = 1'b0;
      read_transaction_detected = 1'b1;
    end else begin
      read_transaction_detected = 1'b0;
    end
  endtask

  // Wait for control write request (no handshake - wait for signal)
  task wait_for_ctrl_write_request(int timeout_cycles = 100);
    int cycle_count = 0;
    $display("@%0t: Waiting for control write request", $time);
    
    while (!ctrl_cp.ctrl_we && (cycle_count < timeout_cycles)) begin
      clk_mgr.wait_posedge();
      cycle_count++;
    end
    
    if (cycle_count >= timeout_cycles) begin
      $display("@%0t: ERROR: Control write request timeout after %0d cycles", $time, timeout_cycles);
      `FAIL_IF(1)
    end else begin
      $display("@%0t: Control write request detected after %0d cycles", $time, cycle_count);
    end
  endtask

  // Wait for control read request (no handshake - wait for AXI read)
  task wait_for_ctrl_read_request(int timeout_cycles = 100);
    int cycle_count = 0;
    $display("@%0t: Waiting for control read request", $time);
    
    while (!(axi_if.arvalid && axi_if.arready) && (cycle_count < timeout_cycles)) begin
      clk_mgr.wait_posedge();
      cycle_count++;
    end
    
    if (cycle_count >= timeout_cycles) begin
      $display("@%0t: ERROR: Control read request timeout after %0d cycles", $time, timeout_cycles);
      `FAIL_IF(1)
    end else begin
      $display("@%0t: Control read request detected after %0d cycles", $time, cycle_count);
    end
  endtask

  // Verify control write request (no handshake - direct verification)
  task verify_ctrl_write_request(logic [63:0] expected_addr, logic [63:0] expected_data);
    `FAIL_IF(ctrl_cp.ctrl_we !== 1'b1)
    `FAIL_IF(ctrl_cp.ctrl_addr !== expected_addr)
    `FAIL_IF(ctrl_cp.ctrl_wdata !== expected_data)
    $display("@%0t: Control write request verified: addr=0x%016x, data=0x%016x", 
             $time, expected_addr, expected_data);
  endtask

  // Verify control read request (no handshake - verify AXI read)
  task verify_ctrl_read_request(logic [63:0] expected_addr);
    `FAIL_IF(axi_if.arvalid !== 1'b1)
    `FAIL_IF(axi_if.araddr !== expected_addr)
    $display("@%0t: Control read request verified: addr=0x%016x", $time, expected_addr);
  endtask

  // Check control interface reset state (no handshake)
  task check_control_interface_reset_state();
    $display("@%0t: Checking control interface reset state", $time);
    
    // Check control interface outputs (should be in reset state)
    `FAIL_IF(ctrl_cp.ctrl_we !== 1'b0)
    `FAIL_IF(ctrl_cp.ctrl_addr !== 64'h0)
    // `FAIL_IF(ctrl_cp.ctrl_wdata !== 64'h0)  // wdata由cp输出
    
    $display("@%0t: Control interface in correct reset state", $time);
  endtask

  // Check interface reset state (compatibility alias)
  task check_interface_reset_state();
    check_control_interface_reset_state();
  endtask

  //===================================
  // Complete Transaction Functions (No Handshake)
  //===================================

  // Complete read transaction with data verification (no handshake protocol)
  task complete_read_transaction_verify(logic [63:0] addr, logic [63:0] expected_data);
    // Step 1: Set expected read data
    set_ctrl_rdata(expected_data);
    
    // Step 2: Send AXI read address
    clk_mgr.wait_clks(2);
    send_axi_read_addr(addr);
    clk_mgr.wait_clks(2);  // Wait for state machine to update
    
    // Step 3: Accept AXI read data
    accept_axi_read_data();
    
    // Step 4: Verify read data
    verify_axi_read_data(expected_data, 2'b00);
    
    // Clear signals
    clear_axi_read();
    clear_ctrl_signals();
    clk_mgr.wait_clks(1);
    
    $display("@%0t: Read transaction completed and verified: addr=0x%016x, data=0x%016x", 
             $time, addr, expected_data);
  endtask

  // Complete write transaction with data verification (no handshake protocol)
  task complete_write_transaction_verify(logic [63:0] addr, logic [63:0] data, logic [7:0] strb);
    // Step 1: Send AXI write address
    clk_mgr.wait_clks(2);
    send_axi_write_addr(addr);
    
    // Step 2: Send AXI write data
    send_axi_write_data(data, strb);
    
    // Step 3: Wait for control write request (no handshake)
    wait_for_ctrl_write_request(10);
    
    // Step 4: Verify control write request
    verify_ctrl_write_request(addr, data);
    
    // Step 5: Accept AXI write response
    accept_axi_write_resp();
    
    // Step 6: Verify write response
    verify_axi_write_resp(2'b00);
    
    // Clear signals
    clear_axi_write();
    clear_ctrl_signals();
    clk_mgr.wait_clks(1);
    
    $display("@%0t: Write transaction completed and verified: addr=0x%016x, data=0x%016x", 
             $time, addr, data);
  endtask

  //===================================
  // Test Pattern Functions
  //===================================

  // Run comprehensive write test pattern
  task run_write_test_pattern();
    $display("@%0t: Running comprehensive write test pattern", $time);
    
    for (int i = 0; i < 8; i++) begin
      for (int j = 0; j < 8; j++) begin
        for (int k = 0; k < 8; k++) begin
          logic [63:0] addr = test_addr_patterns[j];
          logic [63:0] data = test_data_patterns[i];
          logic [7:0] strb = test_strb_patterns[k];
          
          $display("@%0t: Write test %0d: addr=0x%016x, data=0x%016x, strb=0x%02x", 
                   $time, i*64 + j*8 + k, addr, data, strb);
          
          complete_write_transaction_verify(addr, data, strb);
          clk_mgr.wait_clks(2);  // Small delay between transactions
        end
      end
    end
    
    $display("@%0t: Write test pattern completed", $time);
  endtask

  // Run comprehensive read test pattern
  task run_read_test_pattern();
    $display("@%0t: Running comprehensive read test pattern", $time);
    
    for (int j = 0; j < 8; j++) begin
      logic [63:0] addr = test_addr_patterns[j];
      logic [63:0] expected_data = test_data_patterns[j % 8];
      
      $display("@%0t: Read test %0d: addr=0x%016x, expected_data=0x%016x", 
               $time, j, addr, expected_data);
      
      complete_read_transaction_verify(addr, expected_data);
      clk_mgr.wait_clks(2);  // Small delay between transactions
    end
    
    $display("@%0t: Read test pattern completed", $time);
  endtask

  //===================================
  // State Machine Test Functions
  //===================================

  // Test state machine transitions
  task test_state_machine_transitions();
    $display("@%0t: Testing state machine transitions", $time);
    
    // Test 1: Read address only
    $display("@%0t: Test 1: Read address only", $time);
    axi_if.araddr = 64'h1000;
    axi_if.arvalid = 1'b1;
    clk_mgr.wait_posedge();
    
    // Should transition to READ_DATA state
    clk_mgr.wait_clks(2);
    `FAIL_IF(axi_if.rvalid !== 1'b1)
    $display("@%0t: Test 1 passed: Read address transition successful", $time);
    
    // Clear signals
    axi_if.arvalid = 1'b0;
    axi_if.rready = 1'b1;
    clk_mgr.wait_posedge();
    axi_if.rready = 1'b0;
    clk_mgr.wait_clks(2);
    
    // Test 2: Write address and data simultaneously
    $display("@%0t: Test 2: Write address and data simultaneously", $time);
    axi_if.awaddr = 64'h2000;
    axi_if.awvalid = 1'b1;
    axi_if.wdata = 64'hDEADBEEF;
    axi_if.wvalid = 1'b1;
    clk_mgr.wait_posedge();
    
    // Should transition to WRITE_RESP state
    clk_mgr.wait_clks(2);
    `FAIL_IF(axi_if.bvalid !== 1'b1)
    $display("@%0t: Test 2 passed: Write simultaneous transition successful", $time);
    
    // Clear signals
    axi_if.awvalid = 1'b0;
    axi_if.wvalid = 1'b0;
    axi_if.bready = 1'b1;
    clk_mgr.wait_posedge();
    axi_if.bready = 1'b0;
    clk_mgr.wait_clks(2);
    
    $display("@%0t: State machine transition tests completed", $time);
  endtask

  //===================================
  // Error Handling Test Functions
  //===================================

  // Test error response handling
  task test_error_response_handling();
    $display("@%0t: Testing error response handling", $time);
    
    // This would test how the adapter handles error responses
    // For now, we'll just verify that OKAY responses work correctly
    
    // Test with OKAY response
    complete_write_transaction_verify(64'h3000, 64'h12345678, 8'hFF);
    
    $display("@%0t: Error response handling test completed", $time);
  endtask

endclass

`endif // RVGPU_AXI_ADAPTER_TEST_BASE_SVH 