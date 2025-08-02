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

`ifndef RVGPU_GPC_L15_TAG_ARRAY_SV
`define RVGPU_GPC_L15_TAG_ARRAY_SV


`include "types_cache_op.svh"
`include "const_l15cache.svh"
`include "types_l15cache.svh"
`include "types_cache_op.svh"
`include "function_cache_lru.svh"

`include "interface_l15cache_tag.svh"
`include "rvgpu_sram_if.svh"
`include "rvgpu_debug.svh"
`include "types_l15cache.svh"
`include "types_l15cache_tag.svh"

module rvgpu_gpc_l15cache_tag_array (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // Controller Interface
    l15cache_tag_if.tag_array tag_if
);  
    //=============================================================================
    // 1. 状态机定义 - 明确定义所有状态
    //=============================================================================
    
    typedef enum logic [3:0] {
        TAG_CLEAR = 4'b0000,          // SRAM初始化状态
        TAG_IDLE = 4'b0001,           // 空闲状态
        TAG_LOOKUP = 4'b0010,         // 发起Tag查找
        TAG_LOOKUP_WAIT = 4'b0011,    // 等待Tag查找完成
        TAG_UPDATE = 4'b0100,         // 发起Tag更新
        TAG_UPDATE_WAIT = 4'b0101     // 等待Tag更新完成
    } tag_state_t;

    // 标签数组相关参数
    localparam int L15CACHE_TAG_ENTRY_ADDR_WIDTH = L15CACHE_INDEX_BITS;
    localparam int L15CACHE_TAG_ENTRY_DEPTH = L15CACHE_SETS;
    localparam int L15CACHE_TAG_ENTRY_DATA_WIDTH = $bits(l15cache_tag_entry_t);
    
    //=============================================================================
    // 2. 内部信号定义
    //=============================================================================
    
    // 状态机寄存器
    tag_state_t state_r, state_nxt;
    
    // SRAM初始化相关寄存器
    logic [L15CACHE_TAG_ENTRY_ADDR_WIDTH-1:0] clear_addr_r, clear_addr_nxt;
    logic clear_done_r, clear_done_nxt;
    
    // 查找请求寄存器
    logic [L15CACHE_TAG_ENTRY_ADDR_WIDTH-1:0] lookup_index_r, lookup_index_nxt;
    logic [L15CACHE_TAG_BITS-1:0] lookup_tag_r, lookup_tag_nxt;
    
    // 更新请求寄存器
    logic [L15CACHE_TAG_ENTRY_ADDR_WIDTH-1:0] update_index_r, update_index_nxt;
    logic [L15CACHE_WAYS-1:0] update_way_r, update_way_nxt;
    l15cache_tag_entry_t update_entry_r, update_entry_nxt;
    
    // 查找结果寄存器
    logic lookup_hit_r, lookup_hit_nxt;
    logic [L15CACHE_WAYS-1:0] hit_way_r, hit_way_nxt;
    l15cache_tag_entry_t tag_entry_r, tag_entry_nxt;
    logic lookup_done_r, lookup_done_nxt;
    logic update_done_r, update_done_nxt;
    
    // 接口就绪状态寄存器
    logic lookup_ready_r, lookup_ready_nxt;
    logic update_ready_r, update_ready_nxt;
    
    // Tag比较信号
    logic [L15CACHE_WAYS-1:0] way_hit;
    logic any_hit;
    
    // 错误检测信号
    logic multiple_hit_error;
    logic invalid_way_error;
    
    //=============================================================================
    // 3. SRAM实例化
    //=============================================================================
    
    // 创建SRAM接口实例
    rvgpu_sram_if #(
        .WIDTH(L15CACHE_TAG_ENTRY_DATA_WIDTH),
        .HEIGHT(L15CACHE_TAG_ENTRY_DEPTH)
    ) sram_if_inst();
    
    // 连接时钟
    assign sram_if_inst.clk = clk;
    
    // SRAM实例化
    rvgpu_sram_sp #(
        .WIDTH(L15CACHE_TAG_ENTRY_DATA_WIDTH),
        .HEIGHT(L15CACHE_TAG_ENTRY_DEPTH),
        .RAMNAME("L15CACHE_TAG_SRAM")
    ) u_tag_sram (
        .sram_if(sram_if_inst.sram_port)
    );
    
    //=============================================================================
    // 4. SRAM接口控制逻辑
    //=============================================================================
    
    always_comb begin
        // SRAM控制信号 - 默认值
        sram_if_inst.ce = 1'b0;
        sram_if_inst.we = 1'b0;
        sram_if_inst.addr = '0;
        sram_if_inst.wdata = '0;
        
        case (state_r)
            TAG_CLEAR: begin
                // SRAM初始化 - 写入所有地址
                sram_if_inst.ce = 1'b1;
                sram_if_inst.we = 1'b1;
                sram_if_inst.addr = clear_addr_r;
                sram_if_inst.wdata = '0; // 写入全0，表示无效数据
            end
            TAG_LOOKUP: begin
                // Tag查找 - 读取SRAM
                sram_if_inst.ce = 1'b1;
                sram_if_inst.we = 1'b0;
                sram_if_inst.addr = lookup_index_r;
            end
            TAG_UPDATE: begin
                // Tag更新 - 写入SRAM
                sram_if_inst.ce = 1'b1;
                sram_if_inst.we = 1'b1;
                sram_if_inst.addr = update_index_r;
                sram_if_inst.wdata = l15cache_tag_entry_to_raw(update_entry_r);
            end
            default: begin
                // 其他状态不访问SRAM
            end
        endcase
    end
    
    //=============================================================================
    // 5. 状态机组合逻辑
    //=============================================================================
    
    always_comb begin
        // 默认值 - 避免锁存器
        state_nxt = state_r;
        clear_addr_nxt = clear_addr_r;
        clear_done_nxt = clear_done_r;
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
            TAG_CLEAR: begin
                // SRAM初始化状态 - 多周期初始化
                clear_done_nxt = 1'b0;
                lookup_ready_nxt = 1'b0;  // 初始化期间不接受请求
                update_ready_nxt = 1'b0;
                
                // 检查是否完成初始化
                if (clear_addr_r == L15CACHE_TAG_ENTRY_DEPTH - 1) begin
                    // 初始化完成，进入IDLE状态
                    state_nxt = TAG_IDLE;
                    clear_done_nxt = 1'b1;
                    `DEBUG_PRINT("L15CACHE_TAG", $sformatf("SRAM initialization completed, %0d entries cleared", L15CACHE_TAG_ENTRY_DEPTH));
                end else begin
                    // 继续初始化下一个地址
                    clear_addr_nxt = clear_addr_r + 1;
                end
            end
            
            TAG_IDLE: begin
                // 空闲状态：等待新请求
                lookup_done_nxt = 1'b0;
                update_done_nxt = 1'b0;
                lookup_ready_nxt = 1'b1;
                update_ready_nxt = 1'b1;
                
                // 优先级：更新请求优先于查找请求
                if (tag_if.update_valid && tag_if.update_ready) begin
                    // 开始Tag更新
                    state_nxt = TAG_UPDATE;
                    update_index_nxt = tag_if.update_index;
                    update_way_nxt = tag_if.update_way;
                    update_entry_nxt = tag_if.update_entry;
                    update_ready_nxt = 1'b0;
                    lookup_ready_nxt = 1'b0; // 阻止查找请求
                end else if (tag_if.lookup_valid && tag_if.lookup_ready) begin
                    // 开始Tag查找
                    state_nxt = TAG_LOOKUP;
                    lookup_index_nxt = tag_if.lookup_index;
                    lookup_tag_nxt = tag_if.lookup_tag;
                    lookup_ready_nxt = 1'b0;
                    `DEBUG_PRINT("L15CACHE_TAG", $sformatf("Lookup: index=0x%h, tag=0x%h", tag_if.lookup_index, tag_if.lookup_tag));
                end
            end
            
            TAG_LOOKUP: begin
                // Tag查找状态 - 发起SRAM读取
                state_nxt = TAG_LOOKUP_WAIT;
            end
            
            TAG_LOOKUP_WAIT: begin
                // Tag查找等待状态 - 等待SRAM读取完成
                // 解析Tag条目
                tag_entry_nxt = raw_to_l15cache_tag_entry(sram_if_inst.rdata);
                
                // 并行比较所有way
                for (int i = 0; i < L15CACHE_WAYS; i++) begin
                    way_hit[i] = tag_entry_nxt.ways[i].valid && (tag_entry_nxt.ways[i].tag == lookup_tag_r);
                end
                
                any_hit = |way_hit;
                
                // 错误检测
                multiple_hit_error = $countones(way_hit) > 1;
                invalid_way_error = (tag_if.update_valid && tag_if.update_ready) ? (tag_if.update_way >= L15CACHE_WAYS) : 1'b0;
                
                // 更新查找结果
                lookup_hit_nxt = any_hit;
                hit_way_nxt = way_hit;
                lookup_done_nxt = 1'b1;
                
                // 返回空闲状态
                state_nxt = TAG_IDLE;
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
                `DEBUG_PRINT("L15CACHE_TAG", "Update done");
            end
            
            default: begin
                // 错误状态 - 使用安全的默认值
                state_nxt = TAG_IDLE;
                lookup_hit_nxt = 1'b0;
                hit_way_nxt = '0;
            end
        endcase
    end
    
    //=============================================================================
    // 6. 输出信号赋值
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
            // 复位逻辑 - 进入SRAM初始化状态
            state_r <= TAG_CLEAR;
            clear_addr_r <= '0;
            clear_done_r <= 1'b0;
            lookup_index_r <= '0;
            lookup_tag_r <= '0;
            update_index_r <= '0;
            update_way_r <= '0;
            lookup_hit_r <= 1'b0;
            hit_way_r <= '0;
            lookup_done_r <= 1'b0;
            update_done_r <= 1'b0;
            lookup_ready_r <= 1'b0;
            update_ready_r <= 1'b0;
        end else begin
            // 状态更新
            state_r <= state_nxt;
            clear_addr_r <= clear_addr_nxt;
            clear_done_r <= clear_done_nxt;
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

endmodule : rvgpu_gpc_l15cache_tag_array

`endif // RVGPU_GPC_L15_TAG_ARRAY_SV 