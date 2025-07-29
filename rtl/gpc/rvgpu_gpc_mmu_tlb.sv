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

`ifndef RVGPU_GPC_MMU_TLB_SV
`define RVGPU_GPC_MMU_TLB_SV

`include "rvgpu_typedef.svh"
`include "rvgpu_sram_if.svh"
`include "rvgpu_mmu_if.svh"
`include "rvgpu_mmu_common.svh"
`include "rvgpu_constant_mmu.svh"

module rvgpu_gpc_mmu_tlb #(
    parameter int GPC_ID = 0           // GPC ID
) (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // TLB查找接口
    mmu_tlb_if.tlb_port tlb_if
);

    //=============================================================================
    // 1. 参数定义
    //=============================================================================
    
    // TLB地址计算参数
    localparam int TLB_DATA_WIDTH = $bits(gpc_tlb_entry_t); 
    
    //=============================================================================
    // 3. 状态机定义 
    //=============================================================================
    
    typedef enum logic [1:0] {
        TLB_IDLE = 2'b00,        // 空闲状态
        TLB_READ = 2'b01,        // 读取SRAM
        TLB_WRITE = 2'b10        // 写入SRAM
    } tlb_state_t;
    
    //=============================================================================
    // 4. 内部信号定义 
    //=============================================================================
    
    // 状态机寄存器
    tlb_state_t state_r, state_nxt;
    
    // 当前请求信息
    logic [VA_WIDTH-1:0] current_vaddr;
    logic [PA_WIDTH-1:0] current_paddr;
    
    // 当前地址选择逻辑
    assign current_vaddr = (state_r == TLB_READ) ? tlb_if.req_vaddr : (state_r == TLB_WRITE) ? tlb_if.update_vaddr : '0;
    assign current_paddr = (state_r == TLB_WRITE) ? tlb_if.update_paddr : '0;
    
    // SRAM地址计算
    logic [GPC_TLB_TAG_BITS+GPC_TLB_INDEX_BITS-1:0] tlb_addr;
    logic [GPC_TLB_TAG_BITS-1:0] tlb_tag;
    logic [GPC_TLB_INDEX_BITS-1:0] tlb_index;
    
    // 临时变量用于函数调用结果
    logic [TLB_DATA_WIDTH-1:0] tlb_entry_data;
    
    //=============================================================================
    // 5. SRAM实例化
    //=============================================================================
    
    // 创建SRAM接口实例
    rvgpu_sram_if #(
        .WIDTH(TLB_DATA_WIDTH),
        .HEIGHT(GPC_TLB_ENTRIES)
    ) sram_if_inst();
    
    // 连接时钟
    assign sram_if_inst.clk = clk;
    
    // SRAM实例化
    rvgpu_sram_sp #(
        .WIDTH(TLB_DATA_WIDTH),
        .HEIGHT(GPC_TLB_ENTRIES),
        .RAMNAME("GPC_TLB_SRAM")
    ) u_gpc_tlb_sram (
        .sram_if(sram_if_inst.sram_port)
    );
    
    //=============================================================================
    // 6. 地址计算 - 组合逻辑
    //=============================================================================
    
    // 计算TLB地址 - 使用共用函数
    assign tlb_addr = calc_gpc_tlb_addr(current_vaddr);
    assign tlb_tag = tlb_addr[GPC_TLB_TAG_BITS+GPC_TLB_INDEX_BITS-1:GPC_TLB_INDEX_BITS];
    assign tlb_index = tlb_addr[GPC_TLB_INDEX_BITS-1:0];
    
    //=============================================================================
    // 7. SRAM接口控制 - 直接控制
    //=============================================================================
    
    // SRAM控制信号 - 直接根据状态和请求控制
    assign sram_if_inst.ce = (state_r == TLB_READ) || (state_r == TLB_WRITE);
    assign sram_if_inst.we = (state_r == TLB_WRITE);
    assign sram_if_inst.addr = tlb_index;
    assign sram_if_inst.wdata = tlb_entry_data;
    
    //=============================================================================
    // 8. 状态机组合逻辑 - 简化版本
    //=============================================================================
    
    // 状态机组合逻辑
    always_comb begin
        // 默认值
        state_nxt = state_r;
        
        case (state_r)
            TLB_IDLE: begin
                // 优先处理更新请求
                if (tlb_if.update_valid && tlb_if.update_ready) begin
                    state_nxt = TLB_WRITE;
                    `GPC_PRINT("TLB", $sformatf("Update, vaddr: 0x%h, paddr: 0x%h", tlb_if.update_vaddr, tlb_if.update_paddr));
                end
                // 处理查找请求
                else if (tlb_if.req_valid && tlb_if.req_ready) begin
                    state_nxt = TLB_READ;
                    `GPC_PRINT("TLB", $sformatf("Lookup, vaddr: 0x%h", tlb_if.req_vaddr));
                end
            end
            
            TLB_READ: begin
                // 读取完成，回到空闲状态
                state_nxt = TLB_IDLE;
            end
            
            TLB_WRITE: begin
                // 写入完成，回到空闲状态
                state_nxt = TLB_IDLE;
            end
            
            default: begin
                state_nxt = TLB_IDLE;
            end
        endcase
    end
    
    //=============================================================================
    // 9. 时序逻辑
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_r <= TLB_IDLE;
        end else begin
            state_r <= state_nxt;
        end
    end
    
    //=============================================================================
    // 10. 输出信号
    //=============================================================================
    
    // 将SRAM数据转换为结构体
    gpc_tlb_entry_t tlb_entry;
    assign tlb_entry = sram_if_inst.rdata;
    
    // 查找命中判断 - 直接使用SRAM读取的数据
    logic lookup_hit;
    assign lookup_hit = tlb_entry.common.valid && 
                       (tlb_entry.tag == tlb_tag) &&
                       (state_r == TLB_READ);
    
    // 输出信号 - 合并逻辑
    assign tlb_if.req_ready = (state_r == TLB_IDLE);
    assign tlb_if.update_ready = (state_r == TLB_IDLE);
    assign tlb_if.resp_valid = (state_r == TLB_READ);
    assign tlb_if.resp_hit = lookup_hit;
    assign tlb_if.resp_paddr = lookup_hit ? {tlb_entry.common.ppn, current_vaddr[PAGE_OFFSET_BITS-1:0]} : '0;
    
    // 直接计算TLB条目数据 - 使用共用函数
    assign tlb_entry_data = build_gpc_tlb_entry(current_vaddr, current_paddr);
    
    //=============================================================================
    // 13. 调试输出
    //=============================================================================
    
    generate
    if (1) begin : gen_debug
        always_ff @(posedge clk) begin
            // SRAM访问调试
            if (sram_if_inst.ce && sram_if_inst.we) begin
                `GPC_PRINT("TLB", $sformatf("SRAM Write: addr=0x%02x, data=0x%026x", sram_if_inst.addr, sram_if_inst.wdata));
            end
            if (sram_if_inst.ce && !sram_if_inst.we) begin
                `GPC_PRINT("TLB", $sformatf("SRAM Read: addr=0x%02x, data=0x%026x", sram_if_inst.addr, sram_if_inst.rdata));
            end
            
            // TLB操作调试
            if (tlb_if.req_valid && tlb_if.req_ready && lookup_hit) begin
                `GPC_PRINT("TLB", $sformatf("Hit: vaddr=0x%h, paddr=0x%h", tlb_if.req_vaddr, tlb_if.resp_paddr));
            end else if (tlb_if.req_valid && tlb_if.req_ready && !lookup_hit) begin
                `GPC_PRINT("TLB", $sformatf("Miss: vaddr=0x%h", tlb_if.req_vaddr));
            end
            
            if (tlb_if.update_valid && tlb_if.update_ready) begin
                `GPC_PRINT("TLB", $sformatf("Update: vaddr=0x%h, paddr=0x%h", tlb_if.update_vaddr, tlb_if.update_paddr));
            end
            
            // 状态转换调试
            if (state_r != state_nxt) begin
                `GPC_PRINT("TLB", $sformatf("State transition: %s -> %s", state_r.name(), state_nxt.name()));
            end
        end
    end
    endgenerate

endmodule : rvgpu_gpc_mmu_tlb

`endif // RVGPU_GPC_MMU_TLB_SV 