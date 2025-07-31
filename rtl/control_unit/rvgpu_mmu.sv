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

`ifndef RVGPU_MMU_SV
`define RVGPU_MMU_SV

`include "rvgpu_control_unit_pkg.svh"
`include "rvgpu_control_unit_if.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_mmu_if.svh"
`include "rvgpu_debug.svh"
`include "rvgpu_constant.svh"
`include "rvgpu_mmu_common.svh"
`include "rvgpu_noc_message.svh"
`include "rvgpu_fifo_if.svh"

module rvgpu_mmu (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // 命令处理器接口
    mmu_if.mmu_port mmu_if,
    // MMU配置接口
    cp_mmu_config_if.mmu_port mmu_config_if,

    // 页表访问NOC接口
    rvgpu_internal_noc_if.device noc_if
);

    //=============================================================================
    // 1. 请求缓冲区定义
    //=============================================================================
    
    // 请求来源类型
    typedef enum logic [1:0] {
        REQ_SOURCE_CP = 2'b00,    // 来自命令处理器
        REQ_SOURCE_GPC = 2'b01,   // 来自GPC
        REQ_SOURCE_RESERVED1 = 2'b10,
        REQ_SOURCE_RESERVED2 = 2'b11
    } req_source_t;
    
    // 请求缓冲区条目
    typedef struct packed {
        logic                  valid;          // 有效位
        req_source_t           source;         // 请求来源
        logic [VA_WIDTH-1:0]   vaddr;          // 虚拟地址
        mmu_access_type_e      req_type;       // 访问类型
        logic [7:0]            trans_id;       // 事务ID (用于GPC请求)
        logic [3:0]            tpc_id;         // TPC ID (用于GPC请求)
        logic [3:0]            gpc_id;         // GPC ID (用于GPC请求)
        logic                  pending;        // 请求是否正在处理中
    } req_buffer_entry_t;
    
    // 请求缓冲区参数
    localparam int REQ_BUFFER_DEPTH = 8;
    localparam int REQ_BUFFER_INDEX_BITS = $clog2(REQ_BUFFER_DEPTH);
    localparam int REQ_BUFFER_ENTRY_BITS = $bits(req_buffer_entry_t);
    
    // 缓冲区状态信号
    assign req_buffer_full = req_fifo_if.full;
    assign req_buffer_empty = req_fifo_if.empty;
    
    // 当前处理的请求
    req_buffer_entry_t current_req;
    
    // FIFO写入缓冲区
    req_buffer_entry_t write_data_buf;
    
    // GPC请求数据解析信号
    noc_req_mmu_t gpc_req_data;
    assign gpc_req_data = noc_req_mmu_t'(noc_if.s_req_data);
    
    // 地址位宽参数
    localparam int VA_WIDTH = `RVGPU_CONST_CU_VA_WIDTH;
    localparam int PA_WIDTH = `RVGPU_CONST_CU_PA_WIDTH;
    localparam int PAGE_OFFSET_BITS = `RVGPU_CONST_CU_PAGE_OFFSET_BITS;
    
    //=============================================================================
    // 2. 状态机定义
    //=============================================================================
    
    typedef enum logic [2:0] {
        MMU_STATE_IDLE = 3'b000,        // 空闲状态
        MMU_STATE_TLB_LOOKUP = 3'b001,  // TLB查找
        MMU_STATE_TLB_WAIT = 3'b010,    // TLB等待结果
        MMU_STATE_PAGE_WALK = 3'b011,   // 页表查找
        MMU_STATE_PAGE_WAIT = 3'b100,   // 等待页表响应
        MMU_STATE_TLB_UPDATE = 3'b101,  // TLB更新
        MMU_STATE_RESPONSE = 3'b110,    // 响应
        MMU_STATE_ERROR = 3'b111        // 错误
    } mmu_state_t;
    
    //=============================================================================
    // 3. 内部信号定义
    //=============================================================================
    
    // 状态机寄存器
    mmu_state_t state_r, state_nxt;
    
    // 数据寄存器
    logic [VA_WIDTH-1:0] vaddr_r, vaddr_nxt;
    logic [PA_WIDTH-1:0] paddr_r, paddr_nxt;
    mmu_access_type_e req_type_r, req_type_nxt;
    
    // TLB接口 - 使用新的mmu_tlb_if
    mmu_tlb_if mmu_tlb();
    
    // 页表基地址
    logic [PA_WIDTH-1:0] page_table_base_r, page_table_base_nxt;
    
    // 多级页表查找状态
    logic [PA_WIDTH-1:0] current_pt_base_r, current_pt_base_nxt;  // 当前页表基地址
    logic [1:0] page_level_r, page_level_nxt;  // 当前页表级别：0=L1, 1=L2, 2=L3
    
    // 性能计数器（可选，用于调试）
    logic [31:0] tlb_hit_count_r, tlb_hit_count_nxt;
    logic [31:0] tlb_miss_count_r, tlb_miss_count_nxt;
    logic [31:0] page_walk_count_r, page_walk_count_nxt;
    
    // 输出控制寄存器 - 使用寄存器控制输出
    logic tlb_lookup_valid_r, tlb_lookup_valid_nxt;
    logic tlb_update_valid_r, tlb_update_valid_nxt;
    
    logic noc_req_valid_r, noc_req_valid_nxt;
    logic [31:0] noc_req_header_r, noc_req_header_nxt;
    noc_payload_t noc_req_data_r, noc_req_data_nxt;
    logic noc_req_last_r, noc_req_last_nxt;
    logic noc_resp_ready_r, noc_resp_ready_nxt;
    
    // NOC响应接口
    logic noc_s_resp_valid_r, noc_s_resp_valid_nxt;
    logic [31:0] noc_s_resp_header_r, noc_s_resp_header_nxt;
    logic [255:0] noc_s_resp_data_r, noc_s_resp_data_nxt;
    
    //=============================================================================
    // 4. 握手信号抽象 - 使用三元运算符进行条件赋值
    //=============================================================================
    
    // CP请求握手
    wire cp_req_accept = mmu_if.req_valid && mmu_if.req_ready;
    wire cp_resp_accept = mmu_if.resp_valid && mmu_if.resp_ready;
    
    // GPC请求握手 (通过NOC)
    wire gpc_req_accept = noc_if.s_req_valid && noc_if.s_req_ready;
    
    // 页表访问握手
    wire noc_req_accept = noc_if.m_req_valid && noc_if.m_req_ready;
    wire noc_resp_accept = noc_if.m_resp_valid && noc_resp_ready_r;
    
    //=============================================================================
    // 5. TLB实例化
    //=============================================================================
    
    rvgpu_mmu_tlb u_mmu_tlb (
        .clk(clk),
        .rst_n(rst_n),
        .tlb_if(mmu_tlb.tlb_port)
    );
    
    //=============================================================================
    // 6. 请求FIFO实例化
    //=============================================================================
    
    // Basic FIFO接口实例
    rvgpu_fifo_basic_if #(
        .DATA_WIDTH(REQ_BUFFER_ENTRY_BITS),
        .INDEX_BITS(REQ_BUFFER_INDEX_BITS)
    ) req_fifo_if();
    
    rvgpu_fifo_basic #(
        .DATA_WIDTH(REQ_BUFFER_ENTRY_BITS),
        .INDEX_BITS(REQ_BUFFER_INDEX_BITS)
    ) u_req_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .fifo_if(req_fifo_if.fifo_port)
    );
    
    //=============================================================================
    // 7. 请求缓冲区管理
    //=============================================================================
    
    // FIFO写入逻辑
    always_comb begin
        req_fifo_if.write_en = 1'b0;
        write_data_buf = '0;
        
        // CP请求入队
        if (cp_req_accept && can_accept_request()) begin
            req_fifo_if.write_en = 1'b1;
            write_data_buf = build_cp_req_entry(mmu_if.req_vaddr, mmu_if.req_type);
        end
        // GPC请求入队
        else if (gpc_req_accept && can_accept_request()) begin
            req_fifo_if.write_en = 1'b1;
            write_data_buf = build_gpc_req_entry(noc_if.s_req_header, noc_if.s_req_data);
        end
        
        // 将临时变量赋值给FIFO接口
        req_fifo_if.write_data = write_data_buf;
    end
    
    // FIFO读取逻辑
    assign req_fifo_if.read_en = (state_r == MMU_STATE_IDLE && !req_buffer_empty && !current_req.pending);
    
    // 当前处理的请求
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            current_req <= '0;
        end else begin
            if (req_fifo_if.read_en) begin
                current_req <= req_fifo_if.read_data;
                current_req.pending <= 1'b1;  // 标记为正在处理
            end else if (state_r == MMU_STATE_RESPONSE) begin
                current_req.pending <= 1'b0;  // 处理完成
            end
        end
    end
    
    //=============================================================================
    // 7. 组合逻辑 - 使用 always_comb 处理组合逻辑
    //=============================================================================
    
    // 状态机组合逻辑
    always_comb begin
        // 默认值 - 避免锁存器
        state_nxt = state_r;
        vaddr_nxt = vaddr_r;
        paddr_nxt = paddr_r;
        req_type_nxt = req_type_r;
        current_pt_base_nxt = current_pt_base_r;
        page_level_nxt = page_level_r;
        tlb_hit_count_nxt = tlb_hit_count_r;
        tlb_miss_count_nxt = tlb_miss_count_r;
        page_walk_count_nxt = page_walk_count_r;
        
        // 输出控制寄存器默认值
        tlb_lookup_valid_nxt = 1'b0;
        tlb_update_valid_nxt = 1'b0;
        noc_req_valid_nxt = 1'b0;
        noc_req_header_nxt = noc_req_header_r;
        noc_req_data_nxt = noc_req_data_r;
        noc_req_last_nxt = noc_req_last_r;
        noc_resp_ready_nxt = noc_resp_ready_r;
        
        // NOC响应默认值
        noc_s_resp_valid_nxt = 1'b0;
        noc_s_resp_header_nxt = noc_s_resp_header_r;
        noc_s_resp_data_nxt = noc_s_resp_data_r;
        
        case (state_r)
            MMU_STATE_IDLE: begin
                if (can_process_request()) begin
                    // 从FIFO获取请求 - 这里会触发FIFO读取
                    // 数据会在下一个时钟周期更新到current_req
                    state_nxt = MMU_STATE_TLB_LOOKUP;
                    // 注意：vaddr和req_type会在current_req更新后使用
                    page_level_nxt = L1_LEVEL;  // 从L1开始
                    current_pt_base_nxt = page_table_base_r;  // 使用配置的页表基地址
                end
            end
            
            MMU_STATE_TLB_LOOKUP: begin
                // 使用current_req中的数据
                vaddr_nxt = current_req.vaddr;
                req_type_nxt = current_req.req_type;
                
                // TLB查找 - 设置输出寄存器
                tlb_lookup_valid_nxt = 1'b1;
                
                // 等待TLB准备好接受请求
                if (tlb_lookup_valid_r && mmu_tlb.req_ready) begin
                    // 握手完成，转到等待状态
                    state_nxt = MMU_STATE_TLB_WAIT;
                    tlb_lookup_valid_nxt = 1'b0;
                end
            end
            
            MMU_STATE_TLB_WAIT: begin
                // 等待TLB查找结果（延迟一个周期）
                if (mmu_tlb.resp_valid) begin
                    if (mmu_tlb.resp_hit) begin
                        // TLB命中
                        paddr_nxt = mmu_tlb.resp_paddr;
                        tlb_hit_count_nxt = tlb_hit_count_r + 1;
                        state_nxt = MMU_STATE_RESPONSE;
                    end else begin
                        // TLB未命中，开始页表查找
                        tlb_miss_count_nxt = tlb_miss_count_r + 1;
                        state_nxt = MMU_STATE_PAGE_WALK;
                    end
                end
            end
            
            MMU_STATE_PAGE_WALK: begin
                // 页表查找请求 
                noc_req_valid_nxt = 1'b1;
                noc_req_header_nxt = build_noc_header_mem_request(8'h01, NODE_CONTROL, NOC_NODE_CONTROL_MMU);
                noc_req_data_nxt = build_noc_payload_request_mem_read(calc_page_table_addr(vaddr_r, current_pt_base_r, page_level_r), NOC_SIZE_8B);
                noc_req_last_nxt = 1'b1;
                
                if (noc_req_accept) begin
                    page_walk_count_nxt = page_walk_count_r + 1;
                    state_nxt = MMU_STATE_PAGE_WAIT;
                    noc_req_valid_nxt = 1'b0;
                end
            end
            
            MMU_STATE_PAGE_WAIT: begin
                logic [63:0] respaddr;
                noc_resp_ready_nxt = 1'b1;
                respaddr = select_resp_data(noc_if.m_resp_data);
                
                if (noc_resp_accept && noc_if.m_resp_status == 2'b00) begin
                    // 使用查找表确定下一步状态
                    case (page_level_r)
                        L1_LEVEL: begin
                            current_pt_base_nxt = respaddr[PA_WIDTH-1:0];
                            page_level_nxt = L2_LEVEL;
                            state_nxt = MMU_STATE_PAGE_WALK;
                            noc_resp_ready_nxt = 1'b0;
                        end
                        L2_LEVEL: begin
                            current_pt_base_nxt = respaddr[PA_WIDTH-1:0];
                            page_level_nxt = L3_LEVEL;
                            state_nxt = MMU_STATE_PAGE_WALK;
                            noc_resp_ready_nxt = 1'b0;
                        end
                        L3_LEVEL: begin
                            // L3页表查找成功，得到物理页号
                            paddr_nxt = {respaddr[PA_WIDTH-1:PAGE_OFFSET_BITS], vaddr_r[PAGE_OFFSET_BITS-1:0]};
                            
                            // 更新TLB - 设置输出寄存器
                            tlb_update_valid_nxt = 1'b1;

                            state_nxt = MMU_STATE_TLB_UPDATE;
                            noc_resp_ready_nxt = 1'b0;
                        end
                        default: begin
                            state_nxt = MMU_STATE_ERROR;
                            noc_resp_ready_nxt = 1'b0;
                        end
                    endcase
                end else if (noc_resp_accept) begin
                    // 页表查找失败
                    state_nxt = MMU_STATE_ERROR;
                    noc_resp_ready_nxt = 1'b0;
                end
            end
            
            MMU_STATE_TLB_UPDATE: begin
                if (tlb_update_valid_r && mmu_tlb.update_ready) begin
                    state_nxt = MMU_STATE_RESPONSE;
                    tlb_update_valid_nxt = 1'b0;
                end
            end
            
            MMU_STATE_RESPONSE: begin
                // 根据请求来源发送响应
                if (current_req.source == REQ_SOURCE_CP) begin
                    // 响应CP请求
                    if (cp_resp_accept) begin
                        state_nxt = MMU_STATE_IDLE;
                    end
                end else if (current_req.source == REQ_SOURCE_GPC) begin
                    // 响应GPC请求
                    noc_s_resp_valid_nxt = 1'b1;
                    noc_s_resp_header_nxt = build_noc_header_mmu_response(
                        current_req.trans_id,
                        NODE_SHADER_0 + current_req.gpc_id,
                        NOC_NODE_CONTROL_MMU
                    );
                    // 构建响应数据
                    noc_s_resp_data_nxt = build_mmu_response_data(paddr_r, current_req.tpc_id, current_req.gpc_id);
                    
                    // 等待NOC接受响应
                    if (noc_if.s_resp_ready) begin
                        state_nxt = MMU_STATE_IDLE;
                        noc_s_resp_valid_nxt = 1'b0;
                    end
                end
            end
            
            MMU_STATE_ERROR: begin
                // 根据请求来源发送错误响应
                if (current_req.source == REQ_SOURCE_CP) begin
                    if (cp_resp_accept) begin
                        state_nxt = MMU_STATE_IDLE;
                    end
                end else if (current_req.source == REQ_SOURCE_GPC) begin
                    noc_s_resp_valid_nxt = 1'b1;
                    noc_s_resp_header_nxt = build_noc_header_mmu_response(
                        current_req.trans_id,
                        NODE_SHADER_0 + current_req.gpc_id,
                        NOC_NODE_CONTROL_MMU
                    );
                    // 构建错误响应数据
                    noc_s_resp_data_nxt = build_mmu_error_data();
                    
                    // 等待NOC接受响应
                    if (noc_if.s_resp_ready) begin
                        state_nxt = MMU_STATE_IDLE;
                        noc_s_resp_valid_nxt = 1'b0;
                    end
                end
            end
            
            default: begin
                // 错误处理 - 在无效情况下使用 X 值
                state_nxt = MMU_STATE_IDLE;
                paddr_nxt = 'x;
            end
        endcase
    end
    
    //=============================================================================
    // 8. 时序逻辑 - 使用 always_ff 处理时序逻辑
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // 状态寄存器复位
            state_r <= MMU_STATE_IDLE;
            vaddr_r <= '0;
            paddr_r <= '0;
            req_type_r <= MMU_READ;
            page_level_r <= L1_LEVEL;
            current_pt_base_r <= '0;
            tlb_hit_count_r <= '0;
            tlb_miss_count_r <= '0;
            page_walk_count_r <= '0;
            
            // 输出控制寄存器复位
            tlb_lookup_valid_r <= 1'b0;
            tlb_update_valid_r <= 1'b0;
            
            noc_req_valid_r <= 1'b0;
            noc_req_header_r <= '0;
            noc_req_data_r <= '0;
            noc_req_last_r <= 1'b0;
            noc_resp_ready_r <= 1'b0;
            
            // NOC响应寄存器复位
            noc_s_resp_valid_r <= 1'b0;
            noc_s_resp_header_r <= '0;
            noc_s_resp_data_r <= '0;
        end else begin
            // 状态更新
            state_r <= state_nxt;
            vaddr_r <= vaddr_nxt;
            paddr_r <= paddr_nxt;
            req_type_r <= req_type_nxt;
            page_level_r <= page_level_nxt;
            current_pt_base_r <= current_pt_base_nxt;
            tlb_hit_count_r <= tlb_hit_count_nxt;
            tlb_miss_count_r <= tlb_miss_count_nxt;
            page_walk_count_r <= page_walk_count_nxt;
            
            // 输出控制寄存器更新
            tlb_lookup_valid_r <= tlb_lookup_valid_nxt;
            tlb_update_valid_r <= tlb_update_valid_nxt;
            noc_req_valid_r <= noc_req_valid_nxt;
            noc_req_header_r <= noc_req_header_nxt;
            noc_req_data_r <= noc_req_data_nxt;
            noc_req_last_r <= noc_req_last_nxt;
            noc_resp_ready_r <= noc_resp_ready_nxt;
            
            // NOC响应寄存器更新
            noc_s_resp_valid_r <= noc_s_resp_valid_nxt;
            noc_s_resp_header_r <= noc_s_resp_header_nxt;
            noc_s_resp_data_r <= noc_s_resp_data_nxt;
        end
    end
    
    //=============================================================================
    // 9. 配置处理时序逻辑
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            page_table_base_r <= '0;
        end else begin
            if (mmu_config_if.cfg_en) begin
                page_table_base_r <= mmu_config_if.cfg_base_addr;
                `DEBUG_PRINT("MMU", $sformatf("MMU cfg_en, page_table_base: 0x%h", mmu_config_if.cfg_base_addr));
            end
        end
    end
    
    //=============================================================================
    // 10. 输出逻辑 - 使用三元运算符进行条件赋值
    //=============================================================================
    
    // TLB接口连接
    assign mmu_tlb.req_valid = tlb_lookup_valid_r;
    assign mmu_tlb.req_vaddr = vaddr_r;
    assign mmu_tlb.resp_ready = (state_r == MMU_STATE_TLB_WAIT);
    assign mmu_tlb.update_valid = tlb_update_valid_r;
    assign mmu_tlb.update_vaddr = vaddr_r;
    assign mmu_tlb.update_paddr = paddr_r;
    
    // NOC接口连接 - 页表访问
    assign noc_if.m_req_valid = noc_req_valid_r;
    assign noc_if.m_req_header = noc_req_header_r;
    assign noc_if.m_req_data = noc_req_data_r;
    assign noc_if.m_req_strb = '0;
    assign noc_if.m_req_last = noc_req_last_r;
    assign noc_if.m_resp_ready = noc_resp_ready_r;
    
    // NOC接口连接 - GPC请求响应
    assign noc_if.s_req_ready = !req_buffer_full;  // 当缓冲区不满时接受请求
    assign noc_if.s_resp_valid = noc_s_resp_valid_r;
    assign noc_if.s_resp_header = noc_s_resp_header_r;
    assign noc_if.s_resp_data = noc_s_resp_data_r;
    assign noc_if.s_resp_status = 2'b00;  // 成功状态
    assign noc_if.s_resp_last = 1'b1;
    
    // CP接口输出
    assign mmu_if.req_ready = !req_buffer_full;  // 当缓冲区不满时接受请求
    assign mmu_if.resp_valid = (state_r == MMU_STATE_RESPONSE && current_req.source == REQ_SOURCE_CP) || 
                               (state_r == MMU_STATE_ERROR && current_req.source == REQ_SOURCE_CP);
    assign mmu_if.resp_paddr = paddr_r;
    assign mmu_if.resp_hit = (state_r == MMU_STATE_RESPONSE);
    assign mmu_if.resp_status = (state_r == MMU_STATE_ERROR) ? MMU_RESP_FAULT : MMU_RESP_OKAY;
    
    //=============================================================================
    // 11. 辅助函数
    //=============================================================================
    
    // 选择响应数据函数
    function automatic logic [63:0] select_resp_data(input logic [255:0] data);
        logic [63:0] result;
        case (noc_req_data_r.req_mem_read.addr[4:3])
            2'b00: result = data[63:0];
            2'b01: result = data[127:64];
            2'b10: result = data[191:128];
            2'b11: result = data[255:192];
        endcase
        return result;
    endfunction
    
    // 构建CP请求缓冲区条目
    function automatic req_buffer_entry_t build_cp_req_entry(
        input logic [VA_WIDTH-1:0] vaddr,
        input mmu_access_type_e req_type
    );
        req_buffer_entry_t entry;
        entry.valid = 1'b1;
        entry.pending = 1'b0;
        entry.source = REQ_SOURCE_CP;
        entry.vaddr = vaddr;
        entry.req_type = req_type;
        entry.trans_id = 8'h0;
        entry.tpc_id = 4'h0;
        entry.gpc_id = 4'h0;
        return entry;
    endfunction
    
    // 构建GPC请求缓冲区条目
    function automatic req_buffer_entry_t build_gpc_req_entry(
        input noc_header_t header,
        input noc_req_mmu_t payload
    );
        req_buffer_entry_t entry;
        entry.valid = 1'b1;
        entry.pending = 1'b0;
        entry.source = REQ_SOURCE_GPC;
        entry.vaddr = payload.vaddr;
        entry.req_type = payload.req_type;
        entry.trans_id = header.trans_id;
        entry.tpc_id = payload.tpc_id;
        entry.gpc_id = payload.gpc_id;
        return entry;
    endfunction
    
    // 检查是否可以接受新请求
    function automatic logic can_accept_request();
        return !req_buffer_full;
    endfunction
    
    // 检查是否可以处理请求
    function automatic logic can_process_request();
        return !req_buffer_empty && !current_req.pending;
    endfunction
    
    // 构建MMU响应数据
    function automatic logic [255:0] build_mmu_response_data(
        input logic [PA_WIDTH-1:0] paddr,
        input logic [3:0] tpc_id,
        input logic [3:0] gpc_id
    );
        return {paddr, 32'h0, tpc_id, gpc_id};
    endfunction
    
    // 构建MMU错误响应数据
    function automatic logic [255:0] build_mmu_error_data();
        return {32'h0, 32'h0, 32'h0, 32'h1}; // 错误标志
    endfunction

    //=============================================================================
    // 12. 调试输出 - 简化版本
    //=============================================================================
    generate
    if (1) begin : gen_debug
        always_ff @(posedge clk) begin
            // CP请求调试
            if (cp_req_accept) begin
                `DEBUG_PRINT("MMU", $sformatf("CP MMU Request, vaddr: 0x%h, req_type: %s", mmu_if.req_vaddr, mmu_if.req_type.name()));
            end
            
            // GPC请求调试
            if (gpc_req_accept) begin
                `DEBUG_PRINT("MMU", $sformatf("GPC MMU Request, %s", noc_request_mmu_to_string(noc_if.s_req_header, noc_if.s_req_data)));
            end

            if ((state_r == MMU_STATE_PAGE_WAIT) && noc_resp_accept) begin
                `DEBUG_PRINT("MMU", $sformatf("L%-d Page Wait, Noc response: %s", page_level_r + 1, noc_response_mem_read_to_string(noc_if.m_resp_header, noc_if.m_resp_data)));
            end

            if (state_r == MMU_STATE_PAGE_WALK && noc_req_accept) begin
                `DEBUG_PRINT("MMU", $sformatf("Page Walk, %s", noc_request_mem_read_to_string(noc_req_header_nxt, noc_req_data_nxt)));
            end

            if ((state_r == MMU_STATE_TLB_WAIT) && mmu_tlb.resp_valid) begin
                if (mmu_tlb.resp_hit) begin
                    `DEBUG_PRINT("MMU", $sformatf("TLB Hit, paddr: 0x%h", mmu_tlb.resp_paddr));
                end else begin
                    `DEBUG_PRINT("MMU", $sformatf("TLB Miss, vaddr: 0x%h", vaddr_r));
                end
            end

            // 监控TLB握手
            if (tlb_lookup_valid_r && mmu_tlb.req_ready) begin
                `DEBUG_PRINT("MMU", $sformatf("TLB lookup handshake detected"));
            end
            if (tlb_update_valid_r && mmu_tlb.update_ready) begin
                `DEBUG_PRINT("MMU", $sformatf("TLB update handshake detected"));
            end
            
            // TLB信号调试
            if (tlb_lookup_valid_r) begin
                `DEBUG_PRINT("MMU", $sformatf("TLB lookup request: valid=%b, ready=%b, vaddr=0x%h", 
                         tlb_lookup_valid_r, mmu_tlb.req_ready, vaddr_r));
            end
            if (mmu_tlb.resp_valid) begin
                `DEBUG_PRINT("MMU", $sformatf("TLB response: valid=%b, ready=%b, hit=%b, paddr=0x%h", 
                         mmu_tlb.resp_valid, mmu_tlb.resp_ready, mmu_tlb.resp_hit, mmu_tlb.resp_paddr));
            end
            
            // 详细的状态调试
            if (state_r == MMU_STATE_TLB_WAIT) begin
                `DEBUG_PRINT("MMU", $sformatf("In MMU_STATE_TLB_WAIT: resp_valid=%b, resp_ready=%b", 
                         mmu_tlb.resp_valid, mmu_tlb.resp_ready));
            end
            if (state_r == MMU_STATE_TLB_LOOKUP) begin
                `DEBUG_PRINT("MMU", $sformatf("In MMU_STATE_TLB_LOOKUP: req_valid=%b, req_ready=%b, tlb_lookup_valid_r=%b, tlb_lookup_valid_nxt=%b", 
                         tlb_lookup_valid_r, mmu_tlb.req_ready, tlb_lookup_valid_r, tlb_lookup_valid_nxt));
            end
            
            // 状态转换调试
            if (state_r != state_nxt) begin
                `DEBUG_PRINT("MMU", $sformatf("State transition: %s -> %s", state_r.name(), state_nxt.name()));
            end
            
            // 缓冲区状态调试
            if (req_buffer_full) begin
                `DEBUG_PRINT("MMU", $sformatf("Request buffer full!"));
            end
            if (!req_buffer_empty && !current_req.pending) begin
                `DEBUG_PRINT("MMU", $sformatf("Processing request from %s, vaddr: 0x%h", 
                         current_req.source.name(), current_req.vaddr));
            end
        end
    end
    endgenerate

endmodule : rvgpu_mmu

`endif // RVGPU_MMU_SV 