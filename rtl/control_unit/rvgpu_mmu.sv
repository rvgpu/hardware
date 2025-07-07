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
`include "rvgpu_mmu_tlb.sv"

module rvgpu_mmu #(
    parameter control_unit_config_t CONTROL_UNIT_CONFIG = DEFAULT_CONTROL_UNIT_CONFIG,
    parameter int DEBUG = 1
) (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // 命令处理器接口
    mmu_if.mmu_port mmu_if,

    // 页表访问NOC接口
    rvgpu_internal_noc_if.device noc_if
);

    //=============================================================================
    // 1. 状态机定义 - 明确定义所有状态
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
    // 2. 参数化设计 - 使用 localparam 定义所有常量
    //=============================================================================
    
    // 地址位宽参数
    localparam int VA_WIDTH = CONTROL_UNIT_CONFIG.va_width;
    localparam int PA_WIDTH = CONTROL_UNIT_CONFIG.pa_width;
    localparam int TLB_ENTRIES = CONTROL_UNIT_CONFIG.tlb_entries;
    localparam int TLB_TAG_BITS = `RVGPU_CONST_CU_TLB_TAG_BITS;
    localparam int PPN_BITS = `RVGPU_CONST_CU_TLB_PPN_BITS;
    
    // 页表相关常量
    localparam int PAGE_OFFSET_BITS = 12;  // 4KB页大小
    localparam int PAGE_INDEX_BITS = 9;    // 每级页表索引位数
    localparam int PAGE_ENTRY_SIZE = 8;    // 页表条目大小（字节）
    localparam int PAGE_ENTRY_SHIFT = 3;   // 页表条目大小对数（8字节 = 2^3）
    
    // 页表级别常量
    localparam int MAX_PAGE_LEVELS = 3;    // 最大页表级别
    localparam int L1_LEVEL = 2'b00;       // L1页表级别
    localparam int L2_LEVEL = 2'b01;       // L2页表级别
    localparam int L3_LEVEL = 2'b10;       // L3页表级别
    
    //=============================================================================
    // 3. 内部信号定义 - 使用清晰的前缀命名规范
    //=============================================================================
    
    // 状态机寄存器
    mmu_state_t state_r, state_nxt;
    
    // 数据寄存器
    logic [VA_WIDTH-1:0] vaddr_r, vaddr_nxt;
    logic [PA_WIDTH-1:0] paddr_r, paddr_nxt;
    logic req_read_r, req_read_nxt;
    logic req_write_r, req_write_nxt;
    
    // TLB接口
    tlb_if #(
        .TLB_ENTRIES(TLB_ENTRIES),
        .TLB_TAG_BITS(TLB_TAG_BITS),
        .PPN_BITS(PPN_BITS)
    ) mmu_tlb();
    
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
    logic [TLB_TAG_BITS + $clog2(TLB_ENTRIES) - 1:0] tlb_lookup_addr_r, tlb_lookup_addr_nxt;
    logic tlb_update_valid_r, tlb_update_valid_nxt;
    logic [$clog2(TLB_ENTRIES)-1:0] tlb_update_addr_r, tlb_update_addr_nxt;
    tlb_entry_t tlb_update_data_r, tlb_update_data_nxt;
    
    logic noc_req_valid_r, noc_req_valid_nxt;
    logic [31:0] noc_req_header_r, noc_req_header_nxt;
    logic [63:0] noc_req_data_r, noc_req_data_nxt;
    logic noc_req_last_r, noc_req_last_nxt;
    logic noc_resp_ready_r, noc_resp_ready_nxt;
    
    //=============================================================================
    // 4. 辅助函数 - 使用位掩码进行信号验证和过滤
    //=============================================================================
    
    // TLB地址计算函数 - 优化版本
    function automatic logic [TLB_TAG_BITS + $clog2(TLB_ENTRIES) - 1:0] calc_tlb_addr(
        input logic [VA_WIDTH-1:0] vaddr
    );
        // TLB地址格式：{标签, 索引}
        // 标签：虚拟地址的高位（除去页内偏移和索引位）
        // 索引：虚拟地址的中间位（用于SRAM地址）
        localparam int INDEX_BITS = $clog2(TLB_ENTRIES);
        localparam int TAG_START = VA_WIDTH - 1;
        localparam int TAG_END = PAGE_OFFSET_BITS + INDEX_BITS;
        localparam int INDEX_START = PAGE_OFFSET_BITS + INDEX_BITS - 1;
        localparam int INDEX_END = PAGE_OFFSET_BITS;
        
        logic [TLB_TAG_BITS-1:0] tag = {{TLB_TAG_BITS-(TAG_START-TAG_END+1){1'b0}}, vaddr[TAG_START:TAG_END]};
        logic [INDEX_BITS-1:0] index = vaddr[INDEX_START:INDEX_END];

        return {tag, index};
    endfunction
    
    // 多级页表地址计算函数
    function automatic logic [PA_WIDTH-1:0] calc_page_table_addr(
        input logic [VA_WIDTH-1:0] vaddr,
        input logic [PA_WIDTH-1:0] base_addr,
        input logic [1:0] level
    );
        logic [PAGE_INDEX_BITS-1:0] page_index;
        case (level)
            L1_LEVEL: page_index = vaddr[38:30];  // L1索引
            L2_LEVEL: page_index = vaddr[29:21];  // L2索引
            L3_LEVEL: page_index = vaddr[20:12];  // L3索引
            default: page_index = '0;
        endcase
        // 页表条目是8字节，所以索引需要左移3位
        return base_addr + {page_index, 3'b0};
    endfunction
    
    //=============================================================================
    // 5. 握手信号抽象 - 使用三元运算符进行条件赋值
    //=============================================================================
    
    wire req_accept = mmu_if.req_valid && mmu_if.req_ready;
    wire resp_accept = mmu_if.resp_valid && mmu_if.resp_ready;
    wire noc_req_accept = noc_req_valid_r && noc_if.m_req_ready;
    wire noc_resp_accept = noc_if.m_resp_valid && noc_resp_ready_r;
    
    //=============================================================================
    // 6. TLB实例化
    //=============================================================================
    
    rvgpu_mmu_tlb #(
        .TLB_ENTRIES(TLB_ENTRIES),
        .TLB_TAG_BITS(TLB_TAG_BITS),
        .PPN_BITS(PPN_BITS),
        .DEBUG(0)
    ) u_mmu_tlb (
        .clk(clk),
        .rst_n(rst_n),
        .tlb_if(mmu_tlb.tlb_port)
    );
    
    //=============================================================================
    // 6. 组合逻辑 - 使用 always_comb 处理组合逻辑
    //=============================================================================
    
    // 状态机组合逻辑
    always_comb begin
        // 默认值 - 避免锁存器
        state_nxt = state_r;
        vaddr_nxt = vaddr_r;
        paddr_nxt = paddr_r;
        req_read_nxt = req_read_r;
        req_write_nxt = req_write_r;
        current_pt_base_nxt = current_pt_base_r;
        page_level_nxt = page_level_r;
        tlb_hit_count_nxt = tlb_hit_count_r;
        tlb_miss_count_nxt = tlb_miss_count_r;
        page_walk_count_nxt = page_walk_count_r;
        
        // 输出控制寄存器默认值
        tlb_lookup_valid_nxt = 1'b0;
        tlb_lookup_addr_nxt = tlb_lookup_addr_r;
        tlb_update_valid_nxt = 1'b0;
        tlb_update_addr_nxt = tlb_update_addr_r;
        tlb_update_data_nxt = tlb_update_data_r;
        noc_req_valid_nxt = 1'b0;
        noc_req_header_nxt = noc_req_header_r;
        noc_req_data_nxt = noc_req_data_r;
        noc_req_last_nxt = noc_req_last_r;
        noc_resp_ready_nxt = noc_resp_ready_r;
        
        case (state_r)
            MMU_STATE_IDLE: begin
                if (req_accept) begin
                    state_nxt = MMU_STATE_TLB_LOOKUP;
                    vaddr_nxt = mmu_if.req_vaddr;
                    req_read_nxt = mmu_if.req_read;
                    req_write_nxt = mmu_if.req_write;
                    page_level_nxt = L1_LEVEL;  // 从L1开始
                    current_pt_base_nxt = page_table_base_r;  // 使用配置的页表基地址
                end
            end
            
            MMU_STATE_TLB_LOOKUP: begin
                // TLB查找 - 设置输出寄存器
                tlb_lookup_valid_nxt = 1'b1;
                tlb_lookup_addr_nxt = {vaddr_r[38:19], vaddr_r[18:12]};
                
                // 等待TLB查找完成（同步查找需要等待一个周期）
                if (tlb_lookup_valid_r && mmu_tlb.tlb_lookup_ready) begin
                    // 等待下一个周期获取结果
                    state_nxt = MMU_STATE_TLB_WAIT;
                    tlb_lookup_valid_nxt = 1'b0;
                end
            end
            
            MMU_STATE_TLB_WAIT: begin
                // 等待TLB查找结果（延迟一个周期）
                if (mmu_tlb.tlb_lookup_ready) begin
                    if (mmu_tlb.tlb_lookup_hit) begin
                        // TLB命中
                        paddr_nxt = {mmu_tlb.tlb_lookup_data.ppn, vaddr_r[PAGE_OFFSET_BITS-1:0]};
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
                // 页表查找请求 - 使用查找表减少if语句
                noc_req_valid_nxt = 1'b1;
                noc_req_header_nxt = build_noc_header(MSG_MEM_READ_REQ, 8'h01, NODE_CONTROL, NODE_L2_CACHE, 8'h00);
                noc_req_data_nxt = calc_page_table_addr(vaddr_r, current_pt_base_r, page_level_r);
                noc_req_last_nxt = 1'b1;
                
                if (noc_req_accept) begin
                    page_walk_count_nxt = page_walk_count_r + 1;
                    state_nxt = MMU_STATE_PAGE_WAIT;
                    noc_req_valid_nxt = 1'b0;
                end
            end
            
            MMU_STATE_PAGE_WAIT: begin
                noc_resp_ready_nxt = 1'b1;
                
                if (noc_resp_accept && noc_if.m_resp_status == 2'b00) begin
                    // 使用查找表确定下一步状态
                    case (page_level_r)
                        L1_LEVEL: begin
                            current_pt_base_nxt = noc_if.m_resp_data[PA_WIDTH-1:0];
                            page_level_nxt = L2_LEVEL;
                            state_nxt = MMU_STATE_PAGE_WALK;
                            noc_resp_ready_nxt = 1'b0;
                        end
                        L2_LEVEL: begin
                            current_pt_base_nxt = noc_if.m_resp_data[PA_WIDTH-1:0];
                            page_level_nxt = L3_LEVEL;
                            state_nxt = MMU_STATE_PAGE_WALK;
                            noc_resp_ready_nxt = 1'b0;
                        end
                        L3_LEVEL: begin
                            // L3页表查找成功，得到物理页号
                            paddr_nxt = {noc_if.m_resp_data[PA_WIDTH-1:PAGE_OFFSET_BITS], vaddr_r[PAGE_OFFSET_BITS-1:0]};
                            
                            // 更新TLB - 设置输出寄存器
                            tlb_update_valid_nxt = 1'b1;
                            tlb_update_addr_nxt = calc_tlb_addr(vaddr_r);
                            tlb_update_data_nxt = '{
                                valid: 1'b1,
                                dirty: 1'b0,
                                accessed: 1'b1,
                                permission: 2'b11,  // 读写权限
                                tag: vaddr_r[VA_WIDTH-1:PAGE_OFFSET_BITS+$clog2(TLB_ENTRIES)],
                                ppn: noc_if.m_resp_data[PA_WIDTH-1:PAGE_OFFSET_BITS]
                            };
                            
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
                if (tlb_update_valid_r && mmu_tlb.tlb_update_ready) begin
                    state_nxt = MMU_STATE_RESPONSE;
                    tlb_update_valid_nxt = 1'b0;
                end
            end
            
            MMU_STATE_RESPONSE: begin
                if (resp_accept) begin
                    state_nxt = MMU_STATE_IDLE;
                end
            end
            
            MMU_STATE_ERROR: begin
                if (resp_accept) begin
                    state_nxt = MMU_STATE_IDLE;
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
    // 7. 时序逻辑 - 使用 always_ff 处理时序逻辑
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // 状态寄存器复位
            state_r <= MMU_STATE_IDLE;
            vaddr_r <= '0;
            paddr_r <= '0;
            req_read_r <= 1'b0;
            req_write_r <= 1'b0;
            page_level_r <= L1_LEVEL;
            current_pt_base_r <= '0;
            tlb_hit_count_r <= '0;
            tlb_miss_count_r <= '0;
            page_walk_count_r <= '0;
            
            // 输出控制寄存器复位
            tlb_lookup_valid_r <= 1'b0;
            tlb_lookup_addr_r <= '0;
            tlb_update_valid_r <= 1'b0;
            tlb_update_addr_r <= '0;
            tlb_update_data_r <= '0;
            
            noc_req_valid_r <= 1'b0;
            noc_req_header_r <= '0;
            noc_req_data_r <= '0;
            noc_req_last_r <= 1'b0;
            noc_resp_ready_r <= 1'b0;
        end else begin
            // 状态更新
            state_r <= state_nxt;
            vaddr_r <= vaddr_nxt;
            paddr_r <= paddr_nxt;
            req_read_r <= req_read_nxt;
            req_write_r <= req_write_nxt;
            page_level_r <= page_level_nxt;
            current_pt_base_r <= current_pt_base_nxt;
            tlb_hit_count_r <= tlb_hit_count_nxt;
            tlb_miss_count_r <= tlb_miss_count_nxt;
            page_walk_count_r <= page_walk_count_nxt;
            
            // 输出控制寄存器更新
            tlb_lookup_valid_r <= tlb_lookup_valid_nxt;
            tlb_lookup_addr_r <= tlb_lookup_addr_nxt;
            tlb_update_valid_r <= tlb_update_valid_nxt;
            tlb_update_addr_r <= tlb_update_addr_nxt;
            tlb_update_data_r <= tlb_update_data_nxt;
            noc_req_valid_r <= noc_req_valid_nxt;
            noc_req_header_r <= noc_req_header_nxt;
            noc_req_data_r <= noc_req_data_nxt;
            noc_req_last_r <= noc_req_last_nxt;
            noc_resp_ready_r <= noc_resp_ready_nxt;
        end
    end
    
    //=============================================================================
    // 8. 配置处理时序逻辑
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            page_table_base_r <= '0;
        end else begin
            if (mmu_if.cfg_en) begin
                page_table_base_r <= mmu_if.cfg_base_addr;
            end
        end
    end
    
    //=============================================================================
    // 9. 输出逻辑 - 使用三元运算符进行条件赋值
    //=============================================================================
    
    // TLB接口连接
    assign mmu_tlb.tlb_lookup_valid = tlb_lookup_valid_r;
    assign mmu_tlb.tlb_lookup_addr = tlb_lookup_addr_r;
    assign mmu_tlb.tlb_update_valid = tlb_update_valid_r;
    assign mmu_tlb.tlb_update_addr = tlb_update_addr_r;
    assign mmu_tlb.tlb_update_data = tlb_update_data_r;
    
    // NOC接口连接
    assign noc_if.m_req_valid = noc_req_valid_r;
    assign noc_if.m_req_header = noc_req_header_r;
    assign noc_if.m_req_data = noc_req_data_r;
    assign noc_if.m_req_strb = '0;
    assign noc_if.m_req_last = noc_req_last_r;
    assign noc_if.m_resp_ready = noc_resp_ready_r;
    
    // MMU接口输出
    assign mmu_if.req_ready = (state_r == MMU_STATE_IDLE);
    assign mmu_if.resp_valid = (state_r == MMU_STATE_RESPONSE) || (state_r == MMU_STATE_ERROR);
    assign mmu_if.resp_paddr = paddr_r;
    assign mmu_if.resp_hit = (state_r == MMU_STATE_RESPONSE);
    assign mmu_if.resp_status = (state_r == MMU_STATE_ERROR) ? 2'b10 : 2'b00;
    
    //=============================================================================
    // 10. 调试输出 - 使用 generate 块进行条件编译
    //=============================================================================
    
    generate
    if (DEBUG) begin : gen_debug
        always_ff @(posedge clk) begin
            // 监控TLB握手
            if (tlb_lookup_valid_r && mmu_tlb.tlb_lookup_ready) begin
                $display("@%0t: [MMU] TLB lookup handshake detected", $time);
            end
            if (tlb_update_valid_r && mmu_tlb.tlb_update_ready) begin
                $display("@%0t: [MMU] TLB update handshake detected", $time);
            end
            
            // 状态转换调试
            if (state_r != state_nxt) begin
                $display("@%0t: [MMU] State transition: %s -> %s", $time, 
                         state_r.name(), state_nxt.name());
            end
        end
    end
    endgenerate

endmodule : rvgpu_mmu

`endif // RVGPU_MMU_SV 