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

`ifndef RVGPU_L2CACHE_TB_SV
`define RVGPU_L2CACHE_TB_SV

`include "rvgpu_l2cache_pkg.svh"
`include "rvgpu_l2cache_if.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_interface_axi.svh"

`ifndef RVGPU_L2CACHE_PKG_IMPORTED
`define RVGPU_L2CACHE_PKG_IMPORTED
import rvgpu_l2cache_pkg::*;
`endif // RVGPU_L2CACHE_PKG_IMPORTED

`ifndef RVGPU_INTERNAL_NOC_PKG_IMPORTED
`define RVGPU_INTERNAL_NOC_PKG_IMPORTED
import rvgpu_internal_noc_pkg::*;
`endif // RVGPU_INTERNAL_NOC_PKG_IMPORTED

//=============================================================================
// RVGPU L2 Cache Testbench
// 
// 主要功能：
// 1. 基本读写测试
// 2. 缓存命中/未命中测试
// 3. 并发访问测试
// 4. 性能统计测试
//=============================================================================

module rvgpu_l2cache_tb;

    //=============================================================================
    // Clock and Reset Generation
    //=============================================================================
    
    logic clk;
    logic rst_n;
    
    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz时钟
    end
    
    // 复位生成
    initial begin
        rst_n = 0;
        #100;
        rst_n = 1;
    end
    
    //=============================================================================
    // Test Configuration
    //=============================================================================
    
    // 测试配置
    localparam l2cache_config_t TEST_CONFIG = '{
        cache_size: 512*1024,           // 512KB
        slice_number: 1,                // 1个slice
        line_size: 64,                  // 64字节缓存行
        ways: 8,                        // 8路组相联
        sets: 1024,                     // 1024个组
        tag_bits: 46,                   // 46位Tag
        index_bits: 10,                 // 10位索引
        offset_bits: 6,                 // 6位偏移
        lru_bits: 8,                    // 8位LRU（对应8路组相联）
        axi_data_width: 64,             // 64位数据
        axi_addr_width: 64,             // 64位地址
        noc_data_width: 256,            // 256位NOC数据
        noc_header_width: 32,           // 32位NOC头部
        debug_enable: 1                 // 调试使能
    };
    
    // 消息类型
    localparam int MSG_MEM_READ_REQ = 8'h01;
    localparam int MSG_MEM_WRITE_REQ = 8'h02;
    localparam int MSG_MEM_READ_RESP = 8'h03;
    localparam int MSG_MEM_WRITE_RESP = 8'h04;
    localparam int MSG_CACHE_INVALIDATE = 8'h05;
    localparam int MSG_CACHE_FLUSH = 8'h06;
    
    // NOC头部类型定义
    typedef struct packed {
        logic [7:0] msg_type;
        logic [7:0] trans_id;
        logic [7:0] src_node;
        logic [7:0] dest_node;
        logic [1:0] local_addr;
    } noc_header_t;
    
    //=============================================================================
    // DUT Instance
    //=============================================================================
    
    // L2 Cache实例
    rvgpu_l2cache #(
        .L2CACHE_CONFIG(TEST_CONFIG)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .noc_if(noc_if),
        .mem_if(mem_if)
    );
    
    //=============================================================================
    // Interface Instances
    //=============================================================================
    
    // NOC接口
    rvgpu_internal_noc_if noc_if();
    
    // 内存接口
    memory_if mem_if();
    
    //=============================================================================
    // Test Variables
    //=============================================================================
    
    // 测试计数器
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;
    
    // 测试数据
    logic [63:0] test_addr;
    logic [255:0] test_data;
    logic [31:0] test_strb;
    logic [7:0] test_size;
    
    // 响应数据
    logic [255:0] resp_data;
    logic [31:0] resp_strb;
    logic [1:0] resp_status;
    
    //=============================================================================
    // Test Tasks
    //=============================================================================
    
    // 发送读请求
    task send_read_request(
        input logic [63:0] addr,
        input logic [7:0] size = 8'd64
    );
        automatic noc_header_t header;
        automatic logic [255:0] data;
        
        // 构建NOC头部
        header.msg_type = MSG_MEM_READ_REQ;
        header.src_node = 8'h01;
        header.dest_node = 8'h02;
        header.trans_id = test_count[7:0];
        header.local_addr = 2'b00;
        
        // 构建数据
        data[63:0] = addr;
        data[71:64] = size;
        data[255:72] = '0;
        
        // 发送请求
        @(posedge clk);
        noc_if.s_req_valid = 1'b1;
        noc_if.s_req_header = header;
        noc_if.s_req_data = data;
        noc_if.s_req_strb = '1;
        noc_if.s_req_last = 1'b1;
        
        // 等待接受
        @(posedge clk);
        while (!noc_if.s_req_ready) @(posedge clk);
        noc_if.s_req_valid = 1'b0;
        
        $display("@%0t: [TB] Read Request: addr=0x%h, size=%0d", 
                 $time, addr, size);
    endtask
    
    // 发送写请求
    task send_write_request(
        input logic [63:0] addr,
        input logic [255:0] data,
        input logic [31:0] strb = '1,
        input logic [7:0] size = 8'd64
    );
        automatic noc_header_t header;
        automatic logic [255:0] req_data;
        
        // 构建NOC头部
        header.msg_type = MSG_MEM_WRITE_REQ;
        header.src_node = 8'h01;
        header.dest_node = 8'h02;
        header.trans_id = test_count[7:0];
        header.local_addr = 2'b00;
        
        // 构建数据
        req_data[63:0] = addr;
        req_data[71:64] = size;
        req_data[255:72] = data[183:0];
        
        // 发送请求
        @(posedge clk);
        noc_if.s_req_valid = 1'b1;
        noc_if.s_req_header = header;
        noc_if.s_req_data = req_data;
        noc_if.s_req_strb = strb;
        noc_if.s_req_last = 1'b1;
        
        // 等待接受
        @(posedge clk);
        while (!noc_if.s_req_ready) @(posedge clk);
        noc_if.s_req_valid = 1'b0;
        
        $display("@%0t: [TB] Write Request: addr=0x%h, data=0x%h, strb=0x%h", 
                 $time, addr, data, strb);
    endtask
    
    // 等待读响应
    task wait_read_response(
        output logic [255:0] data,
        output logic [31:0] strb,
        output logic [1:0] status
    );
        // 等待响应
        @(posedge clk);
        while (!noc_if.s_resp_valid) @(posedge clk);
        
        // 接收响应
        data = noc_if.s_resp_data;
        strb = noc_if.s_resp_strb;
        status = noc_if.s_resp_status;
        
        // 确认响应
        noc_if.s_resp_ready = 1'b1;
        @(posedge clk);
        noc_if.s_resp_ready = 1'b0;
        
        $display("@%0t: [TB] Read Response: data=0x%h, status=%0d", 
                 $time, data, status);
    endtask
    
    // 等待写响应
    task wait_write_response(
        output logic [1:0] status
    );
        // 等待响应
        @(posedge clk);
        while (!noc_if.s_resp_valid) @(posedge clk);
        
        // 接收响应
        status = noc_if.s_resp_status;
        
        // 确认响应
        noc_if.s_resp_ready = 1'b1;
        @(posedge clk);
        noc_if.s_resp_ready = 1'b0;
        
        $display("@%0t: [TB] Write Response: status=%0d", $time, status);
    endtask
    
    // 模拟内存响应
    task simulate_memory_response(
        input logic [63:0] addr,
        input logic [255:0] data,
        input logic [1:0] status = 2'b00
    );
        // 等待内存请求
        @(posedge clk);
        while (!mem_if.arvalid && !mem_if.awvalid) @(posedge clk);
        
        if (mem_if.arvalid) begin
            // 读请求
            mem_if.arready = 1'b1;
            @(posedge clk);
            mem_if.arready = 1'b0;
            
            // 发送读数据
            mem_if.rvalid = 1'b1;
            mem_if.rdata = data;
            mem_if.rresp = status;
            mem_if.rlast = 1'b1;
            mem_if.rid = 8'h00;
            
            @(posedge clk);
            while (!mem_if.rready) @(posedge clk);
            mem_if.rvalid = 1'b0;
            
            $display("@%0t: [TB] Memory Read Response: addr=0x%h, data=0x%h", 
                     $time, addr, data);
        end else if (mem_if.awvalid) begin
            // 写请求
            mem_if.awready = 1'b1;
            @(posedge clk);
            mem_if.awready = 1'b0;
            
            // 等待写数据
            @(posedge clk);
            while (!mem_if.wvalid) @(posedge clk);
            mem_if.wready = 1'b1;
            @(posedge clk);
            mem_if.wready = 1'b0;
            
            // 发送写响应
            mem_if.bvalid = 1'b1;
            mem_if.bresp = status;
            mem_if.bid = 8'h00;
            
            @(posedge clk);
            while (!mem_if.bready) @(posedge clk);
            mem_if.bvalid = 1'b0;
            
            $display("@%0t: [TB] Memory Write Response: addr=0x%h, status=%0d", 
                     $time, addr, status);
        end
    endtask
    
    //=============================================================================
    // Test Cases
    //=============================================================================
    
    // 测试1: 基本读操作
    task test_basic_read();
        automatic logic [255:0] read_data;
        automatic logic [31:0] read_strb;
        automatic logic [1:0] read_status;
        
        $display("=== Test 1: Basic Read Operation ===");
        test_count++;
        
        // 发送读请求
        test_addr = 64'h1000_0000;
        send_read_request(test_addr, 8'd64);
        
        // 模拟内存响应
        test_data = 256'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0;
        simulate_memory_response(test_addr, test_data);
        
        // 等待缓存响应
        wait_read_response(read_data, read_strb, read_status);
        
        // 验证结果
        if (read_data == test_data && read_status == 2'b00) begin
            $display("PASS: Basic read test passed");
            pass_count++;
        end else begin
            $display("FAIL: Basic read test failed - expected=0x%h, got=0x%h", 
                     test_data, read_data);
            fail_count++;
        end
        
        #100;
    endtask
    
    // 测试2: 基本写操作
    task test_basic_write();
        automatic logic [1:0] write_status;
        
        $display("=== Test 2: Basic Write Operation ===");
        test_count++;
        
        // 发送写请求
        test_addr = 64'h2000_0000;
        test_data = 256'hFEDC_BA98_7654_3210_ABCD_EF01_2345_6789;
        test_strb = 32'hFFFF_FFFF;
        send_write_request(test_addr, test_data, test_strb);
        
        // 等待写响应
        wait_write_response(write_status);
        
        // 验证结果
        if (write_status == 2'b00) begin
            $display("PASS: Basic write test passed");
            pass_count++;
        end else begin
            $display("FAIL: Basic write test failed - status=%0d", write_status);
            fail_count++;
        end
        
        #100;
    endtask
    
    // 测试3: 缓存命中测试
    task test_cache_hit();
        automatic logic [255:0] read_data1, read_data2;
        automatic logic [31:0] read_strb1, read_strb2;
        automatic logic [1:0] read_status1, read_status2;
        
        $display("=== Test 3: Cache Hit Test ===");
        test_count++;
        
        // 第一次读（缓存未命中）
        test_addr = 64'h3000_0000;
        test_data = 256'h1111_2222_3333_4444_5555_6666_7777_8888;
        send_read_request(test_addr, 8'd64);
        simulate_memory_response(test_addr, test_data);
        wait_read_response(read_data1, read_strb1, read_status1);
        
        // 第二次读相同地址（缓存命中）
        send_read_request(test_addr, 8'd64);
        wait_read_response(read_data2, read_strb2, read_status2);
        
        // 验证结果
        if (read_data1 == test_data && read_data2 == test_data && 
            read_status1 == 2'b00 && read_status2 == 2'b00) begin
            $display("PASS: Cache hit test passed");
            pass_count++;
        end else begin
            $display("FAIL: Cache hit test failed");
            fail_count++;
        end
        
        #100;
    endtask
    
    // 测试4: 并发访问测试
    task test_concurrent_access();
        automatic logic [255:0] read_data1, read_data2;
        automatic logic [31:0] read_strb1, read_strb2;
        automatic logic [1:0] read_status1, read_status2;
        
        $display("=== Test 4: Concurrent Access Test ===");
        test_count++;
        
        // 并发发送两个读请求
        test_addr = 64'h4000_0000;
        test_data = 256'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111;
        
        fork
            begin
                send_read_request(test_addr, 8'd64);
                simulate_memory_response(test_addr, test_data);
                wait_read_response(read_data1, read_strb1, read_status1);
            end
            begin
                #10;
                send_read_request(test_addr + 64, 8'd64);
                simulate_memory_response(test_addr + 64, test_data + 1);
                wait_read_response(read_data2, read_strb2, read_status2);
            end
        join
        
        // 验证结果
        if (read_status1 == 2'b00 && read_status2 == 2'b00) begin
            $display("PASS: Concurrent access test passed");
            pass_count++;
        end else begin
            $display("FAIL: Concurrent access test failed");
            fail_count++;
        end
        
        #100;
    endtask
    
    //=============================================================================
    // Main Test Sequence
    //=============================================================================
    
    initial begin
        // 初始化接口
        noc_if.s_req_valid = 1'b0;
        noc_if.s_req_header = '0;
        noc_if.s_req_data = '0;
        noc_if.s_req_strb = '0;
        noc_if.s_req_last = 1'b0;
        noc_if.s_resp_ready = 1'b0;
        
        mem_if.arready = 1'b0;
        mem_if.rvalid = 1'b0;
        mem_if.rdata = '0;
        mem_if.rresp = 2'b00;
        mem_if.rlast = 1'b0;
        mem_if.rid = '0;
        mem_if.awready = 1'b0;
        mem_if.wready = 1'b0;
        mem_if.bvalid = 1'b0;
        mem_if.bresp = 2'b00;
        mem_if.bid = '0;
        
        // 等待复位完成
        wait(rst_n);
        #100;
        
        $display("=== RVGPU L2 Cache Testbench Started ===");
        
        // 运行测试用例
        test_basic_read();
        test_basic_write();
        test_cache_hit();
        test_concurrent_access();
        
        // 测试结果统计
        #100;
        $display("=== Test Results ===");
        $display("Total Tests: %0d", test_count);
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);
        $display("Success Rate: %.1f%%", (real'(pass_count) / real'(test_count)) * 100.0);
        
        if (fail_count == 0) begin
            $display("=== ALL TESTS PASSED ===");
        end else begin
            $display("=== SOME TESTS FAILED ===");
        end
        
        $finish;
    end
    
    //=============================================================================
    // Monitoring
    //=============================================================================
    
    // 监控缓存状态
    always @(posedge clk) begin
        if (dut.controller.state_r != dut.controller.L2_STATE_IDLE) begin
            $display("@%0t: [MONITOR] Cache State: %0d", 
                     $time, dut.controller.state_r);
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
    
    // 超时保护
    initial begin
        #1000000; // 1ms超时
        $display("ERROR: Testbench timeout");
        $finish;
    end

endmodule : rvgpu_l2cache_tb

`endif // RVGPU_L2CACHE_TB_SV 