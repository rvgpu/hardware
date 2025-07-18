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

`ifndef RVGPU_MEMORY_AXI_SVH
`define RVGPU_MEMORY_AXI_SVH

`include "rvgpu_interface_axi.svh"
`include "../test/common/rvgpu_clk_rst.svh"

// DPI导入声明 - 从C++导入GPU内存访问函数
import "DPI-C" context function void gpu_write_mem(input longint unsigned addr, input longint unsigned data);
import "DPI-C" context function longint unsigned gpu_read_mem(input longint unsigned addr);

// 定义AXI状态枚举
typedef enum logic [1:0] {
    AXI_IDLE = 2'b00,
    AXI_BUSY = 2'b01,
    AXI_DONE = 2'b10,
    AXI_ERROR = 2'b11
} axi_state_t;

// 定义FIFO条目结构 - 使用packed优化内存布局
typedef struct packed {
    logic [7:0]  id;
    logic [47:0] addr;
    logic [7:0]  len;
    logic        valid;
    logic        error;
    int          latency;
    axi_state_t  state;
} write_fifo_entry_t;

typedef struct packed {
    logic [7:0] id;
    logic       valid;
    logic       error;
    int         latency;
    axi_state_t state;
} response_fifo_entry_t;

typedef struct packed {
    logic [7:0]  id;
    logic [47:0] addr;
    logic [7:0]  len;
    logic        valid;
    logic        error;
    int          latency;
    axi_state_t  state;
} read_fifo_entry_t;

// 延迟配置结构
typedef struct {
    int read_a_latency = 0;      // 读地址通道延迟
    int read_a2r_latency = 2;    // 读地址到读数据延迟
    int read_r2r_latency = 0;    // 读数据到读数据延迟
    int write_a_latency = 0;     // 写地址通道延迟
    int write_a2w_latency = 1;   // 写地址到写数据延迟
    int write_w2w_latency = 0;   // 写数据到写数据延迟
    int write_w2b_latency = 1;   // 写数据到写响应延迟
} latency_config_t;

// 统计信息结构
typedef struct {
    int write_transactions;
    int read_transactions;
    int total_latency;
    int max_queue_depth;
    int error_count;
} statistics_t;

