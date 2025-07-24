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

`ifndef RVGPU_TPC_TOP_SV
`define RVGPU_TPC_TOP_SV

`include "rvgpu_typedef.svh"
`include "gpc_block_tpc_if.svh"
`include "gpc_l15_cache_if.svh"
`include "gpc_l0_tlb_if.svh"
`include "ldst_sm_if.svh"

// TPC顶层模块 - 简化版本
// 专注于SM管理、任务分发和资源监控
// 不再包含LDST单元和L0 TLB，这些功能已移至SM内部
module rvgpu_tpc_top #(
    parameter int NUM_SM = 2,                // 每个TPC中的SM数量
    parameter int MAX_WARPS_PER_SM = 32,     // 每个SM最大warp数
    parameter int TPC_ID = 0                 // TPC ID
) (
    input  logic clk,
    input  logic rst_n,
    
    // Block Scheduler接口
    gpc_block_tpc_if.tpc block_dispatch_if,
    
    // L1.5 Cache接口（汇聚所有SM的缓存请求）
    gpc_l15_cache_if.requester l15_if,
    
    // GPC MMU接口（汇聚所有SM的TLB请求）
    gpc_l0_tlb_if.tpc tlb_if,
    
    // 状态输出（简化）
    output logic [7:0] active_warps_count,   // 活跃warp数量
    output logic [7:0] sm_utilization        // SM利用率 (0-100)
);

    // SM状态定义
    typedef enum logic [1:0] {
        SM_IDLE,
        SM_BUSY,
        SM_STALLED,
        SM_ERROR
    } sm_state_t;
    
    // SM状态跟踪
    sm_state_t sm_states[NUM_SM];
    logic [7:0] sm_active_warps[NUM_SM];      // 每个SM的活跃warp数
    logic [7:0] sm_pending_requests[NUM_SM];  // 每个SM的未完成请求数
    logic sm_available[NUM_SM];               // SM是否可用于新任务
    
    // 任务分发逻辑
    logic [$clog2(NUM_SM)-1:0] next_sm_id;   // 下一个分配的SM ID
    logic [$clog2(NUM_SM)-1:0] round_robin_counter; // 轮询计数器
    
    // SM接口信号
    gpc_l15_cache_if sm_l15_if[NUM_SM]();     // 每个SM的L1.5 Cache接口
    gpc_l0_tlb_if sm_tlb_if[NUM_SM]();        // 每个SM的TLB接口
    gpc_block_tpc_if sm_dispatch_if[NUM_SM](); // 每个SM的任务分发接口
    ldst_sm_if sm_ldst_if[NUM_SM]();          // 每个SM的LDST接口（暂时保留）
    
    // 内部信号
    logic [31:0] total_active_warps;
    logic [31:0] total_max_warps;
    
    // =========================================================================
    // SM选择逻辑 - 轮询调度
    // =========================================================================
    
    always_comb begin
        next_sm_id = '0;
        
        // 轮询查找可用的SM
        for (int i = 0; i < NUM_SM; i++) begin
            int sm_idx = (round_robin_counter + i) % NUM_SM;
            if (sm_available[sm_idx]) begin
                next_sm_id = sm_idx[$clog2(NUM_SM)-1:0];
                break;
            end
        end
    end
    
    // =========================================================================
    // 任务分发逻辑
    // =========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            round_robin_counter <= '0;
            block_dispatch_if.warp_ready <= 1'b0;
            
            for (int i = 0; i < NUM_SM; i++) begin
                sm_dispatch_if[i].warp_valid <= 1'b0;
            end
        end else begin
            // 默认状态
            block_dispatch_if.warp_ready <= 1'b0;
            
            // 处理来自Block Scheduler的任务
            if (block_dispatch_if.warp_valid && sm_available[next_sm_id]) begin
                // 将任务分发给选中的SM
                sm_dispatch_if[next_sm_id].warp_valid <= 1'b1;
                sm_dispatch_if[next_sm_id].warp_id <= block_dispatch_if.warp_id;
                sm_dispatch_if[next_sm_id].block_id <= block_dispatch_if.block_id;
                sm_dispatch_if[next_sm_id].program_addr <= block_dispatch_if.program_addr;
                sm_dispatch_if[next_sm_id].arglist_ptr <= block_dispatch_if.arglist_ptr;
                sm_dispatch_if[next_sm_id].argument_size <= block_dispatch_if.argument_size;
                sm_dispatch_if[next_sm_id].thread_mask <= block_dispatch_if.thread_mask;
                sm_dispatch_if[next_sm_id].arglist_data <= block_dispatch_if.arglist_data;
                
                // 确认接收任务
                block_dispatch_if.warp_ready <= 1'b1;
                
                // 更新轮询计数器
                round_robin_counter <= (round_robin_counter + 1) % NUM_SM;
            end
            
            // 清除已完成的分发
            for (int i = 0; i < NUM_SM; i++) begin
                if (sm_dispatch_if[i].warp_valid && sm_dispatch_if[i].warp_ready) begin
                    sm_dispatch_if[i].warp_valid <= 1'b0;
                end
            end
        end
    end
    
    // =========================================================================
    // SM状态监控和管理
    // =========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_SM; i++) begin
                sm_states[i] <= SM_IDLE;
                sm_active_warps[i] <= '0;
                sm_pending_requests[i] <= '0;
                sm_available[i] <= 1'b1;
            end
        end else begin
            for (int i = 0; i < NUM_SM; i++) begin
                // 更新SM状态（这里需要从SM获取实际状态）
                // 简化实现：基于活跃warp数判断状态
                if (sm_active_warps[i] == 0) begin
                    sm_states[i] <= SM_IDLE;
                    sm_available[i] <= 1'b1;
                end else if (sm_active_warps[i] < MAX_WARPS_PER_SM) begin
                    sm_states[i] <= SM_BUSY;
                    sm_available[i] <= 1'b1;  // 仍可接受新任务
                end else begin
                    sm_states[i] <= SM_BUSY;
                    sm_available[i] <= 1'b0;  // 已满，不能接受新任务
                end
                
                // TODO: 从实际SM模块获取这些状态
                // 这里是占位符实现
                if (sm_dispatch_if[i].warp_valid && sm_dispatch_if[i].warp_ready) begin
                    sm_active_warps[i] <= sm_active_warps[i] + 1;
                end
                
                // 处理SM完成通知
                if (sm_dispatch_if[i].complete_valid) begin
                    if (sm_active_warps[i] > 0) begin
                        sm_active_warps[i] <= sm_active_warps[i] - 1;
                    end
                    sm_dispatch_if[i].complete_ready <= 1'b1;
                end else begin
                    sm_dispatch_if[i].complete_ready <= 1'b0;
                end
            end
        end
    end
    
    // =========================================================================
    // L1.5 Cache请求仲裁（汇聚所有SM的缓存请求）
    // =========================================================================
    
    // 简单轮询仲裁器
    logic [$clog2(NUM_SM)-1:0] cache_arb_counter;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cache_arb_counter <= '0;
            l15_if.req_valid <= 1'b0;
        end else begin
            l15_if.req_valid <= 1'b0;
            
            // 轮询检查每个SM的缓存请求
            for (int i = 0; i < NUM_SM; i++) begin
                int sm_idx = (cache_arb_counter + i) % NUM_SM;
                if (sm_l15_if[sm_idx].req_valid) begin
                    // 转发请求到L1.5 Cache
                    l15_if.req_valid <= 1'b1;
                    l15_if.req_is_read <= sm_l15_if[sm_idx].req_is_read;
                    l15_if.req_paddr <= sm_l15_if[sm_idx].req_paddr;
                    l15_if.req_size <= sm_l15_if[sm_idx].req_size;
                    l15_if.req_type <= sm_l15_if[sm_idx].req_type;
                    l15_if.req_data <= sm_l15_if[sm_idx].req_data;
                    l15_if.req_mask <= sm_l15_if[sm_idx].req_mask;
                    l15_if.req_id <= {sm_idx[$clog2(NUM_SM)-1:0], sm_l15_if[sm_idx].req_id[31-$clog2(NUM_SM):0]};
                    
                    // 确认SM请求
                    sm_l15_if[sm_idx].req_ready <= l15_if.req_ready;
                    
                    if (l15_if.req_ready) begin
                        cache_arb_counter <= (cache_arb_counter + 1) % NUM_SM;
                    end
                    break;
                end
            end
        end
    end
    
    // L1.5 Cache响应分发
    always_comb begin
        // 根据响应ID的高位确定目标SM
        logic [$clog2(NUM_SM)-1:0] target_sm = l15_if.resp_id[31:31-$clog2(NUM_SM)+1];
        
        for (int i = 0; i < NUM_SM; i++) begin
            if (i == target_sm && l15_if.resp_valid) begin
                sm_l15_if[i].resp_valid = 1'b1;
                sm_l15_if[i].resp_data = l15_if.resp_data;
                sm_l15_if[i].resp_error = l15_if.resp_error;
                sm_l15_if[i].resp_id = {l15_if.resp_id[31-$clog2(NUM_SM):0], {$clog2(NUM_SM){1'b0}}};
            end else begin
                sm_l15_if[i].resp_valid = 1'b0;
                sm_l15_if[i].resp_data = '0;
                sm_l15_if[i].resp_error = 1'b0;
                sm_l15_if[i].resp_id = '0;
            end
        end
        
        l15_if.resp_ready = sm_l15_if[target_sm].resp_ready;
    end
    
    // =========================================================================
    // TLB请求仲裁（汇聚所有SM的TLB请求）
    // =========================================================================
    
    // 类似的仲裁逻辑用于TLB请求
    logic [$clog2(NUM_SM)-1:0] tlb_arb_counter;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tlb_arb_counter <= '0;
        end else begin
            // TLB仲裁逻辑（简化实现）
            // TODO: 实现完整的TLB请求仲裁
        end
    end
    
    // =========================================================================
    // SM实例化
    // =========================================================================
    
    genvar i;
    generate
        for (i = 0; i < NUM_SM; i++) begin : sm_gen
            rvgpu_sm #(
                .SM_ID(i),
                .WARP_COUNT(MAX_WARPS_PER_SM),
                .MAX_THREAD_PER_WARP(32),
                .MAX_ACTIVE_WARPS(16),
                .NUM_CUDA_CORES(4)
            ) u_sm (
                .clk(clk),
                .rst_n(rst_n),
                
                // 任务分发接口
                .block_dispatch_if(sm_dispatch_if[i].sm),
                
                // LDST接口（暂时保留，实际由SM内部L1 Data Cache处理）
                .ldst_if(sm_ldst_if[i].sm),
                
                // L1.5 Cache接口（指令获取）
                .l15_if(sm_l15_if[i].requester),
                
                // TLB接口
                .tlb_if(sm_tlb_if[i].requester),
                
                // 完成信号
                .warp_complete(sm_dispatch_if[i].complete_valid),
                .warp_id(sm_dispatch_if[i].complete_warp_id)
            );
        end
    endgenerate
    
    // =========================================================================
    // 状态统计
    // =========================================================================
    
    always_comb begin
        total_active_warps = '0;
        total_max_warps = NUM_SM * MAX_WARPS_PER_SM;
        
        for (int i = 0; i < NUM_SM; i++) begin
            total_active_warps += sm_active_warps[i];
        end
        
        active_warps_count = total_active_warps[7:0];
        
        // 计算利用率 (0-100)
        if (total_max_warps > 0) begin
            sm_utilization = (total_active_warps * 100) / total_max_warps;
        end else begin
            sm_utilization = '0;
        end
    end

endmodule : rvgpu_tpc_top

`endif // RVGPU_TPC_TOP_SV 