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

// TPC路由器节点 - 智能路由消息到SM或下游TPC
module rvgpu_tpc_router_node #(
    parameter int TPC_ID = 0,
    parameter int IS_LAST = 0
) (
    input  logic clk,
    input  logic rst_n,
    
    // 上游接口（连接前一个节点或GPC路由器）
    interface_gpc_router.up_port upstream_if,
    
    // 下游接口（连接下一个TPC，最后一个TPC没有此接口）
    interface_gpc_router.down_port downstream_if,
    
    // SM接口
    interface_gpc_router.down_port sm0_if,
    interface_gpc_router.down_port sm1_if
);
    
    // 下行消息路由逻辑：从GPC到TPC/SM
    always_comb begin
        // 默认值
        sm0_if.gpc2sm_header = '0;
        sm0_if.gpc2sm_data = '0;
        sm0_if.gpc2sm_valid = 1'b0;
        sm1_if.gpc2sm_header = '0;
        sm1_if.gpc2sm_data = '0;
        sm1_if.gpc2sm_valid = 1'b0;
        downstream_if.gpc2sm_header = '0;
        downstream_if.gpc2sm_data = '0;
        downstream_if.gpc2sm_valid = 1'b0;
        
        // 根据目标ID和消息类型进行路由
        if (upstream_if.gpc2sm_valid) begin
            case (upstream_if.gpc2sm_header.dst_id[7:4])
                TPC_ID: begin
                    // 消息目标是当前TPC
                    case (upstream_if.gpc2sm_header.dst_id[3:2])
                        2'b00: begin
                            // 目标SM0
                            sm0_if.gpc2sm_header = upstream_if.gpc2sm_header;
                            sm0_if.gpc2sm_data = upstream_if.gpc2sm_data;
                            sm0_if.gpc2sm_valid = upstream_if.gpc2sm_valid;
                        end
                        2'b01: begin
                            // 目标SM1
                            sm1_if.gpc2sm_header = upstream_if.gpc2sm_header;
                            sm1_if.gpc2sm_data = upstream_if.gpc2sm_data;
                            sm1_if.gpc2sm_valid = upstream_if.gpc2sm_valid;
                        end
                        default: begin
                            // 无效的SM ID，转发到下游
                            if (!IS_LAST) begin
                                downstream_if.gpc2sm_header = upstream_if.gpc2sm_header;
                                downstream_if.gpc2sm_data = upstream_if.gpc2sm_data;
                                downstream_if.gpc2sm_valid = upstream_if.gpc2sm_valid;
                            end
                        end
                    endcase
                end
                default: begin
                    // 消息目标是其他TPC，转发到下游
                    if (!IS_LAST) begin
                        downstream_if.gpc2sm_header = upstream_if.gpc2sm_header;
                        downstream_if.gpc2sm_data = upstream_if.gpc2sm_data;
                        downstream_if.gpc2sm_valid = upstream_if.gpc2sm_valid;
                    end
                end
            endcase
        end
    end
    
    // 上行响应消息路由逻辑：从SM/TPC到GPC
    always_comb begin
        // 默认值
        upstream_if.sm2gpc_header = '0;
        upstream_if.sm2gpc_data = '0;
        upstream_if.sm2gpc_valid = 1'b0;
        sm0_if.sm2gpc_ready = 1'b0;
        sm1_if.sm2gpc_ready = 1'b0;
        downstream_if.sm2gpc_ready = 1'b0;
        
        // 优先级：SM0 > SM1 > downstream
        if (sm0_if.sm2gpc_valid) begin
            // SM0有上行消息，优先发送
            upstream_if.sm2gpc_header = sm0_if.sm2gpc_header;
            upstream_if.sm2gpc_data = sm0_if.sm2gpc_data;
            upstream_if.sm2gpc_valid = sm0_if.sm2gpc_valid;
            sm0_if.sm2gpc_ready = upstream_if.sm2gpc_ready;
            
            // 其他接口不发送
            sm1_if.sm2gpc_ready = 1'b0;
            if (!IS_LAST) downstream_if.sm2gpc_ready = 1'b0;
        end else if (sm1_if.sm2gpc_valid) begin
            // SM1有上行消息，其次发送
            upstream_if.sm2gpc_header = sm1_if.sm2gpc_header;
            upstream_if.sm2gpc_data = sm1_if.sm2gpc_data;
            upstream_if.sm2gpc_valid = sm1_if.sm2gpc_valid;
            sm1_if.sm2gpc_ready = upstream_if.sm2gpc_ready;
            
            // 其他接口不发送
            sm0_if.sm2gpc_ready = 1'b0;
            if (!IS_LAST) downstream_if.sm2gpc_ready = 1'b0;
        end else if (!IS_LAST && downstream_if.sm2gpc_valid) begin
            // 下游TPC有上行消息，最后发送
            upstream_if.sm2gpc_header = downstream_if.sm2gpc_header;
            upstream_if.sm2gpc_data = downstream_if.sm2gpc_data;
            upstream_if.sm2gpc_valid = downstream_if.sm2gpc_valid;
            downstream_if.sm2gpc_ready = upstream_if.sm2gpc_ready;
            
            // SM接口不发送
            sm0_if.sm2gpc_ready = 1'b0;
            sm1_if.sm2gpc_ready = 1'b0;
        end else begin
            // 没有上行消息，设置所有ready信号
            upstream_if.sm2gpc_valid = 1'b0;
            sm0_if.sm2gpc_ready = 1'b1;
            sm1_if.sm2gpc_ready = 1'b1;
            if (!IS_LAST) downstream_if.sm2gpc_ready = 1'b1;
        end
    end
    
    // Ready信号连接逻辑
    always_comb begin
        // 下行ready信号 - 只有当所有下游接口都准备好时才向上游报告ready
        upstream_if.gpc2sm_ready = (sm0_if.gpc2sm_ready && sm1_if.gpc2sm_ready && 
                                   (IS_LAST || downstream_if.gpc2sm_ready));
        
        // 注意：downstream_if.gpc2sm_ready 是输入端口，不能被驱动
        // 下游TPC的ready信号由其自身控制，我们只能读取它
    end
    
endmodule : rvgpu_tpc_router_node

`endif // RVGPU_TPC_ROUTER_NODE_SV
