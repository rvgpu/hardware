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
`include "rvgpu_mmu_pkg.svh"

`include "rvgpu_sram_sp_sim.sv"

`ifndef RVGPU_MMU_PKG_IMPORTED
`define RVGPU_MMU_PKG_IMPORTED
import rvgpu_mmu_pkg::*;
`endif // RVGPU_MMU_PKG_IMPORTED

module rvgpu_mmu_tlb #(
    parameter control_unit_config_t CU_CONFIG = DEFAULT_CONTROL_UNIT_CONFIG
) (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // TLB接口
    tlb_if.tlb_port tlb_if
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
    logic [TLB_TAG_BITS+TLB_ADDR_WIDTH-1:0] lookup_addr_r, lookup_addr_nxt;
    logic [TLB_TAG_BITS-1:0] lookup_tag_r, lookup_tag_nxt;
    
    // SRAM数据寄存器
    logic [TLB_DATA_WIDTH-1:0] sram_data_r, sram_data_nxt;
    logic [TLB_DATA_WIDTH-1:0] lookup_data_r, lookup_data_nxt;
    
    // 查找结果寄存器
    logic lookup_hit_r, lookup_hit_nxt;
    logic lookup_ready_r, lookup_ready_nxt;
    
    // TLB更新请求寄存器
    logic [TLB_ADDR_WIDTH-1:0] update_addr_r, update_addr_nxt;
    logic [TLB_DATA_WIDTH-1:0] update_data_r, update_data_nxt;
    logic update_pending_r, update_pending_nxt;
    
    //=============================================================================
    // 4. SRAM实例化
    //=============================================================================
    
    // 创建SRAM接口实例
    rvgpu_sram_if #(
        .WIDTH(TLB_DATA_WIDTH),
        .HEIGHT(TLB_ENTRIES)
    ) sram_if_inst();
    
    // 连接时钟
    assign sram_if_inst.clk = clk;
    
    // SRAM实例化
    rvgpu_sram_sp #(
        .WIDTH(TLB_DATA_WIDTH),
        .HEIGHT(TLB_ENTRIES),
        .RAMNAME("TLB_SRAM")
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
        sram_if_inst.addr = (state_r == TLB_READ) ? lookup_addr_r[TLB_ADDR_WIDTH-1:0] : 
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
        lookup_ready_nxt = lookup_ready_r;
        update_addr_nxt = update_addr_r;
        update_data_nxt = update_data_r;
        update_pending_nxt = update_pending_r;
        
        case (state_r)
            TLB_IDLE: begin
                lookup_ready_nxt = 1'b1;
                
                // 如果有TLB更新请求，优先处理
                if (tlb_if.tlb_update_valid && tlb_if.tlb_update_ready) begin
                    state_nxt = TLB_WRITE;
                    update_addr_nxt = tlb_if.tlb_update_addr[TLB_ADDR_WIDTH-1:0];
                    update_data_nxt = tlb_if.tlb_update_data;
                    update_pending_nxt = 1'b1;
                    lookup_ready_nxt = 1'b0;
                    `DEBUG_PRINT("TLB", $sformatf("TLB Update, addr: 0x%h, data: 0x%h", tlb_if.tlb_update_addr, tlb_if.tlb_update_data));
                end
                // 如果有新的查找请求，进入读取状态
                else if (tlb_if.tlb_lookup_valid && tlb_if.tlb_lookup_ready) begin
                    state_nxt = TLB_READ;
                    lookup_addr_nxt = tlb_if.tlb_lookup_addr[TLB_ADDR_WIDTH-1:0];
                    lookup_tag_nxt = tlb_if.tlb_lookup_addr[TLB_TAG_BITS+TLB_ADDR_WIDTH-1:TLB_ADDR_WIDTH];
                    lookup_ready_nxt = 1'b0;
                    `DEBUG_PRINT("TLB", $sformatf("TLB Lookup, addr: 0x%h, tag: 0x%h", tlb_if.tlb_lookup_addr, tlb_if.tlb_lookup_addr[TLB_TAG_BITS+TLB_ADDR_WIDTH-1:TLB_ADDR_WIDTH]));
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
                lookup_hit_nxt = sram_if_inst.rdata[VALID_BIT] && (sram_if_inst.rdata[TAG_START:TAG_END] == lookup_tag_r);
                lookup_data_nxt = sram_if_inst.rdata;
                
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
            lookup_ready_r <= 1'b1;
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
            lookup_ready_r <= lookup_ready_nxt;
            update_addr_r <= update_addr_nxt;
            update_data_r <= update_data_nxt;
            update_pending_r <= update_pending_nxt;
        end
    end
    
    //=============================================================================
    // 7. 输出信号 - 使用三元运算符进行条件赋值
    //=============================================================================
    
    // TLB查找接口
    assign tlb_if.tlb_lookup_ready = (state_r == TLB_IDLE) && !update_pending_r;
    assign tlb_if.tlb_lookup_data = lookup_data_r;
    assign tlb_if.tlb_lookup_hit = lookup_hit_r;
    
    // TLB更新接口
    assign tlb_if.tlb_update_ready = (state_r == TLB_IDLE) && !update_pending_r;
    
    //=============================================================================
    // 8. 调试输出 - 使用 generate 块进行条件编译
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
            if (tlb_if.tlb_lookup_valid && tlb_if.tlb_lookup_ready && tlb_if.tlb_lookup_hit) begin
                $display("@%0t: [TLB] Hit: addr=0x%h, tag=0x%h, ppn=0x%h", 
                         $time, tlb_if.tlb_lookup_addr, tlb_if.tlb_lookup_data[33:5], tlb_if.tlb_lookup_data[69:34]);
            end else if (tlb_if.tlb_lookup_valid && tlb_if.tlb_lookup_ready && !tlb_if.tlb_lookup_hit) begin
                $display("@%0t: [TLB] Miss: addr=0x%h", $time, tlb_if.tlb_lookup_addr);
            end
            
            if (tlb_if.tlb_update_valid && tlb_if.tlb_update_ready) begin
                $display("@%0t: [TLB] Update: addr=0x%h, data=0x%h", 
                         $time, tlb_if.tlb_update_addr, tlb_if.tlb_update_data);
            end
        end
    end
    endgenerate

endmodule : rvgpu_mmu_tlb

`endif // RVGPU_MMU_TLB_SV 