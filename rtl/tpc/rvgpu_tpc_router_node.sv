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
    
    // 左侧接口（连接上游节点或GPC路由器）
    interface_gpc_router.left_port left_if,
    
    // 右侧接口（连接下一个TPC，最后一个TPC没有此接口）
    interface_gpc_router.right_port right_if,
    
    // SM接口
    interface_gpc_router.right_port sm0_if,
    interface_gpc_router.right_port sm1_if
);
    
    // 内部信号：下游接口是否准备好接收消息
    logic downstream_ready;
    logic sm0_ready, sm1_ready;
    
    // 计算下游接口的ready状态
    assign downstream_ready = IS_LAST ? 1'b1 : right_if.down_ready;
    assign sm0_ready = sm0_if.down_ready;
    assign sm1_ready = sm1_if.down_ready;
    
    // 下行消息路由逻辑：从GPC到TPC/SM
    always_comb begin
        // 默认值 - 所有接口都不接收消息
        sm0_if.down_valid = 1'b0;
        sm0_if.down_msg = build_router_message_raw();

        sm1_if.down_valid = 1'b0;
        sm1_if.down_msg = build_router_message_raw();

        right_if.down_valid = 1'b0;
        right_if.down_msg = build_router_message_raw();
        
        // 只有当上游有有效消息时才进行路由
        if (left_if.down_valid) begin
            // 根据目标ID进行路由
            case (left_if.down_msg.dst_id[7:4])
                TPC_ID: begin
                    // 消息目标是当前TPC
                    case (left_if.down_msg.dst_id[3:2])
                        2'b00: begin
                            // 目标SM0
                            if (sm0_ready) begin
                                sm0_if.down_msg = left_if.down_msg;
                                sm0_if.down_valid = 1'b1;
                            end
                        end
                        2'b01: begin
                            // 目标SM1
                            if (sm1_ready) begin
                                sm1_if.down_msg = left_if.down_msg;
                                sm1_if.down_valid = 1'b1;
                            end
                        end
                        default: begin
                            // 无效的SM ID，转发到下游
                            if (!IS_LAST && downstream_ready) begin
                                right_if.down_msg = left_if.down_msg;
                                right_if.down_valid = 1'b1;
                            end
                        end
                    endcase
                end
                default: begin
                    // 消息目标是其他TPC，转发到下游
                    if (!IS_LAST && downstream_ready) begin
                        right_if.down_msg = left_if.down_msg;
                        right_if.down_valid = 1'b1;
                    end
                end
            endcase
        end
    end
    
    // 上行响应消息路由逻辑：从SM/TPC到GPC
    always_comb begin
        // 默认值 - 所有ready信号为0，只有在确定可以握手时才拉高
        left_if.up_valid = 1'b0;
        left_if.up_msg = build_router_message_raw();

        sm0_if.up_ready = 1'b0;
        sm1_if.up_ready = 1'b0;
        right_if.up_ready = 1'b0;
        
        // 正确的握手逻辑：
        // 只有当上游准备好接收消息时，我们才从下游接收消息并向上游转发
        if (left_if.up_ready) begin  // 上游准备好接收
            // 优先级仲裁：SM0 > SM1 > 下游TPC
            if (sm0_if.up_valid) begin
                // SM0有上行消息，转发给上游
                left_if.up_msg = sm0_if.up_msg;
                left_if.up_valid = 1'b1;
                sm0_if.up_ready = 1'b1;  // 告诉SM0我们准备好接收
            end else if (sm1_if.up_valid) begin
                // SM1有上行消息，转发给上游
                left_if.up_msg = sm1_if.up_msg;
                left_if.up_valid = 1'b1;
                sm1_if.up_ready = 1'b1;  // 告诉SM1我们准备好接收
            end else if (!IS_LAST && right_if.up_valid) begin
                // 下游TPC有上行消息，转发给上游
                left_if.up_msg = right_if.up_msg;
                left_if.up_valid = 1'b1;
                right_if.up_ready = 1'b1;  // 告诉下游TPC我们准备好接收
            end
        end
    end
    
    always_comb begin
        left_if.down_ready = sm0_ready && sm1_ready && downstream_ready;
    end
    
endmodule : rvgpu_tpc_router_node

`endif // RVGPU_TPC_ROUTER_NODE_SV
