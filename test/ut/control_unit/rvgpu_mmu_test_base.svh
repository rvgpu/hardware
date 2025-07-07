`ifndef RVGPU_MMU_TEST_BASE_SVH
`define RVGPU_MMU_TEST_BASE_SVH

`include "rvgpu_control_unit_pkg.svh"
`include "rvgpu_control_unit_if.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_clk_rst.svh"

`ifndef RVGPU_CONTROL_UNIT_PKG_IMPORTED
`define RVGPU_CONTROL_UNIT_PKG_IMPORTED
import rvgpu_control_unit_pkg::*;
`endif // RVGPU_CONTROL_UNIT_PKG_IMPORTED

// Common type definitions for MMU testing
typedef struct packed {
    logic [47:0] vaddr;      // 虚拟地址
    logic [47:0] paddr;      // 物理地址
    logic read;              // 读请求
    logic write;             // 写请求
    logic hit;               // TLB命中
    logic [1:0] status;      // 响应状态
} mmu_transaction_t;

// Virtual interface types for task parameters
typedef virtual mmu_if #(.VA_WIDTH(48), .PA_WIDTH(48)) mmu_vif_t;
typedef virtual rvgpu_internal_noc_if #(.NOC_CONFIG(DEFAULT_NOC_CONFIG)) noc_vif_t;
typedef virtual clk_rst_if clk_rst_vif_t;

// Base class for RVGPU MMU testing
class rvgpu_mmu_test_base;

    // Interface references (to be connected from testbench)
    mmu_vif_t mmu_if;
    noc_vif_t noc_if;
    clk_rst_vif_t clk_rst_if;
    
    // Clock manager for elegant time control
    rvgpu_clk_manager clk_mgr;
    
    // Test data patterns for comprehensive testing
    logic [47:0] test_vaddr_patterns[8];
    logic [47:0] test_paddr_patterns[8];
    logic [47:0] test_page_table_patterns[4];

    // Transaction monitoring variables
    mmu_transaction_t captured_mmu_trans;
    logic mmu_req_detected;
    logic mmu_resp_detected;
    logic tlb_hit_detected;
    logic tlb_miss_detected;

    // Constructor
    function new(mmu_vif_t mmu_vif, noc_vif_t noc_vif, clk_rst_vif_t clk_rst_vif, rvgpu_clk_manager clk_manager);
        this.mmu_if = mmu_vif;
        this.noc_if = noc_vif;
        this.clk_rst_if = clk_rst_vif;
        this.clk_mgr = clk_manager;
        
        // Initialize test virtual address patterns
        test_vaddr_patterns[0] = 48'h000000000000;  // Base address
        test_vaddr_patterns[1] = 48'h000000001000;  // 4KB aligned
        test_vaddr_patterns[2] = 48'h000000010000;  // 64KB aligned
        test_vaddr_patterns[3] = 48'h100000000000;  // High bit set
        test_vaddr_patterns[4] = 48'h0000FFFFFFFF;  // Lower 48 bits
        test_vaddr_patterns[5] = 48'h800000000008;  // Unaligned
        test_vaddr_patterns[6] = 48'h0123456789AB;  // Pattern address
        test_vaddr_patterns[7] = 48'hFEDCBA987654;  // Reverse pattern

        // Initialize test physical address patterns
        test_paddr_patterns[0] = 48'h000000000000;  // Base address
        test_paddr_patterns[1] = 48'h000000002000;  // 8KB aligned
        test_paddr_patterns[2] = 48'h000000020000;  // 128KB aligned
        test_paddr_patterns[3] = 48'h200000000000;  // High bit set
        test_paddr_patterns[4] = 48'h0000FFFFFFFE;  // Lower 48 bits
        test_paddr_patterns[5] = 48'h800000000010;  // Unaligned
        test_paddr_patterns[6] = 48'h02468ACE1357;  // Pattern address
        test_paddr_patterns[7] = 48'hFDB97531ECA8;  // Reverse pattern

        // Initialize test page table patterns
        test_page_table_patterns[0] = 48'h000000000000;  // Base page table
        test_page_table_patterns[1] = 48'h000000010000;  // 64KB aligned
        test_page_table_patterns[2] = 48'h100000000000;  // High bit set
        test_page_table_patterns[3] = 48'h0000FFFFFFF0;  // Near max address
    endfunction

    // Initialize all interface signals to known state
    task initialize_signals();
        // MMU interface - initialize to idle state
        mmu_if.req_valid = 1'b0;
        mmu_if.req_vaddr = 48'h0;
        mmu_if.req_read = 1'b0;
        mmu_if.req_write = 1'b0;
        mmu_if.resp_ready = 1'b1;  // MMU ready to accept responses
        mmu_if.resp_valid = 1'b0;
        mmu_if.resp_paddr = 48'h0;
        mmu_if.resp_hit = 1'b0;
        mmu_if.resp_status = 2'b00;
        
        // MMU configuration interface
        mmu_if.cfg_en = 1'b0;
        mmu_if.cfg_base_addr = 48'h0;

        // NOC interface - initialize to idle state
        noc_if.m_req_valid = 1'b0;
        noc_if.m_req_header = '0;
        noc_if.m_req_data = '0;
        noc_if.m_req_strb = '0;
        noc_if.m_req_last = 1'b0;
        noc_if.m_req_ready = 1'b1;  // NOC ready to accept requests
        noc_if.m_resp_valid = 1'b0;
        noc_if.m_resp_header = '0;
        noc_if.m_resp_data = '0;
        noc_if.m_resp_status = 2'b00;
        noc_if.m_resp_last = 1'b0;
        noc_if.m_resp_ready = 1'b1;  // MMU ready to accept NOC responses
        noc_if.s_req_valid = 1'b0;
        noc_if.s_req_header = '0;
        noc_if.s_req_data = '0;
        noc_if.s_req_strb = '0;
        noc_if.s_req_last = 1'b0;
        noc_if.s_req_ready = 1'b0;
        noc_if.s_resp_valid = 1'b0;
        noc_if.s_resp_header = '0;
        noc_if.s_resp_data = '0;
        noc_if.s_resp_status = 2'b00;
        noc_if.s_resp_last = 1'b0;
        noc_if.s_resp_ready = 1'b1;  // NOC ready to accept responses
    endtask

    // Clear MMU interface signals
    task clear_mmu_signals();
        mmu_if.req_valid = 1'b0;
        mmu_if.req_vaddr = '0;
        mmu_if.req_read = 1'b0;
        mmu_if.req_write = 1'b0;
        mmu_if.resp_ready = 1'b1;  // Keep ready
    endtask

    // Clear NOC interface signals
    task clear_noc_signals();
        noc_if.m_req_valid = 1'b0;
        noc_if.m_req_header = '0;
        noc_if.m_req_data = '0;
        noc_if.m_req_strb = '0;
        noc_if.m_req_last = 1'b0;
        noc_if.m_req_ready = 1'b1;  // Keep ready
        noc_if.m_resp_valid = 1'b0;
        noc_if.m_resp_header = '0;
        noc_if.m_resp_data = '0;
        noc_if.m_resp_status = 2'b00;
        noc_if.m_resp_last = 1'b0;
        noc_if.m_resp_ready = 1'b1;  // Keep ready
        noc_if.s_req_valid = 1'b0;
        noc_if.s_req_header = '0;
        noc_if.s_req_data = '0;
        noc_if.s_req_strb = '0;
        noc_if.s_req_last = 1'b0;
        noc_if.s_req_ready = 1'b0;
        noc_if.s_resp_valid = 1'b0;
        noc_if.s_resp_header = '0;
        noc_if.s_resp_data = '0;
        noc_if.s_resp_status = 2'b00;
        noc_if.s_resp_last = 1'b0;
        noc_if.s_resp_ready = 1'b1;  // Keep ready
    endtask

    // Initialize transaction monitoring variables
    task initialize_monitors();
        captured_mmu_trans = '{default: 1'b0};
        mmu_req_detected = 1'b0;
        mmu_resp_detected = 1'b0;
        tlb_hit_detected = 1'b0;
        tlb_miss_detected = 1'b0;
    endtask

    //===================================
    // MMU Configuration Tasks
    //===================================

    // Configure MMU page table base address
    task configure_mmu_page_table(logic [47:0] base_addr);
        $display("@%0t: Configuring MMU page table: base_addr=0x%012x", $time, base_addr);
        
        mmu_if.cfg_en = 1'b1;
        mmu_if.cfg_base_addr = base_addr;
        clk_mgr.wait_posedge_and_delay_ns(1);
        mmu_if.cfg_en = 1'b0;
        
        $display("@%0t: MMU page table configured", $time);
    endtask

    //===================================
    // MMU Request/Response Tasks
    //===================================

    // Send MMU translation request
    task send_mmu_request(logic [47:0] vaddr, logic read, logic write);
        $display("@%0t: Sending MMU request: vaddr=0x%012x, read=%0d, write=%0d", 
                 $time, vaddr, read, write);
        
        mmu_if.req_valid = 1'b1;
        mmu_if.req_vaddr = vaddr;
        mmu_if.req_read = read;
        mmu_if.req_write = write;
        
        // Wait for handshake completion
        while (!(mmu_if.req_valid && mmu_if.req_ready)) begin
            clk_mgr.wait_posedge();
        end
        clk_mgr.wait_posedge();
        mmu_if.req_valid = 1'b0;
        
        $display("@%0t: MMU request sent", $time);
    endtask

    // Wait for MMU response
    task wait_for_mmu_response(output logic [47:0] paddr, output logic hit, output logic [1:0] status, input int timeout_cycles);
        int cycle_count = 0;
        $display("@%0t: Waiting for MMU response", $time);
        
        // 首先检查MMU响应是否已经存在
        if (mmu_if.resp_valid) begin
            $display("@%0t: MMU response already available", $time);
            cycle_count = 0;
        end else begin
            while (!mmu_if.resp_valid && (cycle_count < timeout_cycles)) begin
                clk_mgr.wait_posedge();
                cycle_count++;
            end
        end
        
        if (cycle_count >= timeout_cycles) begin
            $display("@%0t: ERROR: MMU response timeout after %0d cycles", $time, timeout_cycles);
            `FAIL_IF(1)
        end else begin
            paddr = mmu_if.resp_paddr;
            hit = mmu_if.resp_hit;
            status = mmu_if.resp_status;
            $display("@%0t: MMU response received after %0d cycles: paddr=0x%012x, hit=%0d, status=%0d", 
                     $time, cycle_count, paddr, hit, status);
            
            // Complete handshake
            mmu_if.resp_ready = 1'b1;
            clk_mgr.wait_posedge();
            mmu_if.resp_ready = 1'b0;
        end
    endtask

    // Complete MMU transaction with verification
    task complete_mmu_transaction_verify(logic [47:0] vaddr, logic read, logic write, 
                                       logic [47:0] expected_paddr, logic expected_hit, logic [1:0] expected_status);
        logic [47:0] actual_paddr;
        logic actual_hit;
        logic [1:0] actual_status;
        
        // Send request
        send_mmu_request(vaddr, read, write);
        
        // Wait for response
        wait_for_mmu_response(actual_paddr, actual_hit, actual_status, 50);
        
        // Verify response
        `FAIL_IF(actual_paddr !== expected_paddr)
        `FAIL_IF(actual_hit !== expected_hit)
        `FAIL_IF(actual_status !== expected_status)
        
        $display("@%0t: MMU transaction verified: vaddr=0x%012x -> paddr=0x%012x, hit=%0d, status=%0d", 
                 $time, vaddr, actual_paddr, actual_hit, actual_status);
    endtask

    //===================================
    // NOC Interface Tasks
    //===================================

    // Wait for NOC request (page table access)
    task wait_for_noc_request(output logic [63:0] addr, output logic [15:0] size, input int timeout_cycles);
        int cycle_count = 0;
        $display("@%0t: Waiting for NOC request", $time);
        
        while (!noc_if.m_req_valid && (cycle_count < timeout_cycles)) begin
            clk_mgr.wait_posedge();
            cycle_count++;
        end
        
        if (cycle_count >= timeout_cycles) begin
            $display("@%0t: ERROR: NOC request timeout after %0d cycles", $time, timeout_cycles);
            `FAIL_IF(1)
        end else begin
            addr = noc_if.m_req_data[63:0];  // 64位地址
            size = 64;  // 固定大小，页表条目是64位
            $display("@%0t: NOC request received after %0d cycles: addr=0x%016x, size=%0d", 
                     $time, cycle_count, addr, size);
            
            // Complete handshake
            noc_if.m_req_ready = 1'b1;
            clk_mgr.wait_posedge();
            noc_if.m_req_ready = 1'b0;
        end
    endtask

    // Send NOC response (page table data)
    task send_noc_response(logic [255:0] data, logic [1:0] status, logic [7:0] transaction_id);
        $display("@%0t: [TEST] Sending NOC response: status=%0d, id=%0d, data=0x%016x", $time, status, transaction_id, data);
        
        // 模拟NOC路由：将s_resp信号路由到m_resp信号
        noc_if.m_resp_valid = 1'b1;
        noc_if.m_resp_header = build_noc_header(
            MSG_MEM_READ_RESP,  // 内存读响应
            transaction_id,      // 事务ID
            NODE_L2_CACHE,      // 源节点：L2 Cache
            NODE_CONTROL,       // 目标节点：控制单元
            8'h00              // 本地地址
        );
        noc_if.m_resp_data = data;
        noc_if.m_resp_status = status;
        noc_if.m_resp_last = 1'b1;
        
        $display("@%0t: [TEST] Waiting for NOC response ready: m_resp_ready=%0d", $time, noc_if.m_resp_ready);
        while (!noc_if.m_resp_ready) begin
            clk_mgr.wait_posedge();
        end
        clk_mgr.wait_posedge_and_delay_ns(1);  // 等待下一个时钟周期并延迟1ns
        
        noc_if.m_resp_valid = 1'b0;
        noc_if.m_resp_last = 1'b0;
        
        // 重新设置m_req_ready为1，以便MMU可以发送下一次NOC请求
        noc_if.m_req_ready = 1'b1;
        
        $display("@%0t: [TEST] NOC response sent successfully, m_req_ready set to 1", $time);
    endtask

    //===================================
    // TLB Testing Tasks
    //===================================

    // Test TLB hit scenario
    task test_tlb_hit(logic [47:0] vaddr, logic [47:0] expected_paddr);
        logic [47:0] paddr;
        logic hit;
        logic [1:0] status;
        $display("@%0t: Testing TLB hit: vaddr=0x%012x", $time, vaddr);
        
        // Send MMU request
        send_mmu_request(vaddr, 1'b1, 1'b0);
        
        // Should get immediate response (TLB hit)
        wait_for_mmu_response(paddr, hit, status, 10);
        
        // Verify TLB hit
        `FAIL_IF(!hit)
        `FAIL_IF(paddr !== expected_paddr)
        `FAIL_IF(status !== 2'b00)
        
        $display("@%0t: TLB hit verified: vaddr=0x%012x -> paddr=0x%012x", $time, vaddr, paddr);
    endtask

    // Test TLB miss scenario
    task test_tlb_miss(logic [47:0] vaddr, logic [47:0] page_table_entry, logic [47:0] expected_paddr);
        logic [63:0] noc_addr;
        logic [15:0] noc_size;
        logic [47:0] paddr;
        logic hit;
        logic [1:0] status;
        
        $display("@%0t: Testing TLB miss: vaddr=0x%012x", $time, vaddr);
        
        // Send MMU request
        send_mmu_request(vaddr, 1'b1, 1'b0);
        
        // Wait for NOC request (page table access)
        wait_for_noc_request(noc_addr, noc_size, 50);
        
        // Send NOC response with page table entry
        send_noc_response({208'h0, page_table_entry}, 2'b00, 8'h00);
        
        // Wait for MMU response
        wait_for_mmu_response(paddr, hit, status, 50);
        
        // Verify TLB miss and page table lookup
        `FAIL_IF(hit)  // Should be miss initially
        `FAIL_IF(paddr !== expected_paddr)
        `FAIL_IF(status !== 2'b00)
        
        $display("@%0t: TLB miss verified: vaddr=0x%012x -> paddr=0x%012x", $time, vaddr, paddr);
    endtask

    //===================================
    // Monitoring Tasks
    //===================================

    // Monitor MMU interface
    task monitor_mmu_interface();
        if (mmu_if.req_valid && mmu_if.req_ready) begin
            $display("@%0t: Monitor - MMU request detected: vaddr=0x%012x, read=%0d, write=%0d", 
                     $time, mmu_if.req_vaddr, mmu_if.req_read, mmu_if.req_write);
            captured_mmu_trans.vaddr = mmu_if.req_vaddr;
            captured_mmu_trans.read = mmu_if.req_read;
            captured_mmu_trans.write = mmu_if.req_write;
            mmu_req_detected = 1'b1;
        end else begin
            mmu_req_detected = 1'b0;
        end
        
        if (mmu_if.resp_valid && mmu_if.resp_ready) begin
            $display("@%0t: Monitor - MMU response detected: paddr=0x%012x, hit=%0d, status=%0d", 
                     $time, mmu_if.resp_paddr, mmu_if.resp_hit, mmu_if.resp_status);
            captured_mmu_trans.paddr = mmu_if.resp_paddr;
            captured_mmu_trans.hit = mmu_if.resp_hit;
            captured_mmu_trans.status = mmu_if.resp_status;
            mmu_resp_detected = 1'b1;
            
            if (mmu_if.resp_hit) begin
                tlb_hit_detected = 1'b1;
            end else begin
                tlb_miss_detected = 1'b1;
            end
        end else begin
            mmu_resp_detected = 1'b0;
        end
    endtask

    // Verify MMU transaction
    task verify_mmu_transaction(logic [47:0] expected_vaddr, logic expected_read, logic expected_write);
        `FAIL_IF(captured_mmu_trans.vaddr !== expected_vaddr)
        `FAIL_IF(captured_mmu_trans.read !== expected_read)
        `FAIL_IF(captured_mmu_trans.write !== expected_write)
        $display("@%0t: MMU transaction verified: vaddr=0x%012x, read=%0d, write=%0d", 
                 $time, expected_vaddr, expected_read, expected_write);
    endtask

    // Check MMU interface reset state
    task check_mmu_interface_reset_state();
        $display("@%0t: Checking MMU interface reset state", $time);
        
        // Check MMU interface outputs (should be in reset state)
        `FAIL_IF(mmu_if.req_valid !== 1'b0)
        `FAIL_IF(mmu_if.req_vaddr !== 48'h0)
        `FAIL_IF(mmu_if.req_read !== 1'b0)
        `FAIL_IF(mmu_if.req_write !== 1'b0)
        `FAIL_IF(mmu_if.resp_valid !== 1'b0)
        `FAIL_IF(mmu_if.resp_paddr !== 48'h0)
        `FAIL_IF(mmu_if.resp_hit !== 1'b0)
        `FAIL_IF(mmu_if.resp_status !== 2'b00)
        
        $display("@%0t: MMU interface in correct reset state", $time);
    endtask

    //===================================
    // Test Pattern Functions
    //===================================

    // Run comprehensive MMU test pattern
    task run_mmu_test_pattern();
        int i;
        logic [47:0] paddr;
        logic hit;
        logic [1:0] status;
        
        $display("@%0t: Running comprehensive MMU test pattern", $time);
        
        for (i = 0; i < 8; i++) begin
            $display("@%0t: MMU test %0d", $time, i);
            
            // Test read request
            send_mmu_request(test_vaddr_patterns[i], 1'b1, 1'b0);
            wait_for_mmu_response(paddr, hit, status, 50);
            
            // Test write request
            send_mmu_request(test_vaddr_patterns[i], 1'b0, 1'b1);
            wait_for_mmu_response(paddr, hit, status, 50);
        end
        
        $display("@%0t: MMU test pattern completed", $time);
    endtask

    // Simulate complete MMU workflow with TLB miss
    task simulate_mmu_workflow_tlb_miss(logic [47:0] vaddr, logic [47:0] page_table_entry, logic [47:0] expected_paddr);
        logic [31:0] noc_addr;
        logic [15:0] noc_size;
        logic [47:0] paddr;
        logic hit;
        logic [1:0] status;
        
        $display("@%0t: Starting MMU workflow simulation (TLB miss)", $time);
        
        // 1. Send MMU request
        send_mmu_request(vaddr, 1'b1, 1'b0);
        
        // 2. Wait for NOC request (page table access)
        wait_for_noc_request(noc_addr, noc_size, 50);
        
        // 3. Send NOC response with page table entry
        send_noc_response({208'h0, page_table_entry}, 2'b00, 8'h00);
        
        // 4. Wait for MMU response
        wait_for_mmu_response(paddr, hit, status, 50);
        
        // 5. Verify results
        `FAIL_IF(hit)  // Should be miss initially
        `FAIL_IF(paddr !== expected_paddr)
        `FAIL_IF(status !== 2'b00)
        
        $display("@%0t: MMU workflow simulation completed (TLB miss)", $time);
    endtask

    // Simulate complete MMU workflow with TLB hit
    task simulate_mmu_workflow_tlb_hit(logic [47:0] vaddr, logic [47:0] expected_paddr);
        logic [47:0] paddr;
        logic hit;
        logic [1:0] status;
        
        $display("@%0t: Starting MMU workflow simulation (TLB hit)", $time);
        
        // 1. Send MMU request
        send_mmu_request(vaddr, 1'b1, 1'b0);
        
        // 2. Wait for immediate MMU response (TLB hit)
        wait_for_mmu_response(paddr, hit, status, 10);
        
        // 3. Verify results
        `FAIL_IF(!hit)  // Should be hit
        `FAIL_IF(paddr !== expected_paddr)
        `FAIL_IF(status !== 2'b00)
        
        $display("@%0t: MMU workflow simulation completed (TLB hit)", $time);
    endtask

endclass

`endif // RVGPU_MMU_TEST_BASE_SVH 