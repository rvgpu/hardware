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

`ifndef RVGPU_CUDACORE_TOP_SV
`define RVGPU_CUDACORE_TOP_SV

`include "rvgpu_typedef.svh"
`include "rvgpu_config.svh"
`include "interface_sm_warp_dispatch.svh"
`include "interface_sm_l1cache.svh"

module rvgpu_cudacore_top #(
    parameter int CORE_ID = 0,          // CUDA Core ID
    parameter int WARP_COUNT = 32,      // 支持的warp数量  
    parameter int THREAD_COUNT = 32     // 每个warp的线程数
) (
    input  logic clk,
    input  logic rst_n,
    
    // Warp分发接口 - 连接到SM Frontend
    interface_sm_warp_dispatch.core_port warp_dispatch_if,
    
    // L1 Cache接口 - 连接到L1 Cache
    interface_sm_l1cache.core l1_cache_if
);

    // 设置准备好接收新的Warp
    assign warp_dispatch_if.ready = 1'b1;  // 始终准备好接收新的Warp
    
    // ============================================================================
    // L1 Cache接口信号处理
    // ============================================================================
    
    // 默认不发送内存请求
    assign l1_cache_if.req_valid = 1'b0;
    assign l1_cache_if.req_warp_id = '0;
    assign l1_cache_if.req_mask = '0;
    assign l1_cache_if.req_addr = '{default: '0};
    assign l1_cache_if.req_data = '{default: '0};
    assign l1_cache_if.req_size = 3'b010;  // 32位
    assign l1_cache_if.req_is_load = 1'b1;
    assign l1_cache_if.req_is_shared = 1'b0;
    
    // 始终准备好接收响应
    assign l1_cache_if.resp_ready = 1'b1;

endmodule : rvgpu_cudacore_top

`endif // RVGPU_CUDACORE_TOP_SV
