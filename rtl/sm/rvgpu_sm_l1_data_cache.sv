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

`ifndef RVGPU_SM_L1_DATA_CACHE_SV
`define RVGPU_SM_L1_DATA_CACHE_SV

`include "rvgpu_typedef.svh"

// SM L1 Data Cache/Shared Memory
// 128KB统一缓存，可配置为数据缓存或共享内存
// 类似现代GPU的L1 Data Cache/Shared Memory架构
module rvgpu_sm_l1_data_cache #(
    parameter int CACHE_SIZE = 128 * 1024,   // 总容量128KB
    parameter int LINE_SIZE = 128,            // 缓存行大小128字节
    parameter int ASSOCIATIVITY = 4,          // 4路组相联
    parameter int SHARED_MEM_SIZE = 64 * 1024, // 共享内存部分64KB
    parameter int DATA_CACHE_SIZE = 64 * 1024, // 数据缓存部分64KB
    parameter int ADDR_WIDTH = 40,            // 物理地址宽度
    parameter int WARP_COUNT = 32,            // 支持的warp数量
    parameter int THREAD_COUNT = 32           // 每个warp的线程数
) (
    input  logic clk,
    input  logic rst_n,
    
    // CUDA Core接口 (4个CUDA Core的数据访问)
    input  logic                                req_valid[4],
    input  logic [$clog2(WARP_COUNT)-1:0]      req_warp_id[4],
    input  logic [THREAD_COUNT-1:0]             req_mask[4],
    input  logic [63:0]                         req_addr[4][THREAD_COUNT],
    input  logic [31:0]                         req_data[4][THREAD_COUNT],
    input  logic [2:0]                          req_size[4],
    input  logic                                req_is_write[4],
    input  logic                                req_is_shared[4], // 1=共享内存访问，0=全局内存访问
    output logic                                req_ready[4],
    
    output logic                                resp_valid[4],
    output logic [$clog2(WARP_COUNT)-1:0]      resp_warp_id[4],
    output logic [THREAD_COUNT-1:0]             resp_mask[4],
    output logic [31:0]                         resp_data[4][THREAD_COUNT],
    input  logic                                resp_ready[4],
    
    // L1.5 Cache接口 (用于数据缓存未命中)
    output logic                                l15_req_valid,
    output logic [63:0]                         l15_req_paddr,
    output logic [3:0]                          l15_req_size,
    output logic                                l15_req_is_read,
    output logic [511:0]                        l15_req_data,
    output logic [63:0]                         l15_req_mask,
    output logic [31:0]                         l15_req_id,
    input  logic                                l15_req_ready,
    
    input  logic                                l15_resp_valid,
    input  logic [511:0]                        l15_resp_data,
    input  logic                                l15_resp_error,
    input  logic [31:0]                         l15_resp_id,
    output logic                                l15_resp_ready,
    
    // 配置接口
    input  logic [15:0]                         shared_mem_config, // 共享内存配置
    input  logic                                cache_flush,
    
    // 状态输出
    output logic [7:0]                          pending_requests,
    output logic [7:0]                          hit_rate_percent
);

    // =========================================================================
    // 参数计算
    // =========================================================================
    
    localparam int NUM_SETS = (CACHE_SIZE / LINE_SIZE) / ASSOCIATIVITY;
    localparam int INDEX_WIDTH = $clog2(NUM_SETS);
    localparam int TAG_WIDTH = ADDR_WIDTH - INDEX_WIDTH - $clog2(LINE_SIZE);
    localparam int OFFSET_WIDTH = $clog2(LINE_SIZE);
    
    // 共享内存参数
    localparam int SHARED_MEM_BANKS = 32;  // 32个bank避免bank冲突
    localparam int SHARED_MEM_BANK_SIZE = SHARED_MEM_SIZE / SHARED_MEM_BANKS;
    localparam int SHARED_MEM_ADDR_WIDTH = $clog2(SHARED_MEM_SIZE);
    
    // =========================================================================
    // 数据结构定义
    // =========================================================================
    
    // 缓存行结构
    typedef struct packed {
        logic                   valid;
        logic                   dirty;
        logic [TAG_WIDTH-1:0]   tag;
        logic [LINE_SIZE*8-1:0] data;
        logic [1:0]             lru_bits; // 简化LRU
    } cache_line_t;
    
    // 请求结构
    typedef struct packed {
        logic                           valid;
        logic [$clog2(WARP_COUNT)-1:0]  warp_id;
        logic [THREAD_COUNT-1:0]        mask;
        logic [63:0]                    addr[THREAD_COUNT];
        logic [31:0]                    data[THREAD_COUNT];
        logic [2:0]                     size;
        logic                           is_write;
        logic                           is_shared;
        logic [1:0]                     source_core; // 来源CUDA Core
    } cache_req_t;
    
    // =========================================================================
    // 存储结构
    // =========================================================================
    
    // 数据缓存部分 (64KB, 4路组相联)
    cache_line_t data_cache[NUM_SETS/2][ASSOCIATIVITY];
    
    // 共享内存部分 (64KB, 32 banks)
    logic [31:0] shared_memory[SHARED_MEM_BANKS][SHARED_MEM_BANK_SIZE/4];
    
    // 请求队列
    cache_req_t req_queue[$];
    logic [3:0] req_queue_size;
    
    // 未完成请求跟踪
    logic [15:0] pending_req_mask;
    logic [3:0]  next_req_id;
    
    // 性能计数器
    logic [31:0] total_requests;
    logic [31:0] cache_hits;
    
    // =========================================================================
    // 地址解析
    // =========================================================================
    
    function automatic logic is_shared_mem_addr(logic [63:0] addr);
        // 共享内存地址范围：0x0000_0000 - 0x0001_0000 (64KB)
        return (addr[63:16] == 48'h0);
    endfunction
    
    function automatic logic [INDEX_WIDTH-1:0] get_cache_index(logic [63:0] addr);
        return addr[INDEX_WIDTH+OFFSET_WIDTH-1:OFFSET_WIDTH];
    endfunction
    
    function automatic logic [TAG_WIDTH-1:0] get_cache_tag(logic [63:0] addr);
        return addr[ADDR_WIDTH-1:INDEX_WIDTH+OFFSET_WIDTH];
    endfunction
    
    function automatic logic [$clog2(SHARED_MEM_BANKS)-1:0] get_shared_bank(logic [63:0] addr);
        return addr[$clog2(SHARED_MEM_BANKS)+1:2]; // 32-bit对齐
    endfunction
    
    function automatic logic [SHARED_MEM_ADDR_WIDTH-$clog2(SHARED_MEM_BANKS)-3:0] get_shared_offset(logic [63:0] addr);
        return addr[SHARED_MEM_ADDR_WIDTH-1:$clog2(SHARED_MEM_BANKS)+2];
    endfunction
    
    // =========================================================================
    // 请求仲裁和队列管理
    // =========================================================================
    
    // 简单轮询仲裁
    logic [1:0] arbiter_grant;
    logic [1:0] last_grant;
    
    always_comb begin
        arbiter_grant = 2'b00;
        for (int i = 0; i < 4; i++) begin
            logic [1:0] idx = (last_grant + 1 + i) % 4;
            if (req_valid[idx] && req_ready[idx]) begin
                arbiter_grant = idx;
                break;
            end
        end
    end
    
    // 请求入队
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_queue_size <= '0;
            last_grant <= '0;
            for (int i = 0; i < 4; i++) begin
                req_ready[i] <= 1'b1;
            end
        end else begin
            // 仲裁获胜的请求入队
            if (req_valid[arbiter_grant] && req_ready[arbiter_grant] && req_queue_size < 15) begin
                cache_req_t new_req;
                new_req.valid = 1'b1;
                new_req.warp_id = req_warp_id[arbiter_grant];
                new_req.mask = req_mask[arbiter_grant];
                new_req.addr = req_addr[arbiter_grant];
                new_req.data = req_data[arbiter_grant];
                new_req.size = req_size[arbiter_grant];
                new_req.is_write = req_is_write[arbiter_grant];
                new_req.is_shared = req_is_shared[arbiter_grant];
                new_req.source_core = arbiter_grant;
                
                req_queue.push_back(new_req);
                req_queue_size <= req_queue_size + 1;
                last_grant <= arbiter_grant;
            end
            
            // 更新ready信号
            for (int i = 0; i < 4; i++) begin
                req_ready[i] <= (req_queue_size < 15);
            end
        end
    end
    
    // =========================================================================
    // 共享内存访问处理
    // =========================================================================
    
    // 共享内存读写逻辑
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 初始化共享内存
            for (int bank = 0; bank < SHARED_MEM_BANKS; bank++) begin
                for (int addr = 0; addr < SHARED_MEM_BANK_SIZE/4; addr++) begin
                    shared_memory[bank][addr] <= '0;
                end
            end
        end else begin
            // 处理共享内存访问
            if (req_queue.size() > 0 && req_queue[0].valid && req_queue[0].is_shared) begin
                cache_req_t current_req = req_queue[0];
                
                // 并行处理所有活跃线程的共享内存访问
                for (int t = 0; t < THREAD_COUNT; t++) begin
                    if (current_req.mask[t]) begin
                        logic [$clog2(SHARED_MEM_BANKS)-1:0] bank_id;
                        logic [SHARED_MEM_ADDR_WIDTH-$clog2(SHARED_MEM_BANKS)-3:0] bank_offset;
                        
                        bank_id = get_shared_bank(current_req.addr[t]);
                        bank_offset = get_shared_offset(current_req.addr[t]);
                        
                        if (current_req.is_write) begin
                            shared_memory[bank_id][bank_offset] <= current_req.data[t];
                        end
                    end
                end
            end
        end
    end
    
    // =========================================================================
    // 数据缓存访问处理
    // =========================================================================
    
    // 缓存查找逻辑
    logic cache_hit;
    logic [1:0] hit_way;
    logic [INDEX_WIDTH-1:0] cache_index;
    logic [TAG_WIDTH-1:0] cache_tag;
    
    always_comb begin
        cache_hit = 1'b0;
        hit_way = '0;
        
        if (req_queue.size() > 0 && req_queue[0].valid && !req_queue[0].is_shared) begin
            cache_index = get_cache_index(req_queue[0].addr[0]); // 简化：使用线程0的地址
            cache_tag = get_cache_tag(req_queue[0].addr[0]);
            
            // 并行查找所有路
            for (int way = 0; way < ASSOCIATIVITY; way++) begin
                if (data_cache[cache_index][way].valid && 
                    data_cache[cache_index][way].tag == cache_tag) begin
                    cache_hit = 1'b1;
                    hit_way = way[1:0];
                    break;
                end
            end
        end
    end
    
    // 缓存访问状态机
    typedef enum logic [2:0] {
        CACHE_IDLE,
        CACHE_SHARED_ACCESS,
        CACHE_DATA_LOOKUP,
        CACHE_DATA_HIT,
        CACHE_DATA_MISS,
        CACHE_L15_REQ,
        CACHE_L15_WAIT,
        CACHE_RESPONSE
    } cache_state_t;
    
    cache_state_t cache_state;
    cache_req_t current_processing_req;
    logic [31:0] response_data[4][THREAD_COUNT];
    logic [THREAD_COUNT-1:0] response_mask[4];
    logic [$clog2(WARP_COUNT)-1:0] response_warp_id[4];
    logic [3:0] response_valid_reg;
    
    // 主处理状态机
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cache_state <= CACHE_IDLE;
            current_processing_req <= '0;
            l15_req_valid <= 1'b0;
            response_valid_reg <= '0;
            total_requests <= '0;
            cache_hits <= '0;
            
            for (int i = 0; i < 4; i++) begin
                for (int t = 0; t < THREAD_COUNT; t++) begin
                    response_data[i][t] <= '0;
                end
                response_mask[i] <= '0;
                response_warp_id[i] <= '0;
            end
        end else begin
            case (cache_state)
                CACHE_IDLE: begin
                    if (req_queue.size() > 0 && req_queue[0].valid) begin
                        current_processing_req = req_queue[0];
                        void'(req_queue.pop_front());
                        req_queue_size <= req_queue_size - 1;
                        total_requests <= total_requests + 1;
                        
                        if (current_processing_req.is_shared) begin
                            cache_state <= CACHE_SHARED_ACCESS;
                        end else begin
                            cache_state <= CACHE_DATA_LOOKUP;
                        end
                    end
                end
                
                CACHE_SHARED_ACCESS: begin
                    // 共享内存访问（读取）
                    for (int t = 0; t < THREAD_COUNT; t++) begin
                        if (current_processing_req.mask[t]) begin
                            logic [$clog2(SHARED_MEM_BANKS)-1:0] bank_id;
                            logic [SHARED_MEM_ADDR_WIDTH-$clog2(SHARED_MEM_BANKS)-3:0] bank_offset;
                            
                            bank_id = get_shared_bank(current_processing_req.addr[t]);
                            bank_offset = get_shared_offset(current_processing_req.addr[t]);
                            
                            if (!current_processing_req.is_write) begin
                                response_data[current_processing_req.source_core][t] <= 
                                    shared_memory[bank_id][bank_offset];
                            end
                        end
                    end
                    
                    response_mask[current_processing_req.source_core] <= current_processing_req.mask;
                    response_warp_id[current_processing_req.source_core] <= current_processing_req.warp_id;
                    cache_state <= CACHE_RESPONSE;
                end
                
                CACHE_DATA_LOOKUP: begin
                    if (cache_hit) begin
                        cache_hits <= cache_hits + 1;
                        cache_state <= CACHE_DATA_HIT;
                    end else begin
                        cache_state <= CACHE_DATA_MISS;
                    end
                end
                
                CACHE_DATA_HIT: begin
                    // 从缓存读取数据
                    for (int t = 0; t < THREAD_COUNT; t++) begin
                        if (current_processing_req.mask[t]) begin
                            // 简化：从缓存行中提取32位数据
                            logic [OFFSET_WIDTH-1:0] offset = current_processing_req.addr[t][OFFSET_WIDTH-1:0];
                            response_data[current_processing_req.source_core][t] <= 
                                data_cache[cache_index][hit_way].data[offset*8 +: 32];
                        end
                    end
                    
                    response_mask[current_processing_req.source_core] <= current_processing_req.mask;
                    response_warp_id[current_processing_req.source_core] <= current_processing_req.warp_id;
                    cache_state <= CACHE_RESPONSE;
                end
                
                CACHE_DATA_MISS: begin
                    // 发起L1.5请求
                    if (!l15_req_valid) begin
                        l15_req_valid <= 1'b1;
                        l15_req_paddr <= {current_processing_req.addr[0][63:OFFSET_WIDTH], {OFFSET_WIDTH{1'b0}}};
                        l15_req_size <= 4'h6; // 128字节
                        l15_req_is_read <= !current_processing_req.is_write;
                        l15_req_id <= next_req_id;
                        next_req_id <= next_req_id + 1;
                        
                        if (!current_processing_req.is_write) begin
                            l15_req_data <= '0;
                            l15_req_mask <= '0;
                        end else begin
                            // 构造写数据
                            for (int t = 0; t < THREAD_COUNT; t++) begin
                                if (current_processing_req.mask[t]) begin
                                    logic [OFFSET_WIDTH-1:0] offset = current_processing_req.addr[t][OFFSET_WIDTH-1:0];
                                    l15_req_data[offset*8 +: 32] <= current_processing_req.data[t];
                                    l15_req_mask[offset +: 4] <= 4'hF;
                                end
                            end
                        end
                        
                        cache_state <= CACHE_L15_REQ;
                    end
                end
                
                CACHE_L15_REQ: begin
                    if (l15_req_ready) begin
                        l15_req_valid <= 1'b0;
                        cache_state <= CACHE_L15_WAIT;
                    end
                end
                
                CACHE_L15_WAIT: begin
                    if (l15_resp_valid && l15_resp_id == (next_req_id - 1)) begin
                        // 更新缓存
                        logic [1:0] replace_way = 2'b00; // 简化替换策略
                        
                        data_cache[cache_index][replace_way].valid <= 1'b1;
                        data_cache[cache_index][replace_way].tag <= cache_tag;
                        data_cache[cache_index][replace_way].data <= l15_resp_data[LINE_SIZE*8-1:0];
                        data_cache[cache_index][replace_way].dirty <= current_processing_req.is_write;
                        
                        // 提取响应数据
                        if (!current_processing_req.is_write) begin
                            for (int t = 0; t < THREAD_COUNT; t++) begin
                                if (current_processing_req.mask[t]) begin
                                    logic [OFFSET_WIDTH-1:0] offset = current_processing_req.addr[t][OFFSET_WIDTH-1:0];
                                    response_data[current_processing_req.source_core][t] <= 
                                        l15_resp_data[offset*8 +: 32];
                                end
                            end
                        end
                        
                        response_mask[current_processing_req.source_core] <= current_processing_req.mask;
                        response_warp_id[current_processing_req.source_core] <= current_processing_req.warp_id;
                        cache_state <= CACHE_RESPONSE;
                    end
                end
                
                CACHE_RESPONSE: begin
                    response_valid_reg[current_processing_req.source_core] <= 1'b1;
                    
                    if (resp_ready[current_processing_req.source_core]) begin
                        response_valid_reg[current_processing_req.source_core] <= 1'b0;
                        cache_state <= CACHE_IDLE;
                    end
                end
                
                default: begin
                    cache_state <= CACHE_IDLE;
                end
            endcase
        end
    end
    
    // =========================================================================
    // 输出信号赋值
    // =========================================================================
    
    // 响应信号
    always_comb begin
        for (int i = 0; i < 4; i++) begin
            resp_valid[i] = response_valid_reg[i];
            resp_warp_id[i] = response_warp_id[i];
            resp_mask[i] = response_mask[i];
            resp_data[i] = response_data[i];
        end
    end
    
    // L1.5接口
    assign l15_resp_ready = (cache_state == CACHE_L15_WAIT);
    
    // 状态输出
    assign pending_requests = req_queue_size + (cache_state != CACHE_IDLE ? 1 : 0);
    assign hit_rate_percent = (total_requests > 0) ? 
                             ((cache_hits * 100) / total_requests) : 8'h0;

endmodule : rvgpu_sm_l1_data_cache

`endif // RVGPU_SM_L1_DATA_CACHE_SV 