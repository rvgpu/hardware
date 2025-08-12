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

`ifndef RVGPU_SM_FRONTEND_SV
`define RVGPU_SM_FRONTEND_SV

`include "rvgpu_typedef.svh"
`include "interface_gpc_router.svh"
`include "gpc_block_tpc_if.svh"
`include "ldst_sm_if.svh"
`include "interface_l15cache.svh"
`include "rvgpu_mmu_if.svh"

// SM前端模块 - 处理路由器接口的接收和发送
module rvgpu_sm_frontend #(
    parameter int SM_ID = 0
) (
    input  logic clk,
    input  logic rst_n,
    
    // 路由器接口
    interface_gpc_router.up_port router_if,
    
    // 功能模块接口
    gpc_block_tpc_if.sm block_dispatch_if,
    ldst_sm_if.sm ldst_if,
    interface_l15cache.requester l15_icache_if,
    mmu_if.requester_port tlb_if
);
    
    // 消息解析和路由逻辑
    always_comb begin
        // 根据消息类型路由到相应的功能模块
        if (router_if.gpc2sm_valid) begin
            case (router_if.gpc2sm_msg.msg_type)
                ROUTER_MSG_BLOCK_DISP: begin
                    router_if.gpc2sm_ready = 1'b1; // 临时处理
                end
                
                ROUTER_MSG_L15_REQ: begin
                    // L1.5 Cache请求 - 路由到L1.5 Cache
                    router_if.gpc2sm_ready = 1'b1; // 临时处理
                end
                
                ROUTER_MSG_MMU_REQ: begin
                    router_if.gpc2sm_ready = 1'b1; // 临时处理
                end
                
                default: begin
                    router_if.gpc2sm_ready = 1'b1;
                end
            endcase
        end else begin
            // 没有消息，设置所有ready信号
            router_if.gpc2sm_ready = 1'b1;
        end
    end
    
    // 响应消息发送逻辑
    always_comb begin
        // 默认值
        router_if.sm2gpc_valid = 1'b0;
        router_if.sm2gpc_msg.msg_type = ROUTER_MSG_L15_RESP;  // 默认值
        router_if.sm2gpc_msg.dst_id = ROUTER_DST_GPC;          // 默认值
        router_if.sm2gpc_msg.data = '0;
        
        // 优先级：L1.5响应 > MMU响应 > LDST响应
        if (l15_icache_if.resp_valid) begin
            // L1.5 Cache响应
            router_if.sm2gpc_valid = 1'b1;
            router_if.sm2gpc_msg.msg_type = ROUTER_MSG_L15_RESP;
            router_if.sm2gpc_msg.dst_id = ROUTER_DST_GPC;
            router_if.sm2gpc_msg.data.raw = {224'h0, l15_icache_if.resp_data};
            
        end else if (tlb_if.resp_valid) begin
            // MMU响应
            router_if.sm2gpc_valid = 1'b1;
            router_if.sm2gpc_msg.msg_type = ROUTER_MSG_MMU_RESP;
            router_if.sm2gpc_msg.dst_id = ROUTER_DST_GPC;
            router_if.sm2gpc_msg.data.raw = {224'h0, 32'h0};
            
        end else begin
            // 没有响应，设置所有ready信号
        end
    end

endmodule : rvgpu_sm_frontend

`endif // RVGPU_SM_FRONTEND_SV
