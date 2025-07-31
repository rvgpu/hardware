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
`include "rvgpu_debug.svh"
`include "rvgpu_l2cache_common.svh"

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

module rvgpu_l2cache_tag_array (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // Controller Interface
    l2cache_tag_if.tag_array tag_if
);  
    //=============================================================================
    // 2. 状态机定义 - 明确定义所有状态
    //=============================================================================
    
    typedef enum logic [2:0] {
        TAG_IDLE = 3'b000,           // 空闲状态
        TAG_LOOKUP = 3'b001,         // 发起Tag查找
        TAG_LOOKUP_WAIT = 3'b010,    // 等待Tag查找完成
        TAG_UPDATE = 3'b011,         // 发起Tag更新
        TAG_UPDATE_WAIT = 3'b100     // 等待Tag更新完成
    } tag_state_t;
    
    //=============================================================================
    // 3. 内部信号定义 - 使用清晰的前缀命名规范
    //=============================================================================
    
    // 状态机寄存器
    tag_state_t state_r, state_nxt;
    
    // 查找请求寄存器
    logic [L2CACHE_TAG_ADDR_WIDTH-1:0] lookup_index_r, lookup_index_nxt;
    logic [L2CACHE_TAG_BITS-1:0] lookup_tag_r, lookup_tag_nxt;
    
    // 更新请求寄存器
    logic [L2CACHE_TAG_ADDR_WIDTH-1:0] update_index_r, update_index_nxt;
    logic [L2CACHE_WAYS-1:0] update_way_r, update_way_nxt;
    l2cache_tag_entry_t update_entry_r, update_entry_nxt;
    
    // 查找结果寄存器
    logic lookup_hit_r, lookup_hit_nxt;
    logic [L2CACHE_WAYS-1:0] hit_way_r, hit_way_nxt;
    l2cache_tag_entry_t tag_entry_r, tag_entry_nxt;
    logic lookup_done_r, lookup_done_nxt;
    logic update_done_r, update_done_nxt;
    
    // 接口就绪状态寄存器
    logic lookup_ready_r, lookup_ready_nxt;
    logic update_ready_r, update_ready_nxt;
    
    // Tag比较信号
    logic [L2CACHE_WAYS-1:0] way_hit;
    logic any_hit;
    
    // 错误检测信号
    logic multiple_hit_error;
    logic invalid_way_error;
    
    //=============================================================================
    // 4. SRAM实例化
    //=============================================================================
    
    // 创建SRAM接口实例
    rvgpu_sram_if #(
        .WIDTH(L2CACHE_TAG_DATA_WIDTH),
        .HEIGHT(L2CACHE_TAG_DEPTH)
    ) sram_if_inst();
    
    // 连接时钟
    assign sram_if_inst.clk = clk;
    
    // SRAM实例化
    rvgpu_sram_sp #(
        .WIDTH(L2CACHE_TAG_DATA_WIDTH),
        .HEIGHT(L2CACHE_TAG_DEPTH),
        .RAMNAME("L2CACHE_TAG_SRAM")
    ) u_tag_sram (
        .sram_if(sram_if_inst.sram_port)
    );
    
    //=============================================================================
    // 5. SRAM接口控制逻辑
    //=============================================================================
    
    always_comb begin
        // SRAM控制信号
        sram_if_inst.ce = (state_r == TAG_LOOKUP) || (state_r == TAG_UPDATE);
        sram_if_inst.we = (state_r == TAG_UPDATE);
        sram_if_inst.addr = (state_r == TAG_LOOKUP) ? lookup_index_r : 
                           (state_r == TAG_UPDATE) ? update_index_r : '0;
        sram_if_inst.wdata = (state_r == TAG_UPDATE) ? tag_entry_to_raw(update_entry_r) : '0;
    end
    
    //=============================================================================
    // 6. 状态机组合逻辑
    //=============================================================================
    
    always_comb begin
        // 默认值 - 避免锁存器
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
        lookup_ready_nxt = lookup_ready_r;
        update_ready_nxt = update_ready_r;
        
        case (state_r)
            TAG_IDLE: begin
                // 空闲状态：等待新请求
                lookup_done_nxt = 1'b0;
                update_done_nxt = 1'b0;
                lookup_ready_nxt = 1'b1;
                update_ready_nxt = 1'b1;
                
                // 优先级：更新请求优先于查找请求
                if (tag_if.update_valid) begin
                    // 开始Tag更新
                    state_nxt = TAG_UPDATE;
                    update_index_nxt = tag_if.update_index;
                    update_way_nxt = tag_if.update_way;
                    update_entry_nxt = tag_if.update_entry;
                    update_ready_nxt = 1'b0;
                    lookup_ready_nxt = 1'b0; // 阻止查找请求
                    `DEBUG_PRINT("L2CACHE_TAG", $sformatf("Update: index=0x%h, way=%0d", tag_if.update_index, tag_if.update_way));
                end else if (tag_if.lookup_valid) begin
                    // 开始Tag查找
                    state_nxt = TAG_LOOKUP;
                    lookup_index_nxt = tag_if.lookup_index;
                    lookup_tag_nxt = tag_if.lookup_tag;
                    lookup_ready_nxt = 1'b0;
                    `DEBUG_PRINT("L2CACHE_TAG", $sformatf("Lookup: index=0x%h, tag=0x%h", tag_if.lookup_index, tag_if.lookup_tag));
                end
            end
            
            TAG_LOOKUP: begin
                // Tag查找状态 - 发起SRAM读取
                state_nxt = TAG_LOOKUP_WAIT;
            end
            
            TAG_LOOKUP_WAIT: begin
                // Tag查找等待状态 - 等待SRAM读取完成
                // 解析Tag条目
                tag_entry_nxt = raw_to_tag_entry(sram_if_inst.rdata);
                
                // 并行比较所有way
                for (int i = 0; i < L2CACHE_WAYS; i++) begin
                    way_hit[i] = tag_entry_nxt.valid[i] && 
                                 (tag_entry_nxt.tag[i] == lookup_tag_r);
                end
                
                any_hit = |way_hit;
                
                // 错误检测
                multiple_hit_error = $countones(way_hit) > 1;
                invalid_way_error = (tag_if.update_valid && tag_if.update_ready) ? 
                                  (tag_if.update_way >= L2CACHE_WAYS) : 1'b0;
                
                // 更新查找结果
                lookup_hit_nxt = any_hit;
                hit_way_nxt = way_hit;
                lookup_done_nxt = 1'b1;
                
                // 返回空闲状态
                state_nxt = TAG_IDLE;
                `DEBUG_PRINT("L2CACHE_TAG", $sformatf("Lookup done: hit=%0d, way=%0d, sram_if_inst.rdata=0x%h", lookup_hit_nxt, hit_way_nxt, sram_if_inst.rdata));
            end
            
            TAG_UPDATE: begin
                // Tag更新状态 - 发起SRAM写入
                state_nxt = TAG_UPDATE_WAIT;
            end
            
            TAG_UPDATE_WAIT: begin
                // Tag更新等待状态 - 等待SRAM写入完成
                update_done_nxt = 1'b1;
                
                // 返回空闲状态
                state_nxt = TAG_IDLE;
                `DEBUG_PRINT("L2CACHE_TAG", "Update done");
            end
            
            default: begin
                // 错误状态
                state_nxt = TAG_IDLE;
                lookup_hit_nxt = 1'bx;
                hit_way_nxt = 'x;
                tag_entry_nxt = 'x;
            end
        endcase
    end
    
    //=============================================================================
    // 7. 输出信号赋值
    //=============================================================================
    
    // Tag查找接口
    assign tag_if.lookup_ready = lookup_ready_r;
    assign tag_if.lookup_hit = lookup_hit_r;
    assign tag_if.hit_way = hit_way_r;
    assign tag_if.tag_entry = tag_entry_r;
    assign tag_if.lookup_done = lookup_done_r;
    
    // Tag更新接口
    assign tag_if.update_ready = update_ready_r;
    assign tag_if.update_done = update_done_r;
    
    //=============================================================================
    // 8. 时序逻辑 - 寄存器更新
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // 复位逻辑
            state_r <= TAG_IDLE;
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
            lookup_ready_r <= 1'b1;
            update_ready_r <= 1'b1;
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
            lookup_ready_r <= lookup_ready_nxt;
            update_ready_r <= update_ready_nxt;
        end
    end
    
    //=============================================================================
    // 9. 辅助函数
    //=============================================================================
    
    // Tag条目转换为原始数据
    function automatic logic [L2CACHE_TAG_DATA_WIDTH-1:0] tag_entry_to_raw(
        input l2cache_tag_entry_t entry
    );
        logic [L2CACHE_TAG_DATA_WIDTH-1:0] raw;
        logic [31:0] offset = 0;
        
        // 序列化Tag条目
        for (int i = 0; i < L2CACHE_WAYS; i++) begin
            raw[offset +: 32] = entry.tag[i];
            offset += 32;
        end
        
        for (int i = 0; i < L2CACHE_WAYS; i++) begin
            raw[offset +: 1] = entry.valid[i];
            offset += 1;
        end
        
        for (int i = 0; i < L2CACHE_WAYS; i++) begin
            raw[offset +: 1] = entry.dirty[i];
            offset += 1;
        end
        
        for (int i = 0; i < L2CACHE_WAYS; i++) begin
            raw[offset +: 2] = entry.mesi_state[i];
            offset += 2;
        end
        
        raw[offset +: 8] = entry.lru;
        
        return raw;
    endfunction
    
    // 原始数据转换为Tag条目
    function automatic l2cache_tag_entry_t raw_to_tag_entry(
        input logic [L2CACHE_TAG_DATA_WIDTH-1:0] raw
    );
        l2cache_tag_entry_t entry;
        logic [31:0] offset = 0;
        
        // 反序列化Tag条目
        for (int i = 0; i < L2CACHE_WAYS; i++) begin
            entry.tag[i] = raw[offset +: 32];
            offset += 32;
        end
        
        for (int i = 0; i < L2CACHE_WAYS; i++) begin
            entry.valid[i] = raw[offset +: 1];
            offset += 1;
        end
        
        for (int i = 0; i < L2CACHE_WAYS; i++) begin
            entry.dirty[i] = raw[offset +: 1];
            offset += 1;
        end
        
        for (int i = 0; i < L2CACHE_WAYS; i++) begin
            entry.mesi_state[i] = raw[offset +: 2];
            offset += 2;
        end
        
        entry.lru = raw[offset +: 8];
        
        return entry;
    endfunction

endmodule : rvgpu_l2cache_tag_array

`endif // RVGPU_L2CACHE_TAG_ARRAY_SV 