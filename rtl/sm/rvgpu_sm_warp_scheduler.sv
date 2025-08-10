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

`ifndef RVGPU_SM_WARP_SCHEDULER_SV
`define RVGPU_SM_WARP_SCHEDULER_SV

`include "rvgpu_typedef.svh"
`include "interface_sm_warp_state.svh"
`include "interface_sm_warp_schedule.svh"

module rvgpu_sm_warp_scheduler #(
    parameter int WARP_COUNT = 32,          // 每个SM支持的warp数量
    parameter int MAX_ACTIVE_WARPS = 16,    // 同时活跃的最大warp数量
    parameter int PIPELINE_DEPTH = 5        // 流水线深度
) (
    input  logic clk,
    input  logic rst_n,
    
    // Warp状态输入（接口化）
    interface_sm_warp_state.fetch_view warp_state_if,
    
    // 调度器控制
    input  logic scheduler_stall,           // 调度器暂停信号
    input  logic [$clog2(WARP_COUNT)-1:0] new_warp_id,  // 新warp的ID
    input  logic new_warp_valid,            // 新warp有效
    
    // 调度输出（接口化）
    interface_sm_warp_schedule.scheduler_source sched_if,
    
    // 资源使用情况
    output logic [$clog2(WARP_COUNT):0] active_warp_count, // 活跃warp数量
    output logic [$clog2(WARP_COUNT):0] stalled_warp_count, // 暂停warp数量
    output logic warp_scheduler_full        // 调度器已满
);
    // 调度策略枚举
    typedef enum logic [1:0] {
        ROUND_ROBIN = 2'b00,
        OLDEST_FIRST = 2'b01,
        PRIORITY_BASED = 2'b10
    } schedule_policy_e;
    
    // 当前调度策略
    schedule_policy_e current_policy;
    
    // 调度状态
    logic [WARP_COUNT-1:0] warp_ready;      // 可调度的warp
    logic [WARP_COUNT-1:0] warp_active;     // 活跃的warp
    logic [$clog2(WARP_COUNT)-1:0] last_scheduled_warp; // 上次调度的warp
    logic [WARP_COUNT-1:0] warp_age_counter[WARP_COUNT]; // warp年龄计数器
    
    // 流水线占用跟踪
    logic [WARP_COUNT-1:0] pipeline_usage[PIPELINE_DEPTH]; // 记录每个流水线阶段的warp
    logic [PIPELINE_DEPTH-1:0] pipeline_valid; // 流水线阶段有效
    
    // 计算可调度的warp
    always_comb begin
        warp_ready = warp_state_if.warp_valid & ~warp_state_if.warp_stalled & ~warp_state_if.warp_barrier & ~warp_state_if.warp_waiting;
        
        // 检查流水线冲突
        for (int i = 0; i < PIPELINE_DEPTH; i++) begin
            if (pipeline_valid[i]) begin
                warp_ready = warp_ready & ~pipeline_usage[i];
            end
        end
    end
    
    // 计算活跃warp数量
    always_comb begin
        active_warp_count = '0;
        stalled_warp_count = '0;
        
        for (int i = 0; i < WARP_COUNT; i++) begin
            if (warp_active[i]) begin
                active_warp_count = active_warp_count + 1;
                
                if (warp_state_if.warp_stalled[i] || warp_state_if.warp_barrier[i] || warp_state_if.warp_waiting[i]) begin
                    stalled_warp_count = stalled_warp_count + 1;
                end
            end
        end
        
        warp_scheduler_full = (active_warp_count >= MAX_ACTIVE_WARPS);
    end
    
    // 轮询调度算法
    function automatic logic [$clog2(WARP_COUNT)-1:0] round_robin_select();
        logic [$clog2(WARP_COUNT)-1:0] selected_warp;
        logic found;
        
        selected_warp = '0;
        found = 1'b0;
        
        // 从上次调度的warp开始搜索
        for (int i = 1; i <= WARP_COUNT; i++) begin
            logic [$clog2(WARP_COUNT)-1:0] idx;
            idx = (last_scheduled_warp + i) % WARP_COUNT;
            
            if (warp_ready[idx]) begin
                selected_warp = idx;
                found = 1'b1;
                break;
            end
        end
        
        return selected_warp;
    endfunction
    
    // 最老优先调度算法
    function automatic logic [$clog2(WARP_COUNT)-1:0] oldest_first_select();
        logic [$clog2(WARP_COUNT)-1:0] selected_warp;
        logic [31:0] max_age;
        
        selected_warp = '0;
        max_age = '0;
        
        for (int i = 0; i < WARP_COUNT; i++) begin
            if (warp_ready[i] && warp_age_counter[i] > max_age) begin
                max_age = warp_age_counter[i];
                selected_warp = i[$clog2(WARP_COUNT)-1:0];
            end
        end
        
        return selected_warp;
    endfunction
    
    // 优先级调度算法
    function automatic logic [$clog2(WARP_COUNT)-1:0] priority_based_select();
        // 简化实现，实际应根据warp优先级选择
        return round_robin_select();
    endfunction
    
    // 主调度逻辑
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            sched_if.valid <= 1'b0;
            sched_if.scheduled_warp_id <= '0;
            last_scheduled_warp <= '0;
            current_policy <= ROUND_ROBIN;
            
            for (int i = 0; i < WARP_COUNT; i++) begin
                warp_active[i] <= 1'b0;
                warp_age_counter[i] <= '0;
            end
            
            for (int i = 0; i < PIPELINE_DEPTH; i++) begin
                pipeline_usage[i] <= '0;
                pipeline_valid[i] <= 1'b0;
            end
        end else begin
            // 更新warp年龄计数器
            for (int i = 0; i < WARP_COUNT; i++) begin
                if (warp_active[i] && warp_ready[i]) begin
                    warp_age_counter[i] <= warp_age_counter[i] + 1;
                end
            end
            
            // 处理新warp
            if (new_warp_valid && !warp_scheduler_full) begin
                warp_active[new_warp_id] <= 1'b1;
                warp_age_counter[new_warp_id] <= '0;
            end
            
            // 更新流水线状态
            for (int i = PIPELINE_DEPTH-1; i > 0; i--) begin
                pipeline_usage[i] <= pipeline_usage[i-1];
                pipeline_valid[i] <= pipeline_valid[i-1];
            end
            
            // 调度决策
            if (!scheduler_stall && (|warp_ready)) begin
                logic [$clog2(WARP_COUNT)-1:0] selected_warp;
                
                case (current_policy)
                    ROUND_ROBIN:    selected_warp = round_robin_select();
                    OLDEST_FIRST:   selected_warp = oldest_first_select();
                    PRIORITY_BASED: selected_warp = priority_based_select();
                    default:        selected_warp = round_robin_select();
                endcase
                
                // 输出调度结果
                sched_if.valid <= 1'b1;
                sched_if.scheduled_warp_id <= selected_warp;
                last_scheduled_warp <= selected_warp;
                
                // 更新流水线第一阶段
                pipeline_usage[0] <= '0;
                pipeline_usage[0][selected_warp] <= 1'b1;
                pipeline_valid[0] <= 1'b1;
                
                // 重置被调度warp的年龄计数器
                warp_age_counter[selected_warp] <= '0;
            end else begin
                sched_if.valid <= 1'b0;
                pipeline_valid[0] <= 1'b0;
            end
        end
    end

endmodule : rvgpu_sm_warp_scheduler

`endif // RVGPU_SM_WARP_SCHEDULER_SV 