// 单个Memory Slice AXI操作类
class rvgpu_memory_axi;

    // 端口
    virtual memory_if mem_if;
    rvgpu_clk_manager clk_mgr;
    const int slice_id;  // 当前slice的ID

    // 配置参数 - 使用localparam提高性能
    localparam int unsigned MAX_READ_REQUESTS = 8;
    localparam int unsigned MAX_WRITE_REQUESTS = 8;
    localparam int unsigned MAX_TOTAL_REQUESTS = MAX_READ_REQUESTS + MAX_WRITE_REQUESTS;
    localparam int unsigned VALID_BURST_LENGTHS[] = '{0, 1, 3, 7, 15};
    localparam int unsigned MAX_BURST_SIZE = 16;  // 最大burst大小
    
    // 动态数据宽度 - 在构造函数中计算
    int unsigned DATA_WIDTH_BYTES;
    
    // 延迟配置
    latency_config_t latency_cfg;
    
    // 请求计数器
    int number_of_reads = 0;
    int number_of_writes = 0;
    int number_of_accesses = 0;
    
    // 延迟计数器
    int ar_latency = 0;
    int aw_latency = 0;
    
    // FIFO队列 - 使用queue类型，更灵活
    write_fifo_entry_t wfifo[$];
    response_fifo_entry_t bfifo[$];
    read_fifo_entry_t rfifo[$];
    
    // 读数据寄存器 - 使用动态大小
    logic [`MEMORY_INTERFACE_DATA_WIDTH-1:0] rdata_tmp;  // 使用配置的数据宽度
    logic [31:0] rdata[`MEMORY_INTERFACE_DATA_WIDTH/32];  // 动态数组大小

    // 统计信息
    statistics_t stats;

    // 构造
    function new(virtual memory_if mem, rvgpu_clk_manager clk_mgr, int slice_id);
        this.mem_if = mem;
        this.clk_mgr = clk_mgr;
        this.slice_id = slice_id;
        
        // 计算数据宽度
        DATA_WIDTH_BYTES = $bits(mem_if.wdata) / 8;
        
        // 初始化queue
        wfifo.delete();
        bfifo.delete();
        rfifo.delete();
        
        // 初始化统计信息
        stats = '{0, 0, 0, 0, 0};
    endfunction

    task init();
        // 初始化接口信号
        mem_if.arready = 1'b0;
        mem_if.awready = 1'b0;
        mem_if.wready = 1'b0;
        mem_if.bvalid = 1'b0;
        mem_if.rvalid = 1'b0;
        mem_if.rlast = 1'b0;
        mem_if.bresp = 2'b00;
        mem_if.rresp = 2'b00;
        mem_if.bid = 8'h0;
        mem_if.rid = 8'h0;
        mem_if.rdata = 128'h0;
        
        // 重置计数器
        number_of_reads = 0;
        number_of_writes = 0;
        number_of_accesses = 0;
        ar_latency = 0;
        aw_latency = 0;
        stats = '{0, 0, 0, 0, 0};
        
        // 清空queue
        wfifo.delete();
        bfifo.delete();
        rfifo.delete();
        
        $display("@%0t: [MEM_AXI_SLICE%0d] 初始化完成", $time, slice_id);
    endtask

    task run();
        $display("@%0t: [MEM_AXI_SLICE%0d] 开始运行", $time, slice_id);
        forever begin
            clk_mgr.wait_posedge();
            update_ready_signals();
            handle_write_address();
            handle_write_data();
            handle_write_response();
            handle_read_address();
            handle_read_data();
            update_latency_counters();
            update_statistics();
        end
    endtask

    // 更新就绪信号
    task update_ready_signals();
        // 使用条件运算符简化逻辑
        mem_if.arready = (ar_latency == 0) && 
                        (rfifo.size() < MAX_READ_REQUESTS) &&
                        (number_of_accesses < MAX_TOTAL_REQUESTS);
        
        mem_if.awready = (aw_latency == 0) &&
                        (wfifo.size() < MAX_WRITE_REQUESTS) &&
                        (number_of_accesses < MAX_TOTAL_REQUESTS);
        
        mem_if.wready = (wfifo.size() > 0) && 
                       wfifo[0].valid && 
                       wfifo[0].latency == 0 &&
                       wfifo[0].len != 0;
    endtask

    // 处理写地址通道
    task handle_write_address();
        logic error;
        if (mem_if.awvalid && mem_if.awready) begin
            $display("@%0t: [MEM_AXI_SLICE%0d] 写地址请求: addr=0x%h, len=%0d, size=%0d", 
                     $time, slice_id, mem_if.awaddr, mem_if.awlen, mem_if.awsize);
            
            // 检查协议合规性
            error = check_write_protocol();
            
            // 直接添加到queue
            wfifo.push_back('{
                id: mem_if.awid,
                addr: mem_if.awaddr,
                len: mem_if.awlen + 1,
                valid: 1'b1,
                error: error,
                latency: latency_cfg.write_a2w_latency,
                state: AXI_BUSY
            });
            number_of_writes++;
            number_of_accesses++;
            
            aw_latency = latency_cfg.write_a_latency;
            
            // 断言检查
            assert (wfifo.size() <= MAX_WRITE_REQUESTS) else
                $error("写FIFO溢出: size=%0d, max=%0d", wfifo.size(), MAX_WRITE_REQUESTS);
        end
    endtask

    // 处理写数据通道
    task handle_write_data();
        if (mem_if.wvalid && mem_if.wready && wfifo.size() > 0) begin
            $display("@%0t: [MEM_AXI_SLICE%0d] 写数据: data=0x%h, strb=0x%h, last=%0d", 
                     $time, slice_id, mem_if.wdata, mem_if.wstrb, mem_if.wlast);
            
            // 执行内存写操作
            write_memory_burst(wfifo[0].addr, mem_if.wstrb, mem_if.wdata);
            
            if (mem_if.wlast) begin
                // 最后一个数据，准备写响应
                bfifo.push_back('{
                    id: wfifo[0].id,
                    valid: 1'b1,
                    error: wfifo[0].error,
                    latency: latency_cfg.write_w2b_latency,
                    state: AXI_DONE
                });
                wfifo.pop_front();
                number_of_writes--;
                number_of_accesses--;
                stats.write_transactions++;
            end else begin
                // 更新地址和长度
                wfifo[0].addr += DATA_WIDTH_BYTES;
                wfifo[0].len--;
                wfifo[0].latency = latency_cfg.write_w2w_latency;
            end
        end
    endtask

    // 处理写响应通道
    task handle_write_response();
        if (bfifo.size() > 0 && bfifo[0].latency == 0) begin
            mem_if.bvalid = 1'b1;
            mem_if.bid = bfifo[0].id;
            mem_if.bresp = bfifo[0].error ? 2'b10 : 2'b00;
            
            if (mem_if.bready) begin
                $display("@%0t: [MEM_AXI_SLICE%0d] 写响应: id=%0d, resp=%0d", 
                         $time, slice_id, mem_if.bid, mem_if.bresp);
                bfifo.pop_front();
            end
        end else begin
            mem_if.bvalid = 1'b0;
        end
    endtask

    // 处理读地址通道
    task handle_read_address();
        logic error;
        if (mem_if.arvalid && mem_if.arready) begin
            $display("@%0t: [MEM_AXI_SLICE%0d] 读地址请求: addr=0x%h, len=%0d, size=%0d", 
                     $time, slice_id, mem_if.araddr, mem_if.arlen, mem_if.arsize);
            
            // 检查协议合规性
            error = check_read_protocol();
            
            // 直接添加到queue
            rfifo.push_back('{
                id: mem_if.arid,
                addr: mem_if.araddr,
                len: mem_if.arlen,
                valid: 1'b1,
                error: error,
                latency: latency_cfg.read_a2r_latency,
                state: AXI_BUSY
            });
            number_of_reads++;
            number_of_accesses++;
            
            ar_latency = latency_cfg.read_a_latency;
            
            // 断言检查
            assert (rfifo.size() <= MAX_READ_REQUESTS) else
                $error("读FIFO溢出: size=%0d, max=%0d", rfifo.size(), MAX_READ_REQUESTS);
        end
    endtask

    // 处理读数据通道
    task handle_read_data();
        if (rfifo.size() > 0 && rfifo[0].latency == 0) begin
            // 读取内存数据
            read_memory_burst(rfifo[0].addr);
            
            mem_if.rvalid = 1'b1;
            mem_if.rid = rfifo[0].id;
            mem_if.rdata = rdata_tmp;
            mem_if.rresp = rfifo[0].error ? 2'b10 : 2'b00;
            mem_if.rlast = (rfifo[0].len == 0);
            
            if (mem_if.rready) begin
                $display("@%0t: [MEM_AXI_SLICE%0d] 读数据: id=%0d, addr=0x%h, data=0x%h, last=%0d", 
                         $time, slice_id, mem_if.rid, rfifo[0].addr, mem_if.rdata, mem_if.rlast);
                
                if (mem_if.rlast) begin
                    // 最后一个数据
                    rfifo.pop_front();
                    number_of_reads--;
                    number_of_accesses--;
                    stats.read_transactions++;
                end else begin
                    // 更新地址和长度
                    rfifo[0].addr += DATA_WIDTH_BYTES;
                    rfifo[0].len--;
                    rfifo[0].latency = latency_cfg.read_r2r_latency;
                end
            end
        end else begin
            mem_if.rvalid = 1'b0;
        end
    endtask

    // 更新延迟计数器
    task update_latency_counters();
        // 使用条件运算符简化
        ar_latency = (mem_if.arvalid && ar_latency > 0) ? ar_latency - 1 : latency_cfg.read_a_latency;
        aw_latency = (mem_if.awvalid && aw_latency > 0) ? aw_latency - 1 : latency_cfg.write_a_latency;
        
        // 更新FIFO延迟 - 使用foreach
        foreach (wfifo[i]) begin
            if (wfifo[i].valid && wfifo[i].latency != 0)
                wfifo[i].latency--;
        end
        
        foreach (bfifo[i]) begin
            if (bfifo[i].valid && bfifo[i].latency != 0)
                bfifo[i].latency--;
        end
        
        foreach (rfifo[i]) begin
            if (rfifo[i].valid && rfifo[i].latency != 0)
                rfifo[i].latency--;
        end
    endtask

    // 更新统计信息
    task update_statistics();
        int current_depth;
        // 更新总延迟统计
        stats.total_latency += (wfifo.size() + bfifo.size() + rfifo.size());
        
        // 更新最大队列深度
        current_depth = wfifo.size() + rfifo.size() + bfifo.size();
        if (current_depth > stats.max_queue_depth)
            stats.max_queue_depth = current_depth;
    endtask

    // 检查写协议合规性
    function logic check_write_protocol();
        // 使用inside操作符简化检查
        logic error = 1'b0;
        
        // 检查AWLEN是否为有效值
        if (!(mem_if.awlen inside {VALID_BURST_LENGTHS})) begin
            $display(" * WARNING: 检测到非2的幂次AWLEN(%0d) at time %0t!", mem_if.awlen, $time);
            error = 1'b1;
            stats.error_count++;
        end
        
        // 检查AWSIZE是否在合理范围内 (0到最大支持值)
        // AWSIZE表示每次传输的字节数 = 2^AWSIZE
        if (mem_if.awsize > $clog2(DATA_WIDTH_BYTES)) begin
            $display(" * WARNING: AWSIZE(%0d)超过最大支持值(%0d) at time %0t!", 
                     mem_if.awsize, $clog2(DATA_WIDTH_BYTES), $time);
            $display("   支持的AWSIZE范围: 0-%0d (对应1-%0d字节传输)", 
                     $clog2(DATA_WIDTH_BYTES), DATA_WIDTH_BYTES);
            error = 1'b1;
            stats.error_count++;
        end
        
        // 检查AWBURST是否为增量模式
        if (mem_if.awburst != 2'b01) begin
            $display(" * WARNING: 检测到非增量AWBURST(%0d) at time %0t!", mem_if.awburst, $time);
            $display("   支持的AWBURST: 2'b01 (INCR模式)");
            error = 1'b1;
            stats.error_count++;
        end
        
        return error;
    endfunction

    // 检查读协议合规性
    function logic check_read_protocol();
        logic error = 1'b0;
        
        // 检查ARLEN是否为有效值
        if (!(mem_if.arlen inside {VALID_BURST_LENGTHS})) begin
            $display(" * WARNING: 检测到非2的幂次ARLEN(%0d) at time %0t!", mem_if.arlen, $time);
            error = 1'b1;
            stats.error_count++;
        end
        
        // 检查ARSIZE是否在合理范围内 (0到最大支持值)
        if (mem_if.arsize > $clog2(DATA_WIDTH_BYTES)) begin
            $display(" * WARNING: ARSIZE(%0d)超过最大支持值(%0d) at time %0t!", 
                     mem_if.arsize, $clog2(DATA_WIDTH_BYTES), $time);
            error = 1'b1;
            stats.error_count++;
        end
        
        // 检查ARBURST是否为增量模式
        if (mem_if.arburst != 2'b01) begin
            $display(" * WARNING: 检测到非增量ARBURST(%0d) at time %0t!", mem_if.arburst, $time);
            error = 1'b1;
            stats.error_count++;
        end
        
        return error;
    endfunction

    // 写内存burst操作
    task write_memory_burst(logic [47:0] addr, logic [`MEMORY_INTERFACE_DATA_WIDTH/8-1:0] strb, logic [`MEMORY_INTERFACE_DATA_WIDTH-1:0] data);
        // 动态处理字节
        for (int i = 0; i < `MEMORY_INTERFACE_DATA_WIDTH/8; i++) begin
            if (strb[i]) begin
                logic [7:0] byte_data;
                // 小端序处理 - 低位字节对应低地址
                byte_data = data[i*8 +: 8];
                gpu_write_mem(addr + i, byte_data);
            end
        end
    endtask

    // 读内存burst操作
    task read_memory_burst(logic [47:0] addr);
        // 动态读取数据
        for (int i = 0; i < `MEMORY_INTERFACE_DATA_WIDTH/32; i++) begin
            rdata[i] = gpu_read_mem(addr + i*4);
        end
        // 正确组合数据 - 小端序，低位在前
        // 动态组合数据，从高位到低位
        rdata_tmp = 0;
        for (int i = 0; i < `MEMORY_INTERFACE_DATA_WIDTH/32; i++) begin
            rdata_tmp[(`MEMORY_INTERFACE_DATA_WIDTH-1)-i*32 -: 32] = rdata[(`MEMORY_INTERFACE_DATA_WIDTH/32)-1-i];
        end
    endtask

    // 获取统计信息
    function void get_statistics();
        $display("@%0t: [MEM_AXI_SLICE%0d] 统计信息:", $time, slice_id);
        $display("  写事务: %0d", stats.write_transactions);
        $display("  读事务: %0d", stats.read_transactions);
        $display("  总延迟: %0d", stats.total_latency);
        $display("  最大队列深度: %0d", stats.max_queue_depth);
        $display("  错误计数: %0d", stats.error_count);
        $display("  当前写队列大小: %0d", wfifo.size());
        $display("  当前读队列大小: %0d", rfifo.size());
        $display("  当前响应队列大小: %0d", bfifo.size());
    endfunction

    // 重置统计信息
    function void reset_statistics();
        stats = '{0, 0, 0, 0, 0};
    endfunction

endclass

`endif // RVGPU_MEMORY_AXI_SVH 