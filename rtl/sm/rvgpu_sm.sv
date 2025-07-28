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
    
    // TLB接口
    mmu_if.requester_port tlb_if,
    
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
    // 扁平化声明，避免复杂的数组连接
    logic [11:0] reg_read_enable_flat;  // 12个读端口 (4 cores * 3 ports)
    logic [$clog2(WARP_COUNT)-1:0] reg_read_warp_id_flat[12];
    logic [4:0] reg_read_addr_flat[12];
    logic [31:0] reg_read_data[NUM_CUDA_CORES][3][MAX_THREAD_PER_WARP];
    
    // 寄存器文件连接用的中间信号
    logic [31:0] reg_file_read_data[3*NUM_CUDA_CORES][MAX_THREAD_PER_WARP];
    
    logic [3:0] reg_write_enable_flat;  // 4个写端口
    logic [$clog2(WARP_COUNT)-1:0] reg_write_warp_id_flat[4];
    logic [4:0] reg_write_addr_flat[4];
    logic [31:0] reg_write_data_flat[4][MAX_THREAD_PER_WARP];
    logic [MAX_THREAD_PER_WARP-1:0] reg_write_mask_flat[4];
    
    // CUDA Core寄存器接口信号
    logic reg_read_enable_core[NUM_CUDA_CORES][3];
    logic [$clog2(WARP_COUNT)-1:0] reg_read_warp_id_core[NUM_CUDA_CORES][3];
    logic [4:0] reg_read_addr_core[NUM_CUDA_CORES][3];
    
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
    
    // L1 Data Cache/Shared Memory信号 - 使用简单结构
    logic l1_data_req_valid_0, l1_data_req_valid_1, l1_data_req_valid_2, l1_data_req_valid_3;
    logic [$clog2(WARP_COUNT)-1:0] l1_data_req_warp_id_0, l1_data_req_warp_id_1, l1_data_req_warp_id_2, l1_data_req_warp_id_3;
    logic [MAX_THREAD_PER_WARP-1:0] l1_data_req_mask_0, l1_data_req_mask_1, l1_data_req_mask_2, l1_data_req_mask_3;
    logic [63:0] l1_data_req_addr_0[MAX_THREAD_PER_WARP];
    logic [63:0] l1_data_req_addr_1[MAX_THREAD_PER_WARP];
    logic [63:0] l1_data_req_addr_2[MAX_THREAD_PER_WARP];
    logic [63:0] l1_data_req_addr_3[MAX_THREAD_PER_WARP];
    logic [31:0] l1_data_req_data_0[MAX_THREAD_PER_WARP];
    logic [31:0] l1_data_req_data_1[MAX_THREAD_PER_WARP];
    logic [31:0] l1_data_req_data_2[MAX_THREAD_PER_WARP];
    logic [31:0] l1_data_req_data_3[MAX_THREAD_PER_WARP];
    logic [2:0] l1_data_req_size_0, l1_data_req_size_1, l1_data_req_size_2, l1_data_req_size_3;
    logic l1_data_req_is_load_0, l1_data_req_is_load_1, l1_data_req_is_load_2, l1_data_req_is_load_3;
    logic l1_data_req_is_shared_0, l1_data_req_is_shared_1, l1_data_req_is_shared_2, l1_data_req_is_shared_3;
    logic l1_data_req_ready_0, l1_data_req_ready_1, l1_data_req_ready_2, l1_data_req_ready_3;
    
    logic l1_data_resp_valid_0, l1_data_resp_valid_1, l1_data_resp_valid_2, l1_data_resp_valid_3;
    logic [$clog2(WARP_COUNT)-1:0] l1_data_resp_warp_id_0;
    logic [$clog2(WARP_COUNT)-1:0] l1_data_resp_warp_id_1;
    logic [$clog2(WARP_COUNT)-1:0] l1_data_resp_warp_id_2;
    logic [$clog2(WARP_COUNT)-1:0] l1_data_resp_warp_id_3;
    logic [MAX_THREAD_PER_WARP-1:0] l1_data_resp_mask_0;
    logic [MAX_THREAD_PER_WARP-1:0] l1_data_resp_mask_1;
    logic [MAX_THREAD_PER_WARP-1:0] l1_data_resp_mask_2;
    logic [MAX_THREAD_PER_WARP-1:0] l1_data_resp_mask_3;
    logic [31:0] l1_data_resp_data_0[MAX_THREAD_PER_WARP];
    logic [31:0] l1_data_resp_data_1[MAX_THREAD_PER_WARP];
    logic [31:0] l1_data_resp_data_2[MAX_THREAD_PER_WARP];
    logic [31:0] l1_data_resp_data_3[MAX_THREAD_PER_WARP];
    logic l1_data_resp_ready_0, l1_data_resp_ready_1, l1_data_resp_ready_2, l1_data_resp_ready_3;
    
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
        .l1_resp_data(l15_if.resp_data[255:0]),
        .l1_resp_ready(l15_if.resp_ready),
        .tlb_req_valid(tlb_if.req_valid),
        .tlb_req_vaddr(tlb_if.req_vaddr),
        .tlb_req_type(tlb_if.req_type),
        .tlb_req_ready(tlb_if.req_ready),
        .tlb_resp_valid(tlb_if.resp_valid),
        .tlb_resp_hit(tlb_if.resp_hit),
        .tlb_resp_ppn(tlb_if.resp_paddr[38:12]),  // 从resp_paddr提取PPN
        .tlb_resp_fault(tlb_if.resp_status != MMU_RESP_OKAY)  // 使用MMU状态码
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
        .req_valid({l1_data_req_valid_3, l1_data_req_valid_2, l1_data_req_valid_1, l1_data_req_valid_0}),
        .req_warp_id({l1_data_req_warp_id_3, l1_data_req_warp_id_2, l1_data_req_warp_id_1, l1_data_req_warp_id_0}),
        .req_mask({l1_data_req_mask_3, l1_data_req_mask_2, l1_data_req_mask_1, l1_data_req_mask_0}),
        .req_addr({l1_data_req_addr_3, l1_data_req_addr_2, l1_data_req_addr_1, l1_data_req_addr_0}),
        .req_data({l1_data_req_data_3, l1_data_req_data_2, l1_data_req_data_1, l1_data_req_data_0}),
        .req_size({l1_data_req_size_3, l1_data_req_size_2, l1_data_req_size_1, l1_data_req_size_0}),
        .req_is_load({l1_data_req_is_load_3, l1_data_req_is_load_2, l1_data_req_is_load_1, l1_data_req_is_load_0}),
        .req_is_shared({l1_data_req_is_shared_3, l1_data_req_is_shared_2, l1_data_req_is_shared_1, l1_data_req_is_shared_0}),
        .req_ready('{l1_data_req_ready_3, l1_data_req_ready_2, l1_data_req_ready_1, l1_data_req_ready_0}),
        
        .resp_valid('{l1_data_resp_valid_3, l1_data_resp_valid_2, l1_data_resp_valid_1, l1_data_resp_valid_0}),
        .resp_warp_id('{l1_data_resp_warp_id_3, l1_data_resp_warp_id_2, l1_data_resp_warp_id_1, l1_data_resp_warp_id_0}),
        .resp_mask('{l1_data_resp_mask_3, l1_data_resp_mask_2, l1_data_resp_mask_1, l1_data_resp_mask_0}),
        .resp_data('{l1_data_resp_data_3, l1_data_resp_data_2, l1_data_resp_data_1, l1_data_resp_data_0}),
        .resp_ready({l1_data_resp_ready_3, l1_data_resp_ready_2, l1_data_resp_ready_1, l1_data_resp_ready_0}),
        
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
        .scheduler_stall(1'b0), // 暂时设为0，简化处理
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
        .read_enable(reg_read_enable_flat),
        .read_warp_id(reg_read_warp_id_flat),
        .read_reg_addr(reg_read_addr_flat),
        .read_data(reg_file_read_data),
        .write_enable(reg_write_enable_flat),
        .write_warp_id(reg_write_warp_id_flat),
        .write_reg_addr(reg_write_addr_flat),
        .write_data(reg_write_data_flat),
        .write_mask(reg_write_mask_flat),
        .warp_alloc_valid(warp_alloc_valid),
        .warp_alloc_id(warp_alloc_id),
        .warp_alloc_ready(warp_alloc_ready),
        .warp_dealloc_valid(warp_dealloc_valid),
        .warp_dealloc_id(warp_dealloc_id),
        .warp_allocated(warp_allocated),
        .allocated_warp_count(allocated_warp_count)
    );
    
    // 重新组织寄存器文件输出数据
    always_comb begin
        for (int core = 0; core < NUM_CUDA_CORES; core++) begin
            for (int port = 0; port < 3; port++) begin
                for (int thread = 0; thread < MAX_THREAD_PER_WARP; thread++) begin
                    reg_read_data[core][port][thread] = reg_file_read_data[core * 3 + port][thread];
                end
            end
        end
    end
    
    // 管理扁平化信号和分组信号之间的转换
    always_comb begin
        // 从扁平化信号到寄存器文件信号
        for (int core = 0; core < NUM_CUDA_CORES; core++) begin
            for (int port = 0; port < 3; port++) begin
                reg_read_enable_flat[core*3 + port] = reg_read_enable_core[core][port];
                reg_read_warp_id_flat[core*3 + port] = reg_read_warp_id_core[core][port];
                reg_read_addr_flat[core*3 + port] = reg_read_addr_core[core][port];
            end
        end
    end
    
    // L1 Data Cache输出端口连接 - 简化处理
    // always_comb begin
    //     // 这些信号由u_l1_data_cache模块驱动，不需要在这里初始化
    //     // 移除所有对l1_data_req_ready和l1_data_resp信号的驱动
    // end
    
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
        if (cuda_core_dispatch_ready[0]) begin
            selected_cuda_core = 0;
        end else if (cuda_core_dispatch_ready[1]) begin
            selected_cuda_core = 1;
        end else if (cuda_core_dispatch_ready[2]) begin
            selected_cuda_core = 2;
        end else if (cuda_core_dispatch_ready[3]) begin
            selected_cuda_core = 3;
        end
    end
    
    // CUDA Core分发控制
    always_comb begin
        cuda_core_dispatch_valid[0] = decode_valid && (selected_cuda_core == 0) && cuda_core_dispatch_ready[0];
        cuda_core_dispatch_valid[1] = decode_valid && (selected_cuda_core == 1) && cuda_core_dispatch_ready[1];
        cuda_core_dispatch_valid[2] = decode_valid && (selected_cuda_core == 2) && cuda_core_dispatch_ready[2];
        cuda_core_dispatch_valid[3] = decode_valid && (selected_cuda_core == 3) && cuda_core_dispatch_ready[3];
        
        decode_ready = cuda_core_dispatch_ready[selected_cuda_core];
    end
    
    // =========================================================================
    // 4个CUDA Core单元实例化
    // =========================================================================
    
    // CUDA Core实例化
    generate
        for (genvar i = 0; i < NUM_CUDA_CORES; i++) begin : cuda_core_gen
            rvgpu_sm_cuda_core_unit #(
                .CORE_ID(i),
                .WARP_COUNT(WARP_COUNT),
                .THREAD_COUNT(MAX_THREAD_PER_WARP)
            ) u_cuda_core_unit (
                .clk(clk),
                .rst_n(rst_n),
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
                .reg_read_enable(reg_read_enable_core[i]),
                .reg_read_warp_id(reg_read_warp_id_core[i]),
                .reg_read_addr(reg_read_addr_core[i]),
                .reg_read_data(reg_read_data[i]),
                .reg_write_enable(reg_write_enable_flat[i]),
                .reg_write_warp_id(reg_write_warp_id_flat[i]),
                .reg_write_addr(reg_write_addr_flat[i]),
                .reg_write_data(reg_write_data_flat[i]),
                .reg_write_mask(reg_write_mask_flat[i]),
                
                // L1 Data Cache接口 - 输入端口
                .l1_data_req_ready(i == 0 ? l1_data_req_ready_0 : i == 1 ? l1_data_req_ready_1 : i == 2 ? l1_data_req_ready_2 : l1_data_req_ready_3),
                .l1_data_resp_valid(i == 0 ? l1_data_resp_valid_0 : i == 1 ? l1_data_resp_valid_1 : i == 2 ? l1_data_resp_valid_2 : l1_data_resp_valid_3),
                .l1_data_resp_warp_id(i == 0 ? l1_data_resp_warp_id_0 : i == 1 ? l1_data_resp_warp_id_1 : i == 2 ? l1_data_resp_warp_id_2 : l1_data_resp_warp_id_3),
                .l1_data_resp_mask(i == 0 ? l1_data_resp_mask_0 : i == 1 ? l1_data_resp_mask_1 : i == 2 ? l1_data_resp_mask_2 : l1_data_resp_mask_3),
                .l1_data_resp_data(i == 0 ? l1_data_resp_data_0 : i == 1 ? l1_data_resp_data_1 : i == 2 ? l1_data_resp_data_2 : l1_data_resp_data_3),
                
                // L1 Data Cache接口 - 输出端口 (保持未连接，由always_comb块驱动)
                .l1_data_req_valid(),
                .l1_data_req_warp_id(),
                .l1_data_req_mask(),
                .l1_data_req_addr(),
                .l1_data_req_data(),
                .l1_data_req_size(),
                .l1_data_req_is_load(),
                .l1_data_req_is_shared(),
                .l1_data_resp_ready(),
                
                // 完成信号
                .warp_complete(cuda_core_complete[i]),
                .warp_complete_id(cuda_core_complete_id[i]),
                
                // 分支反馈
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
    
    // L1 Data Cache输出端口初始化
    always_comb begin
        // 初始化所有l1_data_req_*信号
        l1_data_req_valid_0 = 1'b0;
        l1_data_req_valid_1 = 1'b0;
        l1_data_req_valid_2 = 1'b0;
        l1_data_req_valid_3 = 1'b0;
        l1_data_req_warp_id_0 = '0;
        l1_data_req_warp_id_1 = '0;
        l1_data_req_warp_id_2 = '0;
        l1_data_req_warp_id_3 = '0;
        l1_data_req_mask_0 = '0;
        l1_data_req_mask_1 = '0;
        l1_data_req_mask_2 = '0;
        l1_data_req_mask_3 = '0;
        l1_data_req_size_0 = '0;
        l1_data_req_size_1 = '0;
        l1_data_req_size_2 = '0;
        l1_data_req_size_3 = '0;
        l1_data_req_is_load_0 = 1'b0;
        l1_data_req_is_load_1 = 1'b0;
        l1_data_req_is_load_2 = 1'b0;
        l1_data_req_is_load_3 = 1'b0;
        l1_data_req_is_shared_0 = 1'b0;
        l1_data_req_is_shared_1 = 1'b0;
        l1_data_req_is_shared_2 = 1'b0;
        l1_data_req_is_shared_3 = 1'b0;
        l1_data_resp_ready_0 = 1'b0;
        l1_data_resp_ready_1 = 1'b0;
        l1_data_resp_ready_2 = 1'b0;
        l1_data_resp_ready_3 = 1'b0;
        
        // 初始化数组
        for (int thread = 0; thread < MAX_THREAD_PER_WARP; thread++) begin
            l1_data_req_addr_0[thread] = '0;
            l1_data_req_addr_1[thread] = '0;
            l1_data_req_addr_2[thread] = '0;
            l1_data_req_addr_3[thread] = '0;
            l1_data_req_data_0[thread] = '0;
            l1_data_req_data_1[thread] = '0;
            l1_data_req_data_2[thread] = '0;
            l1_data_req_data_3[thread] = '0;
        end
    end
    
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
        
        ldst_req_ready[0] = 1'b0;
        ldst_req_ready[1] = 1'b0;
        ldst_req_ready[2] = 1'b0;
        ldst_req_ready[3] = 1'b0;
        
        // 仲裁逻辑
        if (ldst_req_valid[0]) begin
            ldst_if.req_valid = 1'b1;
            ldst_if.req_warp_id = ldst_req_warp_id[0];
            ldst_if.req_mask = ldst_req_mask[0];
            ldst_if.req_addr = ldst_req_addr[0][0];
            ldst_if.req_data = {ldst_req_data[0][15], ldst_req_data[0][14], ldst_req_data[0][13], ldst_req_data[0][12], 
                                ldst_req_data[0][11], ldst_req_data[0][10], ldst_req_data[0][9], ldst_req_data[0][8],
                                ldst_req_data[0][7], ldst_req_data[0][6], ldst_req_data[0][5], ldst_req_data[0][4],
                                ldst_req_data[0][3], ldst_req_data[0][2], ldst_req_data[0][1], ldst_req_data[0][0]};
            ldst_if.req_size = ldst_req_size[0];
            ldst_req_ready[0] = ldst_if.req_ready;
        end else if (ldst_req_valid[1]) begin
            ldst_if.req_valid = 1'b1;
            ldst_if.req_warp_id = ldst_req_warp_id[1];
            ldst_if.req_mask = ldst_req_mask[1];
            ldst_if.req_addr = ldst_req_addr[1][0];
            ldst_if.req_data = {ldst_req_data[1][15], ldst_req_data[1][14], ldst_req_data[1][13], ldst_req_data[1][12], 
                                ldst_req_data[1][11], ldst_req_data[1][10], ldst_req_data[1][9], ldst_req_data[1][8],
                                ldst_req_data[1][7], ldst_req_data[1][6], ldst_req_data[1][5], ldst_req_data[1][4],
                                ldst_req_data[1][3], ldst_req_data[1][2], ldst_req_data[1][1], ldst_req_data[1][0]};
            ldst_if.req_size = ldst_req_size[1];
            ldst_req_ready[1] = ldst_if.req_ready;
        end else if (ldst_req_valid[2]) begin
            ldst_if.req_valid = 1'b1;
            ldst_if.req_warp_id = ldst_req_warp_id[2];
            ldst_if.req_mask = ldst_req_mask[2];
            ldst_if.req_addr = ldst_req_addr[2][0];
            ldst_if.req_data = {ldst_req_data[2][15], ldst_req_data[2][14], ldst_req_data[2][13], ldst_req_data[2][12], 
                                ldst_req_data[2][11], ldst_req_data[2][10], ldst_req_data[2][9], ldst_req_data[2][8],
                                ldst_req_data[2][7], ldst_req_data[2][6], ldst_req_data[2][5], ldst_req_data[2][4],
                                ldst_req_data[2][3], ldst_req_data[2][2], ldst_req_data[2][1], ldst_req_data[2][0]};
            ldst_if.req_size = ldst_req_size[2];
            ldst_req_ready[2] = ldst_if.req_ready;
        end else if (ldst_req_valid[3]) begin
            ldst_if.req_valid = 1'b1;
            ldst_if.req_warp_id = ldst_req_warp_id[3];
            ldst_if.req_mask = ldst_req_mask[3];
            ldst_if.req_addr = ldst_req_addr[3][0];
            ldst_if.req_data = {ldst_req_data[3][15], ldst_req_data[3][14], ldst_req_data[3][13], ldst_req_data[3][12], 
                                ldst_req_data[3][11], ldst_req_data[3][10], ldst_req_data[3][9], ldst_req_data[3][8],
                                ldst_req_data[3][7], ldst_req_data[3][6], ldst_req_data[3][5], ldst_req_data[3][4],
                                ldst_req_data[3][3], ldst_req_data[3][2], ldst_req_data[3][1], ldst_req_data[3][0]};
            ldst_if.req_size = ldst_req_size[3];
            ldst_req_ready[3] = ldst_if.req_ready;
        end
        
        // 响应分发
        ldst_resp_valid[0] = ldst_if.resp_valid;
        ldst_resp_warp_id[0] = ldst_if.resp_warp_id;
        ldst_resp_data[0] = ldst_if.resp_data;
        ldst_resp_valid[1] = ldst_if.resp_valid;
        ldst_resp_warp_id[1] = ldst_if.resp_warp_id;
        ldst_resp_data[1] = ldst_if.resp_data;
        ldst_resp_valid[2] = ldst_if.resp_valid;
        ldst_resp_warp_id[2] = ldst_if.resp_warp_id;
        ldst_resp_data[2] = ldst_if.resp_data;
        ldst_resp_valid[3] = ldst_if.resp_valid;
        ldst_resp_warp_id[3] = ldst_if.resp_warp_id;
        ldst_resp_data[3] = ldst_if.resp_data;
        
        ldst_if.resp_ready = ldst_resp_ready[0] || ldst_resp_ready[1] || ldst_resp_ready[2] || ldst_resp_ready[3];
    end
    
    // =========================================================================
    // Warp状态管理和控制逻辑
    // =========================================================================
    
    // Warp状态更新
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 初始化前几个warp - 简化处理
            warp_pc[0] <= '0;
            warp_pc[1] <= '0;
            warp_pc[2] <= '0;
            warp_pc[3] <= '0;
            warp_active_mask[0] <= '0;
            warp_active_mask[1] <= '0;
            warp_active_mask[2] <= '0;
            warp_active_mask[3] <= '0;
            warp_valid <= '0;
            warp_stalled <= '0;
            warp_barrier <= '0;
            warp_waiting <= '0;
        end else begin
            // PC更新
            if (pc_update_valid) begin
                warp_pc[pc_update_warp_id] <= pc_update_pc;
            end
            
            // 分支反馈处理 - 简化处理
            if (cuda_core_branch_feedback_valid[0] && cuda_core_branch_feedback_taken[0]) begin
                warp_pc[cuda_core_complete_id[0]] <= cuda_core_branch_feedback_target[0];
            end else if (cuda_core_branch_feedback_valid[1] && cuda_core_branch_feedback_taken[1]) begin
                warp_pc[cuda_core_complete_id[1]] <= cuda_core_branch_feedback_target[1];
            end else if (cuda_core_branch_feedback_valid[2] && cuda_core_branch_feedback_taken[2]) begin
                warp_pc[cuda_core_complete_id[2]] <= cuda_core_branch_feedback_target[2];
            end else if (cuda_core_branch_feedback_valid[3] && cuda_core_branch_feedback_taken[3]) begin
                warp_pc[cuda_core_complete_id[3]] <= cuda_core_branch_feedback_target[3];
            end
            
            // 新warp分配
            if (block_dispatch_if.warp_valid && warp_alloc_ready) begin
                warp_valid[warp_alloc_id] <= 1'b1;
            end
            
            // Warp完成处理 - 简化处理
            if (cuda_core_complete[0]) begin
                warp_valid[cuda_core_complete_id[0]] <= 1'b0;
            end else if (cuda_core_complete[1]) begin
                warp_valid[cuda_core_complete_id[1]] <= 1'b0;
            end else if (cuda_core_complete[2]) begin
                warp_valid[cuda_core_complete_id[2]] <= 1'b0;
            end else if (cuda_core_complete[3]) begin
                warp_valid[cuda_core_complete_id[3]] <= 1'b0;
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
    assign warp_dealloc_valid = cuda_core_complete[0] || cuda_core_complete[1] || cuda_core_complete[2] || cuda_core_complete[3];
    assign warp_dealloc_id = cuda_core_complete[0] ? cuda_core_complete_id[0] :
                            cuda_core_complete[1] ? cuda_core_complete_id[1] :
                            cuda_core_complete[2] ? cuda_core_complete_id[2] :
                            cuda_core_complete_id[3];
    
    // 完成信号输出
    assign warp_complete = cuda_core_complete[0] || cuda_core_complete[1] || cuda_core_complete[2] || cuda_core_complete[3];
    assign warp_id = {24'b0, warp_dealloc_id};
    
    // 流水线控制
    assign pipeline_stall = 1'b0; // 简化实现
    assign pipeline_flush = 1'b0; // 简化实现
    // scheduler_stall = pipeline_stall || !decode_ready; // 移除此行
    
    // L1.5 Cache接口连接 (指令获取)
    assign l15_if.req_is_read = 1'b1;
    assign l15_if.req_type = 4'b0000; // 普通访问
    assign l15_if.req_data = '0;
    assign l15_if.req_mask = '0;
    assign l15_if.flush = 1'b0;

endmodule : rvgpu_sm

`endif // RVGPU_SM_SV 