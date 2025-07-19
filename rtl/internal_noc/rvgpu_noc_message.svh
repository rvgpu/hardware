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

`ifndef RVGPU_NOC_MESSAGE_SVH
`define RVGPU_NOC_MESSAGE_SVH

`include "rvgpu_typedef.svh"
`include "rvgpu_constant.svh"

`ifndef RVGPU_INTERNAL_NOC_PKG_SVH
`error "Do not include rvgpu_noc_message.svh directly! Please include rvgpu_internal_noc_pkg.svh instead."
`endif
    
// 消息类型定义
typedef enum l8_t {
    MSG_MEM_READ_REQ        = 8'h20,    // 内存读请求
    MSG_MEM_READ_RESP       = 8'h21,    // 内存读响应  
    MSG_MEM_WRITE_REQ       = 8'h22,    // 内存写请求
    MSG_MEM_WRITE_RESP      = 8'h23,    // 内存写响应
    MSG_COMPUTE_REQ         = 8'h10,    // 计算请求
    MSG_COMPUTE_RESP        = 8'h11,    // 计算响应
    MSG_SYNC_REQ            = 8'h30,    // 同步请求
    MSG_SYNC_RESP           = 8'h31,    // 同步响应
    MSG_STATUS              = 8'h50,    // 状态报告
    MSG_ERROR               = 8'h51     // 错误报告
} noc_msg_type_t;
    
// 节点ID定义 - GPU内部节点
typedef enum l4_t {
    NODE_CONTROL            = 4'h0,     // 控制单元
    NODE_L2_CACHE           = 4'h1,     // L2 Cache
    NODE_SHADER_0           = 4'h2,     // Shader Core 0
    NODE_SHADER_1           = 4'h3,     // Shader Core 1
    NODE_SHADER_2           = 4'h4,     // Shader Core 2
    NODE_SHADER_3           = 4'h5,     // Shader Core 3
    NODE_SHADER_4           = 4'h6,     // Shader Core 4
    NODE_SHADER_5           = 4'h7,     // Shader Core 5
    NODE_SHADER_6           = 4'h8,     // Shader Core 6
    NODE_SHADER_7           = 4'h9,     // Shader Core 7
    NODE_DEBUG              = 4'hF      // 调试接口
} noc_node_id_t;

typedef l8_t noc_trans_id_t;
typedef l8_t noc_local_addr_t;
localparam noc_local_addr_t NOC_NODE_CONTROL_MMU = 8'h00;
localparam noc_local_addr_t NOC_NODE_CONTROL_JD  = 8'h01;

typedef struct packed {
    noc_msg_type_t          msg_type;   // [31:24] 消息类型
    noc_trans_id_t          trans_id;   // [23:16] 事务ID
    noc_node_id_t           src_node;   // [15:12] 源节点ID
    noc_node_id_t           dest_node;  // [11:8]  目标节点ID
    noc_local_addr_t        local_addr; // [7:0]   节点内本地地址
} noc_header_t;

// 响应状态码
typedef enum l2_t {
    RESP_OKAY               = 2'b00,    // 正常完成
    RESP_EXOKAY             = 2'b01,    // 独占访问正常
    RESP_SLVERR             = 2'b10,    // 从设备错误
    RESP_DECERR             = 2'b11     // 解码错误
} noc_resp_t;
    
function automatic noc_local_addr_t get_noc_header_local_addr(
    input noc_header_t header
);
    return header.local_addr;
endfunction

// 构建NOC header
function automatic noc_header_t build_noc_header(
    input noc_msg_type_t    msg_type,
    input noc_trans_id_t    trans_id,
    input noc_node_id_t     src_node,
    input noc_node_id_t     dest_node,
    input noc_local_addr_t  local_addr = 8'h00
);
    noc_header_t header;
    header.msg_type         = msg_type;
    header.trans_id         = trans_id;
    header.src_node         = src_node;
    header.dest_node        = dest_node;
    header.local_addr       = local_addr;
    return header;
endfunction

function automatic noc_header_t build_noc_header_mem_request(
    input noc_trans_id_t    trans_id,
    input noc_node_id_t     src_node,
    input noc_local_addr_t  local_addr = 8'h00
);
    return build_noc_header(MSG_MEM_READ_REQ, trans_id, src_node, NODE_L2_CACHE, local_addr);
endfunction
    
// 解析NOC header
function automatic void parse_noc_header(
    input noc_header_t header,
    output noc_msg_type_t msg_type,
    output noc_trans_id_t trans_id,
    output noc_node_id_t src_node,
    output noc_node_id_t dest_node,
    output logic [7:0] local_addr
);
    msg_type = noc_msg_type_t'(header.msg_type);
    trans_id = header.trans_id;
    src_node = noc_node_id_t'(header.src_node);
    dest_node = noc_node_id_t'(header.dest_node);
    local_addr = header.local_addr;
endfunction

// noc size与axi awsize/arsize 相同
localparam l8_t NOC_SIZE_1B = 8'h00;        // 0: 1字节传输
localparam l8_t NOC_SIZE_2B = 8'h01;        // 1: 2字节传输
localparam l8_t NOC_SIZE_4B = 8'h02;        // 2: 4字节传输
localparam l8_t NOC_SIZE_8B = 8'h03;        // 3: 8字节传输
localparam l8_t NOC_SIZE_16B = 8'h04;       // 4: 16字节传输
localparam l8_t NOC_SIZE_32B = 8'h05;       // 5: 32字节传输

typedef struct packed {
    logic [63:0]    reserver2;
    logic [63:0]    reserver1;
    logic [63-8:0]  reserved0;
    logic [7:0]     size;
    logic [63:0]    addr;
} noc_req_mem_read_t;

typedef struct packed {
    logic [63:0]    reserver2;
    logic [63:0]    reserver1;
    logic [63:0]    reserved0;
    logic [63:0]    data;
} noc_resp_mem_read_t;

typedef union packed {
    logic [`RVGPU_CONST_CU_MAX_PAYLOAD_SIZE-1:0] payload_256b; // 256bit   
    noc_req_mem_read_t req_mem_read;
    noc_resp_mem_read_t resp_mem_read;
} noc_payload_t;

function automatic noc_payload_t build_noc_payload_request_mem_read(
    input logic [63:0] addr,
    input logic [7:0] size
);
    noc_payload_t payload;
    payload.req_mem_read.addr = addr;
    payload.req_mem_read.size = size;
    payload.req_mem_read.reserver2 = '0;
    payload.req_mem_read.reserver1 = '0;
    payload.req_mem_read.reserved0 = '0;
    return payload;
endfunction

function automatic noc_payload_t build_noc_payload_response_mem_read(
    input logic [63:0] data
);
    noc_payload_t payload;
    payload.resp_mem_read.data = data;
    payload.resp_mem_read.reserver2 = '0;
    payload.resp_mem_read.reserver1 = '0;
    payload.resp_mem_read.reserved0 = '0;
    return payload;
endfunction

`endif // RVGPU_NOC_MESSAGE_SVH 