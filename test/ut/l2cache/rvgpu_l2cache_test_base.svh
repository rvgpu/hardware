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

`ifndef RVGPU_L2CACHE_TEST_BASE_SVH
`define RVGPU_L2CACHE_TEST_BASE_SVH

`include "rvgpu_l2cache_pkg.svh"
`include "rvgpu_internal_noc_pkg.sv"
`include "rvgpu_interface_axi.svh"
`include "rvgpu_clk_rst.svh"

`ifndef RVGPU_L2CACHE_PKG_IMPORTED
`define RVGPU_L2CACHE_PKG_IMPORTED
import rvgpu_l2cache_pkg::*;
`endif // RVGPU_L2CACHE_PKG_IMPORTED

`ifndef RVGPU_INTERNAL_NOC_PKG_IMPORTED
`define RVGPU_INTERNAL_NOC_PKG_IMPORTED
import rvgpu_internal_noc_pkg::*;
`endif // RVGPU_INTERNAL_NOC_PKG_IMPORTED

//=============================================================================
// L2 Cache Test Transaction Types
//=============================================================================

// NOC请求事务结构
typedef struct packed {
    logic [63:0] addr;                // 访问地址
    logic [7:0]  size;                // 访问大小
    logic        read;                 // 读操作标志
    logic        write;                // 写操作标志
    logic [7:0]  trans_id;            // 事务ID
    logic [3:0]  src_node;            // 源节点ID
    logic [255:0] data;               // 写数据
    logic [31:0] strb;                // 写使能
} l2cache_noc_transaction_t;

// 内存响应事务结构
typedef struct packed {
    logic [255:0] data;               // 读数据
    logic [1:0]   status;             // 响应状态
    logic [7:0]   trans_id;           // 事务ID
    logic         last;                // 最后一个传输
} l2cache_mem_response_t;

// Virtual interface types for task parameters
typedef virtual rvgpu_internal_noc_if noc_vif_t;
typedef virtual memory_if mem_vif_t;
typedef virtual clk_rst_if clk_rst_vif_t;

//=============================================================================
// L2 Cache Test Base Class
//=============================================================================

