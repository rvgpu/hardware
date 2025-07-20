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

`ifndef RVGPU_INTERNAL_NOC_2SC_SV
`define RVGPU_INTERNAL_NOC_2SC_SV

`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_internal_noc_pkg.svh"

`ifndef RVGPU_INTERNAL_NOC_PKG_IMPORTED
`define RVGPU_INTERNAL_NOC_PKG_IMPORTED
import rvgpu_internal_noc_pkg::*;
`endif // RVGPU_INTERNAL_NOC_PKG_IMPORTED

module rvgpu_internal_noc #(
    parameter noc_config_t NOC_CONFIG = DEFAULT_NOC_CONFIG
) (
    input logic clk,
    input logic rst_n,
    
    // Control Unit NOC Interface
    rvgpu_internal_noc_if.noc control_unit,
    
    // L2Cache NOC Interface
    rvgpu_internal_noc_if.noc l2cache,

    // Shader Core NOC Interfaces
    rvgpu_internal_noc_if.noc shader_core [2]
);

    // 内部参数定义
    localparam int NUM_PORTS = 4; // Control Unit + L2Cache + 2 Shader Cores
    
    // 内部信号定义
    typedef struct packed {
        logic                                           valid;
        logic [NOC_CONFIG.if_config.header_width-1:0]   header;
        logic [NOC_CONFIG.if_config.data_width-1:0]     data;
        logic [NOC_CONFIG.if_config.strb_width-1:0]     strb;
        logic                                           last;
    } noc_req_t;
    
    typedef struct packed {
        logic                                           valid;
        logic [NOC_CONFIG.if_config.header_width-1:0]   header;
        logic [NOC_CONFIG.if_config.data_width-1:0]     data;
        logic [NOC_CONFIG.if_config.status_width-1:0]   status;
        logic                                           last;
    } noc_resp_t;
    
    // 端口信号
    noc_req_t  port_req_out [NUM_PORTS];
    logic      port_req_ready [NUM_PORTS];
    noc_req_t  port_req_in [NUM_PORTS];
    logic      port_req_in_ready [NUM_PORTS];
    
    noc_resp_t port_resp_out [NUM_PORTS];
    logic      port_resp_ready [NUM_PORTS];
    noc_resp_t port_resp_in [NUM_PORTS];
    logic      port_resp_in_ready [NUM_PORTS];
    
    // 仲裁状态
    logic [1:0] req_arb_state [NUM_PORTS];
    logic [1:0] resp_arb_state [NUM_PORTS];
    
    //=============================================================================
    // 端口信号连接
    //=============================================================================
    
    // Control Unit端口连接 (端口0)
    assign port_req_out[NODE_CONTROL].valid  = control_unit.m_req_valid;
    assign port_req_out[NODE_CONTROL].header = control_unit.m_req_header;
    assign port_req_out[NODE_CONTROL].data   = control_unit.m_req_data;
    assign port_req_out[NODE_CONTROL].strb   = control_unit.m_req_strb;
    assign port_req_out[NODE_CONTROL].last   = control_unit.m_req_last;
    assign control_unit.m_req_ready = port_req_ready[NODE_CONTROL];
    
    assign control_unit.s_req_valid  = port_req_in[NODE_CONTROL].valid;
    assign control_unit.s_req_header = port_req_in[NODE_CONTROL].header;
    assign control_unit.s_req_data   = port_req_in[NODE_CONTROL].data;
    assign control_unit.s_req_strb   = port_req_in[NODE_CONTROL].strb;
    assign control_unit.s_req_last   = port_req_in[NODE_CONTROL].last;
    assign port_req_in_ready[NODE_CONTROL] = control_unit.s_req_ready;
    
    assign control_unit.m_resp_valid  = port_resp_in[NODE_CONTROL].valid;
    assign control_unit.m_resp_header = port_resp_in[NODE_CONTROL].header;
    assign control_unit.m_resp_data   = port_resp_in[NODE_CONTROL].data;
    assign control_unit.m_resp_status = port_resp_in[NODE_CONTROL].status;
    assign control_unit.m_resp_last   = port_resp_in[NODE_CONTROL].last;
    assign port_resp_in_ready[NODE_CONTROL] = control_unit.m_resp_ready;
    
    assign port_resp_out[NODE_CONTROL].valid  = control_unit.s_resp_valid;
    assign port_resp_out[NODE_CONTROL].header = control_unit.s_resp_header;
    assign port_resp_out[NODE_CONTROL].data   = control_unit.s_resp_data;
    assign port_resp_out[NODE_CONTROL].status = control_unit.s_resp_status;
    assign port_resp_out[NODE_CONTROL].last   = control_unit.s_resp_last;
    assign control_unit.s_resp_ready = port_resp_ready[NODE_CONTROL];
    
    // L2Cache端口连接 (端口1)
    assign port_req_out[NODE_L2_CACHE].valid  = l2cache.m_req_valid;
    assign port_req_out[NODE_L2_CACHE].header = l2cache.m_req_header;
    assign port_req_out[NODE_L2_CACHE].data   = l2cache.m_req_data;
    assign port_req_out[NODE_L2_CACHE].strb   = l2cache.m_req_strb;
    assign port_req_out[NODE_L2_CACHE].last   = l2cache.m_req_last;
    assign l2cache.m_req_ready = port_req_ready[NODE_L2_CACHE];
    
    assign l2cache.s_req_valid  = port_req_in[NODE_L2_CACHE].valid;
    assign l2cache.s_req_header = port_req_in[NODE_L2_CACHE].header;
    assign l2cache.s_req_data   = port_req_in[NODE_L2_CACHE].data;
    assign l2cache.s_req_strb   = port_req_in[NODE_L2_CACHE].strb;
    assign l2cache.s_req_last   = port_req_in[NODE_L2_CACHE].last;
    assign port_req_in_ready[NODE_L2_CACHE] = l2cache.s_req_ready;
    
    assign l2cache.m_resp_valid  = port_resp_in[NODE_L2_CACHE].valid;
    assign l2cache.m_resp_header = port_resp_in[NODE_L2_CACHE].header;
    assign l2cache.m_resp_data   = port_resp_in[NODE_L2_CACHE].data;
    assign l2cache.m_resp_status = port_resp_in[NODE_L2_CACHE].status;
    assign l2cache.m_resp_last   = port_resp_in[NODE_L2_CACHE].last;
    assign port_resp_in_ready[NODE_L2_CACHE] = l2cache.m_resp_ready;
    
    assign port_resp_out[NODE_L2_CACHE].valid  = l2cache.s_resp_valid;
    assign port_resp_out[NODE_L2_CACHE].header = l2cache.s_resp_header;
    assign port_resp_out[NODE_L2_CACHE].data   = l2cache.s_resp_data;
    assign port_resp_out[NODE_L2_CACHE].status = l2cache.s_resp_status;
    assign port_resp_out[NODE_L2_CACHE].last   = l2cache.s_resp_last;
    assign l2cache.s_resp_ready = port_resp_ready[NODE_L2_CACHE];
    
    // Shader Core 0 端口连接 (端口2)
    assign port_req_out[NODE_SHADER_0].valid  = shader_core[0].m_req_valid;
    assign port_req_out[NODE_SHADER_0].header = shader_core[0].m_req_header;
    assign port_req_out[NODE_SHADER_0].data   = shader_core[0].m_req_data;
    assign port_req_out[NODE_SHADER_0].strb   = shader_core[0].m_req_strb;
    assign port_req_out[NODE_SHADER_0].last   = shader_core[0].m_req_last;
    assign shader_core[0].m_req_ready = port_req_ready[NODE_SHADER_0];
    assign shader_core[0].s_req_valid  = port_req_in[NODE_SHADER_0].valid;
    assign shader_core[0].s_req_header = port_req_in[NODE_SHADER_0].header;
    assign shader_core[0].s_req_data   = port_req_in[NODE_SHADER_0].data;
    assign shader_core[0].s_req_strb   = port_req_in[NODE_SHADER_0].strb;
    assign shader_core[0].s_req_last   = port_req_in[NODE_SHADER_0].last;
    assign port_req_in_ready[NODE_SHADER_0] = shader_core[0].s_req_ready;
    
    assign shader_core[0].m_resp_valid  = port_resp_in[NODE_SHADER_0].valid;
    assign shader_core[0].m_resp_header = port_resp_in[NODE_SHADER_0].header;
    assign shader_core[0].m_resp_data   = port_resp_in[NODE_SHADER_0].data;
    assign shader_core[0].m_resp_status = port_resp_in[NODE_SHADER_0].status;
    assign shader_core[0].m_resp_last   = port_resp_in[NODE_SHADER_0].last;
    assign port_resp_in_ready[NODE_SHADER_0] = shader_core[0].m_resp_ready;
    
    assign port_resp_out[NODE_SHADER_0].valid  = shader_core[0].s_resp_valid;
    assign port_resp_out[NODE_SHADER_0].header = shader_core[0].s_resp_header;
    assign port_resp_out[NODE_SHADER_0].data   = shader_core[0].s_resp_data;
    assign port_resp_out[NODE_SHADER_0].status = shader_core[0].s_resp_status;
    assign port_resp_out[NODE_SHADER_0].last   = shader_core[0].s_resp_last;
    assign shader_core[0].s_resp_ready = port_resp_ready[NODE_SHADER_0];
    
    // Shader Core 1 端口连接 (端口3)
    assign port_req_out[NODE_SHADER_1].valid  = shader_core[1].m_req_valid;
    assign port_req_out[NODE_SHADER_1].header = shader_core[1].m_req_header;
    assign port_req_out[NODE_SHADER_1].data   = shader_core[1].m_req_data;
    assign port_req_out[NODE_SHADER_1].strb   = shader_core[1].m_req_strb;
    assign port_req_out[NODE_SHADER_1].last   = shader_core[1].m_req_last;
    assign shader_core[1].m_req_ready = port_req_ready[NODE_SHADER_1];
    
    assign shader_core[1].s_req_valid  = port_req_in[NODE_SHADER_1].valid;
    assign shader_core[1].s_req_header = port_req_in[NODE_SHADER_1].header;
    assign shader_core[1].s_req_data   = port_req_in[NODE_SHADER_1].data;
    assign shader_core[1].s_req_strb   = port_req_in[NODE_SHADER_1].strb;
    assign shader_core[1].s_req_last   = port_req_in[NODE_SHADER_1].last;
    assign port_req_in_ready[NODE_SHADER_1] = shader_core[1].s_req_ready;
    
    assign shader_core[1].m_resp_valid  = port_resp_in[NODE_SHADER_1].valid;
    assign shader_core[1].m_resp_header = port_resp_in[NODE_SHADER_1].header;
    assign shader_core[1].m_resp_data   = port_resp_in[NODE_SHADER_1].data;
    assign shader_core[1].m_resp_status = port_resp_in[NODE_SHADER_1].status;
    assign shader_core[1].m_resp_last   = port_resp_in[NODE_SHADER_1].last;
    assign port_resp_in_ready[NODE_SHADER_1] = shader_core[1].m_resp_ready;
    
    assign port_resp_out[NODE_SHADER_1].valid  = shader_core[1].s_resp_valid;
    assign port_resp_out[NODE_SHADER_1].header = shader_core[1].s_resp_header;
    assign port_resp_out[NODE_SHADER_1].data   = shader_core[1].s_resp_data;
    assign port_resp_out[NODE_SHADER_1].status = shader_core[1].s_resp_status;
    assign port_resp_out[NODE_SHADER_1].last   = shader_core[1].s_resp_last;
    assign shader_core[1].s_resp_ready = port_resp_ready[NODE_SHADER_1];
    
    //=============================================================================
    // 路由和仲裁逻辑
    //=============================================================================
    
    // 请求路由和仲裁 - 使用具体名称提高可读性
    logic [NUM_PORTS-1:0] req_grant_cu;    // Control Unit的grant信号
    logic [NUM_PORTS-1:0] req_grant_l2;    // L2Cache的grant信号
    logic [NUM_PORTS-1:0] req_grant_s0;    // Shader Core 0的grant信号
    logic [NUM_PORTS-1:0] req_grant_s1;    // Shader Core 1的grant信号
    
    // 功能函数：检查目标为dst的端口req有哪些，使用mask标记
    function automatic logic [NUM_PORTS-1:0] get_req_mask(noc_node_id_t dst);
        logic [NUM_PORTS-1:0] mask = 4'b0000;
        mask[0] = port_req_out[0].valid && (get_noc_header_dest_node(port_req_out[0].header) == dst);
        mask[1] = port_req_out[1].valid && (get_noc_header_dest_node(port_req_out[1].header) == dst);
        mask[2] = port_req_out[2].valid && (get_noc_header_dest_node(port_req_out[2].header) == dst);
        mask[3] = port_req_out[3].valid && (get_noc_header_dest_node(port_req_out[3].header) == dst);
        return mask;
    endfunction
    
    // 功能函数：检查目标为dst的端口resp有哪些，使用mask标记
    function automatic logic [NUM_PORTS-1:0] get_resp_mask(noc_node_id_t dst);
        logic [NUM_PORTS-1:0] mask = 4'b0000;
        mask[0] = port_resp_out[0].valid && (get_noc_header_dest_node(port_resp_out[0].header) == dst);
        mask[1] = port_resp_out[1].valid && (get_noc_header_dest_node(port_resp_out[1].header) == dst);
        mask[2] = port_resp_out[2].valid && (get_noc_header_dest_node(port_resp_out[2].header) == dst);
        mask[3] = port_resp_out[3].valid && (get_noc_header_dest_node(port_resp_out[3].header) == dst);
        return mask;
    endfunction
    
    // 功能函数：更新req的仲裁状态，如果有请求，状态按照 0 -> 1 -> 2 -> 3 的顺序轮转
    function automatic void update_req_arb_state(int port);
        logic [NUM_PORTS-1:0] req_mask = get_req_mask(port);
        if (req_mask != 4'b0000) begin
            case (req_arb_state[port])
                2'b00: req_arb_state[port] <= 2'b01;
                2'b01: req_arb_state[port] <= 2'b10;
                2'b10: req_arb_state[port] <= 2'b11;
                2'b11: req_arb_state[port] <= 2'b00;
            endcase
        end else begin
            req_arb_state[port] <= req_arb_state[port];
        end
    endfunction

    // 功能函数：更新resp的仲裁状态，如果有请求，状态按照 0 -> 1 -> 2 -> 3 的顺序轮转
    function automatic void update_resp_arb_state(int port);
        logic [NUM_PORTS-1:0] resp_mask = get_resp_mask(port);
        if (resp_mask != 4'b0000) begin
            case (resp_arb_state[port])
                2'b00: resp_arb_state[port] <= 2'b01;
                2'b01: resp_arb_state[port] <= 2'b10;
                2'b10: resp_arb_state[port] <= 2'b11;
                2'b11: resp_arb_state[port] <= 2'b00;
            endcase
        end else begin
            resp_arb_state[port] <= resp_arb_state[port];
        end
    endfunction
    
    // 更新req和resp的仲裁状态
    // 仲裁状态 logic[1:0] xxxx_arb_state[NUM_PORTS]，即对于每个端口，有4个状态
    // 状态0表示优先级顺序是 0 -> 1 -> 2 -> 3，0号端口的优先级最高
    // 状态1表示优先级顺序是 1 -> 2 -> 3 -> 0，1号端口的优先级最高
    // 状态2表示优先级顺序是 2 -> 3 -> 0 -> 1，2号端口的优先级最高
    // 状态3表示优先级顺序是 3 -> 0 -> 1 -> 2，3号端口的优先级最高
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_PORTS; i++) begin
                req_arb_state[i] <= 2'b00;
                resp_arb_state[i] <= 2'b00;
            end
        end else begin
            // 对于每一个port:
            // 1. 检查是否有req请求，如果有的话，来更新req_arb_state状态
            update_req_arb_state(0);
            update_req_arb_state(1);
            update_req_arb_state(2);
            update_req_arb_state(3);

            // 2. 检查是否有resp请求，如果有的话，来更新resp_arb_state状态
            update_resp_arb_state(0);
            update_resp_arb_state(1);
            update_resp_arb_state(2);
            update_resp_arb_state(3);
        end
    end
    
    // 请求仲裁逻辑，根据arb_state来检查grant哪个端口
    function automatic logic [NUM_PORTS-1:0] get_req_grant(int dst, logic [1:0] arb_state);
        logic [NUM_PORTS-1:0] grant = 4'b0000;
        logic [NUM_PORTS-1:0] mask = get_req_mask(dst);
        
        case (arb_state)
            2'b00: begin
                if (mask[0]) grant[0] = 1'b1;
                else if (mask[1]) grant[1] = 1'b1;
                else if (mask[2]) grant[2] = 1'b1;
                else if (mask[3]) grant[3] = 1'b1;
            end
            2'b01: begin
                if (mask[1]) grant[1] = 1'b1;
                else if (mask[2]) grant[2] = 1'b1;
                else if (mask[3]) grant[3] = 1'b1;
                else if (mask[0]) grant[0] = 1'b1;
            end
            2'b10: begin
                if (mask[2]) grant[2] = 1'b1;
                else if (mask[3]) grant[3] = 1'b1;
                else if (mask[0]) grant[0] = 1'b1;
                else if (mask[1]) grant[1] = 1'b1;
            end
            2'b11: begin
                if (mask[3]) grant[3] = 1'b1;
                else if (mask[0]) grant[0] = 1'b1;
                else if (mask[1]) grant[1] = 1'b1;
                else if (mask[2]) grant[2] = 1'b1;
            end
        endcase
        return grant;
    endfunction
    
    // 生成各个端口的grant信号
    always_comb begin
        req_grant_cu = get_req_grant(NODE_CONTROL, req_arb_state[NODE_CONTROL]);
        req_grant_l2 = get_req_grant(NODE_L2_CACHE, req_arb_state[NODE_L2_CACHE]);
        req_grant_s0 = get_req_grant(NODE_SHADER_0, req_arb_state[NODE_SHADER_0]);
        req_grant_s1 = get_req_grant(NODE_SHADER_1, req_arb_state[NODE_SHADER_1]);
    end
    
    // 请求多路选择器，优先级编码器，选择第一个为true的grant位，get_req_grant已经根据arb_state顺序检查mask设置了grant
    function automatic noc_req_t select_req(int dst, logic [NUM_PORTS-1:0] grant);
        noc_req_t selected = '0;
        case (1'b1)
            grant[0]: selected = port_req_out[0];
            grant[1]: selected = port_req_out[1];
            grant[2]: selected = port_req_out[2];
            grant[3]: selected = port_req_out[3];
            default: selected = '0;
        endcase
        return selected;
    endfunction
    
    // 将grant信号传递给各个端口
    always_comb begin
        port_req_in[NODE_CONTROL] = select_req(NODE_CONTROL, req_grant_cu);
        port_req_in[NODE_L2_CACHE] = select_req(NODE_L2_CACHE, req_grant_l2);
        port_req_in[NODE_SHADER_0] = select_req(NODE_SHADER_0, req_grant_s0);
        port_req_in[NODE_SHADER_1] = select_req(NODE_SHADER_1, req_grant_s1);
    end
    
    // 请求Ready信号连接 - 使用函数
    function automatic logic get_req_ready(int src);
        logic ready = 1'b0;
        // 当某个源被grant时，使用对应目标端口的ready信号
        // 由于每个grant信号最多只有一位为true，所以只需要检查对应的ready
        if (req_grant_cu[src]) begin
            ready = port_req_in_ready[NODE_CONTROL];
        end else if (req_grant_l2[src]) begin
            ready = port_req_in_ready[NODE_L2_CACHE];
        end else if (req_grant_s0[src]) begin
            ready = port_req_in_ready[NODE_SHADER_0];
        end else if (req_grant_s1[src]) begin
            ready = port_req_in_ready[NODE_SHADER_1];
        end
        return ready;
    endfunction
    
    always_comb begin
        port_req_ready[NODE_CONTROL]   = get_req_ready(NODE_CONTROL);
        port_req_ready[NODE_L2_CACHE]  = get_req_ready(NODE_L2_CACHE);
        port_req_ready[NODE_SHADER_0]  = get_req_ready(NODE_SHADER_0);
        port_req_ready[NODE_SHADER_1]  = get_req_ready(NODE_SHADER_1); 
    end
    
    //=============================================================================
    // 响应路由和仲裁逻辑
    //=============================================================================
    
    // 响应路由和仲裁 - 使用具体名称提高可读性
    logic [NUM_PORTS-1:0] resp_grant_cu;    // Control Unit的响应grant信号
    logic [NUM_PORTS-1:0] resp_grant_l2;    // L2Cache的响应grant信号
    logic [NUM_PORTS-1:0] resp_grant_s0;    // Shader Core 0的响应grant信号
    logic [NUM_PORTS-1:0] resp_grant_s1;    // Shader Core 1的响应grant信号
    
    // 响应仲裁逻辑 - 使用函数和查找表
    function automatic logic [NUM_PORTS-1:0] get_resp_grant(int dst, logic [1:0] arb_state);
        logic [NUM_PORTS-1:0] grant = 4'b0000;
        logic [NUM_PORTS-1:0] mask = get_resp_mask(dst);
        
        case (arb_state)
            2'b00: begin
                if (mask[0]) grant[0] = 1'b1;
                else if (mask[1]) grant[1] = 1'b1;
                else if (mask[2]) grant[2] = 1'b1;
                else if (mask[3]) grant[3] = 1'b1;
            end
            2'b01: begin
                if (mask[1]) grant[1] = 1'b1;
                else if (mask[2]) grant[2] = 1'b1;
                else if (mask[3]) grant[3] = 1'b1;
                else if (mask[0]) grant[0] = 1'b1;
            end
            2'b10: begin
                if (mask[2]) grant[2] = 1'b1;
                else if (mask[3]) grant[3] = 1'b1;
                else if (mask[0]) grant[0] = 1'b1;
                else if (mask[1]) grant[1] = 1'b1;
            end
            2'b11: begin
                if (mask[3]) grant[3] = 1'b1;
                else if (mask[0]) grant[0] = 1'b1;
                else if (mask[1]) grant[1] = 1'b1;
                else if (mask[2]) grant[2] = 1'b1;
            end
        endcase
        return grant;
    endfunction
    
    // 生成各个端口的响应grant信号
    always_comb begin
        resp_grant_cu = get_resp_grant(NODE_CONTROL, resp_arb_state[NODE_CONTROL]);
        resp_grant_l2 = get_resp_grant(NODE_L2_CACHE, resp_arb_state[NODE_L2_CACHE]);
        resp_grant_s0 = get_resp_grant(NODE_SHADER_0, resp_arb_state[NODE_SHADER_0]);
        resp_grant_s1 = get_resp_grant(NODE_SHADER_1, resp_arb_state[NODE_SHADER_1]);
    end
    
    // 响应多路选择器 - 使用函数
    function automatic noc_resp_t select_resp(int dst, logic [NUM_PORTS-1:0] grant);
        noc_resp_t selected = '0;
        case (1'b1)
            grant[0]: selected = port_resp_out[0];
            grant[1]: selected = port_resp_out[1];
            grant[2]: selected = port_resp_out[2];
            grant[3]: selected = port_resp_out[3];
            default: selected = '0;
        endcase
        return selected;
    endfunction
    
    // 将响应grant信号传递给各个端口
    always_comb begin
        port_resp_in[NODE_CONTROL] = select_resp(NODE_CONTROL, resp_grant_cu);
        port_resp_in[NODE_L2_CACHE] = select_resp(NODE_L2_CACHE, resp_grant_l2);
        port_resp_in[NODE_SHADER_0] = select_resp(NODE_SHADER_0, resp_grant_s0);
        port_resp_in[NODE_SHADER_1] = select_resp(NODE_SHADER_1, resp_grant_s1);
    end
    
    // 响应Ready信号连接 - 使用函数
    function automatic logic get_resp_ready(int src);
        logic ready = 1'b0;
        // 当某个源被grant时，使用对应目标端口的ready信号
        // 由于每个grant信号最多只有一位为true，所以只需要检查对应的ready
        if (resp_grant_cu[src]) begin
            ready = port_resp_in_ready[NODE_CONTROL];
        end else if (resp_grant_l2[src]) begin
            ready = port_resp_in_ready[NODE_L2_CACHE];
        end else if (resp_grant_s0[src]) begin
            ready = port_resp_in_ready[NODE_SHADER_0];
        end else if (resp_grant_s1[src]) begin
            ready = port_resp_in_ready[NODE_SHADER_1];
        end
        return ready;
    endfunction
    
    always_comb begin
        port_resp_ready[NODE_CONTROL]   = get_resp_ready(NODE_CONTROL);
        port_resp_ready[NODE_L2_CACHE]  = get_resp_ready(NODE_L2_CACHE);
        port_resp_ready[NODE_SHADER_0]  = get_resp_ready(NODE_SHADER_0);
        port_resp_ready[NODE_SHADER_1]  = get_resp_ready(NODE_SHADER_1);
    end

endmodule : rvgpu_internal_noc

`endif // RVGPU_INTERNAL_NOC_2SC_SV