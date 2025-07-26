`ifndef RVGPU_JOB_DISPATCHER_TEST_BASE_SVH
`define RVGPU_JOB_DISPATCHER_TEST_BASE_SVH

`include "rvgpu_control_unit_pkg.svh"
`include "rvgpu_control_unit_if.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_clk_rst.svh"
`include "rvgpu_command_package.svh"

`ifndef RVGPU_CONTROL_UNIT_PKG_IMPORTED
`define RVGPU_CONTROL_UNIT_PKG_IMPORTED
import rvgpu_control_unit_pkg::*;
`endif // RVGPU_CONTROL_UNIT_PKG_IMPORTED

// Common type definitions for Job Dispatcher testing
typedef struct packed {
    logic [63:0] package_addr;    // Package基地址
    logic [63:0] mmu_addr;        // MMU页表基地址
    logic enable;                 // 使能信号
    logic reset;                  // 复位信号
    logic complete;               // 完成信号
    logic error;                  // 错误信号
    logic busy;                   // 忙碌状态
} job_dispatcher_transaction_t;

// Virtual interface types for task parameters
typedef virtual job_dispatcher_if jd_vif_t;
typedef virtual rvgpu_internal_noc_if noc_vif_t;
typedef virtual mmu_if mmu_vif_t;
typedef virtual clk_rst_if clk_rst_vif_t;

// Base class for RVGPU Job Dispatcher testing
class rvgpu_job_dispatcher_test_base;

    // Interface references (to be connected from testbench)
    jd_vif_t jd_if;
    noc_vif_t noc_if;
    mmu_vif_t mmu_if;
    clk_rst_vif_t clk_rst_if;
    
    // Clock manager for elegant time control
    rvgpu_clk_manager clk_mgr;
    
    // Test data patterns for comprehensive testing
    logic [63:0] test_package_addr_patterns[8];
    logic [63:0] test_mmu_addr_patterns[8];

    // Transaction monitoring variables
    job_dispatcher_transaction_t captured_jd_trans;
    logic jd_enable_detected;
    logic jd_reset_detected;
    logic jd_complete_detected;
    logic jd_error_detected;
    logic jd_busy_detected;

    // Constructor
    function new(jd_vif_t jd_vif, noc_vif_t noc_vif, mmu_vif_t mmu_vif, clk_rst_vif_t clk_rst_vif, rvgpu_clk_manager clk_manager);
        this.jd_if = jd_vif;
        this.noc_if = noc_vif;
        this.mmu_if = mmu_vif;
        this.clk_rst_if = clk_rst_vif;
        this.clk_mgr = clk_manager;
        
        // Initialize test patterns
        test_package_addr_patterns[0] = 64'h0000000000000000;
        test_package_addr_patterns[1] = 64'h0000000000001000;
        test_package_addr_patterns[2] = 64'h0000000000010000;
        test_package_addr_patterns[3] = 64'h1000000000000000;
        test_package_addr_patterns[4] = 64'h0000FFFFFFFFFFFF;
        test_package_addr_patterns[5] = 64'h8000000000000008;
        test_package_addr_patterns[6] = 64'h0123456789ABCDEF;
        test_package_addr_patterns[7] = 64'hFEDCBA9876543210;

        test_mmu_addr_patterns[0] = 64'h0000000000000000;
        test_mmu_addr_patterns[1] = 64'h0000000000001000;
        test_mmu_addr_patterns[2] = 64'h0000000000010000;
        test_mmu_addr_patterns[3] = 64'h1000000000000000;
        test_mmu_addr_patterns[4] = 64'h0000FFFFFFFFFFFF;
        test_mmu_addr_patterns[5] = 64'h8000000000000008;
        test_mmu_addr_patterns[6] = 64'h0123456789ABCDEF;
        test_mmu_addr_patterns[7] = 64'hFEDCBA9876543210;

    endfunction

    // Initialize all interface signals to known state
    task initialize_signals();
        // Job Dispatcher interface
        jd_if.enable = 1'b0;
        jd_if.reset = 1'b0;
        jd_if.package_addr = 64'h0;
        jd_if.mmu_addr = 64'h0;

        // NOC interface
        noc_if.m_req_valid = 1'b0;
        noc_if.m_req_header = 32'h0;
        noc_if.m_req_data = 256'h0;
        noc_if.m_req_strb = 32'h0;
        noc_if.m_req_last = 1'b0;
        noc_if.m_req_ready = 1'b1;  // 设置m_req_ready为1，允许DUT发送请求
        noc_if.m_resp_ready = 1'b1;  // 设置m_resp_ready为1，允许DUT接收响应
        noc_if.m_resp_valid = 1'b0;
        noc_if.m_resp_header = 32'h0;
        noc_if.m_resp_data = 256'h0;
        noc_if.m_resp_status = 2'b00;
        noc_if.m_resp_last = 1'b0;
        noc_if.s_req_ready = 1'b0;
        noc_if.s_resp_valid = 1'b0;
        noc_if.s_resp_header = 32'h0;
        noc_if.s_resp_data = 256'h0;
        noc_if.s_resp_status = 2'b00;
        noc_if.s_resp_last = 1'b0;
        noc_if.s_req_valid = 1'b0;
        noc_if.s_req_header = 32'h0;
        noc_if.s_req_data = 256'h0;
        noc_if.s_req_strb = 32'h0;
        noc_if.s_req_last = 1'b0;

        // MMU interface
        mmu_if.req_valid = 1'b0;
        mmu_if.req_vaddr = 48'h0;
        mmu_if.req_read = 1'b0;
        mmu_if.req_write = 1'b0;
        mmu_if.req_ready = 1'b1;  // 设置req_ready为1，允许DUT发送请求
        mmu_if.resp_ready = 1'b1;
        mmu_if.resp_valid = 1'b0;
        mmu_if.resp_paddr = 48'h0;
        mmu_if.resp_hit = 1'b0;
        mmu_if.resp_status = 2'b00;
        // MMU配置接口 - 这些是输入到MMU的信号，由Job Dispatcher驱动
        // mmu_if.cfg_en 和 mmu_if.cfg_base_addr 由DUT驱动，不需要初始化
    endtask

    // Clear interface signals
    task clear_jd_signals();
        jd_if.enable = 1'b0;
        jd_if.reset = 1'b0;
        jd_if.package_addr = 64'h0;
        jd_if.mmu_addr = 64'h0;
    endtask

    task clear_noc_signals();
        noc_if.m_req_valid = 1'b0;
        noc_if.m_req_header = 32'h0;
        noc_if.m_req_data = 256'h0;
        noc_if.m_req_strb = 32'h0;
        noc_if.m_req_last = 1'b0;
        noc_if.m_req_ready = 1'b1;  // 保持m_req_ready为1
        noc_if.m_resp_ready = 1'b1;  // 保持m_resp_ready为1
    endtask

    task clear_mmu_signals();
        mmu_if.req_valid = 1'b0;
        mmu_if.req_vaddr = 48'h0;
        mmu_if.req_read = 1'b0;
        mmu_if.req_write = 1'b0;
        mmu_if.req_ready = 1'b1;  // 保持req_ready为1
        mmu_if.resp_ready = 1'b1;  // 保持resp_ready为1
    endtask

    // Initialize transaction monitoring variables
    task initialize_monitors();
        captured_jd_trans = '{default: 1'b0};
        jd_enable_detected = 1'b0;
        jd_reset_detected = 1'b0;
        jd_complete_detected = 1'b0;
        jd_error_detected = 1'b0;
        jd_busy_detected = 1'b0;
    endtask

    //===================================
    // Job Dispatcher Control Tasks
    //===================================

    // Enable Job Dispatcher
    task enable_job_dispatcher(logic [63:0] package_addr, logic [63:0] mmu_addr);
        $display("@%0t: Enabling Job Dispatcher: package_addr=0x%016x, mmu_addr=0x%016x", 
                 $time, package_addr, mmu_addr);
        
        jd_if.package_addr = package_addr;
        jd_if.mmu_addr = mmu_addr;
        jd_if.enable = 1'b1;
        clk_mgr.wait_posedge_and_delay_ns(1);
        jd_if.enable = 1'b0;  // Single pulse
    endtask

    // Reset Job Dispatcher
    task reset_job_dispatcher();
        $display("@%0t: Resetting Job Dispatcher", $time);
        
        jd_if.reset = 1'b1;
        clk_mgr.wait_posedge_and_delay_ns(1);
        jd_if.reset = 1'b0;
    endtask

    // Wait for Job Dispatcher completion
    task wait_for_job_completion(input int timeout_cycles);
        int cycle_count = 0;
        $display("@%0t: Waiting for Job Dispatcher completion", $time);
        
        while (!jd_if.complete && !jd_if.error && (cycle_count < timeout_cycles)) begin
            clk_mgr.wait_posedge();
            cycle_count++;
        end
        
        if (cycle_count >= timeout_cycles) begin
            $display("@%0t: ERROR: Job Dispatcher completion timeout after %0d cycles", $time, timeout_cycles);
            `FAIL_IF(1)
        end else begin
            $display("@%0t: Job Dispatcher completed after %0d cycles", $time, cycle_count);
        end
    endtask

    // Check Job Dispatcher status
    task check_job_dispatcher_status(output logic complete, output logic error, output logic busy);
        complete = jd_if.complete;
        error = jd_if.error;
        busy = jd_if.busy;
        
        $display("@%0t: Job Dispatcher status: complete=%0d, error=%0d, busy=%0d, error_status=%b", 
                 $time, complete, error, busy, jd_if.error_status);
    endtask

    //===================================
    // NOC Interface Tasks
    //===================================

    // Send NOC read response
    task send_noc_read_response(input logic [255:0] data, input logic [1:0] status, input logic [7:0] transaction_id);
        $display("@%0t: Sending NOC read response: status=%0d, id=%0d, data=0x%h", $time, status, transaction_id, data);
        clk_mgr.wait_clks(5);
        
        noc_if.m_resp_valid = 1'b1;
        noc_if.m_resp_header = build_noc_header_mem_response(transaction_id, NODE_CONTROL, NOC_NODE_CONTROL_JD);
        noc_if.m_resp_data = data;
        noc_if.m_resp_status = status;
        noc_if.m_resp_last = 1'b1;
        $display("@%0t: m_resp_ready=%0d", $time, noc_if.m_resp_ready);
        
        while (!noc_if.m_resp_ready) begin
            clk_mgr.wait_posedge();
        end
        clk_mgr.wait_posedge_and_delay_ns();
        
        noc_if.m_resp_valid = 1'b0;
        noc_if.m_resp_last = 1'b0;
    endtask

    // Wait for NOC request with handshake
    task wait_for_noc_request(output logic [63:0] addr, output logic [7:0] size, input int timeout_cycles);
        int cycle_count = 0;
        $display("@%0t: Waiting for NOC request", $time);
        
        while (!noc_if.m_req_valid && (cycle_count < timeout_cycles)) begin
            clk_mgr.wait_posedge();
            cycle_count++;
        end
        
        clk_mgr.delay_ns(1);
        if (cycle_count >= timeout_cycles) begin
            $display("@%0t: ERROR: NOC request timeout after %0d cycles", $time, timeout_cycles);
            `FAIL_IF(1)
        end else begin
            noc_payload_t noc_req = noc_if.m_req_data;
            addr = noc_req.req_mem_read.addr;
            size = noc_req.req_mem_read.size;
            $display("@%0t: NOC request data: %s", $time, noc_request_mem_read_to_string(noc_if.m_req_header, noc_if.m_req_data));
            
            // 确保m_req_ready为1，允许握手完成
            noc_if.m_req_ready = 1'b1;
        end
    endtask

    //===================================
    // MMU Interface Tasks
    //===================================

    // Send MMU translation response with handshake
    task send_mmu_translation_response(input logic [47:0] paddr, input logic hit, input logic [1:0] status);
        $display("@%0t: Sending MMU translation response: paddr=0x%012x, hit=%0d, status=%0d", 
                 $time, paddr, hit, status);
        // Delay cycles
        clk_mgr.wait_clks(5);
        
        mmu_if.resp_valid = 1'b1;
        mmu_if.resp_paddr = paddr;
        mmu_if.resp_hit = hit;
        mmu_if.resp_status = status;
        
        // 等待握手完成
        while (!mmu_if.resp_ready) begin
            clk_mgr.wait_posedge();
        end
        clk_mgr.wait_posedge_and_delay_ns();
        
        mmu_if.resp_valid = 1'b0;
    endtask

    // Wait for MMU request with handshake
    task wait_for_mmu_request(output logic [47:0] vaddr, output logic read, output logic write, input int timeout_cycles);
        int cycle_count = 0;
        $display("@%0t: Waiting for MMU request", $time);
        
        while (!mmu_if.req_valid && (cycle_count < timeout_cycles)) begin
            clk_mgr.wait_posedge();
            cycle_count++;
        end
        
        if (cycle_count >= timeout_cycles) begin
            $display("@%0t: ERROR: MMU request timeout after %0d cycles", $time, timeout_cycles);
            `FAIL_IF(1)
        end else begin
            vaddr = mmu_if.req_vaddr;
            read = mmu_if.req_read;
            write = mmu_if.req_write;
            $display("@%0t: MMU request received after %0d cycles: vaddr=0x%012x, read=%0d, write=%0d", 
                     $time, cycle_count, vaddr, read, write);
            
            // 确保req_ready为1，允许握手完成
            mmu_if.req_ready = 1'b1;
        end
    endtask

    // Wait for MMU configuration
    task wait_for_mmu_config(output logic cfg_en, output logic [47:0] cfg_base_addr, input int timeout_cycles);
        int cycle_count = 0;
        $display("@%0t: Waiting for MMU configuration", $time);
        
        while (!mmu_if.cfg_en && (cycle_count < timeout_cycles)) begin
            clk_mgr.wait_posedge();
            cycle_count++;
        end
        
        if (cycle_count >= timeout_cycles) begin
            $display("@%0t: ERROR: MMU configuration timeout after %0d cycles", $time, timeout_cycles);
            `FAIL_IF(1)
        end else begin
            cfg_en = mmu_if.cfg_en;
            cfg_base_addr = mmu_if.cfg_base_addr;
            $display("@%0t: MMU configuration received after %0d cycles: cfg_en=%0d, cfg_base_addr=0x%012x", 
                     $time, cycle_count, cfg_en, cfg_base_addr);
        end
    endtask



    // Wait for MMU configuration with correct base address (在同一个cycle生效)
    task wait_for_mmu_config_with_base(output logic cfg_en, output logic [47:0] cfg_base_addr, 
                                      input logic [47:0] expected_base_addr, input int timeout_cycles);
        int cycle_count = 0;
        $display("@%0t: Waiting for MMU configuration with base address", $time);
        
        while (!mmu_if.cfg_en && (cycle_count < timeout_cycles)) begin
            clk_mgr.wait_posedge();
            cycle_count++;
        end
        
        if (cycle_count >= timeout_cycles) begin
            $display("@%0t: ERROR: MMU configuration timeout after %0d cycles", $time, timeout_cycles);
            `FAIL_IF(1)
        end else begin
            cfg_en = mmu_if.cfg_en;
            cfg_base_addr = mmu_if.cfg_base_addr;
            $display("@%0t: MMU configuration with base address: cfg_en=%0d, cfg_base_addr=0x%012x (expected=0x%012x)", 
                     $time, cfg_en, cfg_base_addr, expected_base_addr);
        end
    endtask

    //===================================
    // Monitoring Tasks
    //===================================

    // Monitor Job Dispatcher interface
    task monitor_job_dispatcher_interface();
        if (jd_if.enable) begin
            $display("@%0t: Monitor - Job Dispatcher enable detected", $time);
            jd_enable_detected = 1'b1;
            captured_jd_trans.enable = 1'b1;
            captured_jd_trans.package_addr = jd_if.package_addr;
            captured_jd_trans.mmu_addr = jd_if.mmu_addr;
        end
        
        if (jd_if.reset) begin
            $display("@%0t: Monitor - Job Dispatcher reset detected", $time);
            jd_reset_detected = 1'b1;
            captured_jd_trans.reset = 1'b1;
        end
        
        if (jd_if.complete) begin
            $display("@%0t: Monitor - Job Dispatcher complete detected", $time);
            jd_complete_detected = 1'b1;
            captured_jd_trans.complete = 1'b1;
        end
        
        if (jd_if.error) begin
            $display("@%0t: Monitor - Job Dispatcher error detected", $time);
            jd_error_detected = 1'b1;
            captured_jd_trans.error = 1'b1;
        end
        
        if (jd_if.busy) begin
            $display("@%0t: Monitor - Job Dispatcher busy detected", $time);
            jd_busy_detected = 1'b1;
            captured_jd_trans.busy = 1'b1;
        end
    endtask

    // Verify Job Dispatcher transaction
    task verify_job_dispatcher_transaction(logic [63:0] expected_package_addr, logic [63:0] expected_mmu_addr);
        `FAIL_IF(captured_jd_trans.package_addr !== expected_package_addr)
        `FAIL_IF(captured_jd_trans.mmu_addr !== expected_mmu_addr)
        $display("@%0t: Job Dispatcher transaction verified: package_addr=0x%016x, mmu_addr=0x%016x", 
                 $time, expected_package_addr, expected_mmu_addr);
    endtask

    //===================================
    // Test Pattern Functions
    //===================================

    // Run comprehensive Job Dispatcher test pattern
    task run_job_dispatcher_test_pattern();
        int i;
        logic complete, error, busy;
        
        $display("@%0t: Running comprehensive Job Dispatcher test pattern", $time);
        
        for (i = 0; i < 8; i++) begin
            $display("@%0t: Job Dispatcher test %0d", $time, i);
            
            enable_job_dispatcher(test_package_addr_patterns[i], test_mmu_addr_patterns[i]);
            wait_for_job_completion(100);
            
            check_job_dispatcher_status(complete, error, busy);
            
            reset_job_dispatcher();
            clk_mgr.wait_clks(5);
        end
        
        $display("@%0t: Job Dispatcher test pattern completed", $time);
    endtask

    // Simulate complete Job Dispatcher workflow - 适配重构后的状态机
    task simulate_job_dispatcher_workflow(logic [63:0] package_addr, logic [63:0] mmu_addr);
        logic [47:0] vaddr;
        logic read, write;
        logic [31:0] noc_addr;
        logic [15:0] noc_size;
        logic [63:0] payload_addr;
        command_compute_t cmd;
        
        $display("@%0t: Starting Job Dispatcher workflow simulation", $time);
        
        // 1. Enable Job Dispatcher
        enable_job_dispatcher(package_addr, mmu_addr);
        
        // 2. 直接进入MMU请求阶段（config在enable时已经生效）
        
        // 3. Wait for Header fetch MMU request
        wait_for_mmu_request(vaddr, read, write, 50);
        `FAIL_IF(vaddr !== package_addr[47:0])
        `FAIL_IF(read !== 1'b1)
        `FAIL_IF(write !== 1'b0)
        
        // 4. Send Header fetch MMU response
        send_mmu_translation_response(48'h2000, 1'b1, 2'b00);
        
        // 5. Wait for Header NOC request
        wait_for_noc_request(noc_addr, noc_size, 50);
        `FAIL_IF(noc_addr !== 32'h2000)
        `FAIL_IF(noc_size !== NOC_SIZE_8B)

        clk_mgr.wait_clks(2);
        // 6. Send Header NOC response
        // Resp Command Header
        cmd.header.cmd_type = CMD_COMPUTE_JOB;
        cmd.header.size = 3'h0;
        cmd.header.last = 1'b1;
        cmd.header.reserved0 = 24'h0;
        cmd.header.job_dim = '{
            grid_x: 16'h0000,
            grid_y: 16'h0000,
            grid_z: 16'h0000,
            cluster_x: 4'h1,
            cluster_y: 4'h0,
            cluster_z: 4'h0,
            block_x: 12'h01,
            block_y: 12'h00,
            block_z: 12'h00
        };

        fork
            wait_for_job_block_and_response(100);
        join_none

        fork
            wait_for_job_completion(100);
        join_none

        send_noc_read_response(cmd, 2'b00, 8'h00);

        $display("@%0t: Job Dispatcher workflow simulation completed", $time);
    endtask

    task wait_for_job_block_and_response(input int timeout_cycles);
        int cycle_count = 0;
        $display("@%0t: Waiting for Job Block and Response", $time);
        
        while (!noc_if.m_req_valid && (cycle_count < timeout_cycles)) begin
            clk_mgr.wait_posedge();
            cycle_count++;
        end
        
        clk_mgr.delay_ns(1);
        if (cycle_count >= timeout_cycles) begin
            $display("@%0t: ERROR: NOC request timeout after %0d cycles", $time, timeout_cycles);
            `FAIL_IF(1)
        end else begin
            noc_payload_t noc_req = noc_if.m_req_data;
            $display("@%0t: NOC request data: %s", $time, noc_request_mem_read_to_string(noc_if.m_req_header, noc_if.m_req_data));
            
            // 确保m_req_ready为1，允许握手完成
            noc_if.m_req_ready = 1'b1;
        end

        send_noc_read_response(256'h0, 2'b00, 8'h00);
    endtask

endclass

`endif // RVGPU_JOB_DISPATCHER_TEST_BASE_SVH 