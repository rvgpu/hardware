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

`ifndef UT_RVGPU_L2CACHE_ADVANCED_SV
`define UT_RVGPU_L2CACHE_ADVANCED_SV

// 包含SVUnit定义
`include "svunit_defines.svh"

// 包含所有必要的 RTL 文件
`include "rvgpu_l2cache_incfiles.svh"
`include "rvgpu_l2cache_test_base.svh"

//=============================================================================
// RVGPU L2 Cache Advanced Unit Test
// 
// 测试内容：
// 1. 缓存替换测试（LRU策略）
// 2. 压力测试（大量并发请求）
// 3. 边界条件测试
// 4. 缓存一致性测试
// 5. 性能基准测试
// 6. 错误恢复测试
//=============================================================================

// SVUnit中模块名必须以_unit_test结尾
module ut_rvgpu_l2cache_advanced_unit_test;
  import svunit_pkg::svunit_testcase;

  string name = "ut_rvgpu_l2cache_advanced_unit_test";
  svunit_testcase svunit_ut;

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

    //=============================================================================
    // DUT Instance
    //=============================================================================
    
    //=============================================================================
    // Test Configuration
    //=============================================================================
    
    // 测试配置
    localparam l2cache_config_t TEST_CONFIG = '{
        cache_size: 512*1024,           // 512KB
        slice_number: 1,                 // 1个slice
        line_size: 64,                   // 64字节缓存行
        ways: 8,                         // 8路组相联
        sets: 1024,                      // 1024个组
        tag_bits: 32,                    // 32位Tag
        index_bits: 10,                  // 10位索引
        offset_bits: 6,                  // 6位偏移
        lru_bits: 8,                     // 8位LRU（对应8路组相联）
        axi_data_width: 64,              // 64位数据
        axi_addr_width: 64,              // 64位地址
        noc_data_width: 256,             // 256位NOC数据
        noc_header_width: 32,            // 32位NOC头部
        debug_enable: 1                  // 调试使能
    };
    
    //=============================================================================
    // Interface Instances
    //=============================================================================
    
    // NOC接口
    rvgpu_internal_noc_if noc_if();
    
    // 内存接口
    memory_if mem_if();
    
    // L2 Cache实例
    rvgpu_l2cache #(
        .L2CACHE_CONFIG(TEST_CONFIG)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .noc_if(noc_if.device),
        .mem_if(mem_if.master)
    );
    
    //=============================================================================
    // Test Base Instance
    //=============================================================================
    
    // 测试基础类实例
    rvgpu_l2cache_test_base test_base;
    
    //=============================================================================
    // Test Variables
    //=============================================================================
    
    // 测试计数器
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;
    
    // 性能测试变量
    int total_cycles = 0;
    int total_latency = 0;
    real avg_latency = 0.0;
    
    //=============================================================================
    // Advanced Test Tasks
    //=============================================================================
    
    // 测试1: 缓存替换测试（LRU策略）
    task test_cache_replacement();
        automatic logic [255:0] read_data;
        automatic logic [31:0] read_strb;
        automatic logic [1:0] read_status;
        automatic int start_time, end_time;
        
        $display("=== Test 1: Cache Replacement Test (LRU Strategy) ===");
        test_count++;
        
        // 填充缓存到接近满状态
        for (int i = 0; i < 16; i++) begin
            automatic logic [63:0] addr = 64'h8000_0000 + (i * 64);
            automatic logic [255:0] data = 256'h1000_0000_0000_0000_0000_0000_0000_0000 + i;
            
            fork
                begin
                    test_base.send_noc_read_request(addr, 8'd64, 8'h50 + i);
                    test_base.wait_noc_read_response(read_data, read_strb, read_status);
                end
                begin
                    test_base.simulate_memory_read_response(addr, data);
                end
            join
            
            if (read_status != 2'b00) begin
                $display("@%0t: [TEST] ERROR: Cache fill failed at iteration %0d", $time, i);
                fail_count++;
                return;
            end
            
            #10;
        end
        
        // 再次访问第一个地址，应该命中
        start_time = $time;
        fork
            begin
                test_base.send_noc_read_request(64'h8000_0000, 8'd64, 8'h60);
                test_base.wait_noc_read_response(read_data, read_strb, read_status);
            end
        join
        end_time = $time;
        
        // 验证命中（应该很快）
        if (read_status == 2'b00 && (end_time - start_time) < 100) begin
            $display("@%0t: [TEST] PASS: Cache replacement test passed", $time);
            $display("  Hit latency: %0d cycles", (end_time - start_time) / 10);
            pass_count++;
        end else begin
            $display("@%0t: [TEST] FAIL: Cache replacement test failed", $time);
            $display("  Status: %0d, Latency: %0d cycles", read_status, (end_time - start_time) / 10);
            fail_count++;
        end
        
        #100;
    endtask
    
    // 测试2: 压力测试（大量并发请求）
    task test_stress_test();
        automatic logic [255:0] read_data[8];
        automatic logic [31:0] read_strb[8];
        automatic logic [1:0] read_status[8];
        automatic int start_time, end_time;
        
        $display("=== Test 2: Stress Test (Multiple Concurrent Requests) ===");
        test_count++;
        
        start_time = $time;
        
        // 同时发送8个读请求
        fork
            for (int i = 0; i < 8; i++) begin
                automatic int idx = i;
                automatic logic [63:0] addr = 64'h9000_0000 + (idx * 64);
                automatic logic [255:0] data = 256'h2000_0000_0000_0000_0000_0000_0000_0000 + idx;
                
                fork
                    begin
                        test_base.send_noc_read_request(addr, 8'd64, 8'h70 + idx);
                        test_base.wait_noc_read_response(read_data[idx], read_strb[idx], read_status[idx]);
                    end
                    begin
                        test_base.simulate_memory_read_response(addr, data);
                    end
                join
            end
        join
        
        end_time = $time;
        
        // 验证所有请求都成功
        automatic int success_count = 0;
        for (int i = 0; i < 8; i++) begin
            if (read_status[i] == 2'b00) begin
                success_count++;
            end
        end
        
        if (success_count == 8) begin
            $display("@%0t: [TEST] PASS: Stress test passed", $time);
            $display("  All %0d requests completed successfully", success_count);
            $display("  Total time: %0d cycles", (end_time - start_time) / 10);
            pass_count++;
        end else begin
            $display("@%0t: [TEST] FAIL: Stress test failed", $time);
            $display("  Success count: %0d/8", success_count);
            fail_count++;
        end
        
        #100;
    endtask
    
    // 测试3: 边界条件测试
    task test_boundary_conditions();
        automatic logic [255:0] read_data;
        automatic logic [31:0] read_strb;
        automatic logic [1:0] read_status;
        
        $display("=== Test 3: Boundary Conditions Test ===");
        test_count++;
        
        // 测试地址边界
        automatic logic [63:0] boundary_addrs[4] = '{
            64'h0000_0000_0000_0000,  // 最小地址
            64'hFFFF_FFFF_FFFF_FFC0,  // 最大对齐地址
            64'h0000_0000_0000_0001,  // 未对齐地址
            64'h8000_0000_0000_0000   // 高位地址
        };
        
        automatic int success_count = 0;
        
        for (int i = 0; i < 4; i++) begin
            automatic logic [63:0] addr = boundary_addrs[i];
            automatic logic [255:0] data = 256'h3000_0000_0000_0000_0000_0000_0000_0000 + i;
            
            fork
                begin
                    test_base.send_noc_read_request(addr, 8'd64, 8'h80 + i);
                    test_base.wait_noc_read_response(read_data, read_strb, read_status);
                end
                begin
                    test_base.simulate_memory_read_response(addr, data);
                end
            join
            
            if (read_status == 2'b00) begin
                success_count++;
            end
            
            #10;
        end
        
        if (success_count == 4) begin
            $display("@%0t: [TEST] PASS: Boundary conditions test passed", $time);
            pass_count++;
        end else begin
            $display("@%0t: [TEST] FAIL: Boundary conditions test failed", $time);
            $display("  Success count: %0d/4", success_count);
            fail_count++;
        end
        
        #100;
    endtask
    
    // 测试4: 缓存一致性测试
    task test_cache_coherence();
        automatic logic [255:0] read_data1, read_data2;
        automatic logic [31:0] read_strb1, read_strb2;
        automatic logic [1:0] read_status1, read_status2, write_status;
        
        $display("=== Test 4: Cache Coherence Test ===");
        test_count++;
        
        // 先读数据
        automatic logic [63:0] addr = 64'hA000_0000;
        automatic logic [255:0] original_data = 256'h4000_0000_0000_0000_0000_0000_0000_0000;
        automatic logic [255:0] new_data = 256'h5000_0000_0000_0000_0000_0000_0000_0000;
        
        fork
            begin
                test_base.send_noc_read_request(addr, 8'd64, 8'h90);
                test_base.wait_noc_read_response(read_data1, read_strb1, read_status1);
            end
            begin
                test_base.simulate_memory_read_response(addr, original_data);
            end
        join
        
        #20;
        
        // 写新数据
        fork
            begin
                test_base.send_noc_write_request(addr, new_data, 32'hFFFF_FFFF, 8'd64, 8'h91);
                test_base.wait_noc_write_response(write_status);
            end
            begin
                test_base.simulate_memory_write_response(addr);
            end
        join
        
        #20;
        
        // 再次读数据，应该得到新数据
        fork
            begin
                test_base.send_noc_read_request(addr, 8'd64, 8'h92);
                test_base.wait_noc_read_response(read_data2, read_strb2, read_status2);
            end
            begin
                test_base.simulate_memory_read_response(addr, new_data);
            end
        join
        
        // 验证一致性
        if (read_status1 == 2'b00 && write_status == 2'b00 && read_status2 == 2'b00 && 
            read_data2 == new_data) begin
            $display("@%0t: [TEST] PASS: Cache coherence test passed", $time);
            pass_count++;
        end else begin
            $display("@%0t: [TEST] FAIL: Cache coherence test failed", $time);
            $display("  First read status: %0d", read_status1);
            $display("  Write status: %0d", write_status);
            $display("  Second read status: %0d", read_status2);
            $display("  Expected data: 0x%h, got: 0x%h", new_data, read_data2);
            fail_count++;
        end
        
        #100;
    endtask
    
    // 测试5: 性能基准测试
    task test_performance_benchmark();
        automatic logic [255:0] read_data;
        automatic logic [31:0] read_strb;
        automatic logic [1:0] read_status;
        automatic int start_time, end_time;
        automatic int total_latency = 0;
        automatic int request_count = 0;
        
        $display("=== Test 5: Performance Benchmark Test ===");
        test_count++;
        
        // 执行100次读操作，测量平均延迟
        for (int i = 0; i < 100; i++) begin
            automatic logic [63:0] addr = 64'hB000_0000 + (i * 64);
            automatic logic [255:0] data = 256'h6000_0000_0000_0000_0000_0000_0000_0000 + i;
            
            start_time = $time;
            
            fork
                begin
                    test_base.send_noc_read_request(addr, 8'd64, 8'hA0 + i[7:0]);
                    test_base.wait_noc_read_response(read_data, read_strb, read_status);
                end
                begin
                    test_base.simulate_memory_read_response(addr, data);
                end
            join
            
            end_time = $time;
            
            if (read_status == 2'b00) begin
                total_latency += (end_time - start_time) / 10;
                request_count++;
            end
            
            #5;
        end
        
        // 计算平均延迟
        if (request_count > 0) begin
            automatic real avg_latency = real'(total_latency) / real'(request_count);
            automatic real throughput = real'(request_count) / (real'(total_latency) / 100.0); // requests per cycle
            
            $display("@%0t: [TEST] Performance Results:", $time);
            $display("  Total requests: %0d", request_count);
            $display("  Average latency: %.2f cycles", avg_latency);
            $display("  Throughput: %.2f requests/cycle", throughput);
            
            if (avg_latency < 50.0 && request_count == 100) begin
                $display("@%0t: [TEST] PASS: Performance benchmark test passed", $time);
                pass_count++;
            end else begin
                $display("@%0t: [TEST] FAIL: Performance benchmark test failed", $time);
                fail_count++;
            end
        end else begin
            $display("@%0t: [TEST] FAIL: No successful requests in performance test", $time);
            fail_count++;
        end
        
        #100;
    endtask
    
    // 测试6: 错误恢复测试
    task test_error_recovery();
        automatic logic [255:0] read_data;
        automatic logic [31:0] read_strb;
        automatic logic [1:0] read_status;
        
        $display("=== Test 6: Error Recovery Test ===");
        test_count++;
        
        // 第一次请求返回错误
        automatic logic [63:0] addr = 64'hC000_0000;
        automatic logic [255:0] data = 256'h7000_0000_0000_0000_0000_0000_0000_0000;
        
        fork
            begin
                test_base.send_noc_read_request(addr, 8'd64, 8'hB0);
                test_base.wait_noc_read_response(read_data, read_strb, read_status);
            end
            begin
                test_base.simulate_memory_read_response(addr, data, 2'b10); // SLVERR
            end
        join
        
        #20;
        
        // 第二次请求应该正常
        fork
            begin
                test_base.send_noc_read_request(addr, 8'd64, 8'hB1);
                test_base.wait_noc_read_response(read_data, read_strb, read_status);
            end
            begin
                test_base.simulate_memory_read_response(addr, data, 2'b00); // OKAY
            end
        join
        
        // 验证错误恢复
        if (read_status == 2'b00) begin
            $display("@%0t: [TEST] PASS: Error recovery test passed", $time);
            pass_count++;
        end else begin
            $display("@%0t: [TEST] FAIL: Error recovery test failed", $time);
            $display("  Final read status: %0d", read_status);
            fail_count++;
        end
        
        #100;
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
        clk_mgr = new("l2cache_advanced_test", 10.0, 10);
        clk_mgr.initialize(clk_rst_if);
        
        // Create test base with virtual interfaces
        test_base = new(noc_if.device, mem_if.slave, clk_rst_if, clk_mgr);
        
        $display("@%0t: Build completed", $time);
    endfunction

    //===================================
    // Setup for running the Unit Tests
    //===================================
    task setup();
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
    // Advanced Test Cases
    //===================================
    
    `SVTEST(test_reset_state)
        $display("@%0t: Testing L2 Cache advanced reset state", $time);
        
        // Check that all interface signals are in reset state
        test_base.check_interface_reset_state();
        
        $display("@%0t: Reset state test completed", $time);
    `SVTEST_END

    `SVTEST(test_cache_replacement)
        $display("@%0t: Testing cache replacement", $time);
        test_cache_replacement();
    `SVTEST_END

    `SVTEST(test_stress_test)
        $display("@%0t: Testing stress test", $time);
        test_stress_test();
    `SVTEST_END

    `SVTEST(test_boundary_conditions)
        $display("@%0t: Testing boundary conditions", $time);
        test_boundary_conditions();
    `SVTEST_END

    `SVTEST(test_cache_coherence)
        $display("@%0t: Testing cache coherence", $time);
        test_cache_coherence();
    `SVTEST_END

    `SVTEST(test_performance_benchmark)
        $display("@%0t: Testing performance benchmark", $time);
        test_performance_benchmark();
    `SVTEST_END

    `SVTEST(test_error_recovery)
        $display("@%0t: Testing error recovery", $time);
        test_error_recovery();
    `SVTEST_END

    `SVUNIT_TESTS_END
    
    //=============================================================================
    // Advanced Monitoring
    //=============================================================================
    
    // 监控缓存状态变化
    always @(posedge clk) begin
        // 监控缓存状态变化（如果调试接口可用）
        // 注意：这里需要根据实际的调试接口来调整
    end
    
    // 监控性能计数器
    always @(posedge clk) begin
        // 监控性能计数器（如果调试接口可用）
        // 注意：这里需要根据实际的调试接口来调整
    end
    
    // 监控内存带宽使用
    always @(posedge clk) begin
        if (mem_if.arvalid && mem_if.arready) begin
            $display("@%0t: [MONITOR] Memory Read: addr=0x%h, burst_len=%0d", 
                     $time, mem_if.araddr, mem_if.arlen);
        end
        if (mem_if.awvalid && mem_if.awready) begin
            $display("@%0t: [MONITOR] Memory Write: addr=0x%h, burst_len=%0d", 
                     $time, mem_if.awaddr, mem_if.awlen);
        end
    end

endmodule : ut_rvgpu_l2cache_advanced_unit_test

`endif // UT_RVGPU_L2CACHE_ADVANCED_SV 