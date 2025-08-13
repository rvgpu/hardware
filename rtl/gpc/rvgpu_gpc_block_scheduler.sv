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

`ifndef RVGPU_GPC_BLOCK_SCHEDULER_SV
`define RVGPU_GPC_BLOCK_SCHEDULER_SV

`include "rvgpu_typedef.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_noc_message.svh"
`include "types_gpc_router_message.svh"
`include "interface_gpc_router.svh"

`include "gpc_block_raster_if.svh"

module rvgpu_gpc_block_scheduler #(
    parameter int GPC_ID = 0,
    parameter int NUM_TPC = 4,           // TPC数量
    parameter int MAX_WARPS_PER_BLOCK = 32, // 每个Block最大Warp数
    parameter int ADDR_WIDTH = 40        // 地址宽度
) (
    input  logic clk,
    input  logic rst_n,
    
    // NOC Adapter接口
    rvgpu_internal_noc_if.device noc_if,
    
    // 路由器接口 - 连接TPC0
    interface_gpc_router.down_port router_if,
    
    // Raster Engine接口
    gpc_block_raster_if.scheduler raster_if
);
    // 状态机状态
    typedef enum logic [2:0] {
        IDLE,
        RESP_JD,
        DISPATCH_BLOCK,
        WAIT_DISPATCH
    } scheduler_state_t;
    
    // 内部信号
    scheduler_state_t state_r, state_n;
    t_job_cluster current_job_r, current_job_n;
    logic [31:0] current_block_id_r, current_block_id_n;
    logic [31:0] block_count_r, block_count_n;
    logic [7:0] target_sm_r, target_sm_n;  // 直接选择目标SM
    logic [7:0] rr_counter_r, rr_counter_n;  // 轮询计数器
    
    // 轮询选择下一个SM
    function automatic logic [7:0] select_sm_rr(
        input logic [7:0] current_counter,
        input int num_sm
    );
        // 简单的轮询：0->1->2->3->4->5->6->7->0...
        // 确保返回值在有效范围内
        return (current_counter % num_sm);
    endfunction
    
    // 组合逻辑
    always_comb begin
        // 默认赋值
        state_n = state_r;
        current_job_n = current_job_r;
        current_block_id_n = current_block_id_r;
        block_count_n = block_count_r;
        target_sm_n = target_sm_r;
        rr_counter_n = rr_counter_r;
        
        // 接口默认值
        noc_if.s_req_ready = 1'b0;
        noc_if.s_resp_valid = 1'b0;
        noc_if.s_resp_header = '0;
        noc_if.s_resp_data = '0;
        noc_if.s_resp_status = 2'b00;
        noc_if.s_resp_last = 1'b0;
        
        router_if.gpc2sm_valid = 1'b0;
        router_if.gpc2sm_msg = '0;
        
        raster_if.cmd_valid = 1'b0;
        
        case (state_r)
            IDLE: begin
                // 等待接收job cluster请求
                noc_if.s_req_ready = 1'b1;
                
                if (noc_if.s_req_valid && noc_if.s_req_ready) begin
                    if (get_noc_header_msg_type(noc_header_t'(noc_if.s_req_header)) == MSG_COMPUTE_REQ) begin
                        current_job_n = noc_if.s_req_data;
                        block_count_n = tf_get_total_blocks_in_cluster(noc_if.s_req_data);
                        current_block_id_n = 0;
                        state_n = RESP_JD;
                        `GPC_PRINT("Scheduler", $sformatf("Received job cluster: %s", tf_job_cluster_to_string(current_job_n)));
                    end
                end
            end
            
            RESP_JD: begin
                // 发送响应给Job Dispatcher
                noc_if.s_resp_valid = 1'b1;
                noc_if.s_resp_header = build_noc_header_jobcluster_response(8'h01, NODE_SHADER_0 + GPC_ID);
                noc_if.s_resp_data = 32'h0; // 成功响应
                noc_if.s_resp_status = 2'b00; // 成功状态
                noc_if.s_resp_last = 1'b1;
                
                if (noc_if.s_resp_valid && noc_if.s_resp_ready) begin
                    state_n = DISPATCH_BLOCK;
                    `GPC_PRINT("Scheduler", $sformatf("Sent job cluster response"));
                end
            end
            
            DISPATCH_BLOCK: begin
                // 选择目标SM
                target_sm_n = select_sm_rr(rr_counter_r, NUM_TPC * 2);
                
                // 发送消息
                router_if.gpc2sm_valid = 1'b1;
                router_if.gpc2sm_msg = build_router_message_block(
                    ROUTER_MSG_BLOCK_DISP,
                    ROUTER_DST_TPC0_SM0 + target_sm_n, // 使用新选择的目标SM
                    current_job_r,
                    current_block_id_r[15:0]  // 传递block_id
                );
                
                // 等待握手完成
                if (router_if.gpc2sm_valid && router_if.gpc2sm_ready) begin
                    // 握手成功，进入下一个状态
                    state_n = WAIT_DISPATCH;
                    
                    // 更新轮询计数器，为下一个block做准备
                    rr_counter_n = target_sm_n + 1;
                    
                    `GPC_PRINT("Scheduler", $sformatf("Dispatched block %-d to SM %-d", current_block_id_r, target_sm_n));
                end
            end
            
            WAIT_DISPATCH: begin
                // 检查是否还有更多Block需要分发
                if (block_count_r > 1) begin
                    block_count_n = block_count_r - 1;
                    current_block_id_n = current_block_id_r + 1;
                    state_n = DISPATCH_BLOCK;
                end else begin
                    // 所有Block都已分发，返回空闲状态
                    state_n = IDLE;
                    `GPC_PRINT("Scheduler", $sformatf("All blocks dispatched, returning to IDLE"));
                end
            end
            
            default: state_n = IDLE;
        endcase
    end
    
    // 时序逻辑
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_r <= IDLE;
            current_job_r <= '0;
            current_block_id_r <= '0;
            block_count_r <= '0;
            target_sm_r <= '0;
            rr_counter_r <= '0;
        end else begin
            state_r <= state_n;
            current_job_r <= current_job_n;
            current_block_id_r <= current_block_id_n;
            block_count_r <= block_count_n;
            target_sm_r <= target_sm_n;
            rr_counter_r <= rr_counter_n;
        end
    end
    
    // 监听TPC完成消息（通过路由器）
    always_ff @(posedge clk) begin
        if (rst_n) begin
            if (router_if.sm2gpc_valid && router_if.sm2gpc_ready) begin
                if (router_if.sm2gpc_msg.msg_type == ROUTER_MSG_BLOCK_COMP) begin
                    // 解析完成消息
                    logic [31:0] completed_block_id;
                    logic [7:0] sm_id;
                    
                    // 从完成消息中提取block_id和sm_id
                    completed_block_id = router_if.sm2gpc_msg.data.raw[31:0];
                    sm_id = router_if.sm2gpc_msg.data.raw[39:32];
                    
                    // 记录完成信息（可选）
                    `GPC_PRINT("Scheduler", $sformatf("Block %d completed on SM %d", completed_block_id, sm_id));
                end
            end
        end
    end
    
    assign router_if.sm2gpc_ready = 1'b1;

endmodule : rvgpu_gpc_block_scheduler

`endif // RVGPU_GPC_BLOCK_SCHEDULER_SV 