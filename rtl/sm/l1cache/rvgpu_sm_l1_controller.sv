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

`ifndef RVGPU_SM_L1_CONTROLLER_SV
`define RVGPU_SM_L1_CONTROLLER_SV

`include "rvgpu_typedef.svh"
`include "rvgpu_config.svh"
`include "interface_gpc_router.svh"
`include "interface_sm_l1cache.svh"
`include "interface_sm_l1_tag_array.svh"
`include "interface_sm_l1_data_array.svh"

module rvgpu_sm_l1_controller #(
    parameter int SM_ID = 0
) (
    input  logic clk,
    input  logic rst_n,
    
    // 仲裁器接口 - 接收CUDA Core的请求
    interface_sm_l1cache.cache arbiter_if,
    
    // Router接口 - 处理L1.5访问
    interface_gpc_router.left_port router_if,
    
    // Tag Array接口
    interface_sm_l1_tag_array.controller tag_if,
    
    // Data Array接口
    interface_sm_l1_data_array.controller data_if
);

    // ============================================================================
    // 内部状态定义
    // ============================================================================
    typedef enum logic [2:0] {
        CTRL_IDLE,          // 空闲状态
        CTRL_TAG_CHECK,     // Tag检查状态
        CTRL_HIT_PROCESS,   // 命中处理状态
        CTRL_MISS_PROCESS,  // 未命中处理状态
        CTRL_L15_REQ,       // L1.5请求状态
        CTRL_L15_RESP,      // L1.5响应状态
        CTRL_UPDATE         // 更新状态
    } ctrl_state_t;
    
    ctrl_state_t ctrl_state;
    
    // 当前请求信息
    logic [63:0] current_addr;
    logic [31:0] current_data;
    logic [2:0]  current_size;
    logic current_is_load;
    logic [$clog2(`CONFIG_SM_WARP_COUNT)-1:0] current_warp_id;
    logic [`CONFIG_WARP_THREAD_NUMBER-1:0] current_mask;
    
    // Cache行信息
    logic [19:0] current_tag;
    logic [7:0]  current_index;
    logic current_hit;

    // ============================================================================
    // 状态机
    // ============================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_state <= CTRL_IDLE;
            // ... 其他信号复位
        end else begin
            case (ctrl_state)
                CTRL_IDLE: begin
                    if (arbiter_if.req_valid) begin
                        ctrl_state <= CTRL_TAG_CHECK;
                        current_addr <= arbiter_if.req_addr;
                        current_data <= arbiter_if.req_data;
                        current_size <= arbiter_if.req_size;
                        current_is_load <= arbiter_if.req_is_load;
                        current_warp_id <= arbiter_if.req_warp_id;
                        current_mask <= arbiter_if.req_mask;
                    end
                end
                
                CTRL_TAG_CHECK: begin
                    if (tag_if.tag_resp_valid) begin
                        current_tag <= tag_if.tag_resp_tag;
                        current_index <= tag_if.tag_resp_index;
                        current_hit <= tag_if.tag_resp_hit;
                        
                        if (tag_if.tag_resp_hit)
                            ctrl_state <= CTRL_HIT_PROCESS;
                        else
                            ctrl_state <= CTRL_MISS_PROCESS;
                    end
                end
                
                CTRL_HIT_PROCESS: begin
                    if (data_if.data_resp_valid)
                        ctrl_state <= CTRL_UPDATE;
                end
                
                CTRL_MISS_PROCESS: begin
                    ctrl_state <= CTRL_L15_REQ;
                end
                
                CTRL_L15_REQ: begin
                    if (router_if.up_ready)
                        ctrl_state <= CTRL_L15_RESP;
                end
                
                CTRL_L15_RESP: begin
                    if (router_if.down_valid)
                        ctrl_state <= CTRL_UPDATE;
                end
                
                CTRL_UPDATE: begin
                    ctrl_state <= CTRL_IDLE;
                end
            endcase
        end
    end

    // ============================================================================
    // Tag Array访问
    // ============================================================================
    always_comb begin
        tag_if.tag_req_valid = (ctrl_state == CTRL_TAG_CHECK);
        tag_if.tag_req_addr = current_addr;
    end

    // ============================================================================
    // Data Array访问
    // ============================================================================
    always_comb begin
        data_if.data_req_valid = (ctrl_state == CTRL_HIT_PROCESS);
        data_if.data_req_addr = current_addr;
        data_if.data_req_data = current_data;
        data_if.data_req_size = current_size;
        data_if.data_req_is_load = current_is_load;
    end

    // ============================================================================
    // Router接口处理
    // ============================================================================
    always_comb begin
        // 默认值
        router_if.up_valid = 1'b0;
        router_if.up_msg = '0;
        router_if.down_ready = 1'b0;
        
        // L1.5请求
        if (ctrl_state == CTRL_L15_REQ) begin
            router_if.up_valid = 1'b1;
            router_if.up_msg.msg_type = ROUTER_MSG_L15_REQ;
            router_if.up_msg.dst_id = ROUTER_DST_GPC;
            router_if.up_msg.data.raw = {current_addr, current_data};  // 简化示例
        end
        
        // L1.5响应
        if (ctrl_state == CTRL_L15_RESP)
            router_if.down_ready = 1'b1;
    end

    // ============================================================================
    // 仲裁器接口处理
    // ============================================================================
    always_comb begin
        // 默认值
        arbiter_if.req_ready = (ctrl_state == CTRL_IDLE);
        arbiter_if.resp_valid = (ctrl_state == CTRL_UPDATE);
        
        // 响应数据
        if (ctrl_state == CTRL_UPDATE) begin
            if (current_hit)
                arbiter_if.resp_data = data_if.data_resp_data;
            else
                arbiter_if.resp_data = router_if.down_msg.data.raw[31:0];  // 简化示例
            
            arbiter_if.resp_warp_id = current_warp_id;
            arbiter_if.resp_mask = current_mask;
        end else begin
            arbiter_if.resp_data = '0;
            arbiter_if.resp_warp_id = '0;
            arbiter_if.resp_mask = '0;
        end
    end

endmodule : rvgpu_sm_l1_controller

`endif // RVGPU_SM_L1_CONTROLLER_SV