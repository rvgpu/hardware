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

`ifndef RVGPU_TPC_ROUTER_NODE_SV
`define RVGPU_TPC_ROUTER_NODE_SV

`include "rvgpu_typedef.svh"
`include "interface_gpc_router.svh"
`include "types_gpc_router_message.svh"

// TPC路由器节点 - 智能路由消息到SM或下游TPC
module rvgpu_tpc_router_node #(
    parameter int TPC_ID = 0,
    parameter int IS_LAST = 0
) (
    input  logic clk,
    input  logic rst_n,
    
    // 上游接口（连接前一个节点或GPC路由器）
    interface_gpc_router.left_port upstream_if,
    
    // 下游接口（连接下一个TPC，最后一个TPC没有此接口）
    interface_gpc_router.right_port downstream_if,
    
    // SM接口
    interface_gpc_router.right_port sm0_if,
    interface_gpc_router.right_port sm1_if
);
    
    // 内部信号：下游接口是否准备好接收消息
    logic downstream_ready;
    logic sm0_ready, sm1_ready;
    
    // 计算下游接口的ready状态
    assign downstream_ready = IS_LAST ? 1'b1 : downstream_if.down_ready;
    assign sm0_ready = sm0_if.down_ready;
    assign sm1_ready = sm1_if.down_ready;
    
    // 下行消息路由逻辑：从GPC到TPC/SM
    always_comb begin
        // 默认值 - 所有接口都不接收消息
        sm0_if.down_valid = 1'b0;
        sm0_if.down_msg = build_router_message_raw();

        sm1_if.down_valid = 1'b0;
        sm1_if.down_msg = build_router_message_raw();

        downstream_if.down_valid = 1'b0;
        downstream_if.down_msg = build_router_message_raw();
        
        // 只有当上游有有效消息时才进行路由
        if (upstream_if.down_valid) begin
            // 根据目标ID进行路由
            case (upstream_if.down_msg.dst_id[7:4])
                TPC_ID: begin
                    // 消息目标是当前TPC
                    case (upstream_if.down_msg.dst_id[3:2])
                        2'b00: begin
                            // 目标SM0
                            if (sm0_ready) begin
                                sm0_if.down_msg = upstream_if.down_msg;
                                sm0_if.down_valid = 1'b1;
                            end
                        end
                        2'b01: begin
                            // 目标SM1
                            if (sm1_ready) begin
                                sm1_if.down_msg = upstream_if.down_msg;
                                sm1_if.down_valid = 1'b1;
                            end
                        end
                        default: begin
                            // 无效的SM ID，转发到下游
                            if (!IS_LAST && downstream_ready) begin
                                downstream_if.down_msg = upstream_if.down_msg;
                                downstream_if.down_valid = 1'b1;
                            end
                        end
                    endcase
                end
                default: begin
                    // 消息目标是其他TPC，转发到下游
                    if (!IS_LAST && downstream_ready) begin
                        downstream_if.down_msg = upstream_if.down_msg;
                        downstream_if.down_valid = 1'b1;
                    end
                end
            endcase
        end
    end
    
    // 上行响应消息路由逻辑：从SM/TPC到GPC
    always_comb begin
        // 默认值
        upstream_if.up_valid = 1'b0;
        upstream_if.up_msg = build_router_message_raw();

        sm0_if.up_ready = 1'b0;
        sm1_if.up_ready = 1'b0;
        downstream_if.up_ready = 1'b0;
        
        // 轮询调度：公平地处理所有上行消息
        if (sm0_if.up_valid && upstream_if.up_ready) begin
            // SM0有上行消息且上游准备好接收
            upstream_if.up_msg = sm0_if.up_msg;
            upstream_if.up_valid = 1'b1;
            sm0_if.up_ready = 1'b1;
        end else if (sm1_if.up_valid && upstream_if.up_ready) begin
            // SM1有上行消息且上游准备好接收
            upstream_if.up_msg = sm1_if.up_msg;
            upstream_if.up_valid = 1'b1;
            sm1_if.up_ready = 1'b1;
        end else if (!IS_LAST && downstream_if.up_valid && upstream_if.up_ready) begin
            // 下游TPC有上行消息且上游准备好接收
            upstream_if.up_msg = downstream_if.up_msg;
            upstream_if.up_valid = 1'b1;
            downstream_if.up_ready = 1'b1;
        end else begin
            // 没有上行消息或上游不准备好时，设置所有ready信号为高
            // 这样下游接口可以随时发送消息
            sm0_if.up_ready = 1'b1;
            sm1_if.up_ready = 1'b1;
            if (!IS_LAST) downstream_if.up_ready = 1'b1;
        end
    end
    
    // 上游ready信号逻辑：只有当所有下游接口都准备好时才向上游报告ready
    always_comb begin
        // 下行ready：只有当所有下游接口都准备好时才向上游报告ready
        upstream_if.down_ready = sm0_ready && sm1_ready && downstream_ready;
    end
    
endmodule : rvgpu_tpc_router_node

`endif // RVGPU_TPC_ROUTER_NODE_SV
