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

`ifndef RVGPU_SM_SV
`define RVGPU_SM_SV

`include "rvgpu_typedef.svh"

// SM (Streaming Multiprocessor) - 4个CUDA Core架构
// 参考现代GPU架构，每个SM包含4个CUDA Core子单元
// 采用两级调度：GPC Block Scheduler -> SM Warp Scheduler -> CUDA Core Units
module rvgpu_sm #(
    parameter int SM_ID = 0,                    // SM ID
    parameter int WARP_COUNT = 32,              // 每个SM支持的warp数量
    parameter int MAX_THREAD_PER_WARP = 32,     // 每个warp的最大线程数
    parameter int MAX_ACTIVE_WARPS = 16,        // 同时活跃的最大warp数量
    parameter int NUM_CUDA_CORES = 4,           // CUDA Core数量
    parameter int THREAD_COUNT = 1024           // 每个SM的总线程数
) (
    input  logic clk,
    input  logic rst_n,
    
    // TPC接口
    gpc_block_tpc_if.sm block_dispatch_if,
    
    // LDST接口
    ldst_sm_if.sm ldst_if,
    
    // L1.5 Cache接口 (用于指令获取)
    gpc_l15_cache_if.requester l15_if,
    
    // L0 TLB接口 (用于指令地址转换)
    gpc_l0_tlb_if.requester tlb_if,
    
    // 完成信号
    output logic warp_complete,
    output logic [31:0] warp_id
);

    // =========================================================================
    // 内部信号声明
    // =========================================================================
    
    // Warp状态管理
    logic [63:0] warp_pc[WARP_COUNT];
    logic [MAX_THREAD_PER_WARP-1:0] warp_active_mask[WARP_COUNT];
    logic [WARP_COUNT-1:0] warp_valid;
    logic [WARP_COUNT-1:0] warp_stalled;
    logic [WARP_COUNT-1:0] warp_barrier;
    logic [WARP_COUNT-1:0] warp_waiting;
    
    // SM级Warp调度器信号
    logic warp_schedule_valid;
    logic [$clog2(WARP_COUNT)-1:0] scheduled_warp_id;
    logic scheduler_stall;
    logic new_warp_valid;
    logic [$clog2(WARP_COUNT)-1:0] new_warp_id;
    logic [$clog2(WARP_COUNT):0] active_warp_count;
    logic [$clog2(WARP_COUNT):0] stalled_warp_count;
    logic warp_scheduler_full;
    
    // L0 ICache + 取指 + 解码信号
    logic icache_req_valid;
    logic [63:0] icache_req_vaddr;
    logic icache_req_ready;
    logic icache_resp_valid;
    logic [31:0] icache_resp_inst;
    logic icache_resp_ready;
    
    logic fetch_decode_valid;
    logic [31:0] fetch_decode_inst;
    logic [63:0] fetch_decode_pc;
    logic [$clog2(WARP_COUNT)-1:0] fetch_decode_warp_id;
    logic [MAX_THREAD_PER_WARP-1:0] fetch_decode_active_mask;
    logic fetch_decode_ready;
    
    // 解码后的信号
    logic decode_valid;
    logic [31:0] decode_inst;
    logic [63:0] decode_pc;
    logic [$clog2(WARP_COUNT)-1:0] decode_warp_id;
    logic [MAX_THREAD_PER_WARP-1:0] decode_active_mask;
    logic [4:0] decode_rs1, decode_rs2, decode_rs3, decode_rd;
    logic [31:0] decode_imm;
    logic decode_is_alu, decode_is_fpu, decode_is_tensor;
    logic decode_is_branch, decode_is_jump;
    logic decode_is_load, decode_is_store, decode_is_barrier;
    logic [3:0] decode_alu_op;
    logic [2:0] decode_fpu_op, decode_tensor_op, decode_branch_op;
    logic decode_reg_write, decode_use_imm, decode_is_32bit;
    logic decode_ready;
    
    // 共享寄存器文件信号 (16,384 x 32-bit)
    logic [2:0] reg_read_enable[NUM_CUDA_CORES];
    logic [$clog2(WARP_COUNT)-1:0] reg_read_warp_id[NUM_CUDA_CORES][3];
    logic [4:0] reg_read_addr[NUM_CUDA_CORES][3];
    logic [31:0] reg_read_data[NUM_CUDA_CORES][3][MAX_THREAD_PER_WARP];
    
    logic reg_write_enable[NUM_CUDA_CORES];
    logic [$clog2(WARP_COUNT)-1:0] reg_write_warp_id[NUM_CUDA_CORES];
    logic [4:0] reg_write_addr[NUM_CUDA_CORES];
    logic [31:0] reg_write_data[NUM_CUDA_CORES][MAX_THREAD_PER_WARP];
    logic [MAX_THREAD_PER_WARP-1:0] reg_write_mask[NUM_CUDA_CORES];
    
    logic warp_alloc_valid;
    logic [$clog2(WARP_COUNT)-1:0] warp_alloc_id;
    logic warp_alloc_ready;
    logic warp_dealloc_valid;
    logic [$clog2(WARP_COUNT)-1:0] warp_dealloc_id;
    logic [WARP_COUNT-1:0] warp_allocated;
    logic [$clog2(WARP_COUNT):0] allocated_warp_count;
    
    // CUDA Core调度信号
    logic cuda_core_dispatch_valid[NUM_CUDA_CORES];
    logic cuda_core_dispatch_ready[NUM_CUDA_CORES];
    logic [$clog2(NUM_CUDA_CORES)-1:0] selected_cuda_core;
    
    // CUDA Core完成信号
    logic cuda_core_complete[NUM_CUDA_CORES];
    logic [$clog2(WARP_COUNT)-1:0] cuda_core_complete_id[NUM_CUDA_CORES];
    
    // CUDA Core分支反馈
    logic cuda_core_branch_feedback_valid[NUM_CUDA_CORES];
    logic [63:0] cuda_core_branch_feedback_pc[NUM_CUDA_CORES];
    logic cuda_core_branch_feedback_taken[NUM_CUDA_CORES];
    logic [63:0] cuda_core_branch_feedback_target[NUM_CUDA_CORES];
    
    // LDST单元仲裁信号
    logic ldst_req_valid[NUM_CUDA_CORES];
    logic [$clog2(WARP_COUNT)-1:0] ldst_req_warp_id[NUM_CUDA_CORES];
    logic [MAX_THREAD_PER_WARP-1:0] ldst_req_mask[NUM_CUDA_CORES];
    logic [63:0] ldst_req_addr[NUM_CUDA_CORES][MAX_THREAD_PER_WARP];
    logic [31:0] ldst_req_data[NUM_CUDA_CORES][MAX_THREAD_PER_WARP];
    logic [2:0] ldst_req_size[NUM_CUDA_CORES];
    logic ldst_req_is_load[NUM_CUDA_CORES];
    logic ldst_req_ready[NUM_CUDA_CORES];
    
    logic ldst_resp_valid[NUM_CUDA_CORES];
    logic [31:0] ldst_resp_warp_id[NUM_CUDA_CORES];
    logic [MAX_THREAD_PER_WARP-1:0] ldst_resp_data[NUM_CUDA_CORES];
    logic ldst_resp_ready[NUM_CUDA_CORES];
    
    // PC管理
    logic pc_update_valid;
    logic [$clog2(WARP_COUNT)-1:0] pc_update_warp_id;
    logic [63:0] pc_update_pc;
    
    // 流水线控制
    logic pipeline_stall;
    logic pipeline_flush;
    
    // L1 Data Cache/Shared Memory信号
    logic l1_data_req_valid[NUM_CUDA_CORES];
    logic [$clog2(WARP_COUNT)-1:0] l1_data_req_warp_id[NUM_CUDA_CORES];
    logic [THREAD_COUNT-1:0] l1_data_req_mask[NUM_CUDA_CORES];
    logic [63:0] l1_data_req_addr[NUM_CUDA_CORES][THREAD_COUNT];
    logic [31:0] l1_data_req_data[NUM_CUDA_CORES][THREAD_COUNT];
    logic [2:0] l1_data_req_size[NUM_CUDA_CORES];
    logic l1_data_req_is_load[NUM_CUDA_CORES];
    logic l1_data_req_is_shared[NUM_CUDA_CORES];
    logic l1_data_req_ready[NUM_CUDA_CORES];
    
    logic l1_data_resp_valid[NUM_CUDA_CORES];
    logic [$clog2(WARP_COUNT)-1:0] l1_data_resp_warp_id[NUM_CUDA_CORES];
    logic [THREAD_COUNT-1:0] l1_data_resp_mask[NUM_CUDA_CORES];
    logic [31:0] l1_data_resp_data[NUM_CUDA_CORES][THREAD_COUNT];
    logic l1_data_resp_ready[NUM_CUDA_CORES];
    
    // =========================================================================
    // L0 ICache实例化
    // =========================================================================
    
    rvgpu_sm_l0_icache #(
        .CACHE_SIZE(16 * 1024),
        .LINE_SIZE(32),
        .ASSOCIATIVITY(4)
    ) u_l0_icache (
        .clk(clk),
        .rst_n(rst_n),
        .fetch_req_valid(icache_req_valid),
        .fetch_req_vaddr(icache_req_vaddr),
        .fetch_req_ready(icache_req_ready),
        .fetch_resp_valid(icache_resp_valid),
        .fetch_resp_inst(icache_resp_inst),
        .l1_req_valid(l15_if.req_valid),
        .l1_req_paddr(l15_if.req_paddr),
        .l1_req_size(l15_if.req_size),
        .l1_req_ready(l15_if.req_ready),
        .l1_resp_valid(l15_if.resp_valid),
        .l1_resp_data(l15_if.resp_data),
        .l1_resp_ready(l15_if.resp_ready),
        .tlb_req_valid(tlb_if.lookup_valid),
        .tlb_req_vaddr(tlb_if.vaddr),
        .tlb_req_type(tlb_if.access_type),
        .tlb_req_warp_id(tlb_if.warp_id),
        .tlb_req_ready(tlb_if.lookup_ready),
        .tlb_resp_valid(tlb_if.lookup_resp_valid),
        .tlb_resp_hit(tlb_if.lookup_hit),
        .tlb_resp_ppn(tlb_if.ppn),
        .tlb_resp_fault(tlb_if.access_fault),
        .tlb_resp_warp_id(tlb_if.resp_warp_id)
    );
    
    // =========================================================================
    // SM级L1 Data Cache/Shared Memory实例化
    // =========================================================================
    
    rvgpu_sm_l1_data_cache #(
        .CACHE_SIZE(128 * 1024),
        .LINE_SIZE(128),
        .ASSOCIATIVITY(4),
        .SHARED_MEM_SIZE(64 * 1024),
        .DATA_CACHE_SIZE(64 * 1024),
        .ADDR_WIDTH(40),
        .WARP_COUNT(WARP_COUNT),
        .THREAD_COUNT(MAX_THREAD_PER_WARP)
    ) u_l1_data_cache (
        .clk(clk),
        .rst_n(rst_n),
        
        // CUDA Core接口
        .req_valid(l1_data_req_valid),
        .req_warp_id(l1_data_req_warp_id),
        .req_mask(l1_data_req_mask),
        .req_addr(l1_data_req_addr),
        .req_data(l1_data_req_data),
        .req_size(l1_data_req_size),
        .req_is_load(l1_data_req_is_load),
        .req_is_shared(l1_data_req_is_shared),
        .req_ready(l1_data_req_ready),
        
        .resp_valid(l1_data_resp_valid),
        .resp_warp_id(l1_data_resp_warp_id),
        .resp_mask(l1_data_resp_mask),
        .resp_data(l1_data_resp_data),
        .resp_ready(l1_data_resp_ready),
        
        // L1.5 Cache接口 (数据缓存未命中时使用)
        .l15_req_valid(),     // 需要添加新的L1.5接口用于数据访问
        .l15_req_paddr(),
        .l15_req_size(),
        .l15_req_is_read(),
        .l15_req_data(),
        .l15_req_mask(),
        .l15_req_id(),
        .l15_req_ready(1'b1), // 简化实现
        
        .l15_resp_valid(1'b0),
        .l15_resp_data('0),
        .l15_resp_error(1'b0),
        .l15_resp_id('0),
        .l15_resp_ready(),
        
        // 配置接口
        .shared_mem_config(16'h0), // 默认配置
        .cache_flush(1'b0),
        
        // 状态输出
        .pending_requests(),
        .hit_rate_percent()
    );
    
    // =========================================================================
    // SM级Warp调度器实例化
    // =========================================================================
    
    rvgpu_sm_warp_scheduler #(
        .WARP_COUNT(WARP_COUNT),
        .MAX_ACTIVE_WARPS(MAX_ACTIVE_WARPS),
        .PIPELINE_DEPTH(5)
    ) u_warp_scheduler (
        .clk(clk),
        .rst_n(rst_n),
        .warp_valid(warp_valid),
        .warp_stalled(warp_stalled),
        .warp_barrier(warp_barrier),
        .warp_waiting(warp_waiting),
        .scheduler_stall(scheduler_stall),
        .new_warp_id(new_warp_id),
        .new_warp_valid(new_warp_valid),
        .warp_schedule_valid(warp_schedule_valid),
        .scheduled_warp_id(scheduled_warp_id),
        .active_warp_count(active_warp_count),
        .stalled_warp_count(stalled_warp_count),
        .warp_scheduler_full(warp_scheduler_full)
    );
    
    // =========================================================================
    // 共享寄存器文件实例化 (16,384 x 32-bit)
    // =========================================================================
    
    rvgpu_sm_register_file #(
        .WARP_COUNT(WARP_COUNT),
        .THREAD_COUNT(MAX_THREAD_PER_WARP),
        .REG_COUNT(512),  // 增大到512个寄存器/线程 (16384/32)
        .READ_PORTS(3 * NUM_CUDA_CORES),  // 每个CUDA Core 3个读端口
        .WRITE_PORTS(NUM_CUDA_CORES)      // 每个CUDA Core 1个写端口
    ) u_register_file (
        .clk(clk),
        .rst_n(rst_n),
        .read_enable({reg_read_enable[3], reg_read_enable[2], reg_read_enable[1], reg_read_enable[0]}),
        .read_warp_id({reg_read_warp_id[3], reg_read_warp_id[2], reg_read_warp_id[1], reg_read_warp_id[0]}),
        .read_reg_addr({reg_read_addr[3], reg_read_addr[2], reg_read_addr[1], reg_read_addr[0]}),
        .read_data({reg_read_data[3], reg_read_data[2], reg_read_data[1], reg_read_data[0]}),
        .write_enable({reg_write_enable[3], reg_write_enable[2], reg_write_enable[1], reg_write_enable[0]}),
        .write_warp_id({reg_write_warp_id[3], reg_write_warp_id[2], reg_write_warp_id[1], reg_write_warp_id[0]}),
        .write_reg_addr({reg_write_addr[3], reg_write_addr[2], reg_write_addr[1], reg_write_addr[0]}),
        .write_data({reg_write_data[3], reg_write_data[2], reg_write_data[1], reg_write_data[0]}),
        .write_mask({reg_write_mask[3], reg_write_mask[2], reg_write_mask[1], reg_write_mask[0]}),
        .warp_alloc_valid(warp_alloc_valid),
        .warp_alloc_id(warp_alloc_id),
        .warp_alloc_ready(warp_alloc_ready),
        .warp_dealloc_valid(warp_dealloc_valid),
        .warp_dealloc_id(warp_dealloc_id),
        .warp_allocated(warp_allocated),
        .allocated_warp_count(allocated_warp_count)
    );
    
    // =========================================================================
    // 取指和解码阶段实例化
    // =========================================================================
    
    rvgpu_sm_fetch_stage #(
        .WARP_COUNT(WARP_COUNT),
        .THREAD_COUNT(MAX_THREAD_PER_WARP)
    ) u_fetch_stage (
        .clk(clk),
        .rst_n(rst_n),
        .warp_schedule_valid(warp_schedule_valid),
        .scheduled_warp_id(scheduled_warp_id),
        .fetch_ready(scheduler_stall),  // 反向控制
        .warp_pc(warp_pc),
        .warp_active_mask(warp_active_mask),
        .warp_valid(warp_valid),
        .icache_req_valid(icache_req_valid),
        .icache_req_vaddr(icache_req_vaddr),
        .icache_req_ready(icache_req_ready),
        .icache_resp_valid(icache_resp_valid),
        .icache_resp_inst(icache_resp_inst),
        .icache_resp_ready(icache_resp_ready),
        .fetch_decode_valid(fetch_decode_valid),
        .fetch_decode_inst(fetch_decode_inst),
        .fetch_decode_pc(fetch_decode_pc),
        .fetch_decode_warp_id(fetch_decode_warp_id),
        .fetch_decode_active_mask(fetch_decode_active_mask),
        .fetch_decode_ready(fetch_decode_ready),
        .pc_update_valid(pc_update_valid),
        .pc_update_warp_id(pc_update_warp_id),
        .pc_update_pc(pc_update_pc),
        .branch_pred_req_valid(),
        .branch_pred_pc(),
        .branch_pred_taken(1'b0),
        .branch_pred_target(64'h0),
        .pipeline_stall(pipeline_stall),
        .pipeline_flush(pipeline_flush)
    );
    
    rvgpu_sm_decode_stage #(
        .WARP_COUNT(WARP_COUNT),
        .THREAD_COUNT(MAX_THREAD_PER_WARP)
    ) u_decode_stage (
        .clk(clk),
        .rst_n(rst_n),
        .fetch_decode_valid(fetch_decode_valid),
        .fetch_decode_inst(fetch_decode_inst),
        .fetch_decode_pc(fetch_decode_pc),
        .fetch_decode_warp_id(fetch_decode_warp_id),
        .fetch_decode_active_mask(fetch_decode_active_mask),
        .fetch_decode_ready(fetch_decode_ready),
        .decode_exec_valid(decode_valid),
        .decode_exec_inst(decode_inst),
        .decode_exec_pc(decode_pc),
        .decode_exec_warp_id(decode_warp_id),
        .decode_exec_active_mask(decode_active_mask),
        .decode_exec_rs1(decode_rs1),
        .decode_exec_rs2(decode_rs2),
        .decode_exec_rs3(decode_rs3),
        .decode_exec_rd(decode_rd),
        .decode_exec_imm(decode_imm),
        .decode_exec_is_alu(decode_is_alu),
        .decode_exec_is_fpu(decode_is_fpu),
        .decode_exec_is_tensor(decode_is_tensor),
        .decode_exec_is_branch(decode_is_branch),
        .decode_exec_is_jump(decode_is_jump),
        .decode_exec_is_load(decode_is_load),
        .decode_exec_is_store(decode_is_store),
        .decode_exec_is_barrier(decode_is_barrier),
        .decode_exec_alu_op(decode_alu_op),
        .decode_exec_fpu_op(decode_fpu_op),
        .decode_exec_tensor_op(decode_tensor_op),
        .decode_exec_branch_op(decode_branch_op),
        .decode_exec_reg_write(decode_reg_write),
        .decode_exec_use_imm(decode_use_imm),
        .decode_exec_is_32bit(decode_is_32bit),
        .decode_exec_ready(decode_ready),
        .pipeline_stall(pipeline_stall),
        .pipeline_flush(pipeline_flush)
    );
    
    // =========================================================================
    // CUDA Core选择逻辑
    // =========================================================================
    
    // 简单轮询选择可用的CUDA Core
    always_comb begin
        selected_cuda_core = 0;
        for (int i = 0; i < NUM_CUDA_CORES; i++) begin
            if (cuda_core_dispatch_ready[i]) begin
                selected_cuda_core = i[$clog2(NUM_CUDA_CORES)-1:0];
                break;
            end
        end
    end
    
    // CUDA Core分发控制
    always_comb begin
        for (int i = 0; i < NUM_CUDA_CORES; i++) begin
            cuda_core_dispatch_valid[i] = decode_valid && 
                                         (selected_cuda_core == i) && 
                                         cuda_core_dispatch_ready[i];
        end
        
        decode_ready = cuda_core_dispatch_ready[selected_cuda_core];
    end
    
    // =========================================================================
    // 4个CUDA Core单元实例化
    // =========================================================================
    
    genvar i;
    generate
        for (i = 0; i < NUM_CUDA_CORES; i++) begin : cuda_core_gen
            rvgpu_sm_cuda_core_unit #(
                .CORE_ID(i),
                .WARP_COUNT(WARP_COUNT),
                .THREAD_COUNT(MAX_THREAD_PER_WARP)
            ) u_cuda_core_unit (
                .clk(clk),
                .rst_n(rst_n),
                
                // Warp分发接口
                .warp_dispatch_valid(cuda_core_dispatch_valid[i]),
                .warp_dispatch_inst(decode_inst),
                .warp_dispatch_pc(decode_pc),
                .warp_dispatch_warp_id(decode_warp_id),
                .warp_dispatch_active_mask(decode_active_mask),
                .warp_dispatch_rs1(decode_rs1),
                .warp_dispatch_rs2(decode_rs2),
                .warp_dispatch_rs3(decode_rs3),
                .warp_dispatch_rd(decode_rd),
                .warp_dispatch_imm(decode_imm),
                .warp_dispatch_is_alu(decode_is_alu),
                .warp_dispatch_is_fpu(decode_is_fpu),
                .warp_dispatch_is_tensor(decode_is_tensor),
                .warp_dispatch_is_branch(decode_is_branch),
                .warp_dispatch_is_jump(decode_is_jump),
                .warp_dispatch_is_load(decode_is_load),
                .warp_dispatch_is_store(decode_is_store),
                .warp_dispatch_is_barrier(decode_is_barrier),
                .warp_dispatch_alu_op(decode_alu_op),
                .warp_dispatch_fpu_op(decode_fpu_op),
                .warp_dispatch_tensor_op(decode_tensor_op),
                .warp_dispatch_branch_op(decode_branch_op),
                .warp_dispatch_reg_write(decode_reg_write),
                .warp_dispatch_use_imm(decode_use_imm),
                .warp_dispatch_is_32bit(decode_is_32bit),
                .warp_dispatch_ready(cuda_core_dispatch_ready[i]),
                
                // 寄存器文件接口
                .reg_read_enable(reg_read_enable[i]),
                .reg_read_warp_id(reg_read_warp_id[i]),
                .reg_read_addr(reg_read_addr[i]),
                .reg_read_data(reg_read_data[i]),
                .reg_write_enable(reg_write_enable[i]),
                .reg_write_warp_id(reg_write_warp_id[i]),
                .reg_write_addr(reg_write_addr[i]),
                .reg_write_data(reg_write_data[i]),
                .reg_write_mask(reg_write_mask[i]),
                
                // L1 Data Cache接口 (替换原来的LDST接口)
                .l1_data_req_valid(l1_data_req_valid[i]),
                .l1_data_req_warp_id(l1_data_req_warp_id[i]),
                .l1_data_req_mask(l1_data_req_mask[i]),
                .l1_data_req_addr(l1_data_req_addr[i]),
                .l1_data_req_data(l1_data_req_data[i]),
                .l1_data_req_size(l1_data_req_size[i]),
                .l1_data_req_is_load(l1_data_req_is_load[i]),
                .l1_data_req_is_shared(l1_data_req_is_shared[i]),
                .l1_data_req_ready(l1_data_req_ready[i]),
                .l1_data_resp_valid(l1_data_resp_valid[i]),
                .l1_data_resp_warp_id(l1_data_resp_warp_id[i]),
                .l1_data_resp_mask(l1_data_resp_mask[i]),
                .l1_data_resp_data(l1_data_resp_data[i]),
                .l1_data_resp_ready(l1_data_resp_ready[i]),
                
                // 完成和反馈信号
                .warp_complete(cuda_core_complete[i]),
                .warp_complete_id(cuda_core_complete_id[i]),
                .branch_feedback_valid(cuda_core_branch_feedback_valid[i]),
                .branch_feedback_pc(cuda_core_branch_feedback_pc[i]),
                .branch_feedback_taken(cuda_core_branch_feedback_taken[i]),
                .branch_feedback_target(cuda_core_branch_feedback_target[i]),
                
                // 流水线控制
                .pipeline_stall(pipeline_stall),
                .pipeline_flush(pipeline_flush)
            );
        end
    endgenerate
    
    // =========================================================================
    // LDST单元仲裁 (简化实现)
    // =========================================================================
    
    // 简单优先级仲裁：CUDA Core 0 > 1 > 2 > 3
    always_comb begin
        // 默认值
        ldst_if.req_valid = 1'b0;
        ldst_if.req_warp_id = '0;
        ldst_if.req_mask = '0;
        ldst_if.req_addr = '0;
        ldst_if.req_data = '0;
        ldst_if.req_size = '0;
        
        for (int i = 0; i < NUM_CUDA_CORES; i++) begin
            ldst_req_ready[i] = 1'b0;
        end
        
        // 仲裁逻辑
        for (int i = 0; i < NUM_CUDA_CORES; i++) begin
            if (ldst_req_valid[i]) begin
                ldst_if.req_valid = 1'b1;
                ldst_if.req_warp_id = ldst_req_warp_id[i];
                ldst_if.req_mask = ldst_req_mask[i];
                ldst_if.req_addr = ldst_req_addr[i];
                ldst_if.req_data = ldst_req_data[i];
                ldst_if.req_size = ldst_req_size[i];
                ldst_req_ready[i] = ldst_if.req_ready;
                break;
            end
        end
        
        // 响应分发
        for (int i = 0; i < NUM_CUDA_CORES; i++) begin
            ldst_resp_valid[i] = ldst_if.resp_valid;
            ldst_resp_warp_id[i] = ldst_if.resp_warp_id;
            ldst_resp_data[i] = ldst_if.resp_data;
        end
        
        ldst_if.resp_ready = |ldst_resp_ready;
    end
    
    // =========================================================================
    // Warp状态管理和控制逻辑
    // =========================================================================
    
    // Warp状态更新
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < WARP_COUNT; i++) begin
                warp_pc[i] <= '0;
                warp_active_mask[i] <= '0;
            end
            warp_valid <= '0;
            warp_stalled <= '0;
            warp_barrier <= '0;
            warp_waiting <= '0;
        end else begin
            // PC更新
            if (pc_update_valid) begin
                warp_pc[pc_update_warp_id] <= pc_update_pc;
            end
            
            // 分支反馈处理
            for (int i = 0; i < NUM_CUDA_CORES; i++) begin
                if (cuda_core_branch_feedback_valid[i] && cuda_core_branch_feedback_taken[i]) begin
                    warp_pc[cuda_core_complete_id[i]] <= cuda_core_branch_feedback_target[i];
                end
            end
            
            // 新warp分配
            if (block_dispatch_if.warp_valid && warp_alloc_ready) begin
                warp_valid[warp_alloc_id] <= 1'b1;
            end
            
            // Warp完成处理
            for (int i = 0; i < NUM_CUDA_CORES; i++) begin
                if (cuda_core_complete[i]) begin
                    warp_valid[cuda_core_complete_id[i]] <= 1'b0;
                end
            end
            
            // 简化状态更新
            warp_stalled <= '0;
            warp_barrier <= '0;
            warp_waiting <= '0;
        end
    end
    
    // 新warp分配逻辑
    assign new_warp_valid = block_dispatch_if.warp_valid && !warp_scheduler_full;
    assign new_warp_id = warp_alloc_id;
    assign block_dispatch_if.warp_ready = warp_alloc_ready;
    
    // Warp分配/释放
    assign warp_alloc_valid = block_dispatch_if.warp_valid;
    assign warp_dealloc_valid = |cuda_core_complete;
    assign warp_dealloc_id = cuda_core_complete[0] ? cuda_core_complete_id[0] :
                            cuda_core_complete[1] ? cuda_core_complete_id[1] :
                            cuda_core_complete[2] ? cuda_core_complete_id[2] :
                            cuda_core_complete_id[3];
    
    // 完成信号输出
    assign warp_complete = |cuda_core_complete;
    assign warp_id = {24'b0, warp_dealloc_id};
    
    // 流水线控制
    assign pipeline_stall = 1'b0; // 简化实现
    assign pipeline_flush = 1'b0; // 简化实现
    assign scheduler_stall = pipeline_stall || !decode_ready;
    
    // L1.5 Cache接口连接 (指令获取)
    assign l15_if.req_is_read = 1'b1;
    assign l15_if.req_type = 4'b0000; // 普通访问
    assign l15_if.req_data = '0;
    assign l15_if.req_mask = '0;
    assign l15_if.flush = 1'b0;

endmodule : rvgpu_sm

`endif // RVGPU_SM_SV 