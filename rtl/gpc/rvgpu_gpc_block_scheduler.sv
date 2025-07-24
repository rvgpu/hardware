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

`ifndef RVGPU_GPC_BLOCK_SCHEDULER_SV
`define RVGPU_GPC_BLOCK_SCHEDULER_SV

`include "rvgpu_typedef.svh"
`include "rvgpu_job_block.svh"
`include "gpc_noc_adapter_if.svh"
`include "gpc_block_tpc_if.svh"
`include "gpc_block_raster_if.svh"
`include "gpc_l15_cache_if.svh"
`include "gpc_mmu_if.svh"

// GPC Block Scheduler模块
// 负责接收job_block并将其调度到合适的TPC
module rvgpu_gpc_block_scheduler #(
    parameter int NUM_TPC = 4,           // TPC数量
    parameter int MAX_WARPS_PER_BLOCK = 32, // 每个Block最大Warp数
    parameter int ADDR_WIDTH = 40        // 地址宽度
) (
    input  logic clk,
    input  logic rst_n,
    
    // NOC Adapter接口
    gpc_noc_adapter_if.device noc_if,
    
    // TPC接口
    gpc_block_tpc_if.scheduler tpc_if[NUM_TPC],
    
    // Raster Engine接口
    gpc_block_raster_if.scheduler raster_if,
    
    // L1.5 Cache接口
    gpc_l15_cache_if.requester l15_if,
    
    // GPC MMU接口
    gpc_mmu_if.requester tlb_if
);
    // 状态机状态
    typedef enum logic [3:0] {
        IDLE,
        PARSE_JOB,
        TRANSLATE_ARGLIST,
        WAIT_TLB,
        FETCH_ARGLIST,
        WAIT_ARGLIST,
        DISPATCH_COMPUTE,
        DISPATCH_RASTER,
        WAIT_DISPATCH
    } scheduler_state_t;
    
    // Warp定义
    typedef struct packed {
        logic [31:0] warp_id;
        logic [31:0] block_id;
        logic [63:0] program_addr;
        logic [63:0] arglist_ptr;
        logic [31:0] argument_size;
        logic [31:0] thread_mask;
        logic [255:0] arglist_data;
    } warp_t;
    
    // 内部信号
    scheduler_state_t state;
    job_block_t current_job;
    logic [63:0] arglist_paddr;
    logic [31:0] current_block_id;
    logic [31:0] warp_count;
    logic [$clog2(NUM_TPC)-1:0] target_tpc;
    warp_t current_warp;
    logic [7:0] tpc_load[NUM_TPC];
    
    // 解析Job Block
    function automatic void parse_job_block(input job_block_t job);
        current_job = job;
        current_block_id = job.current_block_id;
        
        // 简化实现：假设每个Block有8个Warp
        warp_count = 8;
    endfunction
    
    // 选择负载最低的TPC
    function automatic logic [$clog2(NUM_TPC)-1:0] select_tpc();
        logic [$clog2(NUM_TPC)-1:0] selected_tpc;
        logic [7:0] min_load;
        
        selected_tpc = '0;
        min_load = tpc_load[0];
        
        for (int i = 1; i < NUM_TPC; i++) begin
            if (tpc_load[i] < min_load) begin
                min_load = tpc_load[i];
                selected_tpc = i[$clog2(NUM_TPC)-1:0];
            end
        end
        
        return selected_tpc;
    endfunction
    
    // 生成Warp
    function automatic warp_t create_warp(
        input logic [31:0] warp_id,
        input job_block_t job,
        input logic [255:0] arglist_data
    );
        warp_t warp;
        
        warp.warp_id = warp_id;
        warp.block_id = job.current_block_id;
        warp.program_addr = job.program_addr;
        warp.arglist_ptr = job.arglist_ptr;
        warp.argument_size = job.argument_size;
        warp.thread_mask = '1; // 默认所有线程都活跃
        warp.arglist_data = arglist_data;
        
        return warp;
    endfunction
    
    // 主状态机
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            current_job <= '0;
            arglist_paddr <= '0;
            current_block_id <= '0;
            warp_count <= '0;
            target_tpc <= '0;
            current_warp <= '0;
            
            // 初始化TPC负载
            for (int i = 0; i < NUM_TPC; i++) begin
                tpc_load[i] <= '0;
            end
            
            // 初始化接口信号
            noc_if.job_ready <= 1'b0;
            for (int i = 0; i < NUM_TPC; i++) begin
                tpc_if[i].warp_valid <= 1'b0;
            end
            raster_if.cmd_valid <= 1'b0;
            l15_if.req_valid <= 1'b0;
            tlb_if.req_valid <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    // 接收来自NOC Adapter的Job Block
                    noc_if.job_ready <= 1'b1;
                    
                    if (noc_if.job_valid && noc_if.job_ready) begin
                        parse_job_block(noc_if.job_block);
                        noc_if.job_ready <= 1'b0;
                        state <= PARSE_JOB;
                    end
                end
                
                PARSE_JOB: begin
                    // 解析Job Block并确定任务类型
                    if (current_job.program_addr[63]) begin
                        // 光栅化任务 (假设程序地址最高位为1表示光栅化任务)
                        state <= DISPATCH_RASTER;
                    end else begin
                        // 计算任务，需要获取参数列表
                        state <= TRANSLATE_ARGLIST;
                    end
                end
                
                TRANSLATE_ARGLIST: begin
                    // 请求GPC MMU进行地址转换
                    tlb_if.req_valid <= 1'b1;
                    tlb_if.req_vaddr <= current_job.arglist_ptr[38:0];
                    tlb_if.req_type <= gpc_mmu_if::MMU_READ;
                    tlb_if.req_warp_id <= '0;
                    tlb_if.req_source_id <= '0;
                    
                    if (tlb_if.req_ready) begin
                        tlb_if.req_valid <= 1'b0;
                        state <= WAIT_TLB;
                    end
                end
                
                WAIT_TLB: begin
                    // 等待GPC MMU响应
                    if (tlb_if.resp_valid) begin
                        if (tlb_if.resp_hit && !tlb_if.resp_fault) begin
                            // 地址转换成功
                            arglist_paddr <= {tlb_if.resp_ppn, current_job.arglist_ptr[11:0]};
                            state <= FETCH_ARGLIST;
                        end else begin
                            // 地址转换失败，放弃这个Job
                            state <= IDLE;
                        end
                    end
                end
                
                FETCH_ARGLIST: begin
                    // 从L1.5 Cache获取参数列表
                    l15_if.req_valid <= 1'b1;
                    l15_if.req_is_read <= 1'b1;
                    l15_if.req_paddr <= arglist_paddr;
                    l15_if.req_size <= 5; // 32字节
                    l15_if.req_type <= gpc_l15_cache_if::L15_CACHE_NORMAL;
                    l15_if.req_data <= '0;
                    l15_if.req_mask <= '0;
                    l15_if.req_id <= '0;
                    
                    if (l15_if.req_ready) begin
                        l15_if.req_valid <= 1'b0;
                        state <= WAIT_ARGLIST;
                    end
                end
                
                WAIT_ARGLIST: begin
                    // 等待L1.5 Cache响应
                    l15_if.resp_ready <= 1'b1;
                    
                    if (l15_if.resp_valid) begin
                        l15_if.resp_ready <= 1'b0;
                        
                        // 选择目标TPC
                        target_tpc <= select_tpc();
                        
                        // 创建第一个Warp
                        current_warp <= create_warp(
                            {current_block_id, 8'h00}, // warp_id = block_id + warp_index
                            current_job,
                            l15_if.resp_data
                        );
                        
                        state <= DISPATCH_COMPUTE;
                    end
                end
                
                DISPATCH_COMPUTE: begin
                    // 将Warp分发给TPC
                    tpc_if[target_tpc].warp_valid <= 1'b1;
                    tpc_if[target_tpc].warp_id <= current_warp.warp_id;
                    tpc_if[target_tpc].block_id <= current_warp.block_id;
                    tpc_if[target_tpc].program_addr <= current_warp.program_addr;
                    tpc_if[target_tpc].arglist_ptr <= current_warp.arglist_ptr;
                    tpc_if[target_tpc].argument_size <= current_warp.argument_size;
                    tpc_if[target_tpc].thread_mask <= current_warp.thread_mask;
                    tpc_if[target_tpc].arglist_data <= current_warp.arglist_data;
                    
                    if (tpc_if[target_tpc].warp_ready) begin
                        tpc_if[target_tpc].warp_valid <= 1'b0;
                        
                        // 更新TPC负载
                        tpc_load[target_tpc] <= tpc_load[target_tpc] + 1;
                        
                        // 检查是否还有更多Warp需要分发
                        if (warp_count > 1) begin
                            warp_count <= warp_count - 1;
                            
                            // 创建下一个Warp
                            current_warp.warp_id <= current_warp.warp_id + 1;
                            
                            // 选择下一个目标TPC
                            target_tpc <= select_tpc();
                            
                            state <= DISPATCH_COMPUTE;
                        end else begin
                            // 所有Warp都已分发，返回空闲状态
                            state <= IDLE;
                        end
                    end
                end
                
                DISPATCH_RASTER: begin
                    // 将光栅化命令发送给Raster Engine
                    raster_if.cmd_valid <= 1'b1;
                    raster_if.cmd_addr <= current_job.program_addr;
                    raster_if.cmd_data <= current_job.arglist_ptr;
                    raster_if.cmd_size <= current_job.argument_size;
                    
                    if (raster_if.cmd_ready) begin
                        raster_if.cmd_valid <= 1'b0;
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    // TPC完成处理
    genvar i;
    generate
        for (i = 0; i < NUM_TPC; i++) begin : tpc_complete_gen
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    tpc_if[i].complete_ready <= 1'b0;
                end else begin
                    tpc_if[i].complete_ready <= 1'b1;
                    
                    if (tpc_if[i].complete_valid && tpc_if[i].complete_ready) begin
                        // 减少TPC负载
                        if (tpc_load[i] > 0) begin
                            tpc_load[i] <= tpc_load[i] - 1;
                        end
                    end
                end
            end
        end
    endgenerate

endmodule : rvgpu_gpc_block_scheduler

`endif // RVGPU_GPC_BLOCK_SCHEDULER_SV 