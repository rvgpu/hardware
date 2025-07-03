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
} axi_transaction_t;

// Virtual interface types for task parameters
typedef virtual host_if #(.DATA_WIDTH(64), .ADDR_WIDTH(64)) axi_vif_t;
typedef virtual control_if #(.ADDR_WIDTH(64), .DATA_WIDTH(64)) ctrl_vif_t;
typedef virtual clk_rst_if clk_rst_vif_t;

// Base class for RVGPU AXI Adapter testing
class rvgpu_axi_adapter_test_base;

  // Interface references (to be connected from testbench)
  axi_vif_t axi_if;
  ctrl_vif_t ctrl_if;
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
  logic ctrl_resp_detected;

  // Constructor
  function new(axi_vif_t axi_vif, ctrl_vif_t ctrl_vif, clk_rst_vif_t clk_rst_vif, rvgpu_clk_manager clk_manager);
    this.axi_if = axi_vif;
    this.ctrl_if = ctrl_vif;
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
    ctrl_if.req_ready = 0;     // Control processor ready to accept requests
    ctrl_if.resp_valid = 0;    // Control processor sends responses
    ctrl_if.resp_data = 0;
    ctrl_if.resp_status = 0;
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

  // Clear control interface response signals
  task clear_ctrl_response();
    ctrl_if.resp_valid = 1'b0;
    ctrl_if.resp_data = 64'h0;
    ctrl_if.resp_status = 2'b00;
  endtask

  // Initialize transaction monitoring variables
  task initialize_monitors();
    captured_write_trans = '{default: 0};
    captured_read_trans = '{default: 0};
    write_transaction_detected = 1'b0;
    read_transaction_detected = 1'b0;
    ctrl_req_detected = 1'b0;
    ctrl_resp_detected = 1'b0;
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

  // Send control request response
  task send_ctrl_response(logic [63:0] data, logic [1:0] status = 2'b00);
    ctrl_if.resp_valid = 1'b1;
    ctrl_if.resp_data = data;
    ctrl_if.resp_status = status;
    $display("@%0t: Sending control response: data=0x%016x, status=%0d", $time, data, status);
    
    // Wait for handshake completion using clock manager
    while (!(ctrl_if.resp_valid && ctrl_if.resp_ready)) begin
      clk_mgr.wait_posedge();
    end
    clk_mgr.wait_posedge();
    ctrl_if.resp_valid = 1'b0;
    $display("@%0t: Control response handshake completed", $time);
  endtask

  // Accept control request
  task accept_ctrl_request();
    ctrl_if.req_ready = 1'b1;
    $display("@%0t: Ready to accept control request", $time);
    
    // Wait for request using clock manager
    while (!(ctrl_if.req_valid && ctrl_if.req_ready)) begin
      clk_mgr.wait_posedge();
    end
    clk_mgr.wait_posedge();
    ctrl_if.req_ready = 1'b0;
    $display("@%0t: Control request received", $time);
  endtask

  // Verify AXI write address phase
  task verify_axi_write_addr(logic [63:0] expected_addr);
    `FAIL_IF(axi_if.awvalid !== 1'b1)
    `FAIL_IF(axi_if.awaddr !== expected_addr)
    `FAIL_IF(axi_if.awlen !== 8'h00)  // AXI-Lite single transfer
    `FAIL_IF(axi_if.awsize !== 3'b011)  // 64-bit transfer
    `FAIL_IF(axi_if.awburst !== 2'b01)  // INCR burst
    $display("@%0t: AXI write address verified: 0x%016x", $time, expected_addr);
  endtask

  // Verify AXI write data phase
  task verify_axi_write_data(logic [63:0] expected_data, logic [7:0] expected_strb = 8'hFF);
    `FAIL_IF(axi_if.wvalid !== 1'b1)
    `FAIL_IF(axi_if.wdata !== expected_data)
    `FAIL_IF(axi_if.wstrb !== expected_strb)
    `FAIL_IF(axi_if.wlast !== 1'b1)  // AXI-Lite single transfer
    $display("@%0t: AXI write data verified: 0x%016x, strobe: 0x%02x", $time, expected_data, expected_strb);
  endtask

  // Verify AXI read address phase
  task verify_axi_read_addr(logic [63:0] expected_addr);
    `FAIL_IF(axi_if.arvalid !== 1'b1)
    `FAIL_IF(axi_if.araddr !== expected_addr)
    `FAIL_IF(axi_if.arlen !== 8'h00)  // AXI-Lite single transfer
    `FAIL_IF(axi_if.arsize !== 3'b011)  // 64-bit transfer
    `FAIL_IF(axi_if.arburst !== 2'b01)  // INCR burst
    $display("@%0t: AXI read address verified: 0x%016x", $time, expected_addr);
  endtask

  // Verify AXI write response
  task verify_axi_write_resp(logic [1:0] expected_resp);
    `FAIL_IF(axi_if.bvalid !== 1'b1)
    `FAIL_IF(axi_if.bresp !== expected_resp)
    $display("@%0t: AXI write response verified: 0x%01x", $time, expected_resp);
  endtask

  // Verify AXI read data response
  task verify_axi_read_data(logic [63:0] expected_data, logic [1:0] expected_resp = 2'b00);
    `FAIL_IF(axi_if.rvalid !== 1'b1)
    `FAIL_IF(axi_if.rdata !== expected_data)
    `FAIL_IF(axi_if.rresp !== expected_resp)
    `FAIL_IF(axi_if.rlast !== 1'b1)  // AXI-Lite single transfer
    $display("@%0t: AXI read data verified: 0x%016x, resp: 0x%01x", $time, expected_data, expected_resp);
  endtask

  // Verify control request
  task verify_ctrl_request(logic [63:0] expected_addr, logic [63:0] expected_data, 
                          logic [7:0] expected_strb, logic expected_we);
    `FAIL_IF(ctrl_if.req_valid !== 1'b1)
    `FAIL_IF(ctrl_if.req_addr !== expected_addr)
    `FAIL_IF(ctrl_if.req_data !== expected_data)
    `FAIL_IF(ctrl_if.req_strb !== expected_strb)
    `FAIL_IF(ctrl_if.req_we !== expected_we)
    $display("@%0t: Control request verified: addr=0x%016x, data=0x%016x, strb=0x%02x, we=%b", 
             $time, expected_addr, expected_data, expected_strb, expected_we);
  endtask

  // Check interface reset state
  task check_interface_reset_state();
    $display("@%0t: Checking interface reset state", $time);

    // Check AXI interface inputs (controlled by test)
    `FAIL_IF(axi_if.awvalid !== 1'b0)
    `FAIL_IF(axi_if.wvalid !== 1'b0)
    `FAIL_IF(axi_if.bready !== 1'b0)
    `FAIL_IF(axi_if.arvalid !== 1'b0)
    `FAIL_IF(axi_if.rready !== 1'b0)
    
    // Check control interface inputs (controlled by test)
    `FAIL_IF(ctrl_if.req_ready !== 1'b0)
    `FAIL_IF(ctrl_if.resp_valid !== 1'b0)
    
    $display("@%0t: All interface signals in correct reset state", $time);
  endtask

  // Manual check for control request (for use when no automatic monitor is available)
  task check_ctrl_request_manual();
    if (ctrl_if.req_valid && ctrl_if.req_ready) begin
      ctrl_req_detected = 1'b1;
    end else begin
      ctrl_req_detected = 1'b0;
    end
  endtask

  // Manual check for control response (for use when no automatic monitor is available)
  task check_ctrl_response_manual();
    if (ctrl_if.resp_valid && ctrl_if.resp_ready) begin
      ctrl_resp_detected = 1'b1;
    end else begin
      ctrl_resp_detected = 1'b0;
    end
  endtask

  //===================================
  // Complete Transaction Functions
  //===================================

  // Send complete AXI write transaction
  task send_axi_write_transaction(logic [63:0] addr, logic [63:0] data, logic [7:0] strb = 8'hFF);
    $display("@%0t: Sending complete AXI write: addr=0x%016x, data=0x%016x, strb=0x%02x", 
             $time, addr, data, strb);
    send_axi_write_addr(addr);
    send_axi_write_data(data, strb);
    $display("@%0t: Complete AXI write transaction sent", $time);
  endtask

  // Send complete AXI read transaction
  task send_axi_read_transaction(logic [63:0] addr);
    $display("@%0t: Sending complete AXI read: addr=0x%016x", $time, addr);
    send_axi_read_addr(addr);
    $display("@%0t: Complete AXI read transaction sent", $time);
  endtask

  // Create test write transaction
  function axi_transaction_t create_write_transaction(int pattern_idx, int addr_idx, int strb_idx);
    axi_transaction_t trans;
    trans.addr = test_addr_patterns[addr_idx];
    trans.data = test_data_patterns[pattern_idx];
    trans.strb = test_strb_patterns[strb_idx];
    trans.resp = test_resp_patterns[0];  // Default to OKAY
    return trans;
  endfunction

  // Create test read transaction
  function axi_transaction_t create_read_transaction(int addr_idx);
    axi_transaction_t trans;
    trans.addr = test_addr_patterns[addr_idx];
    trans.data = 64'h0;  // Don't care for read request
    trans.strb = 8'hFF;  // Full read
    trans.resp = test_resp_patterns[0];  // Default to OKAY
    return trans;
  endfunction

endclass

`endif // RVGPU_AXI_ADAPTER_TEST_BASE_SVH 