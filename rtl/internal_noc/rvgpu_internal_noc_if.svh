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

`ifndef RVGPU_INTERNAL_NOC_IF_SVH
`define RVGPU_INTERNAL_NOC_IF_SVH

`include "rvgpu_internal_noc_pkg.svh"

`ifndef RVGPU_INTERNAL_NOC_PKG_IMPORTED
`define RVGPU_INTERNAL_NOC_PKG_IMPORTED
import rvgpu_internal_noc_pkg::*;
`endif // RVGPU_INTERNAL_NOC_PKG_IMPORTED

interface rvgpu_internal_noc_if #(
    parameter noc_config_t NOC_CONFIG = DEFAULT_NOC_CONFIG
);
    // Master通道信号 - 设备作为发起者发送请求
    logic                                   m_req_valid;
    logic [NOC_CONFIG.header_width-1:0]     m_req_header;
    logic [NOC_CONFIG.data_width-1:0]       m_req_data;
    logic [NOC_CONFIG.data_width/8-1:0]     m_req_strb;
    logic                                   m_req_last;
    logic                                   m_req_ready;
    
    logic                                   m_resp_valid;
    logic [NOC_CONFIG.header_width-1:0]     m_resp_header;
    logic [NOC_CONFIG.data_width-1:0]       m_resp_data;
    logic [1:0]                             m_resp_status;
    logic                                   m_resp_last;
    logic                                   m_resp_ready;
    
    // Slave通道信号 - 设备作为接收者接收请求
    logic                                   s_req_valid;
    logic [NOC_CONFIG.header_width-1:0]     s_req_header;
    logic [NOC_CONFIG.data_width-1:0]       s_req_data;
    logic [NOC_CONFIG.data_width/8-1:0]     s_req_strb;
    logic                                   s_req_last;
    logic                                   s_req_ready;
    
    logic                                   s_resp_valid;
    logic [NOC_CONFIG.header_width-1:0]     s_resp_header;
    logic [NOC_CONFIG.data_width-1:0]       s_resp_data;
    logic [1:0]                             s_resp_status;
    logic                                   s_resp_last;
    logic                                   s_resp_ready;
    
    // 设备端modport - 设备使用这个接口
    modport device (
        // Master通道 - 设备发送请求和接收响应
        output m_req_valid, m_req_header, m_req_data, m_req_strb, m_req_last,
        input  m_req_ready,
        input  m_resp_valid, m_resp_header, m_resp_data, m_resp_status, m_resp_last,
        output m_resp_ready,
        // Slave通道 - 设备接收请求和发送响应
        input  s_req_valid, s_req_header, s_req_data, s_req_strb, s_req_last,
        output s_req_ready,
        output s_resp_valid, s_resp_header, s_resp_data, s_resp_status, s_resp_last,
        input  s_resp_ready
    );
    
    // NOC端modport - NOC交换机使用这个接口
    modport noc (
        // Master通道 - NOC接收设备的请求并发送响应
        input  m_req_valid, m_req_header, m_req_data, m_req_strb, m_req_last,
        output m_req_ready,
        output m_resp_valid, m_resp_header, m_resp_data, m_resp_status, m_resp_last,
        input  m_resp_ready,
        // Slave通道 - NOC发送请求给设备并接收响应
        output s_req_valid, s_req_header, s_req_data, s_req_strb, s_req_last,
        input  s_req_ready,
        input  s_resp_valid, s_resp_header, s_resp_data, s_resp_status, s_resp_last,
        output s_resp_ready
    );

endinterface : rvgpu_internal_noc_if

`endif // RVGPU_INTERNAL_NOC_IF_SVH
