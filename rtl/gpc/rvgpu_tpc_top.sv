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
    
    // 循环变量声明
    int sm_search_i;
    int sm_init_i;
    int sm_update_i;
    int sm_util_i;
    int sm_active_i;
    
    // =========================================================================
    // SM可用性检查和轮询
    // =========================================================================
    
    always_comb begin
        next_sm_id = '0;
        
        // 轮询查找可用的SM
        for (sm_search_i = 0; sm_search_i < NUM_SM; sm_search_i++) begin : sm_search_loop
            int sm_idx = (round_robin_counter + sm_search_i) % NUM_SM;
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
            block_dispatch_if.block_ready <= 1'b0;
            // 复位所有SM接口
            sm_dispatch_if[0].warp_valid <= 1'b0;
            sm_dispatch_if[1].warp_valid <= 1'b0;
        end else begin
            // 默认状态
            block_dispatch_if.block_ready <= 1'b0;
            
            // 处理来自Block Scheduler的任务
            if (block_dispatch_if.block_valid && sm_available[next_sm_id]) begin
                // 将任务分发给选中的SM
                case (next_sm_id)
                    0: begin
                        sm_dispatch_if[0].warp_valid <= 1'b1;
                        sm_dispatch_if[0].warp_id <= block_dispatch_if.block_id;  // 使用block_id作为warp_id
                        sm_dispatch_if[0].warp_block_id <= block_dispatch_if.block_id;
                        sm_dispatch_if[0].warp_program_addr <= block_dispatch_if.program_addr;
                        sm_dispatch_if[0].warp_arglist_ptr <= block_dispatch_if.arglist_ptr;
                        sm_dispatch_if[0].warp_argument_size <= block_dispatch_if.argument_size;
                        sm_dispatch_if[0].thread_mask <= 32'hFFFFFFFF;  // 默认所有线程都活跃
                        sm_dispatch_if[0].warp_arglist_data <= block_dispatch_if.arglist_data;
                    end
                    1: begin
                        sm_dispatch_if[1].warp_valid <= 1'b1;
                        sm_dispatch_if[1].warp_id <= block_dispatch_if.block_id;  // 使用block_id作为warp_id
                        sm_dispatch_if[1].warp_block_id <= block_dispatch_if.block_id;
                        sm_dispatch_if[1].warp_program_addr <= block_dispatch_if.program_addr;
                        sm_dispatch_if[1].warp_arglist_ptr <= block_dispatch_if.arglist_ptr;
                        sm_dispatch_if[1].warp_argument_size <= block_dispatch_if.argument_size;
                        sm_dispatch_if[1].thread_mask <= 32'hFFFFFFFF;  // 默认所有线程都活跃
                        sm_dispatch_if[1].warp_arglist_data <= block_dispatch_if.arglist_data;
                    end
                endcase
                
                // 确认接收任务
                block_dispatch_if.block_ready <= 1'b1;
                
                // 更新轮询计数器
                round_robin_counter <= (round_robin_counter + 1) % NUM_SM;
            end
            
            // 清除已完成的分发
            case (0)
                0: if (sm_dispatch_if[0].warp_valid && sm_dispatch_if[0].warp_ready) sm_dispatch_if[0].warp_valid <= 1'b0;
            endcase
            case (1)
                1: if (sm_dispatch_if[1].warp_valid && sm_dispatch_if[1].warp_ready) sm_dispatch_if[1].warp_valid <= 1'b0;
            endcase
        end
    end
    
    // =========================================================================
    // SM状态监控和管理
    // =========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (sm_init_i = 0; sm_init_i < NUM_SM; sm_init_i++) begin : sm_init_loop
                sm_states[sm_init_i] <= SM_IDLE;
                sm_active_warps[sm_init_i] <= '0;
                sm_pending_requests[sm_init_i] <= '0;
                sm_available[sm_init_i] <= 1'b1;
            end
        end else begin
            for (sm_update_i = 0; sm_update_i < NUM_SM; sm_update_i++) begin : sm_update_loop
                // 更新SM状态（这里需要从SM获取实际状态）
                // 简化实现：基于活跃warp数判断状态
                if (sm_active_warps[sm_update_i] == 0) begin
                    sm_states[sm_update_i] <= SM_IDLE;
                    sm_available[sm_update_i] <= 1'b1;
                end else if (sm_active_warps[sm_update_i] < MAX_WARPS_PER_SM) begin
                    sm_states[sm_update_i] <= SM_BUSY;
                    sm_available[sm_update_i] <= 1'b1;  // 仍可接受新任务
                end else begin
                    sm_states[sm_update_i] <= SM_BUSY;
                    sm_available[sm_update_i] <= 1'b0;  // 已满，不能接受新任务
                end
                
                // TODO: 从实际SM模块获取这些状态
                // 这里是占位符实现
                case (sm_update_i)
                    0: if (sm_dispatch_if[0].warp_valid && sm_dispatch_if[0].warp_ready) begin
                        sm_active_warps[0] <= sm_active_warps[0] + 1;
                    end
                    1: if (sm_dispatch_if[1].warp_valid && sm_dispatch_if[1].warp_ready) begin
                        sm_active_warps[1] <= sm_active_warps[1] + 1;
                    end
                endcase
                
                // 处理SM完成通知
                case (sm_update_i)
                    0: begin
                        if (sm_dispatch_if[0].complete_valid) begin
                            if (sm_active_warps[0] > 0) begin
                                sm_active_warps[0] <= sm_active_warps[0] - 1;
                            end
                            sm_dispatch_if[0].complete_ready <= 1'b1;
                        end else begin
                            sm_dispatch_if[0].complete_ready <= 1'b0;
                        end
                    end
                    1: begin
                        if (sm_dispatch_if[1].complete_valid) begin
                            if (sm_active_warps[1] > 0) begin
                                sm_active_warps[1] <= sm_active_warps[1] - 1;
                            end
                            sm_dispatch_if[1].complete_ready <= 1'b1;
                        end else begin
                            sm_dispatch_if[1].complete_ready <= 1'b0;
                        end
                    end
                endcase
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
            for (sm_util_i = 0; sm_util_i < NUM_SM; sm_util_i++) begin : cache_arb_loop
                int sm_idx = (cache_arb_counter + sm_util_i) % NUM_SM;
                
                case (sm_idx)
                    0: if (sm_l15_if[0].req_valid) begin
                        // 转发请求到L1.5 Cache
                        l15_if.req_valid <= 1'b1;
                        l15_if.req_is_read <= sm_l15_if[0].req_is_read;
                        l15_if.req_paddr <= sm_l15_if[0].req_paddr;
                        l15_if.req_size <= sm_l15_if[0].req_size;
                        l15_if.req_type <= sm_l15_if[0].req_type;
                        l15_if.req_data <= sm_l15_if[0].req_data;
                        l15_if.req_mask <= sm_l15_if[0].req_mask;
                        l15_if.req_id <= {1'b0, sm_l15_if[0].req_id[30:0]};
                        
                        // 确认SM请求
                        sm_l15_if[0].req_ready <= l15_if.req_ready;
                        
                        if (l15_if.req_ready) begin
                            cache_arb_counter <= (cache_arb_counter + 1) % NUM_SM;
                        end
                        break;
                    end
                    1: if (sm_l15_if[1].req_valid) begin
                        // 转发请求到L1.5 Cache
                        l15_if.req_valid <= 1'b1;
                        l15_if.req_is_read <= sm_l15_if[1].req_is_read;
                        l15_if.req_paddr <= sm_l15_if[1].req_paddr;
                        l15_if.req_size <= sm_l15_if[1].req_size;
                        l15_if.req_type <= sm_l15_if[1].req_type;
                        l15_if.req_data <= sm_l15_if[1].req_data;
                        l15_if.req_mask <= sm_l15_if[1].req_mask;
                        l15_if.req_id <= {1'b1, sm_l15_if[1].req_id[30:0]};
                        
                        // 确认SM请求
                        sm_l15_if[1].req_ready <= l15_if.req_ready;
                        
                        if (l15_if.req_ready) begin
                            cache_arb_counter <= (cache_arb_counter + 1) % NUM_SM;
                        end
                        break;
                    end
                endcase
            end
        end
    end
    
    // L1.5 Cache响应分发
    always_comb begin
        // 根据响应ID的高位确定目标SM
        logic [$clog2(NUM_SM)-1:0] target_sm = l15_if.resp_id[31:31-$clog2(NUM_SM)+1];
        
        // 默认值
        sm_l15_if[0].resp_valid = 1'b0;
        sm_l15_if[0].resp_data = '0;
        sm_l15_if[0].resp_error = 1'b0;
        sm_l15_if[0].resp_id = '0;
        
        sm_l15_if[1].resp_valid = 1'b0;
        sm_l15_if[1].resp_data = '0;
        sm_l15_if[1].resp_error = 1'b0;
        sm_l15_if[1].resp_id = '0;
        
        // 根据target_sm分发响应
        if (l15_if.resp_valid) begin
            case (target_sm)
                0: begin
                    sm_l15_if[0].resp_valid = 1'b1;
                    sm_l15_if[0].resp_data = l15_if.resp_data;
                    sm_l15_if[0].resp_error = l15_if.resp_error;
                    sm_l15_if[0].resp_id = {l15_if.resp_id[30:0], 1'b0};
                end
                1: begin
                    sm_l15_if[1].resp_valid = 1'b1;
                    sm_l15_if[1].resp_data = l15_if.resp_data;
                    sm_l15_if[1].resp_error = l15_if.resp_error;
                    sm_l15_if[1].resp_id = {l15_if.resp_id[30:0], 1'b0};
                end
            endcase
        end
        
        // 根据target_sm设置resp_ready
        case (target_sm)
            0: l15_if.resp_ready = sm_l15_if[0].resp_ready;
            1: l15_if.resp_ready = sm_l15_if[1].resp_ready;
            default: l15_if.resp_ready = 1'b0;
        endcase
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
                .warp_id(sm_dispatch_if[i].complete_block_id)
            );
        end
    endgenerate
    
    // =========================================================================
    // 状态统计
    // =========================================================================
    
    always_comb begin
        logic [31:0] total_active_warps;
        logic [31:0] total_max_warps;
        int stats_calc_i;
        
        total_active_warps = '0;
        total_max_warps = NUM_SM * MAX_WARPS_PER_SM;
        
        for (stats_calc_i = 0; stats_calc_i < NUM_SM; stats_calc_i++) begin : stats_calc_loop
            total_active_warps += sm_active_warps[stats_calc_i];
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