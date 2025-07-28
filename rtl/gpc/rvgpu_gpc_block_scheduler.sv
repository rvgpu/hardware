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
`include "rvgpu_job_cluster_block.svh"
`include "gpc_block_tpc_if.svh"
`include "gpc_block_raster_if.svh"
`include "gpc_l15_cache_if.svh"
`include "gpc_mmu_if.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_noc_message.svh"

// GPC Block Scheduler模块
// 负责接收job_cluster并将其调度到合适的TPC
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
    
    // TPC接口
    gpc_block_tpc_if.scheduler tpc_if[NUM_TPC],
    
    // Raster Engine接口
    gpc_block_raster_if.scheduler raster_if,
    
    // L1.5 Cache接口
    gpc_l15_cache_if.requester l15_if,
    
    // GPC MMU接口
    gpc_mmu_if.requester tlb_if
);
    // 状态机状态
    typedef enum logic [3:0] {
        IDLE,
        RESP_JD,
        REQUEST_MMU,
        WAIT_MMU,
        REQUEST_CACHE,
        WAIT_CACHE,
        DISPATCH_BLOCK,
        WAIT_DISPATCH
    } scheduler_state_t;
    
    // Block定义
    typedef struct packed {
        logic [31:0] block_id;
        logic [31:0] cluster_id;
        logic [63:0] program_addr;
        logic [63:0] arglist_ptr;
        logic [31:0] argument_size;
        logic [255:0] arglist_data;
        logic [31:0] block_x, block_y, block_z;
        logic [31:0] thread_x, thread_y, thread_z;
    } block_t;
    
    // 内部信号
    scheduler_state_t state_r, state_n;
    job_cluster_t current_job_r, current_job_n;
    logic [63:0] arglist_paddr_r, arglist_paddr_n;
    logic [31:0] current_block_id_r, current_block_id_n;
    logic [31:0] block_count_r, block_count_n;
    logic [$clog2(NUM_TPC)-1:0] target_tpc_r, target_tpc_n;
    block_t current_block_r, current_block_n;
    logic [7:0] tpc_load_r[NUM_TPC], tpc_load_n[NUM_TPC];
    
    // 解析Job Cluster获取Block数量
    function automatic logic [31:0] calculate_block_count(input job_cluster_t job);
        logic [31:0] total_blocks;
        
        // 使用已有的辅助函数计算cluster中的block总数
        total_blocks = get_total_blocks_in_cluster(job);
        return total_blocks;
    endfunction
    
    // 选择负载最低的TPC
    function automatic logic [$clog2(NUM_TPC)-1:0] select_tpc(input logic [7:0] load_array[NUM_TPC]);
        logic [$clog2(NUM_TPC)-1:0] selected_tpc;
        logic [7:0] min_load;
        
        selected_tpc = '0;
        min_load = load_array[0];
        
        for (int i = 1; i < NUM_TPC; i++) begin
            if (load_array[i] < min_load) begin
                min_load = load_array[i];
                selected_tpc = i[$clog2(NUM_TPC)-1:0];
            end
        end
        
        return selected_tpc;
    endfunction
    
    // 生成Block
    function automatic block_t create_block(
        input logic [31:0] block_id,
        input job_cluster_t job,
        input logic [255:0] arglist_data
    );
        block_t block;
        
        block.block_id = block_id;
        block.cluster_id = job.curr_cluster_id;
        block.program_addr = job.program_ptr;
        block.arglist_ptr = job.program_ptr + 64'd8;
        block.argument_size = job.arg_size;
        block.arglist_data = arglist_data;
        // block的维度由job_dim.block_x/y/z定义
        block.block_x = job.job_dim.block_x;
        block.block_y = job.job_dim.block_y;
        block.block_z = job.job_dim.block_z;
        // thread维度暂时使用block维度，后续在SM中会进一步拆分
        block.thread_x = job.job_dim.block_x;
        block.thread_y = job.job_dim.block_y;
        block.thread_z = job.job_dim.block_z;
        
        return block;
    endfunction
    
    // 组合逻辑
    always_comb begin
        // 默认赋值
        state_n = state_r;
        current_job_n = current_job_r;
        arglist_paddr_n = arglist_paddr_r;
        current_block_id_n = current_block_id_r;
        block_count_n = block_count_r;
        target_tpc_n = target_tpc_r;
        current_block_n = current_block_r;
        tpc_load_n = tpc_load_r;
        
        // 接口默认值
        noc_if.s_req_ready = 1'b0;
        noc_if.s_resp_valid = 1'b0;
        noc_if.s_resp_header = '0;
        noc_if.s_resp_data = '0;
        noc_if.s_resp_status = 2'b00;
        noc_if.s_resp_last = 1'b0;
        
        tpc_if[0].block_valid = 1'b0;
        tpc_if[1].block_valid = 1'b0;
        tpc_if[2].block_valid = 1'b0;
        tpc_if[3].block_valid = 1'b0;
        
        raster_if.cmd_valid = 1'b0;
        l15_if.req_valid = 1'b0;
        tlb_if.req_valid = 1'b0;
        
        case (state_r)
            IDLE: begin
                // 等待接收job cluster请求
                noc_if.s_req_ready = 1'b1;
                
                if (noc_if.s_req_valid && noc_if.s_req_ready) begin
                    if (get_noc_header_msg_type(noc_header_t'(noc_if.s_req_header)) == MSG_COMPUTE_REQ) begin
                        current_job_n = noc_if.s_req_data;
                        block_count_n = calculate_block_count(noc_if.s_req_data);
                        current_block_id_n = 0;
                        state_n = RESP_JD;
                        `GPC_PRINT("Scheduler", $sformatf("Received job cluster %0d with %0d blocks", current_job_n.curr_cluster_id, block_count_n));
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
                    state_n = REQUEST_MMU;
                    `GPC_PRINT("Scheduler", $sformatf("Sent job cluster response"));
                end
            end
            
            REQUEST_MMU: begin
                // 请求MMU翻译地址
                tlb_if.req_valid = 1'b1;
                tlb_if.req_vaddr = current_job_r.program_ptr + 64'd8;
                tlb_if.req_type = MMU_READ;
                tlb_if.req_warp_id = '0;
                tlb_if.req_source_id = '0;
                
                if (tlb_if.req_valid && tlb_if.req_ready) begin
                    tlb_if.req_valid = 1'b0;
                    state_n = WAIT_MMU;
                end
                `GPC_PRINT("Scheduler", $sformatf("Requesting MMU translation for program at %h", current_job_r.program_ptr + 64'd8));
            end
            
            WAIT_MMU: begin
                // 等待MMU响应
                if (tlb_if.resp_valid) begin
                    if (!tlb_if.resp_fault) begin
                        // MMU命中，保存物理地址
                        arglist_paddr_n = {tlb_if.resp_ppn, current_job_r.program_ptr[11:0]};
                        state_n = REQUEST_CACHE;
                    end else begin
                        // MMU未命中，返回空闲状态
                        state_n = IDLE;
                    end
                end
            end
            
            REQUEST_CACHE: begin
                // 请求L1.5 Cache
                l15_if.req_valid = 1'b1;
                l15_if.req_is_read = 1'b1;
                l15_if.req_paddr = arglist_paddr_r;
                l15_if.req_size = 4'b0100; // 16字节
                l15_if.req_type = L15_CACHE_NORMAL;
                l15_if.req_data = '0;
                l15_if.req_mask = '0;
                l15_if.req_id = '0;
                
                if (l15_if.req_valid && l15_if.req_ready) begin
                    l15_if.req_valid = 1'b0;
                    state_n = WAIT_CACHE;
                end
            end
            
            WAIT_CACHE: begin
                // 等待L1.5 Cache响应
                l15_if.resp_ready = 1'b1;
                
                if (l15_if.resp_valid && l15_if.resp_ready) begin
                    l15_if.resp_ready = 1'b0;
                    
                    // 选择目标TPC
                    target_tpc_n = select_tpc(tpc_load_r);
                    
                    // 创建第一个Block
                    current_block_n = create_block(
                        current_block_id_r,
                        current_job_r,
                        l15_if.resp_data
                    );
                    
                    state_n = DISPATCH_BLOCK;
                end
            end
            
            DISPATCH_BLOCK: begin
                // 将Block分发给TPC
                case (target_tpc_r)
                    0: begin
                        tpc_if[0].block_valid = 1'b1;
                        tpc_if[0].block_id = current_block_r.block_id;
                        tpc_if[0].cluster_id = current_block_r.cluster_id;
                        tpc_if[0].program_addr = current_block_r.program_addr;
                        tpc_if[0].arglist_ptr = current_block_r.arglist_ptr;
                        tpc_if[0].argument_size = current_block_r.argument_size;
                        tpc_if[0].arglist_data = current_block_r.arglist_data;
                        tpc_if[0].block_x = current_block_r.block_x;
                        tpc_if[0].block_y = current_block_r.block_y;
                        tpc_if[0].block_z = current_block_r.block_z;
                        tpc_if[0].thread_x = current_block_r.thread_x;
                        tpc_if[0].thread_y = current_block_r.thread_y;
                        tpc_if[0].thread_z = current_block_r.thread_z;
                        
                        if (tpc_if[0].block_ready) begin
                            tpc_if[0].block_valid = 1'b0;
                            
                            // 更新TPC负载
                            tpc_load_n[0] = tpc_load_r[0] + 1;
                            state_n = WAIT_DISPATCH;
                        end
                    end
                    1: begin
                        tpc_if[1].block_valid = 1'b1;
                        tpc_if[1].block_id = current_block_r.block_id;
                        tpc_if[1].cluster_id = current_block_r.cluster_id;
                        tpc_if[1].program_addr = current_block_r.program_addr;
                        tpc_if[1].arglist_ptr = current_block_r.arglist_ptr;
                        tpc_if[1].argument_size = current_block_r.argument_size;
                        tpc_if[1].arglist_data = current_block_r.arglist_data;
                        tpc_if[1].block_x = current_block_r.block_x;
                        tpc_if[1].block_y = current_block_r.block_y;
                        tpc_if[1].block_z = current_block_r.block_z;
                        tpc_if[1].thread_x = current_block_r.thread_x;
                        tpc_if[1].thread_y = current_block_r.thread_y;
                        tpc_if[1].thread_z = current_block_r.thread_z;
                        
                        if (tpc_if[1].block_ready) begin
                            tpc_if[1].block_valid = 1'b0;
                            
                            // 更新TPC负载
                            tpc_load_n[1] = tpc_load_r[1] + 1;
                            state_n = WAIT_DISPATCH;
                        end
                    end
                    2: begin
                        tpc_if[2].block_valid = 1'b1;
                        tpc_if[2].block_id = current_block_r.block_id;
                        tpc_if[2].cluster_id = current_block_r.cluster_id;
                        tpc_if[2].program_addr = current_block_r.program_addr;
                        tpc_if[2].arglist_ptr = current_block_r.arglist_ptr;
                        tpc_if[2].argument_size = current_block_r.argument_size;
                        tpc_if[2].arglist_data = current_block_r.arglist_data;
                        tpc_if[2].block_x = current_block_r.block_x;
                        tpc_if[2].block_y = current_block_r.block_y;
                        tpc_if[2].block_z = current_block_r.block_z;
                        tpc_if[2].thread_x = current_block_r.thread_x;
                        tpc_if[2].thread_y = current_block_r.thread_y;
                        tpc_if[2].thread_z = current_block_r.thread_z;
                        
                        if (tpc_if[2].block_ready) begin
                            tpc_if[2].block_valid = 1'b0;
                            
                            // 更新TPC负载
                            tpc_load_n[2] = tpc_load_r[2] + 1;
                            state_n = WAIT_DISPATCH;
                        end
                    end
                    3: begin
                        tpc_if[3].block_valid = 1'b1;
                        tpc_if[3].block_id = current_block_r.block_id;
                        tpc_if[3].cluster_id = current_block_r.cluster_id;
                        tpc_if[3].program_addr = current_block_r.program_addr;
                        tpc_if[3].arglist_ptr = current_block_r.arglist_ptr;
                        tpc_if[3].argument_size = current_block_r.argument_size;
                        tpc_if[3].arglist_data = current_block_r.arglist_data;
                        tpc_if[3].block_x = current_block_r.block_x;
                        tpc_if[3].block_y = current_block_r.block_y;
                        tpc_if[3].block_z = current_block_r.block_z;
                        tpc_if[3].thread_x = current_block_r.thread_x;
                        tpc_if[3].thread_y = current_block_r.thread_y;
                        tpc_if[3].thread_z = current_block_r.thread_z;
                        
                        if (tpc_if[3].block_ready) begin
                            tpc_if[3].block_valid = 1'b0;
                            
                            // 更新TPC负载
                            tpc_load_n[3] = tpc_load_r[3] + 1;
                            state_n = WAIT_DISPATCH;
                        end
                    end
                    default: state_n = IDLE;
                endcase
            end
            
            WAIT_DISPATCH: begin
                // 检查是否还有更多Block需要分发
                if (block_count_r > 1) begin
                    block_count_n = block_count_r - 1;
                    current_block_id_n = current_block_id_r + 1;
                    
                    // 选择下一个目标TPC
                    target_tpc_n = select_tpc(tpc_load_n);
                    
                    // 创建下一个Block
                    current_block_n = create_block(
                        current_block_id_n,
                        current_job_r,
                        current_block_r.arglist_data
                    );
                    
                    state_n = DISPATCH_BLOCK;
                end else begin
                    // 所有Block都已分发，返回空闲状态
                    state_n = IDLE;
                end
            end
            
            default: state_n = IDLE;
        endcase
    end
    
    // 时序逻辑
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_r <= IDLE;
            current_job_r <= '0;
            arglist_paddr_r <= '0;
            current_block_id_r <= '0;
            block_count_r <= '0;
            target_tpc_r <= '0;
            current_block_r <= '0;
            tpc_load_r[0] <= '0;
            tpc_load_r[1] <= '0;
            tpc_load_r[2] <= '0;
            tpc_load_r[3] <= '0;
        end else begin
            state_r <= state_n;
            current_job_r <= current_job_n;
            arglist_paddr_r <= arglist_paddr_n;
            current_block_id_r <= current_block_id_n;
            block_count_r <= block_count_n;
            target_tpc_r <= target_tpc_n;
            current_block_r <= current_block_n;
            tpc_load_r[0] <= tpc_load_n[0];
            tpc_load_r[1] <= tpc_load_n[1];
            tpc_load_r[2] <= tpc_load_n[2];
            tpc_load_r[3] <= tpc_load_n[3];
            
            // TPC完成处理
            if (tpc_if[0].complete_valid && tpc_if[0].complete_ready) begin
                if (tpc_load_r[0] > 0) begin
                    tpc_load_r[0] <= tpc_load_r[0] - 1;
                end
            end
            
            if (tpc_if[1].complete_valid && tpc_if[1].complete_ready) begin
                if (tpc_load_r[1] > 0) begin
                    tpc_load_r[1] <= tpc_load_r[1] - 1;
                end
            end
            
            if (tpc_if[2].complete_valid && tpc_if[2].complete_ready) begin
                if (tpc_load_r[2] > 0) begin
                    tpc_load_r[2] <= tpc_load_r[2] - 1;
                end
            end
            
            if (tpc_if[3].complete_valid && tpc_if[3].complete_ready) begin
                if (tpc_load_r[3] > 0) begin
                    tpc_load_r[3] <= tpc_load_r[3] - 1;
                end
            end
        end
    end
    
    // TPC完成接口
    assign tpc_if[0].complete_ready = 1'b1;
    assign tpc_if[1].complete_ready = 1'b1;
    assign tpc_if[2].complete_ready = 1'b1;
    assign tpc_if[3].complete_ready = 1'b1;

endmodule : rvgpu_gpc_block_scheduler

`endif // RVGPU_GPC_BLOCK_SCHEDULER_SV 