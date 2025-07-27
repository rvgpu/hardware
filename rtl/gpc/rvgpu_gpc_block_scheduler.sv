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
`include "rvgpu_job_cluster_block.svh"
`include "gpc_block_tpc_if.svh"
`include "gpc_block_raster_if.svh"
`include "gpc_l15_cache_if.svh"
`include "gpc_mmu_if.svh"

// GPC Block Scheduler模块
// 负责接收job_cluster并将其调度到合适的TPC
module rvgpu_gpc_block_scheduler #(
    parameter int GPC_ID = 0,
    parameter int NUM_TPC = 4,           // TPC数量
    parameter int MAX_WARPS_PER_BLOCK = 32, // 每个Block最大Warp数
    parameter int ADDR_WIDTH = 40        // 地址宽度
) (
    input  logic clk,
    input  logic rst_n,
    
    // NOC Adapter接口
    rvgpu_internal_noc_if.device noc_if,
    
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
    job_cluster_t current_job;
    logic [63:0] arglist_paddr;
    logic [31:0] current_block_id;
    logic [31:0] warp_count;
    logic [$clog2(NUM_TPC)-1:0] target_tpc;
    warp_t current_warp;
    logic [7:0] tpc_load[NUM_TPC];
    
    // 解析Job Block
    function automatic void parse_job_cluster(input job_cluster_t job);
        current_job = job;
        current_block_id = job.curr_cluster_id;
        
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
        input job_cluster_t job,
        input logic [255:0] arglist_data
    );
        warp_t warp;
        
        warp.warp_id = warp_id;
        warp.block_id = job.curr_cluster_id;
        warp.program_addr = job.program_ptr;
        warp.arglist_ptr = job.program_ptr + 64'd8;
        warp.argument_size = job.arg_size;
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
            tpc_load[0] <= '0;
            tpc_load[1] <= '0;
            tpc_load[2] <= '0;
            tpc_load[3] <= '0;
            
            // 初始化接口信号
            noc_if.s_req_ready <= 1'b0;
            tpc_if[0].warp_valid <= 1'b0;
            tpc_if[1].warp_valid <= 1'b0;
            tpc_if[2].warp_valid <= 1'b0;
            tpc_if[3].warp_valid <= 1'b0;
            raster_if.cmd_valid <= 1'b0;
            l15_if.req_valid <= 1'b0;
            tlb_if.req_valid <= 1'b0;
            
            // 初始化TPC完成接口
            tpc_if[0].complete_ready <= 1'b0;
            tpc_if[1].complete_ready <= 1'b0;
            tpc_if[2].complete_ready <= 1'b0;
            tpc_if[3].complete_ready <= 1'b0;
        end else begin
            // TPC完成处理 - 展开循环避免动态索引
            tpc_if[0].complete_ready <= 1'b1;
            if (tpc_if[0].complete_valid && tpc_if[0].complete_ready) begin
                if (tpc_load[0] > 0) begin
                    tpc_load[0] <= tpc_load[0] - 1;
                end
            end
            
            tpc_if[1].complete_ready <= 1'b1;
            if (tpc_if[1].complete_valid && tpc_if[1].complete_ready) begin
                if (tpc_load[1] > 0) begin
                    tpc_load[1] <= tpc_load[1] - 1;
                end
            end
            
            tpc_if[2].complete_ready <= 1'b1;
            if (tpc_if[2].complete_valid && tpc_if[2].complete_ready) begin
                if (tpc_load[2] > 0) begin
                    tpc_load[2] <= tpc_load[2] - 1;
                end
            end
            
            tpc_if[3].complete_ready <= 1'b1;
            if (tpc_if[3].complete_valid && tpc_if[3].complete_ready) begin
                if (tpc_load[3] > 0) begin
                    tpc_load[3] <= tpc_load[3] - 1;
                end
            end
            
            case (state)
                IDLE: begin
                    // 接收来自NOC Adapter的Job Block
                    noc_if.s_req_ready <= 1'b1;
                    
                    if (noc_if.s_req_valid && noc_if.s_req_ready) begin
                        // 假设 job_cluster 数据打包在 s_req_data 里
                        parse_job_cluster(noc_if.s_req_data);
                        noc_if.s_req_ready <= 1'b0;
                        state <= PARSE_JOB;
                        $display("GPC %d received job cluster", GPC_ID);
                    end
                end
                
                PARSE_JOB: begin
                    // 解析Job Block并确定任务类型
                    if (current_job.program_ptr[63]) begin
                        // 光栅化任务 (假设程序地址最高位为1表示光栅化任务)
                        state <= DISPATCH_RASTER;
                    end else begin
                        // 计算任务，需要获取参数列表
                        state <= TRANSLATE_ARGLIST;
                    end
                end
                
                TRANSLATE_ARGLIST: begin
                    // 翻译参数列表地址
                    tlb_if.req_valid <= 1'b1;
                    tlb_if.req_vaddr <= current_job.program_ptr + 64'd8;
                    tlb_if.req_type <= MMU_READ;
                    tlb_if.req_warp_id <= '0;
                    tlb_if.req_source_id <= '0;
                    
                    if (tlb_if.req_ready) begin
                        tlb_if.req_valid <= 1'b0;
                        state <= WAIT_TLB;
                    end
                end
                
                WAIT_TLB: begin
                    // 等待TLB响应
                    if (tlb_if.resp_valid) begin
                        if (!tlb_if.resp_fault) begin
                            // TLB命中，获取参数列表
                            arglist_paddr <= {tlb_if.resp_ppn, current_job.program_ptr[11:0]};
                            state <= FETCH_ARGLIST;
                        end else begin
                            // TLB未命中，返回错误状态
                            state <= IDLE;
                        end
                    end
                end
                
                FETCH_ARGLIST: begin
                    // 从L1.5 Cache获取参数列表
                    l15_if.req_valid <= 1'b1;
                    l15_if.req_is_read <= 1'b1;
                    l15_if.req_paddr <= arglist_paddr;
                    l15_if.req_size <= 4'b0100; // 16字节
                    l15_if.req_type <= L15_CACHE_NORMAL;
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
                    // 将Warp分发给TPC - 使用case语句避免动态索引
                    case (target_tpc)
                        0: begin
                            tpc_if[0].warp_valid <= 1'b1;
                            tpc_if[0].warp_id <= current_warp.warp_id;
                            tpc_if[0].block_id <= current_warp.block_id;
                            tpc_if[0].program_addr <= current_warp.program_addr;
                            tpc_if[0].arglist_ptr <= current_warp.arglist_ptr;
                            tpc_if[0].argument_size <= current_warp.argument_size;
                            tpc_if[0].thread_mask <= current_warp.thread_mask;
                            tpc_if[0].arglist_data <= current_warp.arglist_data;
                            
                            if (tpc_if[0].warp_ready) begin
                                tpc_if[0].warp_valid <= 1'b0;
                                
                                // 更新TPC负载
                                tpc_load[0] <= tpc_load[0] + 1;
                                
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
                        1: begin
                            tpc_if[1].warp_valid <= 1'b1;
                            tpc_if[1].warp_id <= current_warp.warp_id;
                            tpc_if[1].block_id <= current_warp.block_id;
                            tpc_if[1].program_addr <= current_warp.program_addr;
                            tpc_if[1].arglist_ptr <= current_warp.arglist_ptr;
                            tpc_if[1].argument_size <= current_warp.argument_size;
                            tpc_if[1].thread_mask <= current_warp.thread_mask;
                            tpc_if[1].arglist_data <= current_warp.arglist_data;
                            
                            if (tpc_if[1].warp_ready) begin
                                tpc_if[1].warp_valid <= 1'b0;
                                
                                // 更新TPC负载
                                tpc_load[1] <= tpc_load[1] + 1;
                                
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
                        2: begin
                            tpc_if[2].warp_valid <= 1'b1;
                            tpc_if[2].warp_id <= current_warp.warp_id;
                            tpc_if[2].block_id <= current_warp.block_id;
                            tpc_if[2].program_addr <= current_warp.program_addr;
                            tpc_if[2].arglist_ptr <= current_warp.arglist_ptr;
                            tpc_if[2].argument_size <= current_warp.argument_size;
                            tpc_if[2].thread_mask <= current_warp.thread_mask;
                            tpc_if[2].arglist_data <= current_warp.arglist_data;
                            
                            if (tpc_if[2].warp_ready) begin
                                tpc_if[2].warp_valid <= 1'b0;
                                
                                // 更新TPC负载
                                tpc_load[2] <= tpc_load[2] + 1;
                                
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
                        3: begin
                            tpc_if[3].warp_valid <= 1'b1;
                            tpc_if[3].warp_id <= current_warp.warp_id;
                            tpc_if[3].block_id <= current_warp.block_id;
                            tpc_if[3].program_addr <= current_warp.program_addr;
                            tpc_if[3].arglist_ptr <= current_warp.arglist_ptr;
                            tpc_if[3].argument_size <= current_warp.argument_size;
                            tpc_if[3].thread_mask <= current_warp.thread_mask;
                            tpc_if[3].arglist_data <= current_warp.arglist_data;
                            
                            if (tpc_if[3].warp_ready) begin
                                tpc_if[3].warp_valid <= 1'b0;
                                
                                // 更新TPC负载
                                tpc_load[3] <= tpc_load[3] + 1;
                                
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
                        default: state <= IDLE;
                    endcase
                end
                
                DISPATCH_RASTER: begin
                    // 将光栅化命令发送给Raster Engine
                    raster_if.cmd_valid <= 1'b1;
                    raster_if.cmd_addr <= current_job.program_ptr;
                    raster_if.cmd_data <= current_job.program_ptr + 64'd8;
                    raster_if.cmd_size <= current_job.arg_size;
                    
                    if (raster_if.cmd_ready) begin
                        raster_if.cmd_valid <= 1'b0;
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule : rvgpu_gpc_block_scheduler

`endif // RVGPU_GPC_BLOCK_SCHEDULER_SV 