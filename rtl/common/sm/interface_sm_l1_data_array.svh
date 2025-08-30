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

`ifndef INTERFACE_SM_L1_DATA_ARRAY_SVH
`define INTERFACE_SM_L1_DATA_ARRAY_SVH

`include "rvgpu_typedef.svh"
`include "rvgpu_config.svh"

// L1 Cache Data Array接口
interface interface_sm_l1_data_array;
    // 请求
    logic data_req_valid;
    logic [63:0] data_req_addr;
    logic [31:0] data_req_data;
    logic [2:0] data_req_size;
    logic data_req_is_load;
    logic data_req_ready;
    
    // 响应
    logic data_resp_valid;
    logic [31:0] data_resp_data;
    
    // 控制器端口
    modport controller (
        output data_req_valid, data_req_addr, data_req_data, data_req_size, data_req_is_load,
        input  data_req_ready,
        input  data_resp_valid, data_resp_data
    );
    
    // Data Array端口
    modport data_array (
        input  data_req_valid, data_req_addr, data_req_data, data_req_size, data_req_is_load,
        output data_req_ready,
        output data_resp_valid, data_resp_data
    );
endinterface

`endif // INTERFACE_SM_L1_DATA_ARRAY_SVH
