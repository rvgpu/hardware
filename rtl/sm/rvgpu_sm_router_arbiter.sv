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
    // 常量定义
    // ============================================================================
    localparam int ROUTER_MSG_WIDTH = $bits(t_router_message);
    localparam int DOWN_FIFO_DEPTH = 8;
    localparam int UP_FIFO_DEPTH = 4;

    
    // ============================================================================
    // 内部FIFO接口
    // ============================================================================
    
    // 下行FIFO - 从router_if到下游模块
    interface_fifo_stream #(.DATA_WIDTH(ROUTER_MSG_WIDTH), .FIFO_DEPTH(DOWN_FIFO_DEPTH)) down_fifo_if();
    rvgpu_fifo_stream #(.DATA_WIDTH(ROUTER_MSG_WIDTH), .FIFO_DEPTH(DOWN_FIFO_DEPTH)) u_down_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .fifo_if(down_fifo_if)
    );
    
    // 上行FIFO - 从下游模块到router_if
    interface_fifo_stream #(.DATA_WIDTH(ROUTER_MSG_WIDTH), .FIFO_DEPTH(UP_FIFO_DEPTH)) up_fifo_if();
    rvgpu_fifo_stream #(.DATA_WIDTH(ROUTER_MSG_WIDTH), .FIFO_DEPTH(UP_FIFO_DEPTH)) u_up_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .fifo_if(up_fifo_if)
    );

    // ============================================================================
    // 路由器接口连接 - 使用内部FIFO缓存
    // ============================================================================
    
    // 下行消息接收 (从外部router到下行FIFO)
    always_comb begin
        // 默认值
        router_if.down_ready = down_fifo_if.wr_ready;
        down_fifo_if.wr_valid = router_if.down_valid;
        down_fifo_if.wr_data = router_if.down_msg;
    end
    
    // 下行消息分发 (从下行FIFO到下游模块)
    always_comb begin
        // 默认值
        block_scheduler_if.down_valid = 1'b0;
        block_scheduler_if.down_msg = '0;
        l1cache_if.down_valid = 1'b0;
        l1cache_if.down_msg = '0;
        down_fifo_if.rd_ready = 1'b0;
        
        // 只有当FIFO有数据时才进行分发
        if (down_fifo_if.rd_valid) begin
            // 将FIFO数据转换为router消息类型
            t_router_message router_msg;
            router_msg = t_router_message'(down_fifo_if.rd_data);
            
            // 根据消息类型决定发送到哪个模块
            case (router_msg.msg_type)
                ROUTER_MSG_BLOCK_DISP: begin
                    // Block调度器消息
                    if (block_scheduler_if.down_ready) begin
                        block_scheduler_if.down_valid = 1'b1;
                        block_scheduler_if.down_msg = router_msg;
                        down_fifo_if.rd_ready = 1'b1;
                    end
                end
                
                ROUTER_MSG_L15_RESP: begin
                    // L1 Cache消息
                    if (l1cache_if.down_ready) begin
                        l1cache_if.down_valid = 1'b1;
                        l1cache_if.down_msg = router_msg;
                        down_fifo_if.rd_ready = 1'b1;
                    end
                end
                
                default: begin
                    // 不支持的消息类型，直接丢弃
                    down_fifo_if.rd_ready = 1'b1;
                end
            endcase
        end
    end
    
    // 上行消息仲裁 (从内部模块到上行FIFO)
    always_comb begin
        // 默认值
        up_fifo_if.wr_valid = 1'b0;
        up_fifo_if.wr_data = '0;
        block_scheduler_if.up_ready = 1'b0;
        l1cache_if.up_ready = 1'b0;
        
        // 简单优先级仲裁：Block调度器优先级高于L1 Cache
        if (block_scheduler_if.up_valid && up_fifo_if.wr_ready) begin
            // Block调度器的上行消息
            up_fifo_if.wr_valid = 1'b1;
            // 将router消息转换为FIFO数据类型
            up_fifo_if.wr_data = ROUTER_MSG_WIDTH'(block_scheduler_if.up_msg);
            block_scheduler_if.up_ready = 1'b1;
        end else if (l1cache_if.up_valid && up_fifo_if.wr_ready) begin
            // L1 Cache的上行消息
            up_fifo_if.wr_valid = 1'b1;
            // 将router消息转换为FIFO数据类型
            up_fifo_if.wr_data = ROUTER_MSG_WIDTH'(l1cache_if.up_msg);
            l1cache_if.up_ready = 1'b1;
        end
    end
    
    // 上行消息发送 (从上行FIFO到外部router)
    always_comb begin
        // 默认值
        router_if.up_valid = 1'b0;
        router_if.up_msg = '0;
        up_fifo_if.rd_ready = 1'b0;
        
        // 当上行FIFO有数据且router准备好接收时，发送数据
        if (up_fifo_if.rd_valid && router_if.up_ready) begin
            router_if.up_valid = 1'b1;
            router_if.up_msg = up_fifo_if.rd_data;
            up_fifo_if.rd_ready = 1'b1;
        end
    end

endmodule : rvgpu_sm_router_arbiter

`endif // RVGPU_SM_ROUTER_ARBITER_SV