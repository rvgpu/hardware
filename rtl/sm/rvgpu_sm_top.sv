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

`ifndef RVGPU_SM_TOP_SV
`define RVGPU_SM_TOP_SV

`include "rvgpu_typedef.svh"
`include "interface_gpc_router.svh"
`include "types_gpc_router_message.svh"

module rvgpu_sm_top #(
    parameter int SM_ID = 0                    // SM ID
) (
    input  logic clk,
    input  logic rst_n,
    
    interface_gpc_router.left_port router_if
);

    // =========================================================================
    // 内部信号声明
    // =========================================================================
    
    // 简化的SM状态
    logic sm_ready;
    logic sm_busy;
    
    // =========================================================================
    // 基本逻辑
    // =========================================================================
    
    // SM状态管理
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            sm_ready <= 1'b1;
            sm_busy <= 1'b0;
        end else begin
            // 简化的状态更新逻辑
            if (router_if.down_valid && router_if.down_ready) begin
                // 接收到下行消息
                sm_busy <= 1'b1;
                sm_ready <= 1'b0;
            end
            
            if (router_if.up_valid && router_if.up_ready) begin
                // 发送上行消息
                sm_busy <= 1'b0;
                sm_ready <= 1'b1;
            end
        end
    end
    
    // 路由器接口处理
    always_comb begin
        // 默认值
        router_if.down_ready = sm_ready;  // 只有准备好时才接收下行消息
        router_if.up_valid = 1'b0;
        router_if.up_msg = build_router_message_raw();
        
        // 如果有下行消息且我们准备好，则处理
        if (router_if.down_valid && sm_ready) begin
            // 这里可以添加消息处理逻辑
            // 暂时只是简单地向上游发送确认
            router_if.up_valid = 1'b1;
            router_if.up_msg = build_router_message_raw();  // 需要实现这个函数
        end
    end
    
endmodule : rvgpu_sm_top

`endif // RVGPU_SM_TOP_SV 


