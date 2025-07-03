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
`include "rvgpu_internal_noc_pkg.sv"

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
    localparam int NUM_PORTS = 4; // control_unit + l2cache + 2*shader_core
    
    // 内部信号定义
    typedef struct packed {
        logic                                   valid;
        logic [NOC_CONFIG.header_width-1:0]     header;
        logic [NOC_CONFIG.data_width-1:0]       data;
        logic [NOC_CONFIG.data_width/8-1:0]     strb;
        logic                                   last;
    } noc_req_t;
    
    typedef struct packed {
        logic                                   valid;
        logic [NOC_CONFIG.header_width-1:0]     header;
        logic [NOC_CONFIG.data_width-1:0]       data;
        logic [1:0]                             status;
        logic                                   last;
    } noc_resp_t;
    
    // 请求通道信号
    noc_req_t  port_req_out [NUM_PORTS];    // 各端口发出的请求
    logic      port_req_ready [NUM_PORTS];  // 各端口请求ready信号
    noc_req_t  port_req_in [NUM_PORTS];     // 各端口接收的请求
    logic      port_req_in_ready [NUM_PORTS]; // 各端口接收请求的ready信号
    
    // 响应通道信号
    noc_resp_t port_resp_out [NUM_PORTS];   // 各端口发出的响应
    logic      port_resp_ready [NUM_PORTS]; // 各端口响应ready信号
    noc_resp_t port_resp_in [NUM_PORTS];    // 各端口接收的响应
    logic      port_resp_in_ready [NUM_PORTS]; // 各端口接收响应的ready信号
    
    // 仲裁状态
    logic [1:0] req_arb_state [NUM_PORTS];  // 每个目标端口的请求仲裁状态
    logic [1:0] resp_arb_state [NUM_PORTS]; // 每个目标端口的响应仲裁状态
    
    //=============================================================================
    // 端口信号连接
    //=============================================================================
    
    // Control Unit端口连接 (NODE_CONTROL = 0)
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
    
    // L2Cache端口连接 (NODE_L2_CACHE = 1)
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
    
    // Shader Core端口连接 (NODE_SHADER_0 = 2, NODE_SHADER_1 = 3)
    genvar i;
    generate
        for (i = 0; i < 2; i++) begin : gen_shader_ports
            localparam int PORT_IDX = NODE_SHADER_0 + i;  // 2, 3
            
            assign port_req_out[PORT_IDX].valid  = shader_core[i].m_req_valid;
            assign port_req_out[PORT_IDX].header = shader_core[i].m_req_header;
            assign port_req_out[PORT_IDX].data   = shader_core[i].m_req_data;
            assign port_req_out[PORT_IDX].strb   = shader_core[i].m_req_strb;
            assign port_req_out[PORT_IDX].last   = shader_core[i].m_req_last;
            assign shader_core[i].m_req_ready = port_req_ready[PORT_IDX];
            
            assign shader_core[i].s_req_valid  = port_req_in[PORT_IDX].valid;
            assign shader_core[i].s_req_header = port_req_in[PORT_IDX].header;
            assign shader_core[i].s_req_data   = port_req_in[PORT_IDX].data;
            assign shader_core[i].s_req_strb   = port_req_in[PORT_IDX].strb;
            assign shader_core[i].s_req_last   = port_req_in[PORT_IDX].last;
            assign port_req_in_ready[PORT_IDX] = shader_core[i].s_req_ready;
            
            assign shader_core[i].m_resp_valid  = port_resp_in[PORT_IDX].valid;
            assign shader_core[i].m_resp_header = port_resp_in[PORT_IDX].header;
            assign shader_core[i].m_resp_data   = port_resp_in[PORT_IDX].data;
            assign shader_core[i].m_resp_status = port_resp_in[PORT_IDX].status;
            assign shader_core[i].m_resp_last   = port_resp_in[PORT_IDX].last;
            assign port_resp_in_ready[PORT_IDX] = shader_core[i].m_resp_ready;
            
            assign port_resp_out[PORT_IDX].valid  = shader_core[i].s_resp_valid;
            assign port_resp_out[PORT_IDX].header = shader_core[i].s_resp_header;
            assign port_resp_out[PORT_IDX].data   = shader_core[i].s_resp_data;
            assign port_resp_out[PORT_IDX].status = shader_core[i].s_resp_status;
            assign port_resp_out[PORT_IDX].last   = shader_core[i].s_resp_last;
            assign shader_core[i].s_resp_ready = port_resp_ready[PORT_IDX];
        end
    endgenerate
    
    //=============================================================================
    // 路由逻辑 - 端口ID直接对应节点ID
    //=============================================================================
    
    // 根据目标节点ID确定目标端口 - 现在可以直接返回节点ID作为端口ID
    function automatic int get_target_port(input noc_node_id_t dest_node);
        return int'(dest_node); // 直接转换，因为端口ID = 节点ID
    endfunction
    
    // 根据源节点ID确定源端口 - 现在可以直接返回节点ID作为端口ID  
    function automatic int get_source_port(input noc_node_id_t src_node);
        return int'(src_node); // 直接转换，因为端口ID = 节点ID
    endfunction
    
    //=============================================================================
    // 请求路由和仲裁逻辑
    //=============================================================================
    
    generate
        for (i = 0; i < NUM_PORTS; i++) begin : gen_req_routing
            
            // 请求仲裁器
            logic [NUM_PORTS-1:0] req_grant;
            logic [NUM_PORTS-1:0] req_request;
            noc_header_t req_headers [NUM_PORTS];
            int target_ports [NUM_PORTS];
            
            // 解析每个源端口的请求header并确定目标端口
            for (genvar j = 0; j < NUM_PORTS; j++) begin : gen_req_parse
                assign req_headers[j] = noc_header_t'(port_req_out[j].header);
                assign target_ports[j] = get_target_port(noc_node_id_t'(req_headers[j].dest_node));
                assign req_request[j] = port_req_out[j].valid && (target_ports[j] == i);
            end
            
            // 轮询仲裁器
            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    req_arb_state[i] <= 2'b00;
                end else begin
                    // 简单的轮询仲裁
                    case (req_arb_state[i])
                        2'b00: if (req_request != 4'b0000) req_arb_state[i] <= 2'b01;
                        2'b01: if (req_request != 4'b0000) req_arb_state[i] <= 2'b10;
                        2'b10: if (req_request != 4'b0000) req_arb_state[i] <= 2'b11;
                        2'b11: if (req_request != 4'b0000) req_arb_state[i] <= 2'b00;
                    endcase
                end
            end
            
            // 仲裁逻辑
            always_comb begin
                req_grant = 4'b0000;
                case (req_arb_state[i])
                    2'b00: begin
                        if (req_request[0]) req_grant[0] = 1'b1;
                        else if (req_request[1]) req_grant[1] = 1'b1;
                        else if (req_request[2]) req_grant[2] = 1'b1;
                        else if (req_request[3]) req_grant[3] = 1'b1;
                    end
                    2'b01: begin
                        if (req_request[1]) req_grant[1] = 1'b1;
                        else if (req_request[2]) req_grant[2] = 1'b1;
                        else if (req_request[3]) req_grant[3] = 1'b1;
                        else if (req_request[0]) req_grant[0] = 1'b1;
                    end
                    2'b10: begin
                        if (req_request[2]) req_grant[2] = 1'b1;
                        else if (req_request[3]) req_grant[3] = 1'b1;
                        else if (req_request[0]) req_grant[0] = 1'b1;
                        else if (req_request[1]) req_grant[1] = 1'b1;
                    end
                    2'b11: begin
                        if (req_request[3]) req_grant[3] = 1'b1;
                        else if (req_request[0]) req_grant[0] = 1'b1;
                        else if (req_request[1]) req_grant[1] = 1'b1;
                        else if (req_request[2]) req_grant[2] = 1'b1;
                    end
                endcase
            end
            
            // 多路选择器 - 选择获得仲裁权的请求
            always_comb begin
                port_req_in[i] = '0;
                for (int j = 0; j < NUM_PORTS; j++) begin
                    if (req_grant[j]) begin
                        port_req_in[i] = port_req_out[j];
                        break;
                    end
                end
            end
            
        end
    endgenerate
    
    // Ready信号连接 - 独立于generate块以避免作用域问题
    // 简化ready信号连接 - 使用OR逻辑
    always_comb begin
        for (int src_port = 0; src_port < NUM_PORTS; src_port++) begin
            port_req_ready[src_port] = 1'b0;
            
            // 检查每个目标端口
            for (int dst_port = 0; dst_port < NUM_PORTS; dst_port++) begin
                noc_header_t header_check;
                int target_port_check;
                logic req_match_check;
                logic grant_check;
                
                header_check = noc_header_t'(port_req_out[src_port].header);
                target_port_check = get_target_port(noc_node_id_t'(header_check.dest_node));
                req_match_check = port_req_out[src_port].valid && (target_port_check == dst_port);
                
                // 确定是否获得仲裁权
                grant_check = 1'b0;
                if (req_match_check) begin
                    case (req_arb_state[dst_port])
                        2'b00: grant_check = (src_port == 0) || 
                                           (!port_req_out[0].valid && src_port == 1) || 
                                           (!port_req_out[0].valid && !port_req_out[1].valid && src_port == 2) ||
                                           (!port_req_out[0].valid && !port_req_out[1].valid && !port_req_out[2].valid && src_port == 3);
                        2'b01: grant_check = (src_port == 1) || 
                                           (!port_req_out[1].valid && src_port == 2) || 
                                           (!port_req_out[1].valid && !port_req_out[2].valid && src_port == 3) ||
                                           (!port_req_out[1].valid && !port_req_out[2].valid && !port_req_out[3].valid && src_port == 0);
                        2'b10: grant_check = (src_port == 2) || 
                                           (!port_req_out[2].valid && src_port == 3) || 
                                           (!port_req_out[2].valid && !port_req_out[3].valid && src_port == 0) ||
                                           (!port_req_out[2].valid && !port_req_out[3].valid && !port_req_out[0].valid && src_port == 1);
                        2'b11: grant_check = (src_port == 3) || 
                                           (!port_req_out[3].valid && src_port == 0) || 
                                           (!port_req_out[3].valid && !port_req_out[0].valid && src_port == 1) ||
                                           (!port_req_out[3].valid && !port_req_out[0].valid && !port_req_out[1].valid && src_port == 2);
                    endcase
                end
                
                if (grant_check) begin
                    port_req_ready[src_port] = port_req_in_ready[dst_port];
                    break;
                end
            end
        end
    end
    
    //=============================================================================
    // 响应路由和仲裁逻辑
    //=============================================================================
    
    generate
        for (i = 0; i < NUM_PORTS; i++) begin : gen_resp_routing
            
            // 响应仲裁器
            logic [NUM_PORTS-1:0] resp_grant;
            logic [NUM_PORTS-1:0] resp_request;
            noc_header_t resp_headers [NUM_PORTS];
            int target_ports [NUM_PORTS];
            
            // 解析每个源端口的响应header并确定目标端口
            for (genvar j = 0; j < NUM_PORTS; j++) begin : gen_resp_parse
                assign resp_headers[j] = noc_header_t'(port_resp_out[j].header);
                assign target_ports[j] = get_source_port(noc_node_id_t'(resp_headers[j].dest_node));
                assign resp_request[j] = port_resp_out[j].valid && (target_ports[j] == i);
            end
            
            // 轮询仲裁器
            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    resp_arb_state[i] <= 2'b00;
                end else begin
                    // 简单的轮询仲裁
                    case (resp_arb_state[i])
                        2'b00: if (resp_request != 4'b0000) resp_arb_state[i] <= 2'b01;
                        2'b01: if (resp_request != 4'b0000) resp_arb_state[i] <= 2'b10;
                        2'b10: if (resp_request != 4'b0000) resp_arb_state[i] <= 2'b11;
                        2'b11: if (resp_request != 4'b0000) resp_arb_state[i] <= 2'b00;
                    endcase
                end
            end
            
            // 仲裁逻辑
            always_comb begin
                resp_grant = 4'b0000;
                case (resp_arb_state[i])
                    2'b00: begin
                        if (resp_request[0]) resp_grant[0] = 1'b1;
                        else if (resp_request[1]) resp_grant[1] = 1'b1;
                        else if (resp_request[2]) resp_grant[2] = 1'b1;
                        else if (resp_request[3]) resp_grant[3] = 1'b1;
                    end
                    2'b01: begin
                        if (resp_request[1]) resp_grant[1] = 1'b1;
                        else if (resp_request[2]) resp_grant[2] = 1'b1;
                        else if (resp_request[3]) resp_grant[3] = 1'b1;
                        else if (resp_request[0]) resp_grant[0] = 1'b1;
                    end
                    2'b10: begin
                        if (resp_request[2]) resp_grant[2] = 1'b1;
                        else if (resp_request[3]) resp_grant[3] = 1'b1;
                        else if (resp_request[0]) resp_grant[0] = 1'b1;
                        else if (resp_request[1]) resp_grant[1] = 1'b1;
                    end
                    2'b11: begin
                        if (resp_request[3]) resp_grant[3] = 1'b1;
                        else if (resp_request[0]) resp_grant[0] = 1'b1;
                        else if (resp_request[1]) resp_grant[1] = 1'b1;
                        else if (resp_request[2]) resp_grant[2] = 1'b1;
                    end
                endcase
            end
            
            // 多路选择器 - 选择获得仲裁权的响应
            always_comb begin
                port_resp_in[i] = '0;
                for (int j = 0; j < NUM_PORTS; j++) begin
                    if (resp_grant[j]) begin
                        port_resp_in[i] = port_resp_out[j];
                        break;
                    end
                end
            end
            
        end
    endgenerate
    
    // 响应Ready信号连接
    always_comb begin
        for (int src_port = 0; src_port < NUM_PORTS; src_port++) begin
            port_resp_ready[src_port] = 1'b0;
            
            // 检查每个目标端口
            for (int dst_port = 0; dst_port < NUM_PORTS; dst_port++) begin
                noc_header_t resp_header_check;
                int resp_target_port_check;
                logic resp_match_check;
                logic resp_grant_check;
                
                resp_header_check = noc_header_t'(port_resp_out[src_port].header);
                resp_target_port_check = get_source_port(noc_node_id_t'(resp_header_check.dest_node));
                resp_match_check = port_resp_out[src_port].valid && (resp_target_port_check == dst_port);
                
                // 确定是否获得仲裁权
                resp_grant_check = 1'b0;
                if (resp_match_check) begin
                    case (resp_arb_state[dst_port])
                        2'b00: resp_grant_check = (src_port == 0) || 
                                                (!port_resp_out[0].valid && src_port == 1) || 
                                                (!port_resp_out[0].valid && !port_resp_out[1].valid && src_port == 2) ||
                                                (!port_resp_out[0].valid && !port_resp_out[1].valid && !port_resp_out[2].valid && src_port == 3);
                        2'b01: resp_grant_check = (src_port == 1) || 
                                                (!port_resp_out[1].valid && src_port == 2) || 
                                                (!port_resp_out[1].valid && !port_resp_out[2].valid && src_port == 3) ||
                                                (!port_resp_out[1].valid && !port_resp_out[2].valid && !port_resp_out[3].valid && src_port == 0);
                        2'b10: resp_grant_check = (src_port == 2) || 
                                                (!port_resp_out[2].valid && src_port == 3) || 
                                                (!port_resp_out[2].valid && !port_resp_out[3].valid && src_port == 0) ||
                                                (!port_resp_out[2].valid && !port_resp_out[3].valid && !port_resp_out[0].valid && src_port == 1);
                        2'b11: resp_grant_check = (src_port == 3) || 
                                                (!port_resp_out[3].valid && src_port == 0) || 
                                                (!port_resp_out[3].valid && !port_resp_out[0].valid && src_port == 1) ||
                                                (!port_resp_out[3].valid && !port_resp_out[0].valid && !port_resp_out[1].valid && src_port == 2);
                    endcase
                end
                
                if (resp_grant_check) begin
                    port_resp_ready[src_port] = port_resp_in_ready[dst_port];
                    break;
                end
            end
        end
    end

endmodule : rvgpu_internal_noc

`endif // RVGPU_INTERNAL_NOC_2SC_SV