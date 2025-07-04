`ifndef RVGPU_COMMAND_PROCESSOR_TEST_BASE_SVH
`define RVGPU_COMMAND_PROCESSOR_TEST_BASE_SVH

`include "rvgpu_control_unit_pkg.svh"
`include "rvgpu_control_unit_if.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_clk_rst.svh"

`ifndef RVGPU_CONTROL_UNIT_PKG_IMPORTED
`define RVGPU_CONTROL_UNIT_PKG_IMPORTED
import rvgpu_control_unit_pkg::*;
`endif // RVGPU_CONTROL_UNIT_PKG_IMPORTED

// Common type definitions for Command Processor testing
typedef struct packed {
    logic [63:0] addr;
    logic [63:0] data;
    logic [7:0] strb;
    logic we;
    logic [1:0] resp;
} control_transaction_t;

// Virtual interface types for task parameters
typedef virtual control_if #(.ADDR_WIDTH(64), .DATA_WIDTH(64)) ctrl_vif_t;
typedef virtual rvgpu_internal_noc_if #(.NOC_CONFIG(DEFAULT_NOC_CONFIG)) noc_vif_t;
typedef virtual mmu_if #(.VA_WIDTH(48), .PA_WIDTH(48)) mmu_vif_t;
typedef virtual clk_rst_if clk_rst_vif_t;

// Base class for RVGPU Command Processor testing (No Handshake Protocol)
class rvgpu_command_processor_test_base;

    // Interface references (to be connected from testbench)
    ctrl_vif_t ctrl_cp;
    noc_vif_t noc_if;
    mmu_vif_t mmu_if;
    clk_rst_vif_t clk_rst_if;
    
    // Clock manager for elegant time control
    rvgpu_clk_manager clk_mgr;
    
    // Test data patterns for comprehensive testing
    logic [63:0] test_data_patterns[8];
    logic [63:0] test_addr_patterns[8];

    // Transaction monitoring variables
    logic write_transaction_detected;
    logic read_transaction_detected;
    logic [63:0] captured_write_addr;
    logic [63:0] captured_write_data;
    logic [63:0] captured_read_addr;
    logic [63:0] captured_read_data;

    // Constructor
    function new(ctrl_vif_t ctrl_cp, noc_vif_t noc_if, mmu_vif_t mmu_if, clk_rst_vif_t clk_rst_vif, rvgpu_clk_manager clk_manager);
        this.ctrl_cp = ctrl_cp;
        this.noc_if = noc_if;
        this.mmu_if = mmu_if;
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
    endfunction

    // Initialize all interface signals to known state
    task initialize_signals();
        // Control interface - no handshake protocol
        ctrl_cp.ctrl_we = 0;
        ctrl_cp.ctrl_addr = 0;
        ctrl_cp.ctrl_wdata = 0;
        ctrl_cp.ctrl_rdata = 0;

        // NOC interface - initialize to idle state
        noc_if.m_req_valid = 0;
        noc_if.m_req_header = 0;
        noc_if.m_req_data = 0;
        noc_if.m_req_strb = 0;
        noc_if.m_req_last = 0;
        noc_if.m_resp_ready = 0;
        noc_if.s_req_ready = 0;
        noc_if.s_resp_valid = 0;
        noc_if.s_resp_header = 0;
        noc_if.s_resp_data = 0;
        noc_if.s_resp_status = 2'b00;
        noc_if.s_resp_last = 0;

        // MMU interface - initialize to idle state
        mmu_if.req_valid = 0;
        mmu_if.req_vaddr = 0;
        mmu_if.req_read = 0;
        mmu_if.req_write = 0;
        mmu_if.resp_ready = 1;  // MMU ready to accept requests
        mmu_if.resp_valid = 0;
        mmu_if.resp_paddr = 0;
        mmu_if.resp_hit = 0;
        mmu_if.resp_status = 2'b00;
    endtask

    // Clear control interface signals
    task clear_control_signals();
        ctrl_cp.ctrl_we = 1'b0;
        ctrl_cp.ctrl_addr = 64'h0;
        ctrl_cp.ctrl_wdata = 64'h0;
    endtask

    // Clear NOC interface signals
    task clear_noc_signals();
        noc_if.m_req_valid = 1'b0;
        noc_if.m_req_header = '0;
        noc_if.m_req_data = '0;
        noc_if.m_req_strb = '0;
        noc_if.m_req_last = 1'b0;
        noc_if.m_resp_ready = 1'b0;
    endtask

    // Clear MMU interface signals
    task clear_mmu_signals();
        mmu_if.req_valid = 1'b0;
        mmu_if.req_vaddr = '0;
        mmu_if.req_read = 1'b0;
        mmu_if.req_write = 1'b0;
        mmu_if.resp_ready = 1'b0;
    endtask

    // Initialize transaction monitoring variables
    task initialize_monitors();
        write_transaction_detected = 1'b0;
        read_transaction_detected = 1'b0;
        captured_write_addr = 64'h0;
        captured_write_data = 64'h0;
        captured_read_addr = 64'h0;
        captured_read_data = 64'h0;
    endtask

    //===================================
    // No Handshake Protocol Tasks
    //===================================

    // Write to control register (no handshake - direct write)
    task write_control_reg(logic start, logic reset, logic irq_en);
        logic [63:0] control_data;
        control_data = {61'h0, irq_en, reset, start};
        
        $display("@%0t: Writing control register: start=%0d, reset=%0d, irq_en=%0d", 
                 $time, start, reset, irq_en);
        
        write_register_sync(REG_CONTROL, control_data);
    endtask

    // Read control register (no handshake - direct read)
    task read_control_reg(output logic start, output logic reset, output logic irq_en);
        logic [63:0] control_data;
        
        ctrl_cp.ctrl_addr = REG_CONTROL;
        clk_mgr.wait_posedge();  // Wait for read data to be available
        
        control_data = ctrl_cp.ctrl_rdata;
        start = control_data[0];
        reset = control_data[1];
        irq_en = control_data[2];
        
        $display("@%0t: Read control register: start=%0d, reset=%0d, irq_en=%0d", 
                 $time, start, reset, irq_en);
    endtask

    // Write MMU pagetable address (no handshake - direct write)
    task write_mmu_pagetable_addr(logic [63:0] addr);
        $display("@%0t: Starting MMU pagetable address write: 0x%016x", $time, addr);
        
        // Write low 32 bits using clock-synchronized method
        write_register_sync(REG_MMU_PAGETABLE_LO, {32'h0, addr[31:0]});
        
        // Write high 32 bits using clock-synchronized method
        write_register_sync(REG_MMU_PAGETABLE_HI, {32'h0, addr[63:32]});
        
        $display("@%0t: Wrote MMU pagetable address: 0x%016x", $time, addr);
    endtask

    // Clock-synchronized register write method with proper hold time
    task write_register_sync(logic [15:0] addr, logic [63:0] data);
        // Setup phase: prepare signals before clock edge
        ctrl_cp.ctrl_we = 1'b1;
        ctrl_cp.ctrl_addr = addr;
        ctrl_cp.ctrl_wdata = data;
        
        // Wait for next clock edge to ensure setup time
        clk_mgr.wait_posedge();
        
        #1; // 1ns hold time
        
        // Clear phase: clear write enable after hold time
        ctrl_cp.ctrl_we = 1'b0;
    endtask

    // Read MMU pagetable address (no handshake - direct read)
    task read_mmu_pagetable_addr(output logic [63:0] addr);
        logic [63:0] addr_lo, addr_hi;
        
        // Read low 32 bits
        ctrl_cp.ctrl_addr = REG_MMU_PAGETABLE_LO;
        clk_mgr.wait_posedge();
        addr_lo = ctrl_cp.ctrl_rdata;
        
        // Read high 32 bits
        ctrl_cp.ctrl_addr = REG_MMU_PAGETABLE_HI;
        clk_mgr.wait_posedge();
        addr_hi = ctrl_cp.ctrl_rdata;
        
        // addr_hi contains {32'h0, mmu_pagetable_addr[63:32]}, so extract the high 32 bits
        addr = {addr_hi[31:0], addr_lo[31:0]};
        
        $display("@%0t: Read MMU pagetable address: addr_lo=0x%016x, addr_hi=0x%016x, final=0x%016x", 
                 $time, addr_lo, addr_hi, addr);
    endtask

    // Write command packet address (no handshake - direct write)
    task write_command_packet_addr(logic [63:0] addr);
        // Write low 32 bits using clock-synchronized method
        write_register_sync(REG_COMMAND_PACKET_LO, {32'h0, addr[31:0]});
        
        // Write high 32 bits using clock-synchronized method
        write_register_sync(REG_COMMAND_PACKET_HI, {32'h0, addr[63:32]});
        
        $display("@%0t: Wrote command packet address: 0x%016x", $time, addr);
    endtask

    // Read command packet address (no handshake - direct read)
    task read_command_packet_addr(output logic [63:0] addr);
        logic [63:0] addr_lo, addr_hi;
        
        // Read low 32 bits
        ctrl_cp.ctrl_addr = REG_COMMAND_PACKET_LO;
        clk_mgr.wait_posedge();
        addr_lo = ctrl_cp.ctrl_rdata;
        
        // Read high 32 bits
        ctrl_cp.ctrl_addr = REG_COMMAND_PACKET_HI;
        clk_mgr.wait_posedge();
        addr_hi = ctrl_cp.ctrl_rdata;
        
        addr = {addr_hi[31:0], addr_lo[31:0]};
        
        $display("@%0t: Read command packet address: addr_lo=0x%016x, addr_hi=0x%016x, final=0x%016x", 
                 $time, addr_lo, addr_hi, addr);
    endtask

    // Read status register (no handshake - direct read)
    task read_status_reg(output logic idle, output logic complete, output logic error, output logic mmu_ready);
        logic [63:0] status_data;
        
        ctrl_cp.ctrl_addr = REG_STATUS;
        clk_mgr.wait_posedge();  // Wait for read data to be available
        
        status_data = ctrl_cp.ctrl_rdata;
        idle = status_data[0];
        complete = status_data[1];
        error = status_data[2];
        mmu_ready = status_data[3];
        
        $display("@%0t: Read status register: idle=%0d, complete=%0d, error=%0d, mmu_ready=%0d", 
                 $time, idle, complete, error, mmu_ready);
    endtask

    //===================================
    // Generic Register Access Tasks (No Handshake)
    //===================================

    // Send control write transaction (no handshake)
    task send_control_write_transaction(logic [15:0] addr, logic [63:0] data, logic [7:0] strb = 8'hFF);
        $display("@%0t: Control write: addr=0x%04x, data=0x%016x, strb=0x%02x (strobe ignored)", 
                 $time, addr, data, strb);
        
        // Use the clock-synchronized method for consistent timing
        write_register_sync(addr, data);
    endtask

    // Send control read transaction (no handshake)
    task send_control_read_transaction(logic [15:0] addr);
        ctrl_cp.ctrl_addr = addr;
        
        $display("@%0t: Control read: addr=0x%04x", $time, addr);
        
        clk_mgr.wait_posedge();  // Wait for read data to be available
    endtask

    // Accept control response (no handshake - just get data)
    task accept_control_response();
        logic [63:0] read_data;
        
        read_data = ctrl_cp.ctrl_rdata;
        
        $display("@%0t: Control read response: data=0x%016x", $time, read_data);
    endtask

    //===================================
    // Monitoring Tasks (No Handshake)
    //===================================

    // Monitor control write requests (no handshake - direct monitoring)
    task monitor_control_write_request();
        if (ctrl_cp.ctrl_we) begin
            $display("@%0t: Monitor - Control write detected: addr=0x%04x, data=0x%016x", 
                     $time, ctrl_cp.ctrl_addr[15:0], ctrl_cp.ctrl_wdata);
            captured_write_addr = ctrl_cp.ctrl_addr;
            captured_write_data = ctrl_cp.ctrl_wdata;
            write_transaction_detected = 1'b1;
        end else begin
            write_transaction_detected = 1'b0;
        end
    endtask

    // Monitor control read requests (no handshake - direct monitoring)
    task monitor_control_read_request();
        // In no-handshake protocol, read is always available based on address
        captured_read_addr = ctrl_cp.ctrl_addr;
        captured_read_data = ctrl_cp.ctrl_rdata;
        read_transaction_detected = 1'b1;
        
        $display("@%0t: Monitor - Control read detected: addr=0x%04x, data=0x%016x", 
                 $time, ctrl_cp.ctrl_addr[15:0], ctrl_cp.ctrl_rdata);
    endtask

    // Wait for control write request (no handshake - wait for signal)
    task wait_for_control_write_request(int timeout_cycles = 100);
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

    // Verify control write request (no handshake - direct verification)
    task verify_control_write_request(logic [15:0] expected_addr, logic [63:0] expected_data);
        `FAIL_IF(ctrl_cp.ctrl_we !== 1'b1)
        `FAIL_IF(ctrl_cp.ctrl_addr[15:0] !== expected_addr)
        `FAIL_IF(ctrl_cp.ctrl_wdata !== expected_data)
        $display("@%0t: Control write request verified: addr=0x%04x, data=0x%016x", 
                 $time, expected_addr, expected_data);
    endtask

    // Check control interface reset state (no handshake)
    task check_control_interface_reset_state();
        $display("@%0t: Checking control interface reset state", $time);
        
        // Check control interface outputs (should be in reset state)
        `FAIL_IF(ctrl_cp.ctrl_we !== 1'b0)
        `FAIL_IF(ctrl_cp.ctrl_addr !== 64'h0)
        `FAIL_IF(ctrl_cp.ctrl_wdata !== 64'h0)
        
        $display("@%0t: Control interface in correct reset state", $time);
    endtask

    //===================================
    // Test Pattern Functions
    //===================================

    // Run comprehensive register write test pattern
    task run_register_write_test_pattern();
        logic [63:0] addr, data;
        int i, j;
        
        $display("@%0t: Running comprehensive register write test pattern", $time);
        
        for (i = 0; i < 8; i++) begin
            for (j = 0; j < 8; j++) begin
                addr = test_addr_patterns[j];
                data = test_data_patterns[i];
                
                $display("@%0t: Register write test %0d: addr=0x%016x, data=0x%016x", 
                         $time, i*8 + j, addr, data);
                
                // Write to MMU address register
                write_mmu_pagetable_addr(addr);
                clk_mgr.wait_clks(2);
                
                // Write to command packet address register
                write_command_packet_addr(data);
                clk_mgr.wait_clks(2);
            end
        end
        
        $display("@%0t: Register write test pattern completed", $time);
    endtask

    // Run comprehensive register read test pattern
    task run_register_read_test_pattern();
        logic [63:0] addr, read_data;
        int j;
        
        $display("@%0t: Running comprehensive register read test pattern", $time);
        
        for (j = 0; j < 8; j++) begin
            addr = test_addr_patterns[j];
            
            $display("@%0t: Register read test %0d: addr=0x%016x", $time, j, addr);
            
            // Read from MMU address register
            read_mmu_pagetable_addr(read_data);
            clk_mgr.wait_clks(2);
            
            // Read from command packet address register
            read_command_packet_addr(read_data);
            clk_mgr.wait_clks(2);
        end
        
        $display("@%0t: Register read test pattern completed", $time);
    endtask

endclass

`endif // RVGPU_COMMAND_PROCESSOR_TEST_BASE_SVH 