class rvgpu_l2cache_test_base;

    // Interface references (to be connected from testbench)
    noc_vif_t noc_if;
    mem_vif_t mem_if;
    clk_rst_vif_t clk_rst_if;
    
    // Clock manager for elegant time control
    rvgpu_clk_manager clk_mgr;
    
    // Test statistics
    int read_requests;
    int write_requests;
    
    // 事务监控变量
    l2cache_noc_transaction_t captured_noc_trans;
    l2cache_mem_response_t captured_mem_resp;
    logic noc_transaction_detected;
    logic mem_response_detected;
    
    // 性能统计
    int total_requests;
    int cache_hits;
    int cache_misses;
    
    // 构造函数
    function new(noc_vif_t noc_vif, mem_vif_t mem_vif, clk_rst_vif_t clk_rst_vif, rvgpu_clk_manager clk_manager);
        this.noc_if = noc_vif;
        this.mem_if = mem_vif;
        this.clk_rst_if = clk_rst_vif;
        this.clk_mgr = clk_manager;
        
        // 初始化统计
        read_requests = 0;
        write_requests = 0;
    endfunction
    
    //=============================================================================
    // 接口初始化任务
    //=============================================================================
    
    // 初始化所有接口信号
    task initialize_signals();
        // NOC接口初始化 - 测试用例作为device，DUT作为NOC
        // 在device modport中，s_req_*是输出，s_resp_*是输入
        noc_if.s_req_valid = 1'b0;
        noc_if.s_req_header = '0;
        noc_if.s_req_data = '0;
        noc_if.s_req_strb = '0;
        noc_if.s_req_last = 1'b0;
        noc_if.s_resp_ready = 1'b0;
        
        // 内存接口初始化 - 测试用例作为slave模拟外部内存
        // 在slave modport中，*ready信号是输出，*valid/*data/*resp信号是输入
        // 我们可以驱动*ready信号来允许DUT发送请求
        mem_if.arready = 1'b1;  // 允许DUT发送读地址
        mem_if.awready = 1'b1;  // 允许DUT发送写地址
        mem_if.wready = 1'b1;   // 允许DUT发送写数据
        mem_if.bready = 1'b1;   // 允许DUT接收写响应
        mem_if.rready = 1'b1;   // 允许DUT接收读数据
        
        $display("@%0t: [TEST_BASE] All interfaces initialized", $time);
    endtask
    
    // 清除NOC接口信号
    task clear_noc_signals();
        noc_if.s_req_valid = 1'b0;
        noc_if.s_req_header = '0;
        noc_if.s_req_data = '0;
        noc_if.s_req_strb = '0;
        noc_if.s_req_last = 1'b0;
        noc_if.s_resp_ready = 1'b0;
    endtask
    
    // 清除内存接口信号
    task clear_mem_signals();
        // 在slave modport中，我们可以驱动*ready信号
        // 其他信号（*valid, *data, *resp等）是输入，由DUT驱动
        mem_if.arready = 1'b1;  // 保持允许DUT发送读地址
        mem_if.awready = 1'b1;  // 保持允许DUT发送写地址
        mem_if.wready = 1'b1;   // 保持允许DUT发送写数据
        mem_if.bready = 1'b1;   // 保持允许DUT接收写响应
        mem_if.rready = 1'b1;   // 保持允许DUT接收读数据
    endtask
    
    // 初始化监控变量
    task initialize_monitors();
        captured_noc_trans = '{default: 0};
        captured_mem_resp = '{default: 0};
        noc_transaction_detected = 1'b0;
        mem_response_detected = 1'b0;
        total_requests = 0;
        cache_hits = 0;
        cache_misses = 0;
        read_requests = 0;
        write_requests = 0;
    endtask
    
    //=============================================================================
    // NOC请求发送任务
    //=============================================================================
    
    // 发送NOC读请求
    task send_noc_read_request(
        input logic [63:0] addr,
        input logic [7:0] size = 8'd64,
        input logic [7:0] trans_id = 8'h00,
        input logic [3:0] src_node = 4'h1
    );
        automatic noc_header_t header;
        automatic logic [255:0] data;
        
        // 构建NOC头部
        header.msg_type = MSG_MEM_READ_REQ;
        header.src_node = src_node;
        header.dest_node = NODE_L2_CACHE;
        header.trans_id = trans_id;
        header.local_addr = 8'h00;
        
        // 构建数据
        data[63:0] = addr;
        data[71:64] = size;
        data[255:72] = '0;
        
        // 发送请求
        @(posedge clk_rst_if.clk);
        noc_if.s_req_valid = 1'b1;
        noc_if.s_req_header = header;
        noc_if.s_req_data = data;
        noc_if.s_req_strb = '1;
        noc_if.s_req_last = 1'b1;
        
        // 等待接受
        @(posedge clk_rst_if.clk);
        while (!noc_if.s_req_ready) @(posedge clk_rst_if.clk);
        noc_if.s_req_valid = 1'b0;
        
        total_requests++;
        read_requests++;
        
        $display("@%0t: [TEST_BASE] NOC Read Request: addr=0x%h, size=%0d, trans_id=%0d", 
                 $time, addr, size, trans_id);
    endtask
    
    // 发送NOC写请求
    task send_noc_write_request(
        input logic [63:0] addr,
        input logic [255:0] data,
        input logic [31:0] strb = '1,
        input logic [7:0] size = 8'd64,
        input logic [7:0] trans_id = 8'h00,
        input logic [3:0] src_node = 4'h1
    );
        automatic noc_header_t header;
        automatic logic [255:0] req_data;
        
        // 构建NOC头部
        header.msg_type = MSG_MEM_WRITE_REQ;
        header.src_node = src_node;
        header.dest_node = NODE_L2_CACHE;
        header.trans_id = trans_id;
        header.local_addr = 8'h00;
        
        // 构建数据
        req_data[63:0] = addr;
        req_data[71:64] = size;
        req_data[255:72] = data[183:0];
        
        // 发送请求
        @(posedge clk_rst_if.clk);
        noc_if.s_req_valid = 1'b1;
        noc_if.s_req_header = header;
        noc_if.s_req_data = req_data;
        noc_if.s_req_strb = strb;
        noc_if.s_req_last = 1'b1;
        
        // 等待接受
        @(posedge clk_rst_if.clk);
        while (!noc_if.s_req_ready) @(posedge clk_rst_if.clk);
        noc_if.s_req_valid = 1'b0;
        
        total_requests++;
        write_requests++;
        
        $display("@%0t: [TEST_BASE] NOC Write Request: addr=0x%h, data=0x%h, strb=0x%h", 
                 $time, addr, data, strb);
    endtask
    
    //=============================================================================
    // 响应等待任务
    //=============================================================================
    
    // 等待NOC读响应
    task wait_noc_read_response(
        output logic [255:0] data,
        output logic [31:0] strb,
        output logic [1:0] status,
        input int timeout_cycles = 1000
    );
        int cycle_count = 0;
        
        // 等待响应
        @(posedge clk_rst_if.clk);
        while (!noc_if.s_resp_valid && cycle_count < timeout_cycles) begin
            @(posedge clk_rst_if.clk);
            cycle_count++;
        end
        
        if (cycle_count >= timeout_cycles) begin
            $display("@%0t: [TEST_BASE] ERROR: Timeout waiting for NOC read response", $time);
            data = 'x;
            strb = 'x;
            status = 2'b11; // SLVERR
            return;
        end
        
        // 接收响应
        data = noc_if.s_resp_data;
        strb = '1; // NOC接口没有strb字段，使用默认值
        status = noc_if.s_resp_status;
        
        // 确认响应
        noc_if.s_resp_ready = 1'b1;
        @(posedge clk_rst_if.clk);
        noc_if.s_resp_ready = 1'b0;
        
        $display("@%0t: [TEST_BASE] NOC Read Response: data=0x%h, status=%0d", 
                 $time, data, status);
    endtask
    
    // 等待NOC写响应
    task wait_noc_write_response(
        output logic [1:0] status,
        input int timeout_cycles = 1000
    );
        int cycle_count = 0;
        
        // 等待响应
        @(posedge clk_rst_if.clk);
        while (!noc_if.s_resp_valid && cycle_count < timeout_cycles) begin
            @(posedge clk_rst_if.clk);
            cycle_count++;
        end
        
        if (cycle_count >= timeout_cycles) begin
            $display("@%0t: [TEST_BASE] ERROR: Timeout waiting for NOC write response", $time);
            status = 2'b11; // SLVERR
            return;
        end
        
        // 接收响应
        status = noc_if.s_resp_status;
        
        // 确认响应
        noc_if.s_resp_ready = 1'b1;
        @(posedge clk_rst_if.clk);
        noc_if.s_resp_ready = 1'b0;
        
        $display("@%0t: [TEST_BASE] NOC Write Response: status=%0d", $time, status);
    endtask
    
    //=============================================================================
    // 内存响应模拟任务
    //=============================================================================
    
    // 模拟内存读响应
    task simulate_memory_read_response(
        input logic [63:0] addr,
        input logic [255:0] data,
        input logic [1:0] status = 2'b00,
        input logic [7:0] trans_id = 8'h00
    );
        // 等待内存读请求
        @(posedge clk_rst_if.clk);
        while (!mem_if.arvalid) @(posedge clk_rst_if.clk);
        
        // 接受读地址
        mem_if.arready = 1'b1;
        @(posedge clk_rst_if.clk);
        mem_if.arready = 1'b0;
        
        // 发送读数据 - 在slave modport中，我们可以驱动这些信号
        mem_if.rvalid = 1'b1;
        mem_if.rdata = data;
        mem_if.rresp = status;
        mem_if.rlast = 1'b1;
        mem_if.rid = trans_id;
        
        @(posedge clk_rst_if.clk);
        while (!mem_if.rready) @(posedge clk_rst_if.clk);
        mem_if.rvalid = 1'b0;
        
        $display("@%0t: [TEST_BASE] Memory read response sent for addr 0x%h", $time, addr);
    endtask
    
    // 模拟内存写响应
    task simulate_memory_write_response(
        input logic [63:0] addr,
        input logic [1:0] status = 2'b00,
        input logic [7:0] trans_id = 8'h00
    );
        // 等待内存写地址请求
        @(posedge clk_rst_if.clk);
        while (!mem_if.awvalid) @(posedge clk_rst_if.clk);
        
        // 接受写地址
        mem_if.awready = 1'b1;
        @(posedge clk_rst_if.clk);
        mem_if.awready = 1'b0;
        
        // 等待写数据
        @(posedge clk_rst_if.clk);
        while (!mem_if.wvalid) @(posedge clk_rst_if.clk);
        mem_if.wready = 1'b1;
        @(posedge clk_rst_if.clk);
        mem_if.wready = 1'b0;
        
        // 发送写响应 - 在slave modport中，我们可以驱动这些信号
        mem_if.bvalid = 1'b1;
        mem_if.bresp = status;
        mem_if.bid = trans_id;
        
        @(posedge clk_rst_if.clk);
        while (!mem_if.bready) @(posedge clk_rst_if.clk);
        mem_if.bvalid = 1'b0;
        
        $display("@%0t: [TEST_BASE] Memory write response sent for addr 0x%h", $time, addr);
    endtask
    
    //=============================================================================
    // 性能统计任务
    //=============================================================================
    
    // 打印性能统计
    task print_performance_stats();
        real hit_rate;
        
        if (total_requests > 0) begin
            hit_rate = (real'(cache_hits) / real'(total_requests)) * 100.0;
        end else begin
            hit_rate = 0.0;
        end
        
        $display("@%0t: [TEST_BASE] Performance Statistics:", $time);
        $display("  Total Requests: %0d", total_requests);
        $display("  Read Requests: %0d", read_requests);
        $display("  Write Requests: %0d", write_requests);
        $display("  Cache Hits: %0d", cache_hits);
        $display("  Cache Misses: %0d", cache_misses);
        $display("  Hit Rate: %.2f%%", hit_rate);
    endtask
    
    // 重置性能统计
    task reset_performance_stats();
        total_requests = 0;
        cache_hits = 0;
        cache_misses = 0;
        read_requests = 0;
        write_requests = 0;
    endtask
    
    //=============================================================================
    // 验证任务
    //=============================================================================
    
    // 验证读响应
    task verify_read_response(
        input logic [255:0] expected_data,
        input logic [255:0] actual_data,
        input logic [1:0] expected_status,
        input logic [1:0] actual_status,
        input string test_name
    );
        if (actual_data == expected_data && actual_status == expected_status) begin
            $display("@%0t: [TEST_BASE] PASS: %s", $time, test_name);
            cache_hits++;
        end else begin
            $display("@%0t: [TEST_BASE] FAIL: %s", $time, test_name);
            $display("  Expected data: 0x%h, got: 0x%h", expected_data, actual_data);
            $display("  Expected status: %0d, got: %0d", expected_status, actual_status);
            cache_misses++;
        end
    endtask
    
    // 验证写响应
    task verify_write_response(
        input logic [1:0] expected_status,
        input logic [1:0] actual_status,
        input string test_name
    );
        if (actual_status == expected_status) begin
            $display("@%0t: [TEST_BASE] PASS: %s", $time, test_name);
        end else begin
            $display("@%0t: [TEST_BASE] FAIL: %s", $time, test_name);
            $display("  Expected status: %0d, got: %0d", expected_status, actual_status);
        end
    endtask
    
    //=============================================================================
    // 接口复位状态检查任务
    //=============================================================================
    
    // 检查接口复位状态
    task check_interface_reset_state();
        $display("@%0t: [TEST_BASE] Checking interface reset state", $time);
        // 检查NOC接口输出（应该在复位状态）
        `FAIL_IF(noc_if.s_req_valid !== 1'b0)
        `FAIL_IF(noc_if.s_req_header !== '0)
        `FAIL_IF(noc_if.s_req_data !== '0)
        `FAIL_IF(noc_if.s_req_strb !== '0)
        `FAIL_IF(noc_if.s_req_last !== 1'b0)
        `FAIL_IF(noc_if.s_resp_ready !== 1'b0)
        
        // 检查 MEMIF Master 接口
        // AXI Write
        `FAIL_IF(mem_if.awvalid !== 1'b0)
        `FAIL_IF(mem_if.wvalid !== 1'b0)
        `FAIL_IF(mem_if.bready !== 1'b0)

        // AXI Read
        `FAIL_IF(mem_if.arvalid !== 1'b0)
        `FAIL_IF(mem_if.rready !== 1'b0)
        $display("@%0t: [TEST_BASE] Interface reset state check passed", $time);
    endtask

endclass : rvgpu_l2cache_test_base

`endif // RVGPU_L2CACHE_TEST_BASE_SVH 