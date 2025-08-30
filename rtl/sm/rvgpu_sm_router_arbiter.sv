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

`ifndef RVGPU_SM_ROUTER_ARBITER_SV
`define RVGPU_SM_ROUTER_ARBITER_SV

`include "rvgpu_typedef.svh"
`include "rvgpu_config.svh"
`include "interface_gpc_router.svh"
`include "interface_fifo_stream.svh"
`include "types_gpc_router_message.svh"
`include "rvgpu_fifo_pkg.svh"

module rvgpu_sm_router_arbiter #(
    parameter int SM_ID = 0
) (
    input  logic clk,
    input  logic rst_n,
    
    // 外部路由器接口
    interface_gpc_router.left_port router_if,
    
    // Block调度器路由接口
    interface_gpc_router.right_port block_scheduler_if,
    
    // L1 Cache路由接口
    interface_gpc_router.right_port l1cache_if
);

    // ============================================================================
    // 使用宏定义
    // ============================================================================
    localparam int WARP_COUNT = `CONFIG_SM_WARP_COUNT;
    localparam int THREAD_COUNT = `CONFIG_WARP_THREAD_NUMBER;
    localparam int CUDA_CORE_COUNT = `CONFIG_SM_CUDA_CORE_COUNT;
    
    // ============================================================================
    // 内部FIFO接口
    // ============================================================================
    
    // Block分发FIFO接口
    interface_fifo_stream #(.DATA_WIDTH(256), .FIFO_DEPTH(4)) block_fifo_if();
    
    // L1 Cache请求FIFO接口
    interface_fifo_stream #(.DATA_WIDTH(256), .FIFO_DEPTH(8)) l1_req_fifo_if();
    
    // ============================================================================
    // FIFO实例化
    // ============================================================================
    
    // Block分发FIFO
    rvgpu_fifo_stream #(
        .DATA_WIDTH(256),
        .FIFO_DEPTH(4)
    ) u_block_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .fifo_if(block_fifo_if)
    );
    
    // L1 Cache请求FIFO
    rvgpu_fifo_stream #(
        .DATA_WIDTH(256),
        .FIFO_DEPTH(8)
    ) u_l1_req_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .fifo_if(l1_req_fifo_if)
    );
    
    // ============================================================================
    // 内部信号
    // ============================================================================
    
    // 路由器消息处理状态
    typedef enum logic [1:0] {
        IDLE,           // 空闲状态
        RECV_MSG,       // 接收消息
        SEND_MSG,       // 发送消息
        WAIT_ACK        // 等待确认
    } router_state_t;
    
    router_state_t current_state, next_state;
    
    // 接收到的消息类型
    e_router_msg_type recv_msg_type;
    
    // 临时存储接收到的消息
    t_router_message recv_msg;
    
    // 目标选择
    logic is_block_scheduler_msg;
    logic is_l1cache_msg;
    
    // ============================================================================
    // 消息类型判断
    // ============================================================================
    
    // 判断消息是发给Block调度器还是L1 Cache
    always_comb begin
        is_block_scheduler_msg = 1'b0;
        is_l1cache_msg = 1'b0;
        
        if (router_if.down_valid) begin
            case (router_if.down_msg.msg_type)
                ROUTER_MSG_BLOCK_DISP: begin
                    is_block_scheduler_msg = 1'b1;
                end
                
                ROUTER_MSG_L15_RESP: begin
                    is_l1cache_msg = 1'b1;
                end
                
                default: begin
                    // 不支持的消息类型
                end
            endcase
        end
    end
    
    // ============================================================================
    // 路由器接口连接
    // ============================================================================
    
    // 下行消息路由 (从外部router到内部模块)
    always_comb begin
        // 默认值
        router_if.down_ready = 1'b0;
        block_scheduler_if.down_valid = 1'b0;
        block_scheduler_if.down_msg = '0;
        l1cache_if.down_valid = 1'b0;
        l1cache_if.down_msg = '0;
        
        if (router_if.down_valid) begin
            if (is_block_scheduler_msg) begin
                // 发送给Block调度器
                block_scheduler_if.down_valid = 1'b1;
                block_scheduler_if.down_msg = router_if.down_msg;
                router_if.down_ready = block_scheduler_if.down_ready;
            end else if (is_l1cache_msg) begin
                // 发送给L1 Cache
                l1cache_if.down_valid = 1'b1;
                l1cache_if.down_msg = router_if.down_msg;
                router_if.down_ready = l1cache_if.down_ready;
            end else begin
                // 不支持的消息类型，直接丢弃
                router_if.down_ready = 1'b1;
            end
        end
    end
    
    // 上行消息路由 (从内部模块到外部router)
    always_comb begin
        // 默认值
        router_if.up_valid = 1'b0;
        router_if.up_msg = '0;
        block_scheduler_if.up_ready = 1'b0;
        l1cache_if.up_ready = 1'b0;
        
        if (block_scheduler_if.up_valid) begin
            // Block调度器的上行消息
            router_if.up_valid = 1'b1;
            router_if.up_msg = block_scheduler_if.up_msg;
            block_scheduler_if.up_ready = router_if.up_ready;
        end else if (l1cache_if.up_valid) begin
            // L1 Cache的上行消息
            router_if.up_valid = 1'b1;
            router_if.up_msg = l1cache_if.up_msg;
            l1cache_if.up_ready = router_if.up_ready;
        end
    end

endmodule : rvgpu_sm_router_arbiter

`endif // RVGPU_SM_ROUTER_ARBITER_SV