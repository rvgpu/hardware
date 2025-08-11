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
`include "gpc_block_tpc_if.svh"
`include "ldst_sm_if.svh"
`include "interface_l15cache.svh"
`include "rvgpu_mmu_if.svh"
`include "interface_sm_fetch_decode.svh"
`include "interface_sm_decode_exec.svh"
`include "interface_sm_regfile.svh"
`include "interface_sm_exec_mem.svh"
`include "interface_sm_mem_wb.svh"
`include "interface_sm_l1data.svh"
`include "interface_sm_warp_dispatch.svh"
`include "interface_sm_regfile_access.svh"
`include "interface_sm_tlb.svh"
`include "interface_sm_l15data_reqresp.svh"
`include "interface_sm_ldst.svh"

module rvgpu_sm_top #(
    parameter int SM_ID = 0,                    // SM ID
    parameter int WARP_COUNT = 32,              // 每个SM支持的warp数量
    parameter int MAX_THREAD_PER_WARP = 32,     // 每个warp的最大线程数
    parameter int MAX_ACTIVE_WARPS = 16,        // 同时活跃的最大warp数量
    parameter int NUM_CUDA_CORES = 4,           // CUDA Core数量
    parameter int THREAD_COUNT = 1024           // 每个SM的总线程数
) (
    input  logic clk,
    input  logic rst_n,
    
    // 路由器接口 - 新增
    interface_gpc_router.up_port router_if,
    
    // TPC接口
    gpc_block_tpc_if.sm block_dispatch_if,
    
    // LDST接口
    ldst_sm_if.sm ldst_if,
    
    // L1.5 Cache接口 (用于指令获取)
    interface_l15cache.requester l15_icache_if,
    
    // TLB接口
    mmu_if.requester_port tlb_if,
    
    // 完成信号
    output logic warp_complete,
    output logic [31:0] warp_id
);

    // =========================================================================
    // 内部信号声明
    // =========================================================================
    
    // Warp状态接口实例
    interface_sm_warp_state #(
        .WARP_COUNT(WARP_COUNT),
        .THREAD_COUNT(MAX_THREAD_PER_WARP)
    ) if_warp_state();
    // 迁移到 if_warp_state 接口字段：warp_stalled/warp_barrier/warp_waiting
    
    // SM级Warp调度器信号
    logic warp_schedule_valid;
    logic [$clog2(WARP_COUNT)-1:0] scheduled_warp_id;
    logic scheduler_stall;
    logic new_warp_valid;
    logic [$clog2(WARP_COUNT)-1:0] new_warp_id;
    logic [$clog2(WARP_COUNT):0] active_warp_count;
    logic [$clog2(WARP_COUNT):0] stalled_warp_count;
    logic warp_scheduler_full;
    
    // L0 ICache 接口实例
    interface_sm_icache_fetch ic_if();

    // 接口实例（仅内部桥接，端口保持不变）
    interface_sm_fetch_decode #(
        .WARP_COUNT(WARP_COUNT),
        .THREAD_COUNT(MAX_THREAD_PER_WARP)
    ) if_fd();

    interface_sm_decode_exec #(
        .WARP_COUNT(WARP_COUNT),
        .THREAD_COUNT(MAX_THREAD_PER_WARP)
    ) if_de();

    interface_sm_regfile #(
        .WARP_COUNT(WARP_COUNT),
        .THREAD_COUNT(MAX_THREAD_PER_WARP),
        .READ_PORTS(3*NUM_CUDA_CORES),
        .WRITE_PORTS(NUM_CUDA_CORES)
    ) if_rf();
    
    interface_sm_exec_mem #(
        .WARP_COUNT(WARP_COUNT),
        .THREAD_COUNT(MAX_THREAD_PER_WARP)
    ) if_em();
    
    interface_sm_mem_wb #(
        .WARP_COUNT(WARP_COUNT),
        .THREAD_COUNT(MAX_THREAD_PER_WARP)
    ) if_mw();
    
    // LDST接口实例（用于连接memory stage）
    interface_sm_ldst #(
        .WARP_COUNT(WARP_COUNT),
        .THREAD_COUNT(MAX_THREAD_PER_WARP)
    ) if_ldst();
    
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
    logic [2:0] ldst_req_type[NUM_CUDA_CORES];  // 添加缺失的信号
    logic [4:0] ldst_req_lane_id[NUM_CUDA_CORES];  // 添加缺失的信号
    logic ldst_req_ready[NUM_CUDA_CORES];
    
    logic ldst_resp_valid[NUM_CUDA_CORES];
    logic [31:0] ldst_resp_warp_id[NUM_CUDA_CORES];
    logic [MAX_THREAD_PER_WARP-1:0] ldst_resp_data[NUM_CUDA_CORES];
    logic ldst_resp_ready[NUM_CUDA_CORES];
    
    // PC管理接口实例
    interface_sm_pc_update #(
        .WARP_COUNT(WARP_COUNT)
    ) if_pc_update();
    
    // 流水线控制
    logic pipeline_stall;
    logic pipeline_flush;
    
    // 已接口化L1 Data Cache通道，不需要旧的散列信号声明
    // 指令侧 TLB 接口实例（将 mmu_if 转接为 sm_tlb 接口占位）
    interface_sm_tlb tlb_sm_if();
    // 默认拉线，避免X
    assign tlb_sm_if.req_ready    = 1'b1;
    assign tlb_sm_if.resp_valid   = 1'b0;
    assign tlb_sm_if.resp_hit     = 1'b0;
    assign tlb_sm_if.resp_ppn     = '0;
    assign tlb_sm_if.resp_fault   = 1'b0;
    assign tlb_sm_if.resp_warp_id = '0;
    
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
        .fetch_if(ic_if),
        .l15_if(l15_icache_if),
        .tlb_if(tlb_sm_if)
    );
    
    // =========================================================================
    // SM级L1 Data Cache/Shared Memory实例化
    // =========================================================================

    // 为4个CUDA Core与L1 Data Cache建立接口实例并对接（前置声明，供L1使用）
    interface_sm_l1data #(
        .WARP_COUNT(WARP_COUNT),
        .THREAD_COUNT(MAX_THREAD_PER_WARP)
    ) if_l1_core[4]();

    // 数据侧 L1.5 接口占位实例与默认拉低（前置声明，供L1使用）
    interface_sm_l15data_reqresp #(
        .REQ_DATA_W(512),
        .MASK_W(64),
        .ID_W(32),
        .SIZE_W(4)
    ) if_l15data();
    // 顶层暂未接入真实 L1.5，提供默认就绪/无响应的拉线，避免X
    assign if_l15data.req_ready  = 1'b1;
    assign if_l15data.resp_valid = 1'b0;
    assign if_l15data.resp_data  = '0;
    assign if_l15data.resp_error = 1'b0;
    assign if_l15data.resp_id    = '0;

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
        // CUDA Core接口 - 使用接口数组，直接对接if_l1_core
        .core_l1_if(if_l1_core),
        
        // L1.5 Cache接口 (数据缓存未命中时使用)
        .l15_if(if_l15data),
        
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

    // 调度器 <-> 取指 接口实例（前置声明，避免隐式wire）
    interface_sm_warp_schedule #(
        .WARP_COUNT(WARP_COUNT)
    ) if_sched();

    rvgpu_sm_warp_scheduler #(
        .WARP_COUNT(WARP_COUNT),
        .MAX_ACTIVE_WARPS(MAX_ACTIVE_WARPS),
        .PIPELINE_DEPTH(5)
    ) u_warp_scheduler (
        .clk(clk),
        .rst_n(rst_n),
        .warp_state_if(if_warp_state),
        .scheduler_stall(1'b0), // 简化处理
        .new_warp_id(new_warp_id),
        .new_warp_valid(new_warp_valid),
        .sched_if(if_sched),
        .active_warp_count(active_warp_count),
        .stalled_warp_count(stalled_warp_count),
        .warp_scheduler_full(warp_scheduler_full)
    );
    
    // =========================================================================
    // 共享寄存器文件实例化 (16,384 x 32-bit)
    // =========================================================================
    
    // Warp 管理接口实例
    interface_sm_warp_admin #(
        .WARP_COUNT(WARP_COUNT)
    ) if_warp_admin();

    rvgpu_sm_register_file #(
        .WARP_COUNT(WARP_COUNT),
        .THREAD_COUNT(MAX_THREAD_PER_WARP),
        .REG_COUNT(512),  // 512个寄存器/线程
        .READ_PORTS(3 * NUM_CUDA_CORES),  // 每个CUDA Core 3个读端口
        .WRITE_PORTS(NUM_CUDA_CORES)      // 每个CUDA Core 1个写端口
    ) u_register_file (
        .clk(clk),
        .rst_n(rst_n),
        .rf_if(if_rf),
        .warp_alloc_valid(if_warp_admin.alloc_valid),
        .warp_alloc_id(if_warp_admin.alloc_id),
        .warp_alloc_ready(if_warp_admin.alloc_ready),
        .warp_dealloc_valid(if_warp_admin.dealloc_valid),
        .warp_dealloc_id(if_warp_admin.dealloc_id),
        .warp_allocated(if_warp_admin.allocated_bitmap),
        .allocated_warp_count(if_warp_admin.allocated_count)
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

    // 将现有信号桥接到接口（Regfile数据通道）
    assign if_rf.read_enable   = reg_read_enable_flat;
    assign if_rf.read_warp_id  = reg_read_warp_id_flat;
    assign if_rf.read_reg_addr = reg_read_addr_flat;
    assign reg_file_read_data  = if_rf.read_data;
    assign if_rf.write_enable  = reg_write_enable_flat;
    assign if_rf.write_warp_id = reg_write_warp_id_flat;
    assign if_rf.write_reg_addr= reg_write_addr_flat;
    assign if_rf.write_data    = reg_write_data_flat;
    assign if_rf.write_mask    = reg_write_mask_flat;

    // Warp 管理信号桥接到接口
    assign if_warp_admin.alloc_valid = warp_alloc_valid;
    assign if_warp_admin.alloc_id    = warp_alloc_id;
    assign warp_alloc_ready          = if_warp_admin.alloc_ready;
    assign if_warp_admin.dealloc_valid = warp_dealloc_valid;
    assign if_warp_admin.dealloc_id    = warp_dealloc_id;
    assign warp_allocated            = if_warp_admin.allocated_bitmap;
    assign allocated_warp_count      = if_warp_admin.allocated_count;
    
    // 管理扁平化信号和分组信号之间的转换
    always_comb begin
        for (int core = 0; core < NUM_CUDA_CORES; core++) begin
            for (int port = 0; port < 3; port++) begin
                reg_read_enable_flat[core*3 + port] = reg_read_enable_core[core][port];
                reg_read_warp_id_flat[core*3 + port] = reg_read_warp_id_core[core][port];
                reg_read_addr_flat[core*3 + port] = reg_read_addr_core[core][port];
            end
        end
    end
    
    // =========================================================================
    // 取指和解码阶段实例化
    // =========================================================================
    
    rvgpu_sm_fetch_stage #(
        .WARP_COUNT(WARP_COUNT),
        .THREAD_COUNT(MAX_THREAD_PER_WARP)
    ) u_fetch_stage (
        .clk(clk),
        .rst_n(rst_n),
        .sched_if(if_sched),
        .warp_state_if(if_warp_state),
        .ic_if(ic_if),
        .fd_if(if_fd),
        .pc_update_if(if_pc_update),
        .pipeline_stall(pipeline_stall),
        .pipeline_flush(pipeline_flush)
    );
    
    // 取指就绪回传（以前通过 fetch_ready -> scheduler_stall），现通过接口ready
    assign scheduler_stall = ~if_sched.ready;
    
    rvgpu_sm_decode_stage #(
        .WARP_COUNT(WARP_COUNT),
        .THREAD_COUNT(MAX_THREAD_PER_WARP)
    ) u_decode_stage (
        .clk(clk),
        .rst_n(rst_n),
        .fd_if(if_fd),
        .de_if(if_de),
        .pipeline_stall(pipeline_stall),
        .pipeline_flush(pipeline_flush)
    );
    
    // =========================================================================
    // CUDA Core选择逻辑
    // =========================================================================
    
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
    
    // 执行/访存/写回阶段实例化
    // 执行阶段与寄存器文件的接口实例
    interface_sm_regfile_access #(
        .WARP_COUNT(WARP_COUNT),
        .THREAD_COUNT(MAX_THREAD_PER_WARP)
    ) if_rf_exec();

    rvgpu_sm_execute_stage #(
        .WARP_COUNT(WARP_COUNT),
        .THREAD_COUNT(MAX_THREAD_PER_WARP)
    ) u_execute_stage (
        .clk(clk),
        .rst_n(rst_n),
        .de_if(if_de),
        .em_if(if_em),
        .rf_if(if_rf_exec),
        .pipeline_stall(pipeline_stall),
        .pipeline_flush(pipeline_flush)
    );

    // 执行阶段的寄存器读接口连接到core[0]的接口
    // 注意：具体的寄存器访问由generate循环中的always_comb块处理
    assign if_rf_exec.read_data = reg_read_data[0];

    rvgpu_sm_memory_stage #(
        .WARP_COUNT(WARP_COUNT),
        .THREAD_COUNT(MAX_THREAD_PER_WARP)
    ) u_memory_stage (
        .clk(clk),
        .rst_n(rst_n),
        .em_if(if_em),
        .ldst_if(if_ldst),
        .mw_if(if_mw),
        .pipeline_stall(pipeline_stall),
        .pipeline_flush(pipeline_flush)
    );

    // 为4个CUDA Core与L1 Data Cache建立接口实例并对接（已前置声明）

    // 将接口数组连接到L1 Data Cache
    // 注意：SystemVerilog允许端口为接口数组，直接名义传递
    // 已在L1 Data Cache实例化处使用 .core_l1_if(if_l1_core)
    
    // 写回阶段与寄存器文件的接口实例
    interface_sm_regfile_access #(
        .WARP_COUNT(WARP_COUNT),
        .THREAD_COUNT(MAX_THREAD_PER_WARP)
    ) if_rf_wb();

    rvgpu_sm_writeback_stage #(
        .WARP_COUNT(WARP_COUNT),
        .THREAD_COUNT(MAX_THREAD_PER_WARP)
    ) u_writeback_stage (
        .clk(clk),
        .rst_n(rst_n),
        .mw_if(if_mw),
        .rf_if(if_rf_wb),
        .pc_update_if(if_pc_update),
        .branch_feedback_valid(),
        .branch_feedback_pc(),
        .branch_feedback_taken(),
        .branch_feedback_target(),
        .warp_complete(),
        .warp_complete_id(),
        .pipeline_stall(pipeline_stall),
        .pipeline_flush(pipeline_flush),
        .pipeline_flush_req()
    );

    // 写回阶段的写接口连接到core[0]的接口
    // 注意：具体的写信号由generate循环中的always_comb块处理
    // 这里只做接口连接，避免重复驱动
    
    // LDST接口适配器：连接外部ldst_sm_if和内部if_ldst
    // 注意：if_ldst接口由rvgpu_sm_memory_stage完全控制，此处只做信号桥接
    always_comb begin
        // 将内部if_ldst的请求信号连接到外部ldst_if的请求信号
        // 这些信号由rvgpu_sm_memory_stage驱动，需要连接到外部ldst_if
        ldst_if.req_valid = if_ldst.req_valid;
        ldst_if.req_warp_id = if_ldst.req_warp_id;
        ldst_if.req_mask = if_ldst.req_mask;
        ldst_if.req_addr = if_ldst.req_addr[0]; // 简化：使用第一个线程的地址
        ldst_if.req_data = if_ldst.req_data[0]; // 简化：使用第一个线程的数据
        ldst_if.req_size = if_ldst.req_size;
        ldst_if.req_is_load = if_ldst.req_is_load;
        ldst_if.req_type = 3'b000; // 默认普通访问类型
        ldst_if.req_lane_id = 5'b0; // 默认lane 0
        
        // 将外部ldst_if的响应信号连接到内部if_ldst的响应信号
        // 这些信号由外部LDST单元驱动，需要连接到内部if_ldst
        if_ldst.req_ready = ldst_if.req_ready;
        if_ldst.resp_valid = ldst_if.resp_valid;
        if_ldst.resp_warp_id = ldst_if.resp_warp_id;
        
        // 注意：if_ldst使用resp_mask数组，ldst_if使用resp_data数组
        // 需要将resp_data转换为resp_mask格式
        for (int i = 0; i < THREAD_COUNT; i++) begin
            if_ldst.resp_data[i] = ldst_if.resp_data[32*i +: 32];
        end
        
        // 响应准备信号：由rvgpu_sm_memory_stage驱动
        ldst_if.resp_ready = if_ldst.resp_ready;
        
        ldst_if.flush = 1'b0; // 默认不刷新
    end

    // CUDA Core分发控制
    always_comb begin
        cuda_core_dispatch_valid[0] = if_de.valid && (selected_cuda_core == 0);
        cuda_core_dispatch_valid[1] = if_de.valid && (selected_cuda_core == 1);
        cuda_core_dispatch_valid[2] = if_de.valid && (selected_cuda_core == 2);
        cuda_core_dispatch_valid[3] = if_de.valid && (selected_cuda_core == 3);
    end
    
    // =========================================================================
    // 4个CUDA Core单元实例化
    // =========================================================================
    
    generate
        for (genvar i = 0; i < NUM_CUDA_CORES; i++) begin : cuda_core_gen
            // 每个Core的regfile适配接口
            interface_sm_regfile_access #(
                .WARP_COUNT(WARP_COUNT),
                .THREAD_COUNT(MAX_THREAD_PER_WARP)
            ) if_rf_core();
            // 分发接口（可选：如后续改为每Core独立分发）此处保持共享，通过信号解包
            
            // 每个Core的分发接口
            interface_sm_warp_dispatch #(
                .WARP_COUNT(WARP_COUNT),
                .THREAD_COUNT(MAX_THREAD_PER_WARP)
            ) if_disp_core();

            rvgpu_sm_cuda_core_unit #(
                .CORE_ID(i),
                .WARP_COUNT(WARP_COUNT),
                .THREAD_COUNT(MAX_THREAD_PER_WARP)
            ) u_cuda_core_unit (
                .clk(clk),
                .rst_n(rst_n),
                .disp_if(if_disp_core),
                
                // 寄存器文件接口（每Core独立接口，通过适配层扁平化）
                .rf_if(if_rf_core),
                
                // L1 Data Cache接口 - 接口化
                .l1_if(if_l1_core[i]),
                
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

            // 适配每个Core的寄存器接口到全局扁平信号
            always_comb begin
                // 分发接口赋值
                if_disp_core.valid       = cuda_core_dispatch_valid[i];
                if_disp_core.inst        = if_de.inst;
                if_disp_core.pc          = if_de.pc;
                if_disp_core.warp_id     = if_de.warp_id;
                if_disp_core.active_mask = if_de.active_mask;
                if_disp_core.rs1         = if_de.rs1;
                if_disp_core.rs2         = if_de.rs2;
                if_disp_core.rs3         = if_de.rs3;
                if_disp_core.rd          = if_de.rd;
                if_disp_core.imm         = if_de.imm;
                if_disp_core.is_alu      = if_de.is_alu;
                if_disp_core.is_fpu      = if_de.is_fpu;
                if_disp_core.is_tensor   = if_de.is_tensor;
                if_disp_core.is_branch   = if_de.is_branch;
                if_disp_core.is_jump     = if_de.is_jump;
                if_disp_core.is_load     = if_de.is_load;
                if_disp_core.is_store    = if_de.is_store;
                if_disp_core.is_barrier  = if_de.is_barrier;
                if_disp_core.alu_op      = if_de.alu_op;
                if_disp_core.fpu_op      = if_de.fpu_op;
                if_disp_core.tensor_op   = if_de.tensor_op;
                if_disp_core.branch_op   = if_de.branch_op;
                if_disp_core.reg_write   = if_de.reg_write;
                if_disp_core.use_imm     = if_de.use_imm;
                if_disp_core.is_32bit    = if_de.is_32bit;
                cuda_core_dispatch_ready[i] = if_disp_core.ready;
                
                // 读 - 为core[0]特殊处理，连接执行阶段接口
                if (i == 0) begin
                    reg_read_enable_core[i][0] = if_rf_exec.read_enable[0];
                    reg_read_enable_core[i][1] = if_rf_exec.read_enable[1];
                    reg_read_enable_core[i][2] = if_rf_exec.read_enable[2];
                    reg_read_warp_id_core[i][0] = if_rf_exec.read_warp_id[0];
                    reg_read_warp_id_core[i][1] = if_rf_exec.read_warp_id[1];
                    reg_read_warp_id_core[i][2] = if_rf_exec.read_warp_id[2];
                    reg_read_addr_core[i][0] = if_rf_exec.read_reg_addr[0];
                    reg_read_addr_core[i][1] = if_rf_exec.read_reg_addr[1];
                    reg_read_addr_core[i][2] = if_rf_exec.read_reg_addr[2];
                end else begin
                    reg_read_enable_core[i][0] = if_rf_core.read_enable[0];
                    reg_read_enable_core[i][1] = if_rf_core.read_enable[1];
                    reg_read_enable_core[i][2] = if_rf_core.read_enable[2];
                    reg_read_warp_id_core[i][0] = if_rf_core.read_warp_id[0];
                    reg_read_warp_id_core[i][1] = if_rf_core.read_warp_id[1];
                    reg_read_warp_id_core[i][2] = if_rf_core.read_warp_id[2];
                    reg_read_addr_core[i][0] = if_rf_core.read_reg_addr[0];
                    reg_read_addr_core[i][1] = if_rf_core.read_reg_addr[1];
                    reg_read_addr_core[i][2] = if_rf_core.read_reg_addr[2];
                end
                if_rf_core.read_data = reg_read_data[i];
                
                // 写 - 为core[0]特殊处理，连接写回阶段接口
                if (i == 0) begin
                    reg_write_enable_flat[i] = if_rf_wb.write_enable;
                    reg_write_warp_id_flat[i] = if_rf_wb.write_warp_id;
                    reg_write_addr_flat[i] = if_rf_wb.write_reg_addr;
                    reg_write_data_flat[i] = if_rf_wb.write_data;
                    reg_write_mask_flat[i] = if_rf_wb.write_mask;
                end else begin
                    reg_write_enable_flat[i] = if_rf_core.write_enable;
                    reg_write_warp_id_flat[i] = if_rf_core.write_warp_id;
                    reg_write_addr_flat[i] = if_rf_core.write_reg_addr;
                    reg_write_data_flat[i] = if_rf_core.write_data;
                    reg_write_mask_flat[i] = if_rf_core.write_mask;
                end
            end
        end
    endgenerate
    
    // =========================================================================
    // Warp状态管理和控制逻辑
    // =========================================================================
    
    // Warp状态更新
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // 初始化前几个warp - 简化处理
            if_warp_state.warp_pc[0] <= '0;
            if_warp_state.warp_pc[1] <= '0;
            if_warp_state.warp_pc[2] <= '0;
            if_warp_state.warp_pc[3] <= '0;
            if_warp_state.warp_active_mask[0] <= '0;
            if_warp_state.warp_active_mask[1] <= '0;
            if_warp_state.warp_active_mask[2] <= '0;
            if_warp_state.warp_active_mask[3] <= '0;
            if_warp_state.warp_valid <= '0;
            if_warp_state.warp_stalled <= '0;
            if_warp_state.warp_barrier <= '0;
            if_warp_state.warp_waiting <= '0;
        end else begin
            // PC更新
            if (if_pc_update.valid) begin
                if_warp_state.warp_pc[if_pc_update.warp_id] <= if_pc_update.pc;
            end
            
            // 分支反馈处理 - 简化处理
            if (cuda_core_branch_feedback_valid[0] && cuda_core_branch_feedback_taken[0]) begin
                if_warp_state.warp_pc[cuda_core_complete_id[0]] <= cuda_core_branch_feedback_target[0];
            end else if (cuda_core_branch_feedback_valid[1] && cuda_core_branch_feedback_taken[1]) begin
                if_warp_state.warp_pc[cuda_core_complete_id[1]] <= cuda_core_branch_feedback_target[1];
            end else if (cuda_core_branch_feedback_valid[2] && cuda_core_branch_feedback_taken[2]) begin
                if_warp_state.warp_pc[cuda_core_complete_id[2]] <= cuda_core_branch_feedback_target[2];
            end else if (cuda_core_branch_feedback_valid[3] && cuda_core_branch_feedback_taken[3]) begin
                if_warp_state.warp_pc[cuda_core_complete_id[3]] <= cuda_core_branch_feedback_target[3];
            end
            
            // 新warp分配
            if (block_dispatch_if.warp_valid && warp_alloc_ready) begin
                if_warp_state.warp_valid[warp_alloc_id] <= 1'b1;
            end
            
            // Warp完成处理 - 简化处理
            if (cuda_core_complete[0]) begin
                if_warp_state.warp_valid[cuda_core_complete_id[0]] <= 1'b0;
            end else if (cuda_core_complete[1]) begin
                if_warp_state.warp_valid[cuda_core_complete_id[1]] <= 1'b0;
            end else if (cuda_core_complete[2]) begin
                if_warp_state.warp_valid[cuda_core_complete_id[2]] <= 1'b0;
            end else if (cuda_core_complete[3]) begin
                if_warp_state.warp_valid[cuda_core_complete_id[3]] <= 1'b0;
            end
            
            // 简化状态更新
            if_warp_state.warp_stalled <= '0;
            if_warp_state.warp_barrier <= '0;
            if_warp_state.warp_waiting <= '0;
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
    
    // SM前端模块实例 - 处理路由器接口
    rvgpu_sm_frontend #(
        .SM_ID(SM_ID)
    ) u_sm_frontend (
        .clk(clk),
        .rst_n(rst_n),
        .router_if(router_if),
        .block_dispatch_if(block_dispatch_if),
        .ldst_if(ldst_if),
        .l15_icache_if(l15_icache_if),
        .tlb_if(tlb_if)
    );
    
endmodule : rvgpu_sm_top

`endif // RVGPU_SM_TOP_SV 


