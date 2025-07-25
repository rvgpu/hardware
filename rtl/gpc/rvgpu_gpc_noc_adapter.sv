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
`include "gpc_l15_noc_if.svh"
`include "gpc_mmu_noc_if.svh"

// 目标节点常量定义
localparam logic [3:0] MSG_TARGET_L2CACHE = NODE_L2_CACHE;
localparam logic [3:0] MSG_TARGET_CONTROL_MMU = NODE_CONTROL;

// GPC NOC Adapter模块
// 负责GPC与全局互联网络(Network-on-Chip)之间的通信适配
module rvgpu_gpc_noc_adapter #(
    parameter noc_config_t NOC_CONFIG = DEFAULT_NOC_CONFIG,
    parameter int GPC_ID = 0
) (
    input  logic                                  clk,
    input  logic                                  rst_n,
    
    // 外部NOC接口
    rvgpu_internal_noc_if.device                  noc_external_if,
    
    // L1.5缓存接口
    gpc_l15_noc_if.noc_adapter                    l15_cache_if,

    // GPC MMU接口
    gpc_mmu_noc_if.noc_adapter                    mmu_if
);

    // 消息类型定义
    import rvgpu_internal_noc_pkg::*;
    
    // 状态机状态
    typedef enum logic [2:0] {
        IDLE,
        PARSE_HEADER,
        ROUTE_TO_L1_CACHE,
        ROUTE_TO_MMU,
        WAIT_RESPONSE,
        SEND_RESPONSE
    } noc_adapter_state_t;
    
    // 内部信号
    noc_adapter_state_t state;
    noc_adapter_state_t next_state;
    logic [NOC_CONFIG.if_config.header_width-1:0] current_header;
    logic [NOC_CONFIG.if_config.data_width-1:0] current_data;
    logic [NOC_CONFIG.if_config.data_width/8-1:0] current_strb;
    logic current_last;
    
    // 消息类型和目标解析
    noc_msg_type_t msg_type;
    logic [3:0] msg_target;
    logic [7:0] msg_source;
    logic [15:0] msg_length;
    logic [31:0] msg_id;
    
    // 缓冲队列
    logic [NOC_CONFIG.if_config.header_width-1:0] req_header_queue[$];
    logic [NOC_CONFIG.if_config.data_width-1:0] req_data_queue[$];
    logic [NOC_CONFIG.if_config.data_width/8-1:0] req_strb_queue[$];
    logic req_last_queue[$];
    
    logic [NOC_CONFIG.if_config.header_width-1:0] resp_header_queue[$];
    logic [NOC_CONFIG.if_config.data_width-1:0] resp_data_queue[$];
    logic resp_last_queue[$];
    
    // 临时响应数据变量
    logic [NOC_CONFIG.if_config.data_width-1:0] resp_data;
    
    // 临时请求数据变量
    logic [NOC_CONFIG.if_config.data_width-1:0] req_data;
    
    // 临时消息头变量
    logic [NOC_CONFIG.if_config.header_width-1:0] header;
    
    // 临时请求类型变量
    noc_msg_type_t req_type;
    
    // 临时响应类型变量
    noc_msg_type_t resp_type;
    
    // 解析NOC消息头
    function automatic void parse_header(input logic [NOC_CONFIG.if_config.header_width-1:0] header);
        // 假设消息头格式如下:
        // [3:0]: 消息类型
        // [7:4]: 目标模块
        // [15:8]: 源模块
        // [31:16]: 消息长度
        // [63:32]: 消息ID
        msg_type = header[3:0];
        msg_target = header[7:4];
        msg_source = header[15:8];
        msg_length = header[31:16];
        msg_id = header[63:32];
    endfunction
    
    // 构造响应头
    function automatic logic [NOC_CONFIG.if_config.header_width-1:0] build_response_header(
        input noc_msg_type_t msg_type,
        input logic [3:0] target,
        input logic [7:0] source,
        input logic [15:0] length,
        input logic [31:0] id
    );
        logic [NOC_CONFIG.if_config.header_width-1:0] header;
        header = '0;
        header[3:0] = msg_type;
        header[7:4] = target;
        header[15:8] = source;
        header[31:16] = length;
        header[63:32] = id;
        return header;
    endfunction
    
    // 主状态机
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            next_state <= IDLE;
            current_header <= '0;
            current_data <= '0;
            current_strb <= '0;
            current_last <= 1'b0;
            
            // 清空队列
            req_header_queue = {};
            req_data_queue = {};
            req_strb_queue = {};
            req_last_queue = {};
            resp_header_queue = {};
            resp_data_queue = {};
            resp_last_queue = {};
            
            // 初始化接口信号
            noc_external_if.m_req_valid <= 1'b0;
            noc_external_if.s_req_ready <= 1'b0;
            noc_external_if.s_resp_valid <= 1'b0;
            noc_external_if.m_resp_ready <= 1'b0;
            
            l15_cache_if.req_valid <= 1'b0;
            mmu_if.req_valid <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    // 接收来自NOC的请求
                    noc_external_if.s_req_ready <= 1'b1;
                    
                    if (noc_external_if.s_req_valid && noc_external_if.s_req_ready) begin
                        // 存储请求头和数据
                        req_header_queue.push_back(noc_external_if.s_req_header);
                        req_data_queue.push_back(noc_external_if.s_req_data);
                        req_strb_queue.push_back(noc_external_if.s_req_strb);
                        req_last_queue.push_back(noc_external_if.s_req_last);
                        
                        // 如果是消息头，解析并确定路由
                        if (req_header_queue.size() == 1) begin
                            current_header = noc_external_if.s_req_header;
                            parse_header(current_header);
                            
                            // 根据消息类型和目标确定下一状态
                            case (msg_type)
                                MSG_MEM_READ_REQ, MSG_MEM_WRITE_REQ: begin
                                    next_state = ROUTE_TO_L1_CACHE;
                                end
                                MSG_MMU_REQ: begin
                                    next_state = ROUTE_TO_MMU;
                                end
                                default: begin
                                    // 未知消息类型，丢弃
                                    req_header_queue = {};
                                    req_data_queue = {};
                                    req_strb_queue = {};
                                    req_last_queue = {};
                                    next_state = IDLE;
                                end
                            endcase
                            
                            // 如果是最后一个数据包，切换到下一状态
                            if (noc_external_if.s_req_last) begin
                                state <= next_state;
                                noc_external_if.s_req_ready <= 1'b0;
                            end
                        end else if (noc_external_if.s_req_last) begin
                            // 接收到最后一个数据包，切换到下一状态
                            state <= next_state;
                            noc_external_if.s_req_ready <= 1'b0;
                        end
                    end
                    
                    // 检查是否有响应需要发送
                    if (resp_header_queue.size() > 0) begin
                        state <= SEND_RESPONSE;
                        noc_external_if.s_req_ready <= 1'b0;
                    end
                end
                
                PARSE_HEADER: begin
                    // 解析消息头并确定路由
                    if (req_header_queue.size() > 0) begin
                        current_header = req_header_queue[0];
                        parse_header(current_header);
                        
                        // 根据消息类型和目标确定下一状态
                        case (msg_type)
                            MSG_MEM_READ_REQ, MSG_MEM_WRITE_REQ: begin
                                state <= ROUTE_TO_L1_CACHE;
                            end
                            MSG_MMU_REQ: begin
                                state <= ROUTE_TO_MMU;
                            end
                            default: begin
                                // 未知消息类型，丢弃
                                req_header_queue = {};
                                req_data_queue = {};
                                req_strb_queue = {};
                                req_last_queue = {};
                                state <= IDLE;
                            end
                        endcase
                    end else begin
                        state <= IDLE;
                    end
                end
                
                ROUTE_TO_L1_CACHE: begin
                    // 将内存访问请求转发给L1.5 Cache
                    if (req_header_queue.size() > 0 && req_data_queue.size() > 0) begin
                        l15_cache_if.req_valid <= 1'b1;
                        l15_cache_if.req_is_read <= (msg_type == MSG_MEM_READ_REQ);
                        l15_cache_if.req_paddr <= req_data_queue[0][63:0];
                        l15_cache_if.req_size <= req_data_queue[0][67:64];
                        l15_cache_if.req_type <= req_data_queue[0][71:68];
                        l15_cache_if.req_data <= req_data_queue.size() > 1 ? req_data_queue[1] : '0;
                        l15_cache_if.req_mask <= req_strb_queue[0];
                        l15_cache_if.req_id <= msg_id;
                        
                        if (l15_cache_if.req_ready) begin
                            // 移除已处理的消息
                            void'(req_header_queue.pop_front());
                            void'(req_data_queue.pop_front());
                            void'(req_strb_queue.pop_front());
                            void'(req_last_queue.pop_front());
                            
                            if (req_data_queue.size() > 0 && !req_last_queue[0]) begin
                                void'(req_data_queue.pop_front());
                                void'(req_strb_queue.pop_front());
                                void'(req_last_queue.pop_front());
                            end
                            
                            l15_cache_if.req_valid <= 1'b0;
                            state <= WAIT_RESPONSE;
                        end
                    end else begin
                        state <= IDLE;
                    end
                end
                
                ROUTE_TO_MMU: begin
                    // 将MMU请求转发给GPC MMU
                    if (req_header_queue.size() > 0 && req_data_queue.size() > 0) begin
                        mmu_if.req_valid <= 1'b1;
                        mmu_if.req_vaddr <= req_data_queue[0][38:0];
                        mmu_if.req_type <= req_data_queue[0][42:40];
                        mmu_if.req_warp_id <= req_data_queue[0][74:43];
                        mmu_if.req_source_id <= req_data_queue[0][78:75];
                        mmu_if.req_gpc_id <= GPC_ID;
                        
                        if (mmu_if.req_ready) begin
                            // 移除已处理的消息
                            void'(req_header_queue.pop_front());
                            void'(req_data_queue.pop_front());
                            void'(req_strb_queue.pop_front());
                            void'(req_last_queue.pop_front());
                            
                            mmu_if.req_valid <= 1'b0;
                            state <= WAIT_RESPONSE;
                        end
                    end else begin
                        state <= IDLE;
                    end
                end
                
                WAIT_RESPONSE: begin
                    // 等待内部模块响应
                    if (msg_type == MSG_MEM_READ_REQ || msg_type == MSG_MEM_WRITE_REQ) begin
                        if (l15_cache_if.resp_valid) begin
                            // 构造响应消息
                            resp_type = (msg_type == MSG_MEM_READ_REQ) ? MSG_MEM_READ_RESP : MSG_MEM_WRITE_RESP;
                            resp_header_queue.push_back(build_response_header(
                                resp_type,
                                msg_source[3:0],
                                {4'b0, GPC_ID[3:0]},
                                16'd2,  // 2个数据包 (头 + 数据)
                                l15_cache_if.resp_id
                            ));
                            resp_data_queue.push_back(l15_cache_if.resp_data);
                            resp_last_queue.push_back(1'b1);
                            
                            state <= SEND_RESPONSE;
                        end
                    end else if (msg_type == MSG_MMU_REQ) begin
                        if (mmu_if.resp_valid) begin
                            // 构造响应消息
                            resp_header_queue.push_back(build_response_header(
                                MSG_MMU_RESP,
                                msg_source[3:0],
                                {4'b0, GPC_ID[3:0]},
                                16'd1,  // 1个数据包
                                msg_id
                            ));
                            
                            // 构造响应数据
                            resp_data = '0;
                            resp_data[26:0] = mmu_if.resp_ppn;
                            resp_data[27] = mmu_if.resp_hit;
                            resp_data[28] = mmu_if.resp_fault;
                            resp_data[60:29] = mmu_if.resp_warp_id;
                            resp_data[64:61] = mmu_if.resp_source_id;
                            
                            resp_data_queue.push_back(resp_data);
                            resp_last_queue.push_back(1'b1);
                            
                            state <= SEND_RESPONSE;
                        end
                    end else begin
                        state <= IDLE;
                    end
                end
                
                SEND_RESPONSE: begin
                    // 发送响应到NOC
                    if (resp_header_queue.size() > 0) begin
                        noc_external_if.s_resp_valid <= 1'b1;
                        noc_external_if.s_resp_header <= resp_header_queue[0];
                        noc_external_if.s_resp_data <= resp_data_queue.size() > 0 ? resp_data_queue[0] : '0;
                        noc_external_if.s_resp_last <= resp_header_queue.size() == 1 || 
                                                     (resp_last_queue.size() > 0 && resp_last_queue[0]);
                        
                        if (noc_external_if.s_resp_ready) begin
                            void'(resp_header_queue.pop_front());
                            
                            if (resp_data_queue.size() > 0) begin
                                void'(resp_data_queue.pop_front());
                            end
                            
                            if (resp_last_queue.size() > 0) begin
                                void'(resp_last_queue.pop_front());
                            end
                            
                            if (resp_header_queue.size() == 0) begin
                                noc_external_if.s_resp_valid <= 1'b0;
                                state <= IDLE;
                            end
                        end
                    end else begin
                        noc_external_if.s_resp_valid <= 1'b0;
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
            
            // 处理来自内部模块的请求
            if (state == IDLE) begin
                // 处理L1.5 Cache请求
                if (l15_cache_if.req_valid) begin
                    // 构造NOC请求
                    req_type = l15_cache_if.req_is_read ? MSG_MEM_READ_REQ : MSG_MEM_WRITE_REQ;
                    header = build_response_header(
                        req_type,
                        MSG_TARGET_L2CACHE,
                        {4'b0, GPC_ID[3:0]},
                        l15_cache_if.req_is_read ? 16'd1 : 16'd2,
                        l15_cache_if.req_id
                    );
                    
                    // 发送请求
                    noc_external_if.m_req_valid <= 1'b1;
                    noc_external_if.m_req_header <= header;
                    
                    // 构造请求数据
                    req_data = '0;
                    req_data[63:0] = l15_cache_if.req_paddr;
                    req_data[67:64] = l15_cache_if.req_size;
                    req_data[71:68] = l15_cache_if.req_type;
                    
                    noc_external_if.m_req_data <= req_data;
                    noc_external_if.m_req_strb <= '1;
                    noc_external_if.m_req_last <= l15_cache_if.req_is_read;
                    
                    if (noc_external_if.m_req_ready) begin
                        if (l15_cache_if.req_is_read) begin
                            // 读请求只需要一个数据包
                            noc_external_if.m_req_valid <= 1'b0;
                        end else begin
                            // 写请求需要两个数据包
                            noc_external_if.m_req_valid <= 1'b1;
                            noc_external_if.m_req_header <= '0;
                            noc_external_if.m_req_data <= l15_cache_if.req_data;
                            noc_external_if.m_req_strb <= l15_cache_if.req_mask;
                            noc_external_if.m_req_last <= 1'b1;
                            
                            if (noc_external_if.m_req_ready) begin
                                noc_external_if.m_req_valid <= 1'b0;
                            end
                        end
                    end
                end
                
                // 处理MMU请求
                else if (mmu_if.req_valid) begin
                    // 构造NOC请求
                    header = build_response_header(
                        MSG_MMU_REQ,
                        MSG_TARGET_CONTROL_MMU,
                        {4'b0, GPC_ID[3:0]},
                        16'd1,
                        {GPC_ID[3:0], mmu_if.req_source_id, mmu_if.req_warp_id[23:0]}
                    );
                    
                    // 发送请求
                    noc_external_if.m_req_valid <= 1'b1;
                    noc_external_if.m_req_header <= header;
                    
                    // 构造请求数据
                    req_data = '0;
                    req_data[38:0] = mmu_if.req_vaddr;
                    req_data[42:40] = mmu_if.req_type;
                    req_data[74:43] = mmu_if.req_warp_id;
                    req_data[78:75] = mmu_if.req_source_id;
                    req_data[82:79] = mmu_if.req_gpc_id;
                    
                    noc_external_if.m_req_data <= req_data;
                    noc_external_if.m_req_strb <= '1;
                    noc_external_if.m_req_last <= 1'b1;
                    
                    if (noc_external_if.m_req_ready) begin
                        noc_external_if.m_req_valid <= 1'b0;
                    end
                end
            end
            
            // 处理来自NOC的响应
            noc_external_if.m_resp_ready <= 1'b1;
            if (noc_external_if.m_resp_valid && noc_external_if.m_resp_ready) begin
                // 解析响应头
                parse_header(noc_external_if.m_resp_header);
                
                // 根据消息类型路由响应
                case (msg_type)
                    MSG_MEM_READ_RESP, MSG_MEM_WRITE_RESP: begin
                        // 只需要将响应转发给L1.5缓存，无需驱动信号
                    end
                    
                    MSG_MMU_RESP: begin
                        // 只需要将响应转发给GPC MMU，无需驱动信号
                    end
                    
                    default: begin
                        // 未知响应类型，忽略
                    end
                endcase
            end
        end
    end

endmodule : rvgpu_gpc_noc_adapter

`endif // RVGPU_GPC_NOC_ADAPTER_SV 