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

`ifndef RVGPU_GPC_NOC_ADAPTER_SV
`define RVGPU_GPC_NOC_ADAPTER_SV

`include "rvgpu_typedef.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_internal_noc_pkg.svh"
`include "rvgpu_noc_message.svh"
`ifndef RVGPU_INTERNAL_NOC_PKG_IMPORTED
`define RVGPU_INTERNAL_NOC_PKG_IMPORTED
import rvgpu_internal_noc_pkg::*;
`endif // RVGPU_INTERNAL_NOC_PKG_IMPORTED

module rvgpu_gpc_noc_adapter #(
    parameter noc_config_t NOC_CONFIG = DEFAULT_NOC_CONFIG,
    parameter int GPC_ID = 0
) (
    input  logic                                  clk,
    input  logic                                  rst_n,
    
    // 外部NOC接口
    rvgpu_internal_noc_if.device                  noc_external_if,
    
    // L1.5缓存接口
    rvgpu_internal_noc_if.noc                     l15_cache_if,

    // GPC MMU接口
    rvgpu_internal_noc_if.noc                     mmu_if,
    
    // Block Scheduler接口
    rvgpu_internal_noc_if.noc                     scheduler_if
);

    //=============================================================================
    // Local Parameters and Types
    //=============================================================================
    
    // 请求仲裁状态机 - 处理内部模块发出的请求
    typedef enum logic [2:0] {
        REQ_ARB_IDLE       = 3'b000,
        REQ_ARB_L15        = 3'b001,
        REQ_ARB_MMU        = 3'b010,
        REQ_ARB_SCHED      = 3'b011,
        REQ_WAIT_RESPONSE  = 3'b100,
        REQ_SEND_RESPONSE  = 3'b101
    } req_arb_state_t;
    
    // 响应路由状态机 - 处理来自NOC的响应
    typedef enum logic [2:0] {
        RESP_ROUTE_IDLE    = 3'b000,
        RESP_ROUTE_L15     = 3'b001,
        RESP_ROUTE_MMU     = 3'b010,
        RESP_ROUTE_SCHED   = 3'b011
    } resp_route_state_t;
    
    // 外部请求处理状态机 - 处理来自NOC的请求
    typedef enum logic [2:0] {
        EXT_REQ_IDLE       = 3'b000,
        EXT_REQ_L15        = 3'b001,
        EXT_REQ_MMU        = 3'b010,
        EXT_REQ_SCHED      = 3'b011,
        EXT_REQ_RESPONSE   = 3'b100
    } ext_req_state_t;
    
    //=============================================================================
    // Internal Signals and Registers
    //=============================================================================
    
    req_arb_state_t req_arb_state_r, req_arb_state_next;
    resp_route_state_t resp_route_state_r, resp_route_state_next;
    ext_req_state_t ext_req_state_r, ext_req_state_next;
    
    // 仲裁优先级轮转计数器
    logic [1:0] arb_priority, arb_priority_next;
    
    // 请求缓冲
    logic [NOC_CONFIG.if_config.header_width-1:0] req_header_buffer;
    logic [NOC_CONFIG.if_config.data_width-1:0] req_data_buffer;
    logic [NOC_CONFIG.if_config.data_width/8-1:0] req_strb_buffer;
    logic req_last_buffer;
    logic req_valid_buffer;
    
    // 响应缓冲
    logic [NOC_CONFIG.if_config.header_width-1:0] resp_header_buffer;
    logic [NOC_CONFIG.if_config.data_width-1:0] resp_data_buffer;
    logic resp_last_buffer;
    logic resp_valid_buffer;
    
    // 临时变量
    logic [NOC_CONFIG.if_config.data_width-1:0] temp_data;
    
    //=============================================================================
    // Sequential Logic - State Register Updates
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            req_arb_state_r <= REQ_ARB_IDLE;
            resp_route_state_r <= RESP_ROUTE_IDLE;
            ext_req_state_r <= EXT_REQ_IDLE;
            arb_priority <= 2'b00;
            req_valid_buffer <= 1'b0;
            resp_valid_buffer <= 1'b0;
            req_header_buffer <= '0;
            req_data_buffer <= '0;
            req_strb_buffer <= '0;
            req_last_buffer <= 1'b0;
            resp_header_buffer <= '0;
            resp_data_buffer <= '0;
            resp_last_buffer <= 1'b0;
        end else begin
            req_arb_state_r <= req_arb_state_next;
            resp_route_state_r <= resp_route_state_next;
            ext_req_state_r <= ext_req_state_next;
            arb_priority <= arb_priority_next;
            
            // Buffer 变量赋值逻辑
            case (ext_req_state_r)
                EXT_REQ_IDLE: begin
                    if (noc_external_if.s_req_valid) begin
                        // 捕获请求数据到 buffer
                        req_header_buffer <= noc_external_if.s_req_header;
                        req_data_buffer <= noc_external_if.s_req_data;
                        req_strb_buffer <= noc_external_if.s_req_strb;
                        req_last_buffer <= noc_external_if.s_req_last;
                        req_valid_buffer <= 1'b1;
                    end
                end
                EXT_REQ_L15, EXT_REQ_MMU, EXT_REQ_SCHED: begin
                    // 在发送请求后清除 buffer
                    if (l15_cache_if.s_req_ready || mmu_if.s_req_ready || scheduler_if.s_req_ready) begin
                        req_valid_buffer <= 1'b0;
                    end
                end
                default: begin
                    // 其他状态下保持 buffer 不变
                end
            endcase
        end
    end
    
    //=============================================================================
    // Combinational Logic - Request Arbitration State Machine
    //=============================================================================
    
    always_comb begin
        req_arb_state_next = req_arb_state_r;
        
        case (req_arb_state_r)
            REQ_ARB_IDLE: begin
                // 根据轮转优先级选择主设备
                case (arb_priority)
                    2'b00: begin
                        // 优先级：L15 > MMU > Scheduler
                        if (l15_cache_if.m_req_valid) begin
                            req_arb_state_next = REQ_ARB_L15;
                        end else if (mmu_if.m_req_valid) begin
                            req_arb_state_next = REQ_ARB_MMU;
                        end else if (scheduler_if.m_req_valid) begin
                            req_arb_state_next = REQ_ARB_SCHED;
                        end
                    end
                    2'b01: begin
                        // 优先级：MMU > Scheduler > L15
                        if (mmu_if.m_req_valid) begin
                            req_arb_state_next = REQ_ARB_MMU;
                        end else if (scheduler_if.m_req_valid) begin
                            req_arb_state_next = REQ_ARB_SCHED;
                        end else if (l15_cache_if.m_req_valid) begin
                            req_arb_state_next = REQ_ARB_L15;
                        end
                    end
                    2'b10: begin
                        // 优先级：Scheduler > L15 > MMU
                        if (scheduler_if.m_req_valid) begin
                            req_arb_state_next = REQ_ARB_SCHED;
                        end else if (l15_cache_if.m_req_valid) begin
                            req_arb_state_next = REQ_ARB_L15;
                        end else if (mmu_if.m_req_valid) begin
                            req_arb_state_next = REQ_ARB_MMU;
                        end
                    end
                    default: begin
                        // 优先级：L15 > MMU > Scheduler
                        if (l15_cache_if.m_req_valid) begin
                            req_arb_state_next = REQ_ARB_L15;
                        end else if (mmu_if.m_req_valid) begin
                            req_arb_state_next = REQ_ARB_MMU;
                        end else if (scheduler_if.m_req_valid) begin
                            req_arb_state_next = REQ_ARB_SCHED;
                        end
                    end
                endcase
            end
            
            REQ_ARB_L15: begin
                // 传输完成后返回空闲
                if (l15_cache_if.m_req_valid && noc_external_if.m_req_ready && l15_cache_if.m_req_last) begin
                    req_arb_state_next = REQ_WAIT_RESPONSE;
                end
            end
            
            REQ_ARB_MMU: begin
                // 传输完成后返回空闲
                if (mmu_if.m_req_valid && noc_external_if.m_req_ready && mmu_if.m_req_last) begin
                    req_arb_state_next = REQ_WAIT_RESPONSE;
                end
            end
            
            REQ_ARB_SCHED: begin
                // 传输完成后返回空闲
                if (scheduler_if.m_req_valid && noc_external_if.m_req_ready && scheduler_if.m_req_last) begin
                    req_arb_state_next = REQ_WAIT_RESPONSE;
                end
            end
            
            REQ_WAIT_RESPONSE: begin
                if (noc_external_if.m_resp_valid) begin
                    req_arb_state_next = REQ_SEND_RESPONSE;
                end
            end
            
            REQ_SEND_RESPONSE: begin
                if (noc_external_if.m_resp_ready) begin
                    req_arb_state_next = REQ_ARB_IDLE;
                end
            end
            
            default: begin
                req_arb_state_next = REQ_ARB_IDLE;
            end
        endcase
    end
    
    // 优先级轮转逻辑
    always_comb begin
        arb_priority_next = arb_priority;
        // 每次从空闲状态开始仲裁时切换优先级
        if (req_arb_state_r == REQ_ARB_IDLE && req_arb_state_next != REQ_ARB_IDLE) begin
            arb_priority_next = arb_priority + 1;
        end
    end
    
    //=============================================================================
    // Combinational Logic - Response Routing State Machine
    //=============================================================================
    
    always_comb begin
        resp_route_state_next = resp_route_state_r;
        
        case (resp_route_state_r)
            RESP_ROUTE_IDLE: begin
                if (noc_external_if.m_resp_valid) begin
                    case (get_noc_header_msg_type(noc_external_if.m_resp_header))
                        MSG_MEM_READ_RESP, MSG_MEM_WRITE_RESP: begin
                            resp_route_state_next = RESP_ROUTE_L15;
                        end
                        MSG_MMU_RESP: begin
                            resp_route_state_next = RESP_ROUTE_MMU;
                        end
                        MSG_COMPUTE_RESP: begin
                            resp_route_state_next = RESP_ROUTE_SCHED;
                        end
                        default: begin
                            resp_route_state_next = RESP_ROUTE_IDLE;
                        end
                    endcase
                end
            end
            
            RESP_ROUTE_L15: begin
                if (l15_cache_if.m_resp_ready) begin
                    resp_route_state_next = RESP_ROUTE_IDLE;
                end
            end
            
            RESP_ROUTE_MMU: begin
                if (mmu_if.m_resp_ready) begin
                    resp_route_state_next = RESP_ROUTE_IDLE;
                end
            end
            
            RESP_ROUTE_SCHED: begin
                if (scheduler_if.m_resp_ready) begin
                    resp_route_state_next = RESP_ROUTE_IDLE;
                end
            end
            
            default: begin
                resp_route_state_next = RESP_ROUTE_IDLE;
            end
        endcase
    end
    
    //=============================================================================
    // Combinational Logic - External Request State Machine
    //=============================================================================
    
    always_comb begin
        ext_req_state_next = ext_req_state_r;
        
        case (ext_req_state_r)
            EXT_REQ_IDLE: begin
                if (noc_external_if.s_req_valid) begin
                    // 直接根据消息类型转换到目标状态
                    case (get_noc_header_msg_type(noc_external_if.s_req_header))
                        MSG_MEM_READ_REQ, MSG_MEM_WRITE_REQ: begin
                            ext_req_state_next = EXT_REQ_L15;
                        end
                        MSG_MMU_REQ: begin
                            ext_req_state_next = EXT_REQ_MMU;
                        end
                        MSG_COMPUTE_REQ: begin
                            ext_req_state_next = EXT_REQ_SCHED;
                        end
                        default: begin
                            ext_req_state_next = EXT_REQ_IDLE;
                        end
                    endcase
                end
            end
            
            EXT_REQ_L15: begin
                // 等待请求传输完成
                if (l15_cache_if.s_req_ready && req_last_buffer) begin
                    ext_req_state_next = EXT_REQ_RESPONSE;
                end
            end
            
            EXT_REQ_MMU: begin
                // 等待请求传输完成
                if (mmu_if.s_req_ready && req_last_buffer) begin
                    ext_req_state_next = EXT_REQ_RESPONSE;
                end
            end
            
            EXT_REQ_SCHED: begin
                // 等待Scheduler请求传输完成
                if (scheduler_if.s_req_ready && req_last_buffer) begin
                    ext_req_state_next = EXT_REQ_RESPONSE;
                end
            end
            
            EXT_REQ_RESPONSE: begin
                // 等待L15 Cache、MMU或Scheduler的响应握手完成
                if ((l15_cache_if.s_resp_valid && noc_external_if.s_resp_ready) ||
                    (mmu_if.s_resp_valid && noc_external_if.s_resp_ready) ||
                    (scheduler_if.s_resp_valid && noc_external_if.s_resp_ready)) begin
                    ext_req_state_next = EXT_REQ_IDLE;
                end
            end
            
            default: begin
                ext_req_state_next = EXT_REQ_IDLE;
            end
        endcase
    end
    
    //=============================================================================
    // Combinational Logic - Request Arbitration Output Logic
    //=============================================================================
    
    always_comb begin
        // 默认值
        noc_external_if.m_req_valid = 1'b0;
        noc_external_if.m_req_header = '0;
        noc_external_if.m_req_data = '0;
        noc_external_if.m_req_strb = '0;
        noc_external_if.m_req_last = 1'b0;
        
        l15_cache_if.m_req_ready = 1'b0;
        mmu_if.m_req_ready = 1'b0;
        scheduler_if.m_req_ready = 1'b0;
        
        case (req_arb_state_r)
            REQ_ARB_L15: begin
                // 转发L15 Cache的请求到NOC
                l15_cache_if.m_req_ready = noc_external_if.m_req_ready;
                noc_external_if.m_req_valid = l15_cache_if.m_req_valid;
                noc_external_if.m_req_header = l15_cache_if.m_req_header;
                noc_external_if.m_req_data = l15_cache_if.m_req_data;
                noc_external_if.m_req_strb = l15_cache_if.m_req_strb;
                noc_external_if.m_req_last = l15_cache_if.m_req_last;
            end
            
            REQ_ARB_MMU: begin
                // 转发MMU的请求到NOC
                mmu_if.m_req_ready = noc_external_if.m_req_ready;
                noc_external_if.m_req_valid = mmu_if.m_req_valid;
                noc_external_if.m_req_header = mmu_if.m_req_header;
                noc_external_if.m_req_data = mmu_if.m_req_data;
                noc_external_if.m_req_strb = mmu_if.m_req_strb;
                noc_external_if.m_req_last = mmu_if.m_req_last;
            end
            
            REQ_ARB_SCHED: begin
                // 转发Scheduler的请求到NOC
                scheduler_if.m_req_ready = noc_external_if.m_req_ready;
                noc_external_if.m_req_valid = scheduler_if.m_req_valid;
                noc_external_if.m_req_header = scheduler_if.m_req_header;
                noc_external_if.m_req_data = scheduler_if.m_req_data;
                noc_external_if.m_req_strb = scheduler_if.m_req_strb;
                noc_external_if.m_req_last = scheduler_if.m_req_last;
            end
            
            default: begin
                // 保持默认值 
            end
        endcase
    end
    
    //=============================================================================
    // Combinational Logic - Response Routing Output Logic
    //=============================================================================
    
    always_comb begin
        // 默认值
        l15_cache_if.m_resp_valid = 1'b0;
        l15_cache_if.m_resp_header = '0;
        l15_cache_if.m_resp_data = '0;
        l15_cache_if.m_resp_status = 2'b00;
        l15_cache_if.m_resp_last = 1'b0;
        
        mmu_if.m_resp_valid = 1'b0;
        mmu_if.m_resp_header = '0;
        mmu_if.m_resp_data = '0;
        mmu_if.m_resp_status = 2'b00;
        mmu_if.m_resp_last = 1'b0;
        
        scheduler_if.m_resp_valid = 1'b0;
        scheduler_if.m_resp_header = '0;
        scheduler_if.m_resp_data = '0;
        scheduler_if.m_resp_status = 2'b00;
        scheduler_if.m_resp_last = 1'b0;
        
        noc_external_if.m_resp_ready = 1'b0;
        
        case (resp_route_state_r)
            RESP_ROUTE_IDLE: begin
                noc_external_if.m_resp_ready = 1'b1;
            end
            
            RESP_ROUTE_L15: begin
                if (noc_external_if.m_resp_valid) begin
                    l15_cache_if.m_resp_valid = 1'b1;
                    l15_cache_if.m_resp_header = noc_external_if.m_resp_header;
                    l15_cache_if.m_resp_data = noc_external_if.m_resp_data;
                    l15_cache_if.m_resp_status = noc_external_if.m_resp_status;
                    l15_cache_if.m_resp_last = noc_external_if.m_resp_last;
                    noc_external_if.m_resp_ready = l15_cache_if.m_resp_ready;
                end
            end
            
            RESP_ROUTE_MMU: begin
                if (noc_external_if.m_resp_valid) begin
                    mmu_if.m_resp_valid = 1'b1;
                    mmu_if.m_resp_header = noc_external_if.m_resp_header;
                    mmu_if.m_resp_data = noc_external_if.m_resp_data;
                    mmu_if.m_resp_status = noc_external_if.m_resp_status;
                    mmu_if.m_resp_last = noc_external_if.m_resp_last;
                    noc_external_if.m_resp_ready = mmu_if.m_resp_ready;
                end
            end
            
            RESP_ROUTE_SCHED: begin
                if (noc_external_if.m_resp_valid) begin
                    scheduler_if.m_resp_valid = 1'b1;
                    scheduler_if.m_resp_header = noc_external_if.m_resp_header;
                    scheduler_if.m_resp_data = noc_external_if.m_resp_data;
                    scheduler_if.m_resp_status = noc_external_if.m_resp_status;
                    scheduler_if.m_resp_last = noc_external_if.m_resp_last;
                    noc_external_if.m_resp_ready = scheduler_if.m_resp_ready;
                end
            end
            
            default: begin
                // 保持默认值
            end
        endcase
    end
    
    //=============================================================================
    // Combinational Logic - External Request Output Logic
    //=============================================================================
    
    always_comb begin
        // 默认值
        noc_external_if.s_req_ready = 1'b0;
        l15_cache_if.s_req_valid = 1'b0;
        l15_cache_if.s_req_header = '0;
        l15_cache_if.s_req_data = '0;
        l15_cache_if.s_req_strb = '0;
        l15_cache_if.s_req_last = 1'b0;
        
        mmu_if.s_req_valid = 1'b0;
        mmu_if.s_req_header = '0;
        mmu_if.s_req_data = '0;
        mmu_if.s_req_strb = '0;
        mmu_if.s_req_last = 1'b0;
        
        scheduler_if.s_req_valid = 1'b0;
        scheduler_if.s_req_data = '0;
        
        case (ext_req_state_r)
            EXT_REQ_IDLE: begin
                noc_external_if.s_req_ready = 1'b1;
            end
            
            EXT_REQ_L15: begin
                if (req_valid_buffer) begin
                    l15_cache_if.s_req_valid = 1'b1;
                    l15_cache_if.s_req_header = req_header_buffer;
                    l15_cache_if.s_req_data = req_data_buffer;
                    l15_cache_if.s_req_strb = req_strb_buffer;
                    l15_cache_if.s_req_last = req_last_buffer;
                end
            end
            
            EXT_REQ_MMU: begin
                if (req_valid_buffer) begin
                    mmu_if.s_req_valid = 1'b1;
                    mmu_if.s_req_header = req_header_buffer;
                    mmu_if.s_req_data = req_data_buffer;
                    mmu_if.s_req_strb = req_strb_buffer;
                    mmu_if.s_req_last = req_last_buffer;
                end
            end
            
            EXT_REQ_SCHED: begin
                if (req_valid_buffer) begin
                    // 这里需要特殊处理 job_cluster 数据
                    // 由于 Scheduler 现在使用标准的 NOC 接口，
                    // 我们需要将 job_cluster 数据转换为标准的 NOC 消息格式
                    scheduler_if.s_req_valid = 1'b1;
                    scheduler_if.s_req_header = req_header_buffer;
                    scheduler_if.s_req_data = req_data_buffer;
                    scheduler_if.s_req_strb = req_strb_buffer;
                    scheduler_if.s_req_last = req_last_buffer;
                end
            end
            
            default: begin
                // 保持默认值
            end
        endcase
    end
    
    //=============================================================================
    // Combinational Logic - External Response Output Logic
    //=============================================================================
    
    always_comb begin
        // 默认值
        noc_external_if.s_resp_valid = 1'b0;
        noc_external_if.s_resp_header = '0;
        noc_external_if.s_resp_data = '0;
        noc_external_if.s_resp_status = 2'b00;
        noc_external_if.s_resp_last = 1'b0;
        
        l15_cache_if.s_resp_ready = 1'b0;
        mmu_if.s_resp_ready = 1'b0;
        scheduler_if.s_resp_ready = 1'b0;
        
        case (ext_req_state_r)
            EXT_REQ_RESPONSE: begin
                if (l15_cache_if.s_resp_valid) begin
                    noc_external_if.s_resp_valid = 1'b1;
                    noc_external_if.s_resp_header = l15_cache_if.s_resp_header;
                    noc_external_if.s_resp_data = l15_cache_if.s_resp_data;
                    noc_external_if.s_resp_status = l15_cache_if.s_resp_status;
                    noc_external_if.s_resp_last = l15_cache_if.s_resp_last;
                    l15_cache_if.s_resp_ready = noc_external_if.s_resp_ready;
                end else if (mmu_if.s_resp_valid) begin
                    noc_external_if.s_resp_valid = 1'b1;
                    noc_external_if.s_resp_header = mmu_if.s_resp_header;
                    noc_external_if.s_resp_data = mmu_if.s_resp_data;
                    noc_external_if.s_resp_status = mmu_if.s_resp_status;
                    noc_external_if.s_resp_last = mmu_if.s_resp_last;
                    mmu_if.s_resp_ready = noc_external_if.s_resp_ready;
                end else if (scheduler_if.s_resp_valid) begin
                    noc_external_if.s_resp_valid = 1'b1;
                    noc_external_if.s_resp_header = scheduler_if.s_resp_header;
                    noc_external_if.s_resp_data = scheduler_if.s_resp_data;
                    noc_external_if.s_resp_status = scheduler_if.s_resp_status;
                    noc_external_if.s_resp_last = scheduler_if.s_resp_last;
                    scheduler_if.s_resp_ready = noc_external_if.s_resp_ready;
                end
            end
            
            default: begin
                // 保持默认值
            end
        endcase
    end

endmodule : rvgpu_gpc_noc_adapter

`endif // RVGPU_GPC_NOC_ADAPTER_SV 