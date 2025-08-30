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

`ifndef RVGPU_SM_L1_ARBITER_SV
`define RVGPU_SM_L1_ARBITER_SV

`include "rvgpu_typedef.svh"
`include "rvgpu_config.svh"
`include "interface_sm_l1cache.svh"

module rvgpu_sm_l1_arbiter #(
    parameter int SM_ID = 0
) (
    input  logic clk,
    input  logic rst_n,
    
    // CUDA Core接口 - 4个Core
    interface_sm_l1cache.cache core_if[`CONFIG_SM_CUDA_CORE_COUNT],
    
    // 仲裁后接口 - 连接L1 Controller
    interface_sm_l1cache.core controller_if
);

    // ============================================================================
    // 使用宏定义
    // ============================================================================
    localparam int WARP_COUNT = `CONFIG_SM_WARP_COUNT;
    localparam int THREAD_COUNT = `CONFIG_WARP_THREAD_NUMBER;
    localparam int CUDA_CORE_COUNT = `CONFIG_SM_CUDA_CORE_COUNT;
    
    // ============================================================================
    // 仲裁逻辑 - 轮询优先级
    // ============================================================================
    
    // 当前选择的Core
    logic [$clog2(CUDA_CORE_COUNT)-1:0] selected_core;
    logic has_request;
    
    // 轮询选择算法 - 使用显式条件替代循环
    always_comb begin
        has_request = 1'b0;
        selected_core = '0;
        
        // 优先级轮询 - 显式检查每个核心
        if (core_if[0].req_valid) begin
            has_request = 1'b1;
            selected_core = 0;
        end else if (core_if[1].req_valid) begin
            has_request = 1'b1;
            selected_core = 1;
        end else if (core_if[2].req_valid) begin
            has_request = 1'b1;
            selected_core = 2;
        end else if (core_if[3].req_valid) begin
            has_request = 1'b1;
            selected_core = 3;
        end
    end
    
    // ============================================================================
    // 请求转发
    // ============================================================================
    
    always_comb begin
        // 默认值
        controller_if.req_valid = 1'b0;
        controller_if.req_addr = '0;
        controller_if.req_data = '0;
        controller_if.req_size = '0;
        controller_if.req_is_load = 1'b0;
        controller_if.req_warp_id = '0;
        controller_if.req_mask = '0;
        controller_if.req_is_shared = 1'b0;
        
        // 所有Core的req_ready默认为0 - 显式设置每个核心
        core_if[0].req_ready = 1'b0;
        core_if[1].req_ready = 1'b0;
        core_if[2].req_ready = 1'b0;
        core_if[3].req_ready = 1'b0;
        
        // 如果有请求且控制器准备好接收
        if (has_request && controller_if.req_ready) begin
            // 转发选中的Core请求 - 使用条件语句替代变量索引
            controller_if.req_valid = 1'b1;
            
            // 根据selected_core选择正确的核心
            if (selected_core == 0) begin
                controller_if.req_addr = core_if[0].req_addr;
                controller_if.req_data = core_if[0].req_data;
                controller_if.req_size = core_if[0].req_size;
                controller_if.req_is_load = core_if[0].req_is_load;
                controller_if.req_warp_id = core_if[0].req_warp_id;
                controller_if.req_mask = core_if[0].req_mask;
                controller_if.req_is_shared = core_if[0].req_is_shared;
                core_if[0].req_ready = 1'b1;
            end else if (selected_core == 1) begin
                controller_if.req_addr = core_if[1].req_addr;
                controller_if.req_data = core_if[1].req_data;
                controller_if.req_size = core_if[1].req_size;
                controller_if.req_is_load = core_if[1].req_is_load;
                controller_if.req_warp_id = core_if[1].req_warp_id;
                controller_if.req_mask = core_if[1].req_mask;
                controller_if.req_is_shared = core_if[1].req_is_shared;
                core_if[1].req_ready = 1'b1;
            end else if (selected_core == 2) begin
                controller_if.req_addr = core_if[2].req_addr;
                controller_if.req_data = core_if[2].req_data;
                controller_if.req_size = core_if[2].req_size;
                controller_if.req_is_load = core_if[2].req_is_load;
                controller_if.req_warp_id = core_if[2].req_warp_id;
                controller_if.req_mask = core_if[2].req_mask;
                controller_if.req_is_shared = core_if[2].req_is_shared;
                core_if[2].req_ready = 1'b1;
            end else if (selected_core == 3) begin
                controller_if.req_addr = core_if[3].req_addr;
                controller_if.req_data = core_if[3].req_data;
                controller_if.req_size = core_if[3].req_size;
                controller_if.req_is_load = core_if[3].req_is_load;
                controller_if.req_warp_id = core_if[3].req_warp_id;
                controller_if.req_mask = core_if[3].req_mask;
                controller_if.req_is_shared = core_if[3].req_is_shared;
                core_if[3].req_ready = 1'b1;
            end
        end
    end
    
    // ============================================================================
    // 响应转发
    // ============================================================================
    
    // 当前处理的warp_id
    logic [$clog2(WARP_COUNT)-1:0] current_warp_id;
    logic [CUDA_CORE_COUNT-1:0] core_match;
    
    // 记录当前处理的warp_id
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_warp_id <= '0;
        end else if (has_request && controller_if.req_ready) begin
            // 根据selected_core选择正确的warp_id
            if (selected_core == 0) begin
                current_warp_id <= core_if[0].req_warp_id;
            end else if (selected_core == 1) begin
                current_warp_id <= core_if[1].req_warp_id;
            end else if (selected_core == 2) begin
                current_warp_id <= core_if[2].req_warp_id;
            end else if (selected_core == 3) begin
                current_warp_id <= core_if[3].req_warp_id;
            end
        end
    end
    
    // 匹配响应到对应的Core
    always_comb begin
        // 默认值
        controller_if.resp_ready = 1'b0;
        
        // 所有Core的resp_valid默认为0 - 显式设置每个核心
        core_if[0].resp_valid = 1'b0;
        core_if[0].resp_data = '0;
        core_if[0].resp_warp_id = '0;
        core_if[0].resp_mask = '0;
        
        core_if[1].resp_valid = 1'b0;
        core_if[1].resp_data = '0;
        core_if[1].resp_warp_id = '0;
        core_if[1].resp_mask = '0;
        
        core_if[2].resp_valid = 1'b0;
        core_if[2].resp_data = '0;
        core_if[2].resp_warp_id = '0;
        core_if[2].resp_mask = '0;
        
        core_if[3].resp_valid = 1'b0;
        core_if[3].resp_data = '0;
        core_if[3].resp_warp_id = '0;
        core_if[3].resp_mask = '0;
        
        // 检查哪个Core在等待这个warp_id的响应
        core_match[0] = (core_if[0].resp_ready && controller_if.resp_valid && 
                       controller_if.resp_warp_id == current_warp_id);
        core_match[1] = (core_if[1].resp_ready && controller_if.resp_valid && 
                       controller_if.resp_warp_id == current_warp_id);
        core_match[2] = (core_if[2].resp_ready && controller_if.resp_valid && 
                       controller_if.resp_warp_id == current_warp_id);
        core_match[3] = (core_if[3].resp_ready && controller_if.resp_valid && 
                       controller_if.resp_warp_id == current_warp_id);
        
        // 如果有Core准备好接收响应
        if (|core_match && controller_if.resp_valid) begin
            // 使用显式条件检查每个核心
            if (core_match[0]) begin
                // 转发响应到核心0
                core_if[0].resp_valid = 1'b1;
                core_if[0].resp_data = controller_if.resp_data;
                core_if[0].resp_warp_id = controller_if.resp_warp_id;
                core_if[0].resp_mask = controller_if.resp_mask;
                
                // 通知控制器响应已被接收
                controller_if.resp_ready = 1'b1;
            end else if (core_match[1]) begin
                // 转发响应到核心1
                core_if[1].resp_valid = 1'b1;
                core_if[1].resp_data = controller_if.resp_data;
                core_if[1].resp_warp_id = controller_if.resp_warp_id;
                core_if[1].resp_mask = controller_if.resp_mask;
                
                // 通知控制器响应已被接收
                controller_if.resp_ready = 1'b1;
            end else if (core_match[2]) begin
                // 转发响应到核心2
                core_if[2].resp_valid = 1'b1;
                core_if[2].resp_data = controller_if.resp_data;
                core_if[2].resp_warp_id = controller_if.resp_warp_id;
                core_if[2].resp_mask = controller_if.resp_mask;
                
                // 通知控制器响应已被接收
                controller_if.resp_ready = 1'b1;
            end else if (core_match[3]) begin
                // 转发响应到核心3
                core_if[3].resp_valid = 1'b1;
                core_if[3].resp_data = controller_if.resp_data;
                core_if[3].resp_warp_id = controller_if.resp_warp_id;
                core_if[3].resp_mask = controller_if.resp_mask;
                
                // 通知控制器响应已被接收
                controller_if.resp_ready = 1'b1;
            end
        end
    end

endmodule : rvgpu_sm_l1_arbiter

`endif // RVGPU_SM_L1_ARBITER_SV