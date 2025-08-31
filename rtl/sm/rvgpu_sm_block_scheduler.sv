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

`ifndef RVGPU_SM_BLOCK_SCHEDULER_SV
`define RVGPU_SM_BLOCK_SCHEDULER_SV

`include "rvgpu_typedef.svh"
`include "rvgpu_config.svh"
`include "rvgpu_command_package.svh"
`include "types_job_cluster.svh"
`include "types_gpc_router_message.svh"
`include "interface_gpc_router.svh"
`include "interface_sm_warp_dispatch.svh"
`include "interface_fifo_stream.svh"
`include "rvgpu_fifo_pkg.svh"

module rvgpu_sm_block_scheduler #(
    parameter int SM_ID = 0
) (
    input  logic clk,
    input  logic rst_n,
    
    // 路由器接口 - 连接到router_arbiter
    interface_gpc_router.left_port router_if,
    
    // Warp分发接口 - 连接CUDA Core
    interface_sm_warp_dispatch.frontend_port warp_dispatch_if[`CONFIG_SM_CUDA_CORE_COUNT]
);

    localparam int WARP_COUNT = `CONFIG_SM_WARP_COUNT;
    localparam int THREAD_COUNT = `CONFIG_WARP_THREAD_NUMBER;
    localparam int CUDA_CORE_COUNT = `CONFIG_SM_CUDA_CORE_COUNT;

    // ============================================================================
    // 内部信号
    // ============================================================================
    
    // Block和Warp调度相关信号
    logic [CUDA_CORE_COUNT-1:0] core_ready;
    logic [3:0] next_core_id;
    
    // 当前正在处理的Block任务
    t_job_cluster current_job_cluster;
    logic job_valid;
    logic [15:0] current_block_id;
    logic [31:0] warp_count_per_block;
    logic [31:0] next_warp_id;
    
    // Block完成信号
    logic block_complete;
    t_job_cluster completed_job_cluster;
    
    // ============================================================================
    // Router接口处理
    // ============================================================================
    
    // 处理发送到router的消息
    always_comb begin
        // 默认值
        router_if.up_valid = 1'b0;
        router_if.up_msg = '0;
        
        if (block_complete) begin
            // 发送Block完成消息
            router_if.up_valid = 1'b1;
            router_if.up_msg.msg_type = ROUTER_MSG_BLOCK_COMP;
            router_if.up_msg.dst_id = ROUTER_DST_GPC;
            router_if.up_msg.data.block = completed_job_cluster;
        end
    end
    
    // ============================================================================
    // 核心状态监控
    // ============================================================================
    
    // 使用generate块替代变量索引
    generate
        for (genvar i = 0; i < CUDA_CORE_COUNT; i++) begin : gen_core_ready
            assign core_ready[i] = warp_dispatch_if[i].ready;
        end
    endgenerate
    
    // ============================================================================
    // Block调度状态机
    // ============================================================================
    
    // 状态机定义
    typedef enum logic [1:0] {
        IDLE,           // 空闲状态
        DISPATCH_WARPS, // 分发Warps
        WAIT_COMPLETE   // 等待完成
    } block_state_t;
    
    block_state_t block_state, next_block_state;
    
    // 状态机时序逻辑
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            block_state <= IDLE;
            current_job_cluster <= '0;
            job_valid <= 1'b0;
            current_block_id <= '0;
            warp_count_per_block <= '0;
            next_warp_id <= '0;
            block_complete <= 1'b0;
            completed_job_cluster <= '0;
        end else begin
            block_state <= next_block_state;
            
            // 根据状态更新任务信息
            case (block_state)
                IDLE: begin
                    block_complete <= 1'b0;
                    
                    if (router_if.down_valid && router_if.down_msg.msg_type == ROUTER_MSG_BLOCK_DISP) begin
                        // 接收新的Block任务
                        t_job_cluster job_cluster;
                        job_cluster = router_if.down_msg.data.block;
                        current_job_cluster <= job_cluster;
                        job_valid <= 1'b1;
                        current_block_id <= job_cluster.curr_block_id;
                        
                        // 计算每个Block的warp数量 = (block_x * block_y * block_z + 31) / 32
                        // 简化版：假设每个block有8个warp
                        warp_count_per_block <= 8;
                        next_warp_id <= 0;
                    end
                end
                
                DISPATCH_WARPS: begin
                    if (core_ready[next_core_id] && next_warp_id < warp_count_per_block) begin
                        next_warp_id <= next_warp_id + 1;
                    end
                end
                
                WAIT_COMPLETE: begin
                    // 设置Block完成信号
                    block_complete <= 1'b1;
                    completed_job_cluster <= current_job_cluster;
                end
                
                default: begin
                    // 保持当前状态
                end
            endcase
        end
    end
    
    // 状态机组合逻辑
    always_comb begin
        // 默认值
        next_block_state = block_state;
        next_core_id = 0;
        
        // 路由器接口默认值
        router_if.down_ready = 1'b0;
        
        // warp分发接口默认值 - 使用显式赋值
        warp_dispatch_if[0].valid = 1'b0;
        warp_dispatch_if[0].warp_id = '0;
        warp_dispatch_if[0].job_cluster = '0;
        
        warp_dispatch_if[1].valid = 1'b0;
        warp_dispatch_if[1].warp_id = '0;
        warp_dispatch_if[1].job_cluster = '0;
        
        warp_dispatch_if[2].valid = 1'b0;
        warp_dispatch_if[2].warp_id = '0;
        warp_dispatch_if[2].job_cluster = '0;
        
        warp_dispatch_if[3].valid = 1'b0;
        warp_dispatch_if[3].warp_id = '0;
        warp_dispatch_if[3].job_cluster = '0;
        
        case (block_state)
            IDLE: begin
                // 准备接收新的Block任务
                router_if.down_ready = 1'b1;
                
                if (router_if.down_valid && router_if.down_msg.msg_type == ROUTER_MSG_BLOCK_DISP) begin
                    next_block_state = DISPATCH_WARPS;
                end
            end
            
            DISPATCH_WARPS: begin
                // 使用优先编码器找到第一个可用的CUDA Core
                if (core_ready[0])      next_core_id = 4'd0;
                else if (core_ready[1]) next_core_id = 4'd1;
                else if (core_ready[2]) next_core_id = 4'd2;
                else if (core_ready[3]) next_core_id = 4'd3;
                else                    next_core_id = 4'd0; // 默认值
                
                // 如果找到可用Core且还有warp需要分发
                if (next_warp_id < warp_count_per_block) begin
                    // 使用case语句为每个core分配warp
                    case (next_core_id)
                        4'd0: begin
                            if (core_ready[0]) begin
                                warp_dispatch_if[0].valid = 1'b1;
                                warp_dispatch_if[0].warp_id = next_warp_id;
                                warp_dispatch_if[0].job_cluster = current_job_cluster;
                                next_block_state = DISPATCH_WARPS;
                            end
                        end
                        
                        4'd1: begin
                            if (core_ready[1]) begin
                                warp_dispatch_if[1].valid = 1'b1;
                                warp_dispatch_if[1].warp_id = next_warp_id;
                                warp_dispatch_if[1].job_cluster = current_job_cluster;
                                next_block_state = DISPATCH_WARPS;
                            end
                        end
                        
                        4'd2: begin
                            if (core_ready[2]) begin
                                warp_dispatch_if[2].valid = 1'b1;
                                warp_dispatch_if[2].warp_id = next_warp_id;
                                warp_dispatch_if[2].job_cluster = current_job_cluster;
                                next_block_state = DISPATCH_WARPS;
                            end
                        end
                        
                        4'd3: begin
                            if (core_ready[3]) begin
                                warp_dispatch_if[3].valid = 1'b1;
                                warp_dispatch_if[3].warp_id = next_warp_id;
                                warp_dispatch_if[3].job_cluster = current_job_cluster;
                                next_block_state = DISPATCH_WARPS;
                            end
                        end
                        
                        default: begin
                            // 不做任何事
                        end
                    endcase
                end else begin
                    // 所有warp已分发，等待完成
                    next_block_state = WAIT_COMPLETE;
                end
            end
            
            WAIT_COMPLETE: begin
                // 简化实现：假设所有warp立即完成
                // 实际实现中需要等待所有warp的完成信号
                next_block_state = IDLE;
            end
            
            default: begin
                next_block_state = IDLE;
            end
        endcase
    end

endmodule : rvgpu_sm_block_scheduler

`endif // RVGPU_SM_BLOCK_SCHEDULER_SV