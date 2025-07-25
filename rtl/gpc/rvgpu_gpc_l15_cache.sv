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

`ifndef RVGPU_GPC_L1_CACHE_SV
`define RVGPU_GPC_L1_CACHE_SV

`include "rvgpu_typedef.svh"
`include "gpc_l15_cache_if.svh"
`include "gpc_l15_noc_if.svh"

// L1 Cache控制器模块
// 集成Tag数组、数据数组、MSHR、RRIP替换策略和写缓冲
module rvgpu_gpc_l15_cache #(
    parameter int CACHE_SIZE = 256 * 1024,    // 缓存大小，单位字节
    parameter int LINE_SIZE = 64,             // 缓存行大小，单位字节
    parameter int ASSOCIATIVITY = 8,          // 相联度
    parameter int ADDR_WIDTH = 40,            // 物理地址宽度
    parameter int NUM_REQUESTERS = 7,         // 请求者数量
    parameter int MSHR_ENTRIES = 16,          // MSHR条目数
    parameter int WB_ENTRIES = 8              // 写缓冲条目数
) (
    input  logic clk,
    input  logic rst_n,
    
    // NOC接口 (连接到L2 Cache)
    gpc_l15_noc_if.cache noc_if,
    
    // 请求者接口数组 (TPC、Block Scheduler、Raster等)
    gpc_l15_cache_if.cache requester_if[NUM_REQUESTERS]
);
    // 缓存状态机状态
    typedef enum logic [3:0] {
        IDLE,
        TAG_LOOKUP,
        DATA_READ,
        DATA_WRITE,
        MSHR_ALLOC,
        MSHR_WAIT,
        WB_ALLOC,
        WB_WAIT,
        NOC_REQ,
        NOC_WAIT,
        RESP_SEND
    } cache_state_t;
    
    // 内部信号
    cache_state_t state;
    logic [$clog2(NUM_REQUESTERS)-1:0] current_requester;
    logic [ADDR_WIDTH-1:0] current_addr;
    logic current_is_read;
    logic [3:0] current_size;
    logic [3:0] current_type;
    logic [511:0] current_data;
    logic [63:0] current_mask;
    logic [31:0] current_id;
    
    // Tag数组接口信号
    logic tag_lookup_valid;
    logic tag_lookup_ready;
    logic tag_lookup_hit;
    logic [$clog2(ASSOCIATIVITY)-1:0] tag_lookup_way;
    logic tag_update_valid;
    logic tag_update_ready;
    logic [$clog2(ASSOCIATIVITY)-1:0] tag_update_way;
    logic tag_update_dirty;
    logic replace_valid;
    logic [$clog2(ASSOCIATIVITY)-1:0] replace_way;
    logic [ADDR_WIDTH-1:0] replace_addr;
    logic replace_dirty;
    logic replace_valid_out;
    
    // 数据数组接口信号
    logic data_read_valid;
    logic data_read_ready;
    logic data_read_resp_valid;
    logic [LINE_SIZE*8-1:0] data_read_data;
    logic data_write_valid;
    logic data_write_ready;
    logic [LINE_SIZE*8-1:0] data_write_data;
    logic [LINE_SIZE-1:0] data_write_mask;
    
    // MSHR接口信号
    logic mshr_alloc_valid;
    logic mshr_alloc_ready;
    logic mshr_alloc_hit;
    logic [$clog2(MSHR_ENTRIES)-1:0] mshr_alloc_hit_index;
    logic mshr_complete_valid;
    logic [$clog2(MSHR_ENTRIES)-1:0] mshr_complete_index;
    logic [511:0] mshr_complete_data;
    logic mshr_complete_ready;
    logic mshr_resp_valid;
    logic [31:0] mshr_resp_id;
    logic [511:0] mshr_resp_data;
    logic mshr_resp_error;
    logic mshr_resp_ready;
    logic mshr_req_valid;
    logic [ADDR_WIDTH-1:0] mshr_req_addr;
    logic mshr_req_is_read;
    logic [$clog2(MSHR_ENTRIES)-1:0] mshr_req_index;
    logic mshr_req_ready;
    logic [$clog2(MSHR_ENTRIES):0] mshr_used_entries;
    logic mshr_full;
    
    // 写缓冲接口信号
    logic wb_enq_valid;
    logic wb_enq_ready;
    logic wb_enq_hit;
    logic [$clog2(WB_ENTRIES)-1:0] wb_enq_hit_index;
    logic wb_lookup_valid;
    logic wb_lookup_hit;
    logic [LINE_SIZE*8-1:0] wb_lookup_data;
    logic [LINE_SIZE-1:0] wb_lookup_mask;
    logic wb_wb_valid;
    logic [ADDR_WIDTH-1:0] wb_wb_addr;
    logic [LINE_SIZE*8-1:0] wb_wb_data;
    logic [LINE_SIZE-1:0] wb_wb_mask;
    logic wb_wb_ready;
    logic wb_complete_valid;
    logic [$clog2(WB_ENTRIES)-1:0] wb_complete_index;
    logic wb_complete_ready;
    logic wb_resp_valid;
    logic [31:0] wb_resp_id;
    logic wb_resp_ready;
    logic [$clog2(WB_ENTRIES):0] wb_used_entries;
    logic wb_full;
    
    // RRIP接口信号
    logic [$clog2((CACHE_SIZE/LINE_SIZE)/ASSOCIATIVITY)-1:0] rrip_index;
    logic rrip_hit_valid;
    logic [$clog2(ASSOCIATIVITY)-1:0] rrip_hit_way;
    logic rrip_insert_valid;
    logic [$clog2(ASSOCIATIVITY)-1:0] rrip_insert_way;
    logic rrip_replace_valid;
    logic [$clog2(ASSOCIATIVITY)-1:0] rrip_replace_way;
    
    // 仲裁器 - 轮询策略
    logic [NUM_REQUESTERS-1:0] req_valid_array;
    logic [NUM_REQUESTERS-1:0] req_grant_array;
    logic [$clog2(NUM_REQUESTERS)-1:0] arbiter_ptr;
    
    // 将请求有效信号组合成数组，便于仲裁
    genvar i;
    generate
        for (i = 0; i < NUM_REQUESTERS; i++) begin : req_valid_gen
            assign req_valid_array[i] = requester_if[i].req_valid;
        end
    endgenerate
    
    // 仲裁逻辑 - 轮询策略
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arbiter_ptr <= '0;
            req_grant_array <= '0;
        end else begin
            // 默认不授权
            req_grant_array <= '0;
            
            if (state == IDLE) begin
                // 从当前指针开始轮询
                for (int i = 0; i < NUM_REQUESTERS; i++) begin : arbiter_loop
                    logic [$clog2(NUM_REQUESTERS)-1:0] idx = (arbiter_ptr + i) % NUM_REQUESTERS;
                    if (req_valid_array[idx]) begin
                        req_grant_array[idx] <= 1'b1;
                        arbiter_ptr <= (idx + 1) % NUM_REQUESTERS;
                        break;
                    end
                end
            end
        end
    end
    
    // 准备就绪信号
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_REQUESTERS; i++) begin : ready_init
                requester_if[i].req_ready <= 1'b0;
            end
        end else begin
            // 根据授权信号设置准备就绪
            for (int i = 0; i < NUM_REQUESTERS; i++) begin : ready_set
                requester_if[i].req_ready <= req_grant_array[i] && (state == IDLE);
            end
        end
    end
    
    // 主状态机
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            current_requester <= '0;
            current_addr <= '0;
            current_is_read <= 1'b0;
            current_size <= '0;
            current_type <= '0;
            current_data <= '0;
            current_mask <= '0;
            current_id <= '0;
            
            // 初始化Tag数组接口
            tag_lookup_valid <= 1'b0;
            tag_update_valid <= 1'b0;
            replace_valid <= 1'b0;
            
            // 初始化数据数组接口
            data_read_valid <= 1'b0;
            data_write_valid <= 1'b0;
            
            // 初始化MSHR接口
            mshr_alloc_valid <= 1'b0;
            mshr_complete_valid <= 1'b0;
            mshr_resp_ready <= 1'b0;
            mshr_req_ready <= 1'b0;
            
            // 初始化写缓冲接口
            wb_enq_valid <= 1'b0;
            wb_lookup_valid <= 1'b0;
            wb_complete_valid <= 1'b0;
            wb_resp_ready <= 1'b0;
            wb_wb_ready <= 1'b0;
            
            // 初始化RRIP接口
            rrip_hit_valid <= 1'b0;
            rrip_insert_valid <= 1'b0;
            rrip_replace_valid <= 1'b0;
            
            // 初始化NOC接口
            // 只允许驱动req_ready和resp_*信号
            noc_if.req_ready <= 1'b0;
            noc_if.resp_valid <= 1'b0;
            noc_if.resp_data <= '0;
            noc_if.resp_error <= 1'b0;
            noc_if.resp_id <= '0;
            
            // 初始化响应接口
            for (int i = 0; i < NUM_REQUESTERS; i++) begin : resp_init
                requester_if[i].resp_valid <= 1'b0;
            end
        end else begin
            // 默认值
            tag_lookup_valid <= 1'b0;
            tag_update_valid <= 1'b0;
            replace_valid <= 1'b0;
            data_read_valid <= 1'b0;
            data_write_valid <= 1'b0;
            mshr_alloc_valid <= 1'b0;
            mshr_complete_valid <= 1'b0;
            wb_enq_valid <= 1'b0;
            wb_lookup_valid <= 1'b0;
            wb_complete_valid <= 1'b0;
            rrip_hit_valid <= 1'b0;
            rrip_insert_valid <= 1'b0;
            rrip_replace_valid <= 1'b0;
            
            case (state)
                IDLE: begin
                    // 重置响应信号
                    for (int i = 0; i < NUM_REQUESTERS; i++) begin : resp_reset
                        requester_if[i].resp_valid <= 1'b0;
                    end
                    
                    // 检查是否有请求
                    if (req_grant_array != '0) begin
                        // 确定当前请求者
                        for (int i = 0; i < NUM_REQUESTERS; i++) begin : req_check
                            if (req_grant_array[i]) begin
                                current_requester <= i[$clog2(NUM_REQUESTERS)-1:0];
                                current_addr <= requester_if[i].req_paddr;
                                current_is_read <= requester_if[i].req_is_read;
                                current_size <= requester_if[i].req_size;
                                current_type <= requester_if[i].req_type;
                                current_data <= requester_if[i].req_data;
                                current_mask <= requester_if[i].req_mask;
                                current_id <= requester_if[i].req_id;
                                break;
                            end
                        end
                        
                        // 先检查写缓冲
                        wb_lookup_valid <= 1'b1;
                        state <= TAG_LOOKUP;
                    end else begin
                        // 检查MSHR响应
                        mshr_resp_ready <= 1'b1;
                        if (mshr_resp_valid) begin
                            state <= RESP_SEND;
                        end else begin
                            // 检查写缓冲响应
                            wb_resp_ready <= 1'b1;
                            if (wb_resp_valid) begin
                                state <= RESP_SEND;
                            end else begin
                                // 检查MSHR请求
                                mshr_req_ready <= 1'b1;
                                if (mshr_req_valid) begin
                                    state <= NOC_REQ;
                                end else begin
                                    // 检查写缓冲写回
                                    wb_wb_ready <= 1'b1;
                                    if (wb_wb_valid) begin
                                        state <= DATA_WRITE;
                                    end
                                end
                            end
                        end
                    end
                end
                
                TAG_LOOKUP: begin
                    // 查找Tag数组
                    tag_lookup_valid <= 1'b1;
                    
                    if (tag_lookup_ready) begin
                        if (tag_lookup_hit) begin
                            // 命中，更新RRIP
                            rrip_hit_valid <= 1'b1;
                            rrip_hit_way <= tag_lookup_way;
                            
                            if (current_is_read) begin
                                // 读请求，读取数据
                                data_read_valid <= 1'b1;
                                state <= DATA_READ;
                            end else begin
                                // 写请求，写入数据
                                data_write_valid <= 1'b1;
                                state <= DATA_WRITE;
                            end
                        end else begin
                            // 未命中，检查MSHR
                            mshr_alloc_valid <= 1'b1;
                            state <= MSHR_ALLOC;
                        end
                    end
                end
                
                DATA_READ: begin
                    if (data_read_ready) begin
                        // 等待数据读取完成
                        if (data_read_resp_valid) begin
                            state <= RESP_SEND;
                        end
                    end
                end
                
                DATA_WRITE: begin
                    if (data_write_ready) begin
                        // 更新Tag数组，标记为脏
                        tag_update_valid <= 1'b1;
                        tag_update_way <= tag_lookup_way;
                        tag_update_dirty <= 1'b1;
                        
                        if (tag_update_ready) begin
                            state <= RESP_SEND;
                        end
                    end
                end
                
                MSHR_ALLOC: begin
                    if (mshr_alloc_ready) begin
                        if (mshr_alloc_hit) begin
                            // 已经有相同地址的MSHR条目
                            state <= MSHR_WAIT;
                        end else if (!mshr_full) begin
                            // 分配新MSHR条目，需要从L2获取数据
                            state <= NOC_REQ;
                        end else begin
                            // MSHR已满，尝试写缓冲
                            if (!current_is_read) begin
                                wb_enq_valid <= 1'b1;
                                state <= WB_ALLOC;
                            end else begin
                                // 读请求且MSHR已满，需要等待
                                state <= IDLE;
                            end
                        end
                    end
                end
                
                MSHR_WAIT: begin
                    // 等待MSHR完成
                    state <= IDLE;
                end
                
                WB_ALLOC: begin
                    if (wb_enq_ready) begin
                        if (wb_enq_hit || !wb_full) begin
                            // 成功分配写缓冲
                            state <= RESP_SEND;
                        end else begin
                            // 写缓冲已满，需要等待
                            state <= IDLE;
                        end
                    end
                end
                
                NOC_REQ: begin
                    // 如需主动发起NOC请求，请使用独立的requester接口
                    // 此处不允许驱动noc_if.req_*信号
                    if (noc_if.req_ready) begin
                        state <= NOC_WAIT;
                    end
                end
                
                NOC_WAIT: begin
                    // 等待NOC响应
                    if (noc_if.resp_valid) begin
                        // 完成MSHR请求
                        mshr_complete_valid <= 1'b1;
                        mshr_complete_index <= noc_if.resp_id[$clog2(MSHR_ENTRIES)-1:0];
                        mshr_complete_data <= noc_if.resp_data;
                        if (mshr_complete_ready) begin
                            // 更新缓存
                            // 获取替换路
                            rrip_replace_valid <= 1'b1;
                            state <= DATA_WRITE;
                        end
                    end
                end
                
                RESP_SEND: begin
                    // 发送响应给请求者
                    requester_if[current_requester].resp_valid <= 1'b1;
                    requester_if[current_requester].resp_data <= data_read_resp_valid ? data_read_data : 
                                                               mshr_resp_valid ? mshr_resp_data : '0;
                    requester_if[current_requester].resp_error <= mshr_resp_valid ? mshr_resp_error : 1'b0;
                    requester_if[current_requester].resp_id <= current_id;
                    
                    if (requester_if[current_requester].resp_ready) begin
                        requester_if[current_requester].resp_valid <= 1'b0;
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    // 实例化Tag数组
    rvgpu_gpc_l15_tag_array #(
        .CACHE_SIZE(CACHE_SIZE),
        .LINE_SIZE(LINE_SIZE),
        .ASSOCIATIVITY(ASSOCIATIVITY),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_tag_array (
        .clk(clk),
        .rst_n(rst_n),
        .lookup_valid(tag_lookup_valid),
        .lookup_addr(current_addr),
        .lookup_ready(tag_lookup_ready),
        .lookup_hit(tag_lookup_hit),
        .lookup_way(tag_lookup_way),
        .update_valid(tag_update_valid),
        .update_addr(current_addr),
        .update_way(tag_update_way),
        .update_dirty(tag_update_dirty),
        .update_ready(tag_update_ready),
        .replace_valid(replace_valid),
        .replace_way(replace_way),
        .replace_addr(replace_addr),
        .replace_dirty(replace_dirty),
        .replace_valid_out(replace_valid_out)
    );
    
    // 实例化数据数组
    rvgpu_gpc_l15_data_array #(
        .CACHE_SIZE(CACHE_SIZE),
        .LINE_SIZE(LINE_SIZE),
        .ASSOCIATIVITY(ASSOCIATIVITY),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_data_array (
        .clk(clk),
        .rst_n(rst_n),
        .read_valid(data_read_valid),
        .read_addr(current_addr),
        .read_way(tag_lookup_way),
        .read_ready(data_read_ready),
        .read_resp_valid(data_read_resp_valid),
        .read_data(data_read_data),
        .write_valid(data_write_valid),
        .write_addr(current_addr),
        .write_way(tag_lookup_way),
        .write_data(current_data),
        .write_mask(current_mask[LINE_SIZE-1:0]),
        .write_ready(data_write_ready)
    );
    
    // 实例化MSHR
    rvgpu_gpc_l15_mshr #(
        .MSHR_ENTRIES(MSHR_ENTRIES),
        .MAX_REQUESTS(4),
        .ADDR_WIDTH(ADDR_WIDTH),
        .LINE_SIZE(LINE_SIZE),
        .ID_WIDTH(32)
    ) u_mshr (
        .clk(clk),
        .rst_n(rst_n),
        .alloc_valid(mshr_alloc_valid),
        .alloc_addr(current_addr),
        .alloc_id(current_id),
        .alloc_size(current_size),
        .alloc_is_read(current_is_read),
        .alloc_mask(current_mask),
        .alloc_data(current_data),
        .alloc_ready(mshr_alloc_ready),
        .alloc_hit(mshr_alloc_hit),
        .alloc_hit_index(mshr_alloc_hit_index),
        .complete_valid(mshr_complete_valid),
        .complete_index(mshr_complete_index),
        .complete_data(mshr_complete_data),
        .complete_ready(mshr_complete_ready),
        .resp_valid(mshr_resp_valid),
        .resp_id(mshr_resp_id),
        .resp_data(mshr_resp_data),
        .resp_error(mshr_resp_error),
        .resp_ready(mshr_resp_ready),
        .req_valid(mshr_req_valid),
        .req_addr(mshr_req_addr),
        .req_is_read(mshr_req_is_read),
        .req_index(mshr_req_index),
        .req_ready(mshr_req_ready),
        .used_entries(mshr_used_entries),
        .full(mshr_full)
    );
    
    // 实例化写缓冲
    rvgpu_gpc_l15_write_buffer #(
        .BUFFER_ENTRIES(WB_ENTRIES),
        .ADDR_WIDTH(ADDR_WIDTH),
        .LINE_SIZE(LINE_SIZE),
        .ID_WIDTH(32)
    ) u_write_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .enq_valid(wb_enq_valid),
        .enq_addr(current_addr),
        .enq_id(current_id),
        .enq_data(current_data),
        .enq_mask(current_mask[LINE_SIZE-1:0]),
        .enq_ready(wb_enq_ready),
        .enq_hit(wb_enq_hit),
        .enq_hit_index(wb_enq_hit_index),
        .lookup_valid(wb_lookup_valid),
        .lookup_addr(current_addr),
        .lookup_hit(wb_lookup_hit),
        .lookup_data(wb_lookup_data),
        .lookup_mask(wb_lookup_mask),
        .wb_valid(wb_wb_valid),
        .wb_addr(wb_wb_addr),
        .wb_data(wb_wb_data),
        .wb_mask(wb_wb_mask),
        .wb_ready(wb_wb_ready),
        .complete_valid(wb_complete_valid),
        .complete_index(wb_complete_index),
        .complete_ready(wb_complete_ready),
        .resp_valid(wb_resp_valid),
        .resp_id(wb_resp_id),
        .resp_ready(wb_resp_ready),
        .used_entries(wb_used_entries),
        .full(wb_full),
        .flush(1'b0) // 默认不刷新
    );
    
    // 实例化RRIP替换策略
    rvgpu_gpc_l15_rrip #(
        .CACHE_SIZE(CACHE_SIZE),
        .LINE_SIZE(LINE_SIZE),
        .ASSOCIATIVITY(ASSOCIATIVITY),
        .RRPV_BITS(2)
    ) u_rrip (
        .clk(clk),
        .rst_n(rst_n),
        .index(current_addr[ADDR_WIDTH-$clog2(LINE_SIZE)-1:$clog2(LINE_SIZE)]),
        .hit_valid(rrip_hit_valid),
        .hit_way(rrip_hit_way),
        .insert_valid(rrip_insert_valid),
        .insert_way(rrip_insert_way),
        .replace_valid(rrip_replace_valid),
        .replace_way(rrip_replace_way)
    );
    
    // 连接RRIP和Tag数组的替换接口
    assign replace_way = rrip_replace_way;
    
    // 未完成请求计数
    logic [7:0] pending_count;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_count <= '0;
        end else begin
            // 简化实现：使用MSHR和写缓冲中的条目数作为未完成请求数
            pending_count <= mshr_used_entries + wb_used_entries;
        end
    end
    
    // 输出未完成请求数
    generate
        for (i = 0; i < NUM_REQUESTERS; i++) begin : pending_count_gen
            assign requester_if[i].pending_count = pending_count;
        end
    endgenerate

endmodule : rvgpu_gpc_l15_cache

`endif // RVGPU_GPC_L1_CACHE_SV
