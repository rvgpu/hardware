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

`ifndef RVGPU_SM_ARBITER_SV
`define RVGPU_SM_ARBITER_SV

`include "rvgpu_typedef.svh"
`include "rvgpu_config.svh"
`include "interface_gpc_router.svh"
`include "types_gpc_router_message.svh"
`include "interface_sm_warp_dispatch.svh"
`include "interface_sm_l1cache.svh"

module rvgpu_sm_arbiter #(
    parameter int SM_ID = 0
) (
    input  logic clk,
    input  logic rst_n,
    
    // 外部路由器接口
    interface_gpc_router.left_port router_if,
    
    // Block调度接口 - 连接Block Scheduler
    interface_sm_warp_dispatch.scheduler warp_dispatch_if[`CONFIG_SM_CUDA_CORE_COUNT],
    
    // L1 Cache接口 - 连接L1 Cache
    interface_sm_l1cache.cache l1_cache_if[`CONFIG_SM_CUDA_CORE_COUNT],
    
    // 内部状态反馈
    input  logic [`CONFIG_SM_CUDA_CORE_COUNT-1:0] core_ready,
    input  logic [`CONFIG_SM_CUDA_CORE_COUNT-1:0] core_busy,
    input  logic [`CONFIG_SM_CUDA_CORE_COUNT-1:0] warp_complete,
    input  logic [`CONFIG_SM_CUDA_CORE_COUNT-1:0][$clog2(`CONFIG_SM_WARP_COUNT)-1:0] warp_complete_id
);

    // ============================================================================
    // 使用宏定义
    // ============================================================================
    localparam int WARP_COUNT = `CONFIG_SM_WARP_COUNT;
    localparam int THREAD_COUNT = `CONFIG_WARP_THREAD_NUMBER;
    localparam int CUDA_CORE_COUNT = `CONFIG_SM_CUDA_CORE_COUNT;
    
    // ============================================================================
    // 内部状态和信号
    // ============================================================================
    
    // 路由器消息解析
    logic [7:0] msg_type;
    logic [31:0] msg_src;
    logic [31:0] msg_dst;
    logic [255:0] msg_data;
    
    // Block调度状态
    logic [CUDA_CORE_COUNT-1:0] block_dispatch_valid;
    logic [CUDA_CORE_COUNT-1:0] block_dispatch_ready;
    logic [CUDA_CORE_COUNT-1:0][31:0] block_id;
    logic [CUDA_CORE_COUNT-1:0][63:0] program_addr;
    
    // 内存访问仲裁
    logic [CUDA_CORE_COUNT-1:0] mem_req_valid;
    logic [CUDA_CORE_COUNT-1:0] mem_req_ready;
    logic [CUDA_CORE_COUNT-1:0][63:0] mem_req_addr;
    logic [CUDA_CORE_COUNT-1:0][31:0] mem_req_data;
    logic [CUDA_CORE_COUNT-1:0][2:0] mem_req_size;
    logic [CUDA_CORE_COUNT-1:0] mem_req_is_load;
    
    // 仲裁优先级
    typedef enum logic [1:0] {
        PRIO_BLOCK_DISPATCH = 2'b00,    // Block分发最高优先级
        PRIO_MEMORY_ACCESS = 2'b01,     // 内存访问中等优先级
        PRIO_STATUS_UPDATE = 2'b10      // 状态更新最低优先级
    } arb_priority_t;
    
    arb_priority_t current_priority;
    
    // ============================================================================
    // 路由器消息解析
    // ============================================================================
    
    always_comb begin
        if (router_if.down_valid) begin
            msg_type = router_if.down_msg.msg_type;
            msg_src = router_if.down_msg.src_id;
            msg_dst = router_if.down_msg.dst_id;
            msg_data = router_if.down_msg.data;
        end else begin
            msg_type = 8'h0;
            msg_src = 32'h0;
            msg_dst = 32'h0;
            msg_data = 256'h0;
        end
    end
    
    // ============================================================================
    // 路由器消息处理
    // ============================================================================
    
    always_comb begin
        // 默认设置
        router_if.down_ready = 1'b0;
        
        case (msg_type)
            // Block分发消息
            ROUTER_MSG_BLOCK_DISP: begin
                if (|core_ready) begin
                    router_if.down_ready = 1'b1;
                end
            end
            
            // L1.5 Cache请求
            ROUTER_MSG_L15_REQ: begin
                // 转发到L1 Cache
                router_if.down_ready = 1'b1;
            end
            
            // MMU请求
            ROUTER_MSG_MMU_REQ: begin
                // 转发到MMU
                router_if.down_ready = 1'b1;
            end
            
            default: begin
                router_if.down_ready = 1'b1;
            end
        endcase
    end
    
    // ============================================================================
    // Block调度仲裁
    // ============================================================================
    
    always_comb begin
        // 初始化信号
        for (int i = 0; i < CUDA_CORE_COUNT; i++) begin
            block_dispatch_valid[i] = 1'b0;
            block_dispatch_ready[i] = 1'b0;
            block_id[i] = 32'h0;
            program_addr[i] = 64'h0;
        end
        
        // Block分发逻辑 - 轮询调度
        if (router_if.down_valid && msg_type == ROUTER_MSG_BLOCK_DISP) begin
            for (int i = 0; i < CUDA_CORE_COUNT; i++) begin
                if (core_ready[i]) begin
                    block_dispatch_valid[i] = 1'b1;
                    block_id[i] = msg_data[31:0];
                    program_addr[i] = msg_data[95:32];
                    break;
                end
            end
        end
        
        // 连接warp_dispatch接口
        for (int i = 0; i < CUDA_CORE_COUNT; i++) begin
            warp_dispatch_if[i].warp_valid = block_dispatch_valid[i];
            warp_dispatch_if[i].warp_inst = 32'h0; // 从指令缓存获取
            warp_dispatch_if[i].warp_pc = program_addr[i];
            warp_dispatch_if[i].warp_id = 5'h0; // 新warp ID
            warp_dispatch_if[i].active_mask = {THREAD_COUNT{1'b1}}; // 所有线程活跃
            block_dispatch_ready[i] = warp_dispatch_if[i].warp_ready;
        end
    end
    
    // ============================================================================
    // 内存访问仲裁
    // ============================================================================
    
    always_comb begin
        // 初始化信号
        for (int i = 0; i < CUDA_CORE_COUNT; i++) begin
            mem_req_valid[i] = 1'b0;
            mem_req_ready[i] = 1'b0;
            mem_req_addr[i] = 64'h0;
            mem_req_data[i] = 32'h0;
            mem_req_size[i] = 3'h0;
            mem_req_is_load[i] = 1'b0;
        end
        
        // 从CUDA Core收集内存请求
        for (int i = 0; i < CUDA_CORE_COUNT; i++) begin
            if (l1_cache_if[i].req_valid) begin
                mem_req_valid[i] = 1'b1;
                mem_req_addr[i] = l1_cache_if[i].req_addr;
                mem_req_data[i] = l1_cache_if[i].req_data;
                mem_req_size[i] = l1_cache_if[i].req_size;
                mem_req_is_load[i] = l1_cache_if[i].req_is_load;
                mem_req_ready[i] = l1_cache_if[i].req_ready;
            end
        end
        
        // 连接L1 Cache接口
        for (int i = 0; i < CUDA_CORE_COUNT; i++) begin
            l1_cache_if[i].req_valid = mem_req_valid[i];
            l1_cache_if[i].req_addr = mem_req_addr[i];
            l1_cache_if[i].req_data = mem_req_data[i];
            l1_cache_if[i].req_size = mem_req_size[i];
            l1_cache_if[i].req_is_load = mem_req_is_load[i];
            l1_cache_if[i].req_warp_id = 5'h0; // 从CUDA Core获取
            l1_cache_if[i].req_mask = {THREAD_COUNT{1'b1}}; // 从CUDA Core获取
            mem_req_ready[i] = l1_cache_if[i].req_ready;
        end
    end
    
    // ============================================================================
    // 状态监控和反馈
    // ============================================================================
    
    always_comb begin
        // 监控CUDA Core状态
        for (int i = 0; i < CUDA_CORE_COUNT; i++) begin
            warp_dispatch_if[i].core_ready = core_ready[i];
            warp_dispatch_if[i].core_busy = core_busy[i];
            warp_dispatch_if[i].warp_complete = warp_complete[i];
            warp_dispatch_if[i].warp_complete_id = warp_complete_id[i];
        end
    end

endmodule : rvgpu_sm_arbiter

`endif // RVGPU_SM_ARBITER_SV
