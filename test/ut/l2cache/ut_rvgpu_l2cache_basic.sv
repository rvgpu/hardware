//=============================================================================
// Copyright © 2025 RVGPU Team
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//   
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//=============================================================================

`ifndef UT_RVGPU_L2CACHE_BASIC_SV
`define UT_RVGPU_L2CACHE_BASIC_SV

// 包含SVUnit定义
`include "svunit_defines.svh"

// 包含所有必要的 RTL 文件
`include "rvgpu_l2cache_incfiles.svh"
`include "rvgpu_l2cache_test_base.svh"

//=============================================================================
// RVGPU L2 Cache Basic Unit Test
// 
// 测试内容：
// 1. 基本读操作测试
// 2. 基本写操作测试
// 3. 缓存命中测试
// 4. 缓存未命中测试
// 5. 并发访问测试
// 6. 不同大小访问测试
//=============================================================================

// SVUnit中模块名必须以_unit_test结尾
module ut_rvgpu_l2cache_basic_unit_test;
    import svunit_pkg::svunit_testcase;

    string name = "ut_rvgpu_l2cache_basic_unit_test";
    svunit_testcase svunit_ut = new(name);

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
    
    // NOC接口
    rvgpu_internal_noc_if noc_if();
    
    // 内存接口
    memory_if mem_if();
    
    // Virtual interface references for test base
    virtual rvgpu_internal_noc_if noc_vif = noc_if;
    virtual memory_if mem_vif = mem_if;
    
    // L2 Cache实例
    rvgpu_l2cache #(
        .L2CACHE_CONFIG(DEFAULT_L2CACHE_CONFIG)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .noc_if(noc_if.device),
        .mem_if(mem_if.master)
    );
    
    // 测试基础类实例
    rvgpu_l2cache_test_base test_base;
    
    //=============================================================================
    // Test Variables
    //=============================================================================
    
    // 测试数据
    logic [63:0] test_addr;
    logic [255:0] test_data;
    logic [31:0] test_strb;
    logic [7:0] test_size;
    
    //=============================================================================
    // Test Tasks
    //=============================================================================
    
    // 测试1: 基本读操作
    task t_basic_read();
        automatic logic [255:0] read_data;
        automatic logic [31:0] read_strb;
        automatic logic [1:0] read_status;
        
        // 发送读请求
        test_addr = 64'h1000_0000;
        test_data = 128'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0;
        test_size = 8'd128;
        
        fork
            begin
                test_base.send_noc_read_request(test_addr, test_size, 8'h01);
                test_base.wait_noc_read_response(read_data, read_strb, read_status);
            end
            begin
                // 模拟内存响应
                test_base.simulate_memory_read_response(test_addr, test_data);
            end
        join
        
        // 验证结果
        test_base.verify_read_response(test_data, read_data, 2'b00, read_status, "Basic read test");
        
        clk_mgr.wait_clks(10);
    endtask
    
    // 测试2: 基本写操作
    task t_basic_write();
        automatic logic [1:0] write_status;
        
        // 发送写请求
        test_addr = 64'h2000_0000;
        test_data = 256'hFEDC_BA98_7654_3210_ABCD_EF01_2345_6789_FEDC_BA98_7654_3210_ABCD_EF01_2345_6789;
        test_strb = 32'hFFFF_FFFF;
        test_size = 8'd64;
        
        fork
            begin
                test_base.send_noc_write_request(test_addr, test_data, test_strb, test_size, 8'h02);
                test_base.wait_noc_write_response(write_status);
            end
            begin
                // 模拟内存响应
                test_base.simulate_memory_write_response(test_addr);
            end
        join
        
        // 验证结果
        test_base.verify_write_response(2'b00, write_status, "Basic write test");
        
        clk_mgr.wait_clks(10);
    endtask
    
    // 测试3: 缓存命中测试
    task t_cache_hit();
        automatic logic [255:0] read_data1, read_data2;
        automatic logic [31:0] read_strb1, read_strb2;
        automatic logic [1:0] read_status1, read_status2;
        
        // 第一次读（缓存未命中）
        test_addr = 64'h3000_0000;
        test_data = 256'h1111_2222_3333_4444_5555_6666_7777_8888_1111_2222_3333_4444_5555_6666_7777_8888;
        
        fork
            begin
                test_base.send_noc_read_request(test_addr, 8'd64, 8'h03);
                test_base.wait_noc_read_response(read_data1, read_strb1, read_status1);
            end
            begin
                test_base.simulate_memory_read_response(test_addr, test_data);
            end
        join
        
        // 第二次读相同地址（缓存命中）
        fork
            begin
                test_base.send_noc_read_request(test_addr, 8'd64, 8'h04);
                test_base.wait_noc_read_response(read_data2, read_strb2, read_status2);
            end
        join
        
        // 验证结果
        `FAIL_IF(read_data1 != test_data)
        `FAIL_IF(read_data2 != test_data)
        `FAIL_IF(read_status1 != 2'b00)
        `FAIL_IF(read_status2 != 2'b00)
        
        clk_mgr.wait_clks(10);
    endtask
    
    // 测试4: 不同大小访问测试
    task t_different_sizes();
        automatic logic [255:0] read_data;
        automatic logic [31:0] read_strb;
        automatic logic [1:0] read_status;
        automatic logic [7:0] sizes[4] = '{8'd1, 8'd8, 8'd32, 8'd64};
        automatic string size_names[4] = '{"1 byte", "8 bytes", "32 bytes", "64 bytes"};
        
        for (int i = 0; i < 4; i++) begin
            $display("  Testing %s access", size_names[i]);
            
            test_addr = 64'h4000_0000 + (i * 64);
            test_data = 256'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111_AAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111;
            
            fork
                begin
                    test_base.send_noc_read_request(test_addr, sizes[i], 8'h10 + i);
                    test_base.wait_noc_read_response(read_data, read_strb, read_status);
                end
                begin
                    test_base.simulate_memory_read_response(test_addr, test_data);
                end
            join
            
            `FAIL_IF(read_status != 2'b00)
            
            clk_mgr.wait_clks(5);
        end
        
        clk_mgr.wait_clks(10);
    endtask
    
    // 测试5: 并发访问测试
    task t_concurrent_access();
        automatic logic [255:0] read_data1, read_data2;
        automatic logic [31:0] read_strb1, read_strb2;
        automatic logic [1:0] read_status1, read_status2;
        
        // 并发发送两个读请求
        test_addr = 64'h5000_0000;
        test_data = 256'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111_AAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111;
        
        fork
            begin
                test_base.send_noc_read_request(test_addr, 8'd64, 8'h20);
                test_base.simulate_memory_read_response(test_addr, test_data);
                test_base.wait_noc_read_response(read_data1, read_strb1, read_status1);
            end
            begin
                clk_mgr.wait_clks(1); // 稍微延迟第二个请求
                test_base.send_noc_read_request(test_addr + 64, 8'd64, 8'h21);
                test_base.simulate_memory_read_response(test_addr + 64, test_data + 1);
                test_base.wait_noc_read_response(read_data2, read_strb2, read_status2);
            end
        join
        
        // 验证结果
        `FAIL_IF(read_status1 != 2'b00)
        `FAIL_IF(read_status2 != 2'b00)
        
        clk_mgr.wait_clks(10);
    endtask
    
    // 测试6: 写后读测试
    task t_write_then_read();
        automatic logic [255:0] read_data;
        automatic logic [31:0] read_strb;
        automatic logic [1:0] read_status, write_status;
        
        // 先写数据
        test_addr = 64'h6000_0000;
        test_data = 256'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0_DEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0;
        test_strb = 32'hFFFF_FFFF;
        
        fork
            begin
                test_base.send_noc_write_request(test_addr, test_data, test_strb, 8'd64, 8'h30);
                test_base.wait_noc_write_response(write_status);
            end
            begin
                test_base.simulate_memory_write_response(test_addr);
            end
        join
        
        clk_mgr.wait_clks(5);
        
        // 再读数据
        fork
            begin
                test_base.send_noc_read_request(test_addr, 8'd64, 8'h31);
                test_base.wait_noc_read_response(read_data, read_strb, read_status);
            end
            begin
                test_base.simulate_memory_read_response(test_addr, test_data);
            end
        join
        
        // 验证结果
        `FAIL_IF(write_status != 2'b00)
        `FAIL_IF(read_status != 2'b00)
        
        clk_mgr.wait_clks(10);
    endtask
    
    // 测试7: 错误处理测试
    task t_error_handling();
        automatic logic [255:0] read_data;
        automatic logic [31:0] read_strb;
        automatic logic [1:0] read_status;
        
        // 发送读请求，但内存返回错误
        test_addr = 64'h7000_0000;
        test_data = 256'h0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000;
        
        fork
            begin
                test_base.send_noc_read_request(test_addr, 8'd64, 8'h40);
                test_base.wait_noc_read_response(read_data, read_strb, read_status);
            end
            begin
                // 模拟内存错误响应
                test_base.simulate_memory_read_response(test_addr, test_data, 2'b10); // SLVERR
            end
        join
        
        // 验证错误处理
        `FAIL_IF(read_status != 2'b10)
        
        clk_mgr.wait_clks(10);
    endtask
    
    //=============================================================================
    // SVUnit Required Methods
    //=============================================================================
    
    //===================================
    // Build
    //===================================
    function void build();
        svunit_ut = new(name);
        
        // Initialize clock manager
        clk_mgr = new("l2cache_test_clk", 10.0, 10);
        clk_mgr.initialize(clk_rst_if);
        
        // Create test base with virtual interfaces
        test_base = new(noc_vif, mem_vif, clk_rst_if, clk_mgr);
        
        $display("@%0t: Build completed", $time);
        clk_mgr.display_status();
    endfunction

    //===================================
    // Setup for running the Unit Tests
    //===================================
    task setup();
        $vcdpluson();

        svunit_ut.setup();
        
        // Initialize all signals
        test_base.initialize_signals();
        
        // Apply reset using clock manager
        clk_mgr.apply_reset();
        clk_mgr.wait_clock_stable(2);
        
        $display("@%0t: Setup completed", $time);
    endtask

    //===================================
    // Here we deconstruct anything we 
    // need after running the Unit Tests
    //===================================
    task teardown();
        svunit_ut.teardown();
        
        $display("@%0t: Teardown completed", $time);
    endtask

    //===================================
    // All tests are defined between the
    // SVUNIT_TESTS_BEGIN/END macros
    //===================================
    `SVUNIT_TESTS_BEGIN

    //===================================
    // Test Cases
    //===================================
    
    `SVTEST(test_reset_state)
        $display("@%0t: Testing L2 Cache reset state", $time);
        
        // Check that all interface signals are in reset state
        test_base.check_interface_reset_state();
        
        $display("@%0t: Reset state test completed", $time);
    `SVTEST_END

    `SVTEST(test_basic_read)
        $display("@%0t: Testing basic L2 Cache read", $time);
        t_basic_read();
    `SVTEST_END

    `SVTEST(test_basic_write)
        $display("@%0t: Testing basic L2 Cache write", $time);
        t_basic_write();
    `SVTEST_END

    `SVTEST(test_cache_hit)
        $display("@%0t: Testing L2 Cache hit", $time);
        t_cache_hit();
    `SVTEST_END

    `SVTEST(test_different_sizes)
        $display("@%0t: Testing different access sizes", $time);
        t_different_sizes();
    `SVTEST_END

    `SVTEST(test_concurrent_access)
        $display("@%0t: Testing concurrent access", $time);
        t_concurrent_access();
    `SVTEST_END

    `SVTEST(test_write_then_read)
        $display("@%0t: Testing write then read", $time);
        t_write_then_read();
    `SVTEST_END

    `SVTEST(test_error_handling)
        $display("@%0t: Testing error handling", $time);
        t_error_handling();
    `SVTEST_END

    `SVUNIT_TESTS_END
    
    //=============================================================================
    // Monitoring
    //=============================================================================
    
    // 监控NOC请求
    always @(posedge clk) begin
        if (noc_if.s_req_valid && noc_if.s_req_ready) begin
            automatic noc_header_t header = noc_header_t'(noc_if.s_req_header);
            $display("@%0t: [MONITOR] NOC Request: type=%0d, src=%0d, dest=%0d, trans_id=%0d", 
                     $time, header.msg_type, header.src_node, header.dest_node, header.trans_id);
        end
    end
    
    // 监控NOC响应
    always @(posedge clk) begin
        if (noc_if.s_resp_valid && noc_if.s_resp_ready) begin
            automatic noc_header_t header = noc_header_t'(noc_if.s_resp_header);
            $display("@%0t: [MONITOR] NOC Response: type=%0d, status=%0d, trans_id=%0d", 
                     $time, header.msg_type, noc_if.s_resp_status, header.trans_id);
        end
    end
    
    // 监控内存访问
    always @(posedge clk) begin
        if (mem_if.arvalid && mem_if.arready) begin
            $display("@%0t: [MONITOR] Memory Read: addr=0x%h", 
                     $time, mem_if.araddr);
        end
        if (mem_if.awvalid && mem_if.awready) begin
            $display("@%0t: [MONITOR] Memory Write: addr=0x%h", 
                     $time, mem_if.awaddr);
        end
    end

endmodule : ut_rvgpu_l2cache_basic_unit_test

`endif // UT_RVGPU_L2CACHE_BASIC_SV 