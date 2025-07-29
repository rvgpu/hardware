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

`ifndef RVGPU_MMU_TLB_SV
`define RVGPU_MMU_TLB_SV

`include "rvgpu_control_unit_if.svh"
`include "rvgpu_sram_if.svh"
`include "rvgpu_mmu_if.svh"
`include "rvgpu_mmu_common.svh"
`include "rvgpu_constant_mmu.svh"

module rvgpu_mmu_tlb (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    mmu_tlb_if.tlb_port tlb_if
);  
    //=============================================================================
    // 2. 状态机定义 - 明确定义所有状态
    //=============================================================================
    
    typedef enum logic [2:0] {
        TLB_IDLE = 3'b000,        // 空闲状态
        TLB_WRITE = 3'b001,       // 写SRAM状态
        TLB_WRITE_WAIT = 3'b010,  // 等待写完成
        TLB_READ = 3'b011,        // 读取SRAM
        TLB_RESP = 3'b100         // 响应结果
    } tlb_state_t;
    
    //=============================================================================
    // 3. 内部信号定义 - 使用清晰的前缀命名规范
    //=============================================================================
    
    // 状态机寄存器
    tlb_state_t state_r, state_nxt;
    
    // 查找请求寄存器
    logic [CU_TLB_TAG_BITS+CU_TLB_INDEX_BITS-1:0] lookup_addr_r, lookup_addr_nxt;
    logic [CU_TLB_TAG_BITS-1:0] lookup_tag_r, lookup_tag_nxt;
    
    // SRAM数据寄存器
    logic [$bits(cu_tlb_entry_t)-1:0] sram_data_r, sram_data_nxt;
    logic [$bits(cu_tlb_entry_t)-1:0] lookup_data_r, lookup_data_nxt;
    
    // 查找结果寄存器
    logic lookup_hit_r, lookup_hit_nxt;
    logic req_ready_r, req_ready_nxt;
    logic resp_valid_r, resp_valid_nxt;
    
    // TLB更新请求寄存器
    logic [CU_TLB_INDEX_BITS-1:0] update_addr_r, update_addr_nxt;
    logic [$bits(cu_tlb_entry_t)-1:0] update_data_r, update_data_nxt;
    logic update_pending_r, update_pending_nxt;
    
    // 临时变量用于函数调用结果
    logic [CU_TLB_TAG_BITS+CU_TLB_INDEX_BITS-1:0] lookup_addr_full;
    logic [CU_TLB_TAG_BITS+CU_TLB_INDEX_BITS-1:0] update_addr_full;
    
    //=============================================================================
    // 4. SRAM实例化
    //=============================================================================
    
    // 创建SRAM接口实例
    rvgpu_sram_if #(
        .WIDTH($bits(cu_tlb_entry_t)),
        .HEIGHT(CU_TLB_ENTRIES)
    ) sram_if_inst();
    
    // 连接时钟
    assign sram_if_inst.clk = clk;
    
    // SRAM实例化
    rvgpu_sram_sp #(
        .WIDTH($bits(cu_tlb_entry_t)),
        .HEIGHT(CU_TLB_ENTRIES),
        .RAMNAME("CU_TLB_SRAM")
    ) u_tlb_sram (
        .sram_if(sram_if_inst.sram_port)
    );
    
    //=============================================================================
    // 5. 组合逻辑 - 使用 always_comb 处理组合逻辑
    //=============================================================================
    
    // SRAM接口控制逻辑
    always_comb begin
        // SRAM控制信号
        sram_if_inst.ce = (state_r == TLB_READ) || (state_r == TLB_WRITE);
        sram_if_inst.we = (state_r == TLB_WRITE);
        sram_if_inst.addr = (state_r == TLB_READ) ? lookup_addr_r[CU_TLB_INDEX_BITS-1:0] : 
                           (state_r == TLB_WRITE) ? update_addr_r : '0;
        sram_if_inst.wdata = (state_r == TLB_WRITE) ? update_data_r : '0;
    end
    
    // 状态机组合逻辑
    always_comb begin
        // 默认值 - 避免锁存器
        state_nxt = state_r;
        lookup_addr_nxt = lookup_addr_r;
        lookup_tag_nxt = lookup_tag_r;
        sram_data_nxt = sram_data_r;
        lookup_data_nxt = lookup_data_r;
        lookup_hit_nxt = lookup_hit_r;
        req_ready_nxt = req_ready_r;
        resp_valid_nxt = resp_valid_r;
        update_addr_nxt = update_addr_r;
        update_data_nxt = update_data_r;
        update_pending_nxt = update_pending_r;
        
        case (state_r)
            TLB_IDLE: begin
                req_ready_nxt = 1'b1;
                // 只有在resp_ready为高时才清除resp_valid
                resp_valid_nxt = tlb_if.resp_ready ? 1'b0 : resp_valid_r;
                
                // 如果有TLB更新请求，优先处理
                if (tlb_if.update_valid && tlb_if.update_ready) begin
                    state_nxt = TLB_WRITE;
                    update_addr_full = calc_cu_tlb_addr(tlb_if.update_vaddr);
                    update_addr_nxt = update_addr_full[CU_TLB_INDEX_BITS-1:0];
                    update_data_nxt = build_cu_tlb_entry(tlb_if.update_vaddr, tlb_if.update_paddr);
                    update_pending_nxt = 1'b1;
                    req_ready_nxt = 1'b0;
                    `DEBUG_PRINT("TLB", $sformatf("TLB Update, vaddr: 0x%h, paddr: 0x%h", tlb_if.update_vaddr, tlb_if.update_paddr));
                end
                // 如果有新的查找请求，进入读取状态
                else if (tlb_if.req_valid && tlb_if.req_ready) begin
                    state_nxt = TLB_READ;
                    lookup_addr_full = calc_cu_tlb_addr(tlb_if.req_vaddr);
                    lookup_addr_nxt = lookup_addr_full;
                    lookup_tag_nxt = lookup_addr_full[CU_TLB_TAG_BITS+CU_TLB_INDEX_BITS-1:CU_TLB_INDEX_BITS];
                    req_ready_nxt = 1'b0;
                    `DEBUG_PRINT("TLB", $sformatf("TLB Lookup, vaddr: 0x%h", tlb_if.req_vaddr));
                end
            end
            
            TLB_WRITE: begin
                // 写入SRAM，等待一个周期确保写完成
                state_nxt = TLB_WRITE_WAIT;
            end
            
            TLB_WRITE_WAIT: begin
                // 等待写操作完成，然后回到空闲状态
                state_nxt = TLB_IDLE;
                update_pending_nxt = 1'b0;
            end
            
            TLB_READ: begin
                // 当前状态时发写请求，下一个cycle read data
                state_nxt = TLB_RESP;
            end
            
            TLB_RESP: begin
                // 检查命中 - 直接使用位域
                // 将SRAM数据转换为结构体
                cu_tlb_entry_t tlb_entry;
                assign tlb_entry = sram_if_inst.rdata;
                
                lookup_hit_nxt = tlb_entry.common.valid && (tlb_entry.tag == lookup_tag_r);
                lookup_data_nxt = sram_if_inst.rdata;
                resp_valid_nxt = 1'b1;
                
                // 自动回到空闲状态
                state_nxt = TLB_IDLE;
            end
            
            default: begin
                // 错误处理 - 在无效情况下使用 X 值
                state_nxt = TLB_IDLE;
                lookup_hit_nxt = 1'bx;
                lookup_data_nxt = 'x;
            end
        endcase
    end
    
    //=============================================================================
    // 6. 时序逻辑 - 使用 always_ff 处理时序逻辑
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // 状态寄存器复位
            state_r <= TLB_IDLE;
            lookup_addr_r <= '0;
            lookup_tag_r <= '0;
            sram_data_r <= '0;
            lookup_data_r <= '0;
            lookup_hit_r <= 1'b0;
            req_ready_r <= 1'b1;
            resp_valid_r <= 1'b0;
            update_addr_r <= '0;
            update_data_r <= '0;
            update_pending_r <= 1'b0;
        end else begin
            // 状态更新
            state_r <= state_nxt;
            lookup_addr_r <= lookup_addr_nxt;
            lookup_tag_r <= lookup_tag_nxt;
            sram_data_r <= sram_data_nxt;
            lookup_data_r <= lookup_data_nxt;
            lookup_hit_r <= lookup_hit_nxt;
            req_ready_r <= req_ready_nxt;
            resp_valid_r <= resp_valid_nxt;
            update_addr_r <= update_addr_nxt;
            update_data_r <= update_data_nxt;
            update_pending_r <= update_pending_nxt;
        end
    end
    
    //=============================================================================
    // 7. 输出信号 - 使用三元运算符进行条件赋值
    //=============================================================================
    
    // TLB请求接口
    assign tlb_if.req_ready = (state_r == TLB_IDLE) && !update_pending_r;
    
    // TLB响应接口
    assign tlb_if.resp_valid = resp_valid_r;
    assign tlb_if.resp_hit = lookup_hit_r;
    // 将SRAM数据转换为结构体以访问字段
    cu_tlb_entry_t lookup_entry;
    assign lookup_entry = lookup_data_r;
    assign tlb_if.resp_paddr = lookup_hit_r ? {lookup_entry.common.ppn, tlb_if.req_vaddr[PAGE_OFFSET_BITS-1:0]} : '0;
    
    // TLB更新接口
    assign tlb_if.update_ready = (state_r == TLB_IDLE) && !update_pending_r;
    
    //=============================================================================
    // 9. 调试输出 - 使用 generate 块进行条件编译
    //=============================================================================
    
    generate
    if (1) begin : gen_debug
        always_ff @(posedge clk) begin
            // SRAM访问调试
            if (sram_if_inst.ce && sram_if_inst.we) begin
                $display("@%0t: [TLB] SRAM Write: addr=0x%02x, data=0x%026x", 
                         $time, sram_if_inst.addr, sram_if_inst.wdata);
            end
            if (sram_if_inst.ce && !sram_if_inst.we) begin
                $display("@%0t: [TLB] SRAM Read: addr=0x%02x, data=0x%026x", 
                         $time, sram_if_inst.addr, sram_if_inst.rdata);
            end
            
            // TLB操作调试
            if (tlb_if.req_valid && tlb_if.req_ready && tlb_if.resp_hit) begin
                $display("@%0t: [TLB] Hit: vaddr=0x%h, paddr=0x%h", 
                         $time, tlb_if.req_vaddr, tlb_if.resp_paddr);
            end else if (tlb_if.req_valid && tlb_if.req_ready && !tlb_if.resp_hit) begin
                $display("@%0t: [TLB] Miss: vaddr=0x%h", $time, tlb_if.req_vaddr);
            end
            
            if (tlb_if.update_valid && tlb_if.update_ready) begin
                $display("@%0t: [TLB] Update: vaddr=0x%h, paddr=0x%h", 
                         $time, tlb_if.update_vaddr, tlb_if.update_paddr);
            end
        end
    end
    endgenerate

endmodule : rvgpu_mmu_tlb

`endif // RVGPU_MMU_TLB_SV 