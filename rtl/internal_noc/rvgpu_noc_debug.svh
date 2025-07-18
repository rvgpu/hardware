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

`ifndef RVGPU_NOC_DEBUG_SVH
`define RVGPU_NOC_DEBUG_SVH

function automatic string noc_msg_type_to_string(
    input noc_msg_type_t msg_type
);
    string msg_type_str;
    case (msg_type)
        MSG_MEM_READ_REQ: msg_type_str = "MSG_MEM_READ_REQ";
        MSG_MEM_READ_RESP: msg_type_str = "MSG_MEM_READ_RESP";
        MSG_MEM_WRITE_REQ: msg_type_str = "MSG_MEM_WRITE_REQ";
        MSG_MEM_WRITE_RESP: msg_type_str = "MSG_MEM_WRITE_RESP";
        MSG_COMPUTE_REQ: msg_type_str = "MSG_COMPUTE_REQ";
        MSG_COMPUTE_RESP: msg_type_str = "MSG_COMPUTE_RESP";
        default: msg_type_str = "UNKNOWN";
    endcase
    return msg_type_str;
endfunction

function automatic string noc_node_id_to_string(
    input noc_node_id_t node_id
);
    string node_id_str;
    case (node_id)
        NODE_CONTROL: node_id_str = "NODE_CONTROL";
        NODE_L2_CACHE: node_id_str = "NODE_L2_CACHE";
        NODE_SHADER_0: node_id_str = "NODE_SHADER_0";
        NODE_SHADER_1: node_id_str = "NODE_SHADER_1";
        NODE_SHADER_2: node_id_str = "NODE_SHADER_2";
        NODE_SHADER_3: node_id_str = "NODE_SHADER_3";
        NODE_SHADER_4: node_id_str = "NODE_SHADER_4";
        NODE_SHADER_5: node_id_str = "NODE_SHADER_5";
        NODE_SHADER_6: node_id_str = "NODE_SHADER_6";
        NODE_SHADER_7: node_id_str = "NODE_SHADER_7";
        NODE_DEBUG: node_id_str = "NODE_DEBUG";
        default: node_id_str = "UNKNOWN";
    endcase
    return node_id_str;
endfunction

function automatic string noc_header_to_string(
    input noc_header_t header
);
    // 直接在$sformatf中调用子函数，避免使用string中间变量
    return $sformatf("header: {type: %s, %s -> %s, id: %d, localaddr: %d}", 
                     noc_msg_type_to_string(header.msg_type),
                     noc_node_id_to_string(header.src_node),
                     noc_node_id_to_string(header.dest_node),
                     header.trans_id, header.local_addr);
endfunction

function automatic string noc_payload_request_mem_read_to_string(
    input noc_payload_t payload
);
    return $sformatf("payload: {addr: %h, size: %d}", payload.req_mem_read.addr, payload.req_mem_read.size);
endfunction

function automatic string noc_payload_response_mem_read_to_string(
    input noc_payload_t payload
);
    return $sformatf("payload: {data: %h}", payload.resp_mem_read.data);
endfunction

function automatic string noc_request_mem_read_to_string(
    input noc_header_t header,
    input noc_payload_t payload
);
    return $sformatf("%s, %s", 
                     noc_header_to_string(header), 
                     noc_payload_request_mem_read_to_string(payload));
endfunction

function automatic string noc_response_mem_read_to_string(
    input noc_header_t header,
    input noc_payload_t payload
);
    return $sformatf("%s, %s", 
                     noc_header_to_string(header), 
                     noc_payload_response_mem_read_to_string(payload));
endfunction

`endif // RVGPU_NOC_DEBUG_SVH
