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

`ifndef INTERFACE_SM_L1_TAG_ARRAY_SVH
`define INTERFACE_SM_L1_TAG_ARRAY_SVH

`include "rvgpu_typedef.svh"
`include "rvgpu_config.svh"

// L1 Cache Tag Array接口
interface interface_sm_l1_tag_array;
    // 请求
    logic tag_req_valid;
    logic [63:0] tag_req_addr;
    logic tag_req_ready;
    
    // 响应
    logic tag_resp_valid;
    logic tag_resp_hit;
    logic [19:0] tag_resp_tag;
    logic [7:0] tag_resp_index;
    
    // 控制器端口
    modport controller (
        output tag_req_valid, tag_req_addr,
        input  tag_req_ready,
        input  tag_resp_valid, tag_resp_hit, tag_resp_tag, tag_resp_index
    );
    
    // Tag Array端口
    modport tag_array (
        input  tag_req_valid, tag_req_addr,
        output tag_req_ready,
        output tag_resp_valid, tag_resp_hit, tag_resp_tag, tag_resp_index
    );
endinterface

`endif // INTERFACE_SM_L1_TAG_ARRAY_SVH
