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

`ifndef RVGPU_L2CACHE_TAG_ARRAY_SV
`define RVGPU_L2CACHE_TAG_ARRAY_SV

`include "rvgpu_l2cache_pkg.svh"
`include "rvgpu_l2cache_if.svh"
`include "rvgpu_sram_if.svh"

`ifndef RVGPU_L2CACHE_PKG_IMPORTED
`define RVGPU_L2CACHE_PKG_IMPORTED
import rvgpu_l2cache_pkg::*;
`endif // RVGPU_L2CACHE_PKG_IMPORTED

//=============================================================================
// RVGPU L2 Cache Tag Array
// 
// 主要功能：
// 1. Tag条目存储和管理
// 2. 并行Tag查找
// 3. Tag更新和替换
// 4. LRU替换策略支持
// 5. MESI一致性状态管理
//=============================================================================

module rvgpu_l2cache_tag_array #(
    parameter l2cache_config_t L2CACHE_CONFIG = DEFAULT_L2CACHE_CONFIG
) (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // Controller Interface
    l2cache_tag_if.tag_array tag_if
);

    //=============================================================================
    // Local Parameters and Types
    //=============================================================================
    
    // 从配置中提取的本地参数
    localparam int TAG_BITS = L2CACHE_CONFIG.tag_bits;
    localparam int INDEX_BITS = L2CACHE_CONFIG.index_bits;
    localparam int WAYS = L2CACHE_CONFIG.ways;
    localparam int LRU_BITS = L2CACHE_CONFIG.lru_bits;
    
    // SRAM参数
    localparam int TAG_DATA_WIDTH = $bits(l2cache_tag_entry_t);
    localparam int TAG_ADDR_WIDTH = INDEX_BITS;
    localparam int TAG_DEPTH = L2CACHE_CONFIG.sets;
    
    // 状态机参数
    localparam int STATE_BITS = 2;
    localparam int STATE_IDLE = 2'b00;
    localparam int STATE_LOOKUP = 2'b01;
    localparam int STATE_UPDATE = 2'b10;
    
    //=============================================================================
    // Internal Registers and Signals
    //=============================================================================
    
    // 状态机寄存器
    logic [STATE_BITS-1:0] state_r, state_nxt;
    
    // 查找请求寄存器
    logic [TAG_ADDR_WIDTH-1:0] lookup_index_r, lookup_index_nxt;
    logic [TAG_BITS-1:0] lookup_tag_r, lookup_tag_nxt;
    
    // 更新请求寄存器
    logic [TAG_ADDR_WIDTH-1:0] update_index_r, update_index_nxt;
    logic [WAYS-1:0] update_way_r, update_way_nxt;
    l2cache_tag_entry_t update_entry_r, update_entry_nxt;
    
    // 查找结果寄存器
    logic lookup_hit_r, lookup_hit_nxt;
    logic [WAYS-1:0] hit_way_r, hit_way_nxt;
    l2cache_tag_entry_t tag_entry_r, tag_entry_nxt;
    logic lookup_done_r, lookup_done_nxt;
    logic update_done_r, update_done_nxt;
    
    // SRAM接口信号
    logic sram_ce_r, sram_ce_nxt;
    logic sram_we_r, sram_we_nxt;
    logic [TAG_ADDR_WIDTH-1:0] sram_addr_r, sram_addr_nxt;
    logic [TAG_DATA_WIDTH-1:0] sram_wdata_r, sram_wdata_nxt;
    logic [TAG_DATA_WIDTH-1:0] sram_rdata;
    
    // Tag比较信号
    logic [WAYS-1:0] way_hit;
    logic any_hit;
    
    //=============================================================================
    // SRAM实例化
    //=============================================================================
    
    // 创建SRAM接口实例
    rvgpu_sram_if #(
        .WIDTH(TAG_DATA_WIDTH),
        .HEIGHT(TAG_DEPTH)
    ) sram_if_inst();
    
    // 连接时钟
    assign sram_if_inst.clk = clk;
    
    // SRAM实例化
    rvgpu_sram_sp #(
        .WIDTH(TAG_DATA_WIDTH),
        .HEIGHT(TAG_DEPTH),
        .RAMNAME("L2CACHE_TAG_SRAM")
    ) u_tag_sram (
        .sram_if(sram_if_inst.sram_port)
    );
    
    //=============================================================================
    // 组合逻辑 - 状态机和输出控制
    //=============================================================================
    
    always_comb begin : comb_logic
        // 默认值
        state_nxt = state_r;
        lookup_index_nxt = lookup_index_r;
        lookup_tag_nxt = lookup_tag_r;
        update_index_nxt = update_index_r;
        update_way_nxt = update_way_r;
        update_entry_nxt = update_entry_r;
        lookup_hit_nxt = lookup_hit_r;
        hit_way_nxt = hit_way_r;
        tag_entry_nxt = tag_entry_r;
        lookup_done_nxt = lookup_done_r;
        update_done_nxt = update_done_r;
        sram_ce_nxt = sram_ce_r;
        sram_we_nxt = sram_we_r;
        sram_addr_nxt = sram_addr_r;
        sram_wdata_nxt = sram_wdata_r;
        
        // SRAM接口控制
        sram_if_inst.ce = sram_ce_r;
        sram_if_inst.we = sram_we_r;
        sram_if_inst.addr = sram_addr_r;
        sram_if_inst.wdata = sram_wdata_r;
        sram_rdata = sram_if_inst.rdata;
        
        // 接口输出默认值
        tag_if.lookup_ready = (state_r == STATE_IDLE);
        tag_if.update_ready = (state_r == STATE_IDLE);
        tag_if.lookup_hit = lookup_hit_r;
        tag_if.hit_way = hit_way_r;
        tag_if.tag_entry = tag_entry_r;
        tag_if.lookup_done = lookup_done_r;
        tag_if.update_done = update_done_r;
        
        case (state_r)
            STATE_IDLE: begin
                // 空闲状态：等待新请求
                lookup_done_nxt = 1'b0;
                update_done_nxt = 1'b0;
                
                if (tag_if.lookup_valid) begin
                    // 开始Tag查找
                    state_nxt = STATE_LOOKUP;
                    lookup_index_nxt = tag_if.lookup_index;
                    lookup_tag_nxt = extract_tag_from_addr(tag_if.lookup_index, L2CACHE_CONFIG);
                    sram_ce_nxt = 1'b1;
                    sram_we_nxt = 1'b0;
                    sram_addr_nxt = tag_if.lookup_index;
                end else if (tag_if.update_valid) begin
                    // 开始Tag更新
                    state_nxt = STATE_UPDATE;
                    update_index_nxt = tag_if.update_index;
                    update_way_nxt = tag_if.update_way;
                    update_entry_nxt = tag_if.update_entry;
                    sram_ce_nxt = 1'b1;
                    sram_we_nxt = 1'b1;
                    sram_addr_nxt = tag_if.update_index;
                    sram_wdata_nxt = tag_entry_to_raw(tag_if.update_entry);
                end
            end
            
            STATE_LOOKUP: begin
                // Tag查找状态
                sram_ce_nxt = 1'b0; // 停止SRAM访问
                
                // 解析Tag条目
                tag_entry_nxt = raw_to_tag_entry(sram_rdata);
                
                // 并行比较所有way（固定8路）
                for (int i = 0; i < 8; i++) begin
                    way_hit[i] = tag_entry_nxt.valid[i] && 
                                 (tag_entry_nxt.tag[i] == lookup_tag_r);
                end
                
                any_hit = |way_hit;
                
                // 更新查找结果
                lookup_hit_nxt = any_hit;
                hit_way_nxt = way_hit;
                lookup_done_nxt = 1'b1;
                
                // 返回空闲状态
                state_nxt = STATE_IDLE;
            end
            
            STATE_UPDATE: begin
                // Tag更新状态
                sram_ce_nxt = 1'b0; // 停止SRAM访问
                
                // 更新完成
                update_done_nxt = 1'b1;
                
                // 返回空闲状态
                state_nxt = STATE_IDLE;
            end
            
            default: begin
                // 错误状态
                state_nxt = STATE_IDLE;
                lookup_hit_nxt = 1'bx;
                hit_way_nxt = 'x;
                tag_entry_nxt = 'x;
            end
        endcase
    end
    
    //=============================================================================
    // 辅助函数
    //=============================================================================
    
    // 从地址中提取Tag
    function automatic logic [TAG_BITS-1:0] extract_tag_from_addr(
        input logic [INDEX_BITS-1:0] index,
        input l2cache_config_t config
    );
        // 这里简化处理，实际应该从完整地址中提取
        return index; // 临时实现
    endfunction
    
    // Tag条目转换为原始数据
    function automatic logic [TAG_DATA_WIDTH-1:0] tag_entry_to_raw(
        input l2cache_tag_entry_t entry
    );
        logic [TAG_DATA_WIDTH-1:0] raw;
        logic [31:0] offset = 0;
        
        // 序列化Tag条目（固定8路）
        for (int i = 0; i < 8; i++) begin
            raw[offset +: 32] = entry.tag[i];
            offset += 32;
        end
        
        for (int i = 0; i < 8; i++) begin
            raw[offset +: 1] = entry.valid[i];
            offset += 1;
        end
        
        for (int i = 0; i < 8; i++) begin
            raw[offset +: 1] = entry.dirty[i];
            offset += 1;
        end
        
        for (int i = 0; i < 8; i++) begin
            raw[offset +: 2] = entry.mesi_state[i];
            offset += 2;
        end
        
        raw[offset +: 8] = entry.lru;
        
        return raw;
    endfunction
    
    // 原始数据转换为Tag条目
    function automatic l2cache_tag_entry_t raw_to_tag_entry(
        input logic [TAG_DATA_WIDTH-1:0] raw
    );
        l2cache_tag_entry_t entry;
        logic [31:0] offset = 0;
        
        // 反序列化Tag条目（固定8路）
        for (int i = 0; i < 8; i++) begin
            entry.tag[i] = raw[offset +: 32];
            offset += 32;
        end
        
        for (int i = 0; i < 8; i++) begin
            entry.valid[i] = raw[offset +: 1];
            offset += 1;
        end
        
        for (int i = 0; i < 8; i++) begin
            entry.dirty[i] = raw[offset +: 1];
            offset += 1;
        end
        
        for (int i = 0; i < 8; i++) begin
            entry.mesi_state[i] = raw[offset +: 2];
            offset += 2;
        end
        
        entry.lru = raw[offset +: 8];
        
        return entry;
    endfunction
    
    //=============================================================================
    // 时序逻辑 - 寄存器更新
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // 复位逻辑
            state_r <= STATE_IDLE;
            lookup_index_r <= '0;
            lookup_tag_r <= '0;
            update_index_r <= '0;
            update_way_r <= '0;
            update_entry_r <= '0;
            lookup_hit_r <= 1'b0;
            hit_way_r <= '0;
            tag_entry_r <= '0;
            lookup_done_r <= 1'b0;
            update_done_r <= 1'b0;
            sram_ce_r <= 1'b0;
            sram_we_r <= 1'b0;
            sram_addr_r <= '0;
            sram_wdata_r <= '0;
        end else begin
            // 状态更新
            state_r <= state_nxt;
            lookup_index_r <= lookup_index_nxt;
            lookup_tag_r <= lookup_tag_nxt;
            update_index_r <= update_index_nxt;
            update_way_r <= update_way_nxt;
            update_entry_r <= update_entry_nxt;
            lookup_hit_r <= lookup_hit_nxt;
            hit_way_r <= hit_way_nxt;
            tag_entry_r <= tag_entry_nxt;
            lookup_done_r <= lookup_done_nxt;
            update_done_r <= update_done_nxt;
            sram_ce_r <= sram_ce_nxt;
            sram_we_r <= sram_we_nxt;
            sram_addr_r <= sram_addr_nxt;
            sram_wdata_r <= sram_wdata_nxt;
        end
    end
    
    //=============================================================================
    // 调试输出 (仅在仿真时)
    //=============================================================================
    
    generate
    if (L2CACHE_CONFIG.debug_enable) begin : gen_debug
        always_ff @(posedge clk) begin
            // 监控Tag查找
            if (tag_if.lookup_valid && tag_if.lookup_ready) begin
                $display("@%0t: [L2CACHE_TAG] Lookup: index=0x%h", 
                         $time, tag_if.lookup_index);
            end
            
            if (tag_if.lookup_done) begin
                if (tag_if.lookup_hit) begin
                    $display("@%0t: [L2CACHE_TAG] Hit: way=%0d", 
                             $time, tag_if.hit_way);
                end else begin
                    $display("@%0t: [L2CACHE_TAG] Miss", $time);
                end
            end
            
            // 监控Tag更新
            if (tag_if.update_valid && tag_if.update_ready) begin
                $display("@%0t: [L2CACHE_TAG] Update: index=0x%h, way=%0d", 
                         $time, tag_if.update_index, tag_if.update_way);
            end
            
            // 监控SRAM访问
            if (sram_if_inst.ce && sram_if_inst.we) begin
                $display("@%0t: [L2CACHE_TAG] SRAM Write: addr=0x%h, data=0x%h", 
                         $time, sram_if_inst.addr, sram_if_inst.wdata);
            end
            if (sram_if_inst.ce && !sram_if_inst.we) begin
                $display("@%0t: [L2CACHE_TAG] SRAM Read: addr=0x%h, data=0x%h", 
                         $time, sram_if_inst.addr, sram_if_inst.rdata);
            end
        end
    end
    endgenerate

endmodule : rvgpu_l2cache_tag_array

`endif // RVGPU_L2CACHE_TAG_ARRAY_SV 