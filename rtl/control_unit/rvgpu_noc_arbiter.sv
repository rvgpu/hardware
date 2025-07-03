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

`ifndef RVGPU_NOC_ARBITER_SV
`define RVGPU_NOC_ARBITER_SV

`include "rvgpu_config.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_control_unit_if.svh"

`ifndef RVGPU_INTERNAL_NOC_PKG_IMPORTED
`define RVGPU_INTERNAL_NOC_PKG_IMPORTED
import rvgpu_internal_noc_pkg::*;
`endif // RVGPU_INTERNAL_NOC_PKG_IMPORTED

module rvgpu_noc_arbiter (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // Command Processor Interface
    rvgpu_internal_noc_if.noc cp_if,

    // Memory Management Unit Interface
    rvgpu_internal_noc_if.noc mmu_if,

    // NOC Interface （out put to internal noc）
    rvgpu_internal_noc_if.device noc_if
);

    //=============================================================================
    // Local Parameters and Types
    //=============================================================================
    
    // local_addr分配定义
    localparam logic [3:0] LOCAL_ADDR_CP_RANGE  = 4'h0;
    localparam logic [3:0] LOCAL_ADDR_MMU_RANGE = 4'h1;
    
    // 请求仲裁状态机
    typedef enum logic [1:0] {
        REQ_ARB_IDLE    = 2'b00,
        REQ_ARB_CP      = 2'b01,
        REQ_ARB_MMU     = 2'b10
    } req_arb_state_t;
    
    // 响应路由状态机  
    typedef enum logic [1:0] {
        RESP_ROUTE_IDLE = 2'b00,
        RESP_ROUTE_CP   = 2'b01,
        RESP_ROUTE_MMU  = 2'b10
    } resp_route_state_t;
    
    //=============================================================================
    // Internal Signals and Registers
    //=============================================================================
    
    req_arb_state_t arb_state, arb_state_next;
    resp_route_state_t route_state, route_state_next;
    
    // 仲裁优先级轮转计数器
    logic arb_priority, arb_priority_next;
    
    // 时序逻辑 - 状态寄存器更新
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            arb_state <= REQ_ARB_IDLE;
            arb_priority <= 1'b0;
        end else begin
            arb_state <= arb_state_next;
            arb_priority <= arb_priority_next;
        end
    end
    
    // 组合逻辑 - 状态转换逻辑
    always_comb begin
        arb_state_next = arb_state;
        
        case (arb_state)
            REQ_ARB_IDLE: begin
                // 根据轮转优先级选择主设备
                if (arb_priority == 1'b0) begin
                    // 优先级：CP > MMU
                    if (cp_if.m_req_valid) begin
                        arb_state_next = REQ_ARB_CP;
                    end else if (mmu_if.m_req_valid) begin
                        arb_state_next = REQ_ARB_MMU;
                    end
                end else begin
                    // 优先级：MMU > CP
                    if (mmu_if.m_req_valid) begin
                        arb_state_next = REQ_ARB_MMU;
                    end else if (cp_if.m_req_valid) begin
                        arb_state_next = REQ_ARB_CP;
                    end
                end
            end
            
            REQ_ARB_CP: begin
                // 传输完成后返回空闲
                if (cp_if.m_req_valid && noc_if.m_req_ready && cp_if.m_req_last) begin
                    arb_state_next = REQ_ARB_IDLE;
                end
            end
            
            REQ_ARB_MMU: begin
                // 传输完成后返回空闲
                if (mmu_if.m_req_valid && noc_if.m_req_ready && mmu_if.m_req_last) begin
                    arb_state_next = REQ_ARB_IDLE;
                end
            end
            
            default: begin
                arb_state_next = REQ_ARB_IDLE;
            end
        endcase
    end
    
    // 优先级轮转逻辑
    always_comb begin
        arb_priority_next = arb_priority;
        // 每次从空闲状态开始仲裁时切换优先级
        // 但只有在有竞争的情况下才切换（即CP和MMU都有请求）
        if (arb_state == REQ_ARB_IDLE && arb_state_next != REQ_ARB_IDLE &&
            cp_if.m_req_valid && mmu_if.m_req_valid) begin
            arb_priority_next = ~arb_priority;
        end
    end
    
    // 组合逻辑 - 输出逻辑
    always_comb begin
        // 默认值
        cp_if.m_req_ready = 1'b0;
        mmu_if.m_req_ready = 1'b0;
        noc_if.m_req_valid = 1'b0;
        noc_if.m_req_header = '0;
        noc_if.m_req_data = '0;
        noc_if.m_req_strb = '0;
        noc_if.m_req_last = 1'b0;
        
        case (arb_state)
            REQ_ARB_CP: begin
                // 转发Command Processor的请求到NOC
                cp_if.m_req_ready = noc_if.m_req_ready;
                noc_if.m_req_valid = cp_if.m_req_valid;
                noc_if.m_req_header = cp_if.m_req_header;
                noc_if.m_req_data = cp_if.m_req_data;
                noc_if.m_req_strb = cp_if.m_req_strb;
                noc_if.m_req_last = cp_if.m_req_last;
            end
            
            REQ_ARB_MMU: begin
                // 转发MMU的请求到NOC
                mmu_if.m_req_ready = noc_if.m_req_ready;
                noc_if.m_req_valid = mmu_if.m_req_valid;
                noc_if.m_req_header = mmu_if.m_req_header;
                noc_if.m_req_data = mmu_if.m_req_data;
                noc_if.m_req_strb = mmu_if.m_req_strb;
                noc_if.m_req_last = mmu_if.m_req_last;
            end
            
            default: begin
                // REQ_ARB_IDLE 和其他状态保持默认值
            end
        endcase
    end
    
    //=============================================================================
    // Response Routing Logic 
    //=============================================================================
    
    // 时序逻辑 - 状态寄存器更新
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            route_state <= RESP_ROUTE_IDLE;
        end else begin
            route_state <= route_state_next;
        end
    end
    
    // 组合逻辑 - 状态转换逻辑
    always_comb begin
        route_state_next = route_state;
        
        case (route_state)
            RESP_ROUTE_IDLE: begin
                if (noc_if.m_resp_valid) begin
                    // 基于local_addr高4位判断响应目标，直接使用位选择
                    case (noc_if.m_resp_header[7:4])
                        LOCAL_ADDR_CP_RANGE: begin
                            // 0x0x范围 → Command Processor
                            route_state_next = RESP_ROUTE_CP;
                        end
                        
                        LOCAL_ADDR_MMU_RANGE: begin
                            // 0x1x范围 → MMU
                            route_state_next = RESP_ROUTE_MMU;
                        end
                        
                        default: begin
                            // 未知地址范围，保持IDLE状态，在输出逻辑中丢弃响应
                            route_state_next = RESP_ROUTE_IDLE;
                        end
                    endcase
                end
            end
            
            RESP_ROUTE_CP: begin
                // 响应传输完成后返回空闲
                if (noc_if.m_resp_valid && noc_if.m_resp_ready && noc_if.m_resp_last) begin
                    route_state_next = RESP_ROUTE_IDLE;
                end
            end
            
            RESP_ROUTE_MMU: begin
                // 响应传输完成后返回空闲
                if (noc_if.m_resp_valid && noc_if.m_resp_ready && noc_if.m_resp_last) begin
                    route_state_next = RESP_ROUTE_IDLE;
                end
            end
            
            default: begin
                route_state_next = RESP_ROUTE_IDLE;
            end
        endcase
    end
    
    // 组合逻辑 - 输出逻辑
    always_comb begin
        // 默认值
        cp_if.m_resp_valid = 1'b0;
        cp_if.m_resp_header = '0;
        cp_if.m_resp_data = '0;
        cp_if.m_resp_status = 2'b00;
        cp_if.m_resp_last = 1'b0;
        
        mmu_if.m_resp_valid = 1'b0;
        mmu_if.m_resp_header = '0;
        mmu_if.m_resp_data = '0;
        mmu_if.m_resp_status = 2'b00;
        mmu_if.m_resp_last = 1'b0;
        
        noc_if.m_resp_ready = 1'b0;
        
        case (route_state)
            RESP_ROUTE_IDLE: begin
                // 检查是否为未知地址范围，如果是则丢弃响应
                if (noc_if.m_resp_valid) begin
                    // Extract local_addr directly from header bits [7:0]
                    case (noc_if.m_resp_header[7:4])
                        LOCAL_ADDR_CP_RANGE, LOCAL_ADDR_MMU_RANGE: begin
                            // 已知地址范围，不在这里处理
                        end
                        default: begin
                            // 未知地址范围，丢弃响应
                            noc_if.m_resp_ready = 1'b1;
                        end
                    endcase
                end
            end
            
            RESP_ROUTE_CP: begin
                // 路由响应到Command Processor
                cp_if.m_resp_valid = noc_if.m_resp_valid;
                cp_if.m_resp_header = noc_if.m_resp_header;
                cp_if.m_resp_data = noc_if.m_resp_data;
                cp_if.m_resp_status = noc_if.m_resp_status;
                cp_if.m_resp_last = noc_if.m_resp_last;
                noc_if.m_resp_ready = cp_if.m_resp_ready;
            end
            
            RESP_ROUTE_MMU: begin
                // 路由响应到MMU
                mmu_if.m_resp_valid = noc_if.m_resp_valid;
                mmu_if.m_resp_header = noc_if.m_resp_header;
                mmu_if.m_resp_data = noc_if.m_resp_data;
                mmu_if.m_resp_status = noc_if.m_resp_status;
                mmu_if.m_resp_last = noc_if.m_resp_last;
                noc_if.m_resp_ready = mmu_if.m_resp_ready;
            end
            
            default: begin
                // 保持默认值
            end
        endcase
    end
    
    //=============================================================================
    // Slave Interface (Direct connection to MMU)
    //=============================================================================
    
    // CP slave interface is unused - tie off to inactive values
    // CP only acts as master, never as slave in this architecture
    // DUT (arbiter) should not send any slave requests to CP
    assign cp_if.s_req_valid = 1'b0;
    assign cp_if.s_req_header = '0;
    assign cp_if.s_req_data = '0;
    assign cp_if.s_req_strb = '0;
    assign cp_if.s_req_last = 1'b0;
    
    // DUT (arbiter) should not expect any slave responses from CP
    assign cp_if.s_resp_ready = 1'b0;
    
    // 直接将slave请求转发给MMU (NOC → Arbiter → MMU)
    assign mmu_if.s_req_valid = noc_if.s_req_valid;
    assign mmu_if.s_req_header = noc_if.s_req_header;
    assign mmu_if.s_req_data = noc_if.s_req_data;
    assign mmu_if.s_req_strb = noc_if.s_req_strb;
    assign mmu_if.s_req_last = noc_if.s_req_last;
    assign noc_if.s_req_ready = mmu_if.s_req_ready;
    
    // 直接将MMU响应转发回NOC (MMU → Arbiter → NOC)
    assign noc_if.s_resp_valid = mmu_if.s_resp_valid;
    assign noc_if.s_resp_header = mmu_if.s_resp_header;
    assign noc_if.s_resp_data = mmu_if.s_resp_data;
    assign noc_if.s_resp_status = mmu_if.s_resp_status;
    assign noc_if.s_resp_last = mmu_if.s_resp_last;
    assign mmu_if.s_resp_ready = noc_if.s_resp_ready;

endmodule : rvgpu_noc_arbiter

`endif // RVGPU_NOC_ARBITER_SV 