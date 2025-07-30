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

`ifndef RVGPU_GPC_MMU_SV
`define RVGPU_GPC_MMU_SV

`include "rvgpu_typedef.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_noc_message.svh"
`include "rvgpu_mmu_if.svh"
`include "rvgpu_mmu_common.svh"

module rvgpu_gpc_mmu #(
    parameter int MAX_REQUESTS = 16,    // 最大并发请求数
    parameter int GPC_ID = 0           // GPC ID
) (
    input  logic clk,
    input  logic rst_n,
    
    // Block Scheduler请求接口
    mmu_if.mmu_port bs_if,
    
    // TPC请求接口 (支持多个TPC)
    mmu_if.mmu_port tpc_if[4],
    
    // L0 TLB更新接口
    gpc_tlb_update_if.initiator l0_tlb_if[4],
    
    // NOC Adapter接口 (连接到控制单元MMU)
    rvgpu_internal_noc_if.device noc_if
);

    // 请求队列表项定义
    typedef struct packed {
        logic        valid;          // 有效位
        logic [VA_WIDTH-1:0] vaddr;  // 虚拟地址
        mmu_access_type_e req_type;  // 访问类型
        logic [3:0]  tpc_id;         // TPC ID (0-3表示TPC, 4表示Block Scheduler)
        logic        pending;        // 请求是否正在处理中
    } req_entry_t;
    
    // 状态机状态
    typedef enum logic [2:0] {
        IDLE,
        LOOKUP,
        UPDATE_TLB,
        SEND_TO_NOC,
        WAIT_NOC,
        SEND_RESPONSE,
        UPDATE_L0_TLB
    } mmu_state_t;
    
    mmu_tlb_if mmu_tlb();
    
    // 请求队列
    req_entry_t req_queue[MAX_REQUESTS];
    logic [$clog2(MAX_REQUESTS)-1:0] req_head;
    logic [$clog2(MAX_REQUESTS)-1:0] req_tail;
    logic req_queue_full;
    logic req_queue_empty;
    
    // 内部信号
    mmu_state_t state;
    logic [VPN_BITS-1:0] req_vpn;
    logic tlb_hit;
    
    // 当前处理的请求
    req_entry_t current_req;
    logic [PA_WIDTH-1:0] current_paddr;  // 完整物理地址
    
    // 仲裁器 - 简单的轮询策略
    logic [2:0] arbiter_ptr;
    logic [4:0] req_valid_array;
    logic [4:0] req_grant_array;
    
    // 将请求有效信号组合成数组，便于仲裁
    assign req_valid_array = {bs_if.req_valid, tpc_if[3].req_valid, tpc_if[2].req_valid, tpc_if[1].req_valid, tpc_if[0].req_valid};
    
    // 仲裁逻辑 - 轮询策略
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            arbiter_ptr <= 3'b0;
            req_grant_array <= 5'b0;
        end else begin
            // 默认不授权
            req_grant_array <= 5'b0;
            
            if (!req_queue_full) begin
                // 轮询仲裁 - 从当前指针开始检查
                if (req_valid_array[(arbiter_ptr + 0) % 5]) begin
                    req_grant_array[(arbiter_ptr + 0) % 5] <= 1'b1;
                    arbiter_ptr <= (arbiter_ptr + 1) % 5;
                end else if (req_valid_array[(arbiter_ptr + 1) % 5]) begin
                    req_grant_array[(arbiter_ptr + 1) % 5] <= 1'b1;
                    arbiter_ptr <= (arbiter_ptr + 2) % 5;
                end else if (req_valid_array[(arbiter_ptr + 2) % 5]) begin
                    req_grant_array[(arbiter_ptr + 2) % 5] <= 1'b1;
                    arbiter_ptr <= (arbiter_ptr + 3) % 5;
                end else if (req_valid_array[(arbiter_ptr + 3) % 5]) begin
                    req_grant_array[(arbiter_ptr + 3) % 5] <= 1'b1;
                    arbiter_ptr <= (arbiter_ptr + 4) % 5;
                end else if (req_valid_array[(arbiter_ptr + 4) % 5]) begin
                    req_grant_array[(arbiter_ptr + 4) % 5] <= 1'b1;
                    arbiter_ptr <= (arbiter_ptr + 5) % 5;
                end
            end
        end
    end
    
    // 请求队列管理
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            req_head <= '0;
            req_tail <= '0;
            req_queue_full <= 1'b0;
            req_queue_empty <= 1'b1;
            
            // 初始化队列 
            req_queue[0].valid <= 1'b0;
            req_queue[0].pending <= 1'b0;
            req_queue[1].valid <= 1'b0;
            req_queue[1].pending <= 1'b0;
            req_queue[2].valid <= 1'b0;
            req_queue[2].pending <= 1'b0;
            req_queue[3].valid <= 1'b0;
            req_queue[3].pending <= 1'b0;
            req_queue[4].valid <= 1'b0;
            req_queue[4].pending <= 1'b0;
        end else begin
            // 入队逻辑
            if (req_grant_array != 5'b0 && !req_queue_full) begin
                req_queue[req_tail].valid <= 1'b1;
                req_queue[req_tail].pending <= 1'b0;
                
                // 根据授权信号确定请求来源
                if (req_grant_array[4]) begin
                    // Block Scheduler请求
                    req_queue[req_tail].vaddr <= bs_if.req_vaddr;
                    req_queue[req_tail].req_type <= bs_if.req_type;
                    req_queue[req_tail].tpc_id <= 4; // 4表示Block Scheduler
                end else begin
                    // TPC请求 - 简化处理
                    if (req_grant_array[0]) begin
                        req_queue[req_tail].vaddr <= tpc_if[0].req_vaddr;
                        req_queue[req_tail].req_type <= tpc_if[0].req_type;
                        req_queue[req_tail].tpc_id <= 0;
                    end else if (req_grant_array[1]) begin
                        req_queue[req_tail].vaddr <= tpc_if[1].req_vaddr;
                        req_queue[req_tail].req_type <= tpc_if[1].req_type;
                        req_queue[req_tail].tpc_id <= 1;
                    end else if (req_grant_array[2]) begin
                        req_queue[req_tail].vaddr <= tpc_if[2].req_vaddr;
                        req_queue[req_tail].req_type <= tpc_if[2].req_type;
                        req_queue[req_tail].tpc_id <= 2;
                    end else if (req_grant_array[3]) begin
                        req_queue[req_tail].vaddr <= tpc_if[3].req_vaddr;
                        req_queue[req_tail].req_type <= tpc_if[3].req_type;
                        req_queue[req_tail].tpc_id <= 3;
                    end
                end
                
                // 更新队列状态
                req_tail <= (req_tail + 1) % MAX_REQUESTS;
                req_queue_empty <= 1'b0;
                req_queue_full <= ((req_tail + 1) % MAX_REQUESTS == req_head);
            end
            
            // 出队逻辑
            if (state == SEND_RESPONSE && !req_queue_empty) begin
                req_queue[req_head].valid <= 1'b0;
                req_queue[req_head].pending <= 1'b0;
                
                req_head <= (req_head + 1) % MAX_REQUESTS;
                req_queue_full <= 1'b0;
                req_queue_empty <= ((req_head + 1) % MAX_REQUESTS == req_tail);
            end
            
            // 状态机触发的pending设置
            if (state == IDLE && !req_queue_empty && !req_queue[req_head].pending) begin
                req_queue[req_head].pending <= 1'b1;
            end
        end
    end
    
    // 准备就绪信号
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            bs_if.req_ready <= 1'b0;
            tpc_if[0].req_ready <= 1'b0;
            tpc_if[1].req_ready <= 1'b0;
            tpc_if[2].req_ready <= 1'b0;
            tpc_if[3].req_ready <= 1'b0;
        end else begin
            // 根据授权信号设置准备就绪
            bs_if.req_ready <= req_grant_array[4] && !req_queue_full;
            tpc_if[0].req_ready <= req_grant_array[0] && !req_queue_full;
            tpc_if[1].req_ready <= req_grant_array[1] && !req_queue_full;
            tpc_if[2].req_ready <= req_grant_array[2] && !req_queue_full;
            tpc_if[3].req_ready <= req_grant_array[3] && !req_queue_full;
        end
    end
    
    // 提取虚拟页号
    assign req_vpn = current_req.vaddr[VA_WIDTH-1:PAGE_OFFSET_BITS];
    
    //=============================================================================
    // TLB模块实例化
    //=============================================================================
    
    rvgpu_gpc_mmu_tlb #(
        .GPC_ID(GPC_ID)
    ) u_gpc_mmu_tlb (
        .clk(clk),
        .rst_n(rst_n),
        .tlb_if(mmu_tlb.tlb_port)
    );
    
    //=============================================================================
    // TLB接口连接
    //=============================================================================
    
    // TLB查找接口连接
    assign mmu_tlb.req_valid = (state == LOOKUP);
    assign mmu_tlb.req_vaddr = current_req.vaddr;
    assign mmu_tlb.resp_ready = (state == LOOKUP);
    
    // TLB更新接口连接
    assign mmu_tlb.update_valid = (state == UPDATE_TLB);
    assign mmu_tlb.update_vaddr = current_req.vaddr;
    assign mmu_tlb.update_paddr = current_paddr;
    
    // 从TLB模块获取查找结果
    assign tlb_hit = mmu_tlb.resp_hit;
    
    //=============================================================================
    // 主状态机
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            current_req <= '0;
            current_paddr <= '0;
            noc_if.m_req_valid <= 1'b0;
            noc_if.m_resp_ready <= 1'b0;
            
            // 初始化响应信号
            bs_if.resp_valid <= 1'b0;
            tpc_if[0].resp_valid <= 1'b0;
            tpc_if[1].resp_valid <= 1'b0;
            tpc_if[2].resp_valid <= 1'b0;
            tpc_if[3].resp_valid <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    // 重置响应信号
                    bs_if.resp_valid <= 1'b0;
                    tpc_if[0].resp_valid <= 1'b0;
                    tpc_if[1].resp_valid <= 1'b0;
                    tpc_if[2].resp_valid <= 1'b0;
                    tpc_if[3].resp_valid <= 1'b0;
                    
                    // 检查请求队列
                    if (!req_queue_empty && !req_queue[req_head].pending) begin
                        current_req <= req_queue[req_head];
                        state <= LOOKUP;
                    end
                end
                
                LOOKUP: begin
                    // 等待TLB查找完成
                    if (mmu_tlb.resp_valid) begin
                        if (mmu_tlb.resp_hit) begin
                            // TLB命中，获取物理地址
                            current_paddr <= mmu_tlb.resp_paddr;
                            state <= SEND_RESPONSE;
                            `GPC_PRINT("MMU", $sformatf("Lookup Hit, paddr: 0x%h", mmu_tlb.resp_paddr));
                        end else begin
                            // TLB未命中，需要请求控制单元MMU
                            state <= SEND_TO_NOC;
                            `GPC_PRINT("MMU", $sformatf("Lookup Miss, vaddr: 0x%h", current_req.vaddr));
                        end
                    end
                end
                
                SEND_TO_NOC: begin
                    // 发送请求到NOC Adapter
                    noc_if.m_req_valid <= 1'b1;
                    noc_if.m_req_header <= build_noc_header_mmu_request(8'h01, NODE_SHADER_0 + GPC_ID);
                    noc_if.m_req_data <= {current_req.vaddr, current_req.req_type, 32'h0, current_req.tpc_id, GPC_ID};  // 使用默认值替代warp_id和source_id
                    noc_if.m_req_strb <= '1;
                    noc_if.m_req_last <= 1'b1;
                    
                    if (noc_if.m_req_ready) begin
                        noc_if.m_req_valid <= 1'b0;
                        state <= WAIT_NOC;
                    end
                end
                
                WAIT_NOC: begin
                    // 等待NOC Adapter响应
                    noc_if.m_resp_ready <= 1'b1;
                    
                    if (noc_if.m_resp_valid) begin
                        noc_if.m_resp_ready <= 1'b0;
                        
                        // 从响应数据中提取信息 - 构建完整的物理地址
                        current_paddr <= {noc_if.m_resp_data[PA_WIDTH-1:PAGE_OFFSET_BITS], current_req.vaddr[PAGE_OFFSET_BITS-1:0]};
                        
                        if (!noc_if.m_resp_data[28]) begin // 假设fault位在data[28]
                            // 如果没有错误，更新TLB
                            state <= UPDATE_TLB;
                        end else begin
                            // 如果有错误，直接发送响应
                            state <= SEND_RESPONSE;
                        end
                    end
                end
                
                UPDATE_TLB: begin
                    // 等待TLB更新完成
                    if (mmu_tlb.update_ready) begin
                        // 如果请求来自TPC，还需要更新L0 TLB
                        if (current_req.tpc_id < 4) begin
                            state <= UPDATE_L0_TLB;
                        end else begin
                            state <= SEND_RESPONSE;
                        end
                    end
                end
                
                UPDATE_L0_TLB: begin
                    // L0 TLB更新现在由TLB模块处理
                    // 这里只需要等待更新完成
                    state <= SEND_RESPONSE;
                end
                
                SEND_RESPONSE: begin
                    // 根据请求源发送响应
                    if (current_req.tpc_id == 4) begin
                        // 响应Block Scheduler
                        bs_if.resp_valid <= 1'b1;
                        bs_if.resp_paddr <= current_paddr;
                        bs_if.resp_hit <= mmu_tlb.resp_hit;
                        bs_if.resp_status <= MMU_RESP_OKAY;
                        
                        if (bs_if.resp_ready) begin
                            bs_if.resp_valid <= 1'b0;
                            state <= IDLE;
                        end
                    end else begin
                        // 响应TPC - 使用case语句避免动态索引
                        case (current_req.tpc_id)
                            0: begin
                                tpc_if[0].resp_valid <= 1'b1;
                                tpc_if[0].resp_paddr <= current_paddr;
                                tpc_if[0].resp_hit <= mmu_tlb.resp_hit;
                                tpc_if[0].resp_status <= MMU_RESP_OKAY;
                                
                                if (tpc_if[0].resp_ready) begin
                                    tpc_if[0].resp_valid <= 1'b0;
                                    state <= IDLE;
                                end
                            end
                            1: begin
                                tpc_if[1].resp_valid <= 1'b1;
                                tpc_if[1].resp_paddr <= current_paddr;
                                tpc_if[1].resp_hit <= mmu_tlb.resp_hit;
                                tpc_if[1].resp_status <= MMU_RESP_OKAY;
                                
                                if (tpc_if[1].resp_ready) begin
                                    tpc_if[1].resp_valid <= 1'b0;
                                    state <= IDLE;
                                end
                            end
                            2: begin
                                tpc_if[2].resp_valid <= 1'b1;
                                tpc_if[2].resp_paddr <= current_paddr;
                                tpc_if[2].resp_hit <= mmu_tlb.resp_hit;
                                tpc_if[2].resp_status <= MMU_RESP_OKAY;
                                
                                if (tpc_if[2].resp_ready) begin
                                    tpc_if[2].resp_valid <= 1'b0;
                                    state <= IDLE;
                                end
                            end
                            3: begin
                                tpc_if[3].resp_valid <= 1'b1;
                                tpc_if[3].resp_paddr <= current_paddr;
                                tpc_if[3].resp_hit <= mmu_tlb.resp_hit;
                                tpc_if[3].resp_status <= MMU_RESP_OKAY;
                                
                                if (tpc_if[3].resp_ready) begin
                                    tpc_if[3].resp_valid <= 1'b0;
                                    state <= IDLE;
                                end
                            end
                            default: state <= IDLE;
                        endcase
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
endmodule : rvgpu_gpc_mmu

`endif // RVGPU_GPC_MMU_SV 