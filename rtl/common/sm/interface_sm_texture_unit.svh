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

`ifndef INTERFACE_SM_TEXTURE_UNIT_SVH
`define INTERFACE_SM_TEXTURE_UNIT_SVH

`include "rvgpu_typedef.svh"
`include "rvgpu_config.svh"

// 纹理单元接口
// 用于CUDA Core访问纹理单元
interface interface_sm_texture_unit #(
    parameter int WARP_COUNT = `CONFIG_SM_WARP_COUNT,
    parameter int THREAD_COUNT = `CONFIG_WARP_THREAD_NUMBER
);
    // 时钟和复位
    logic clk;
    logic rst_n;
    
    // 纹理请求
    logic req_valid;
    logic [$clog2(WARP_COUNT)-1:0] req_warp_id;
    logic [THREAD_COUNT-1:0] req_mask;
    logic [THREAD_COUNT-1:0][31:0] req_coords_u;
    logic [THREAD_COUNT-1:0][31:0] req_coords_v;
    logic [31:0] req_texture_id;
    logic [2:0] req_filter_mode;
    logic req_ready;
    
    // 纹理响应
    logic resp_valid;
    logic [$clog2(WARP_COUNT)-1:0] resp_warp_id;
    logic [THREAD_COUNT-1:0] resp_mask;
    logic [THREAD_COUNT-1:0][31:0] resp_color_r;
    logic [THREAD_COUNT-1:0][31:0] resp_color_g;
    logic [THREAD_COUNT-1:0][31:0] resp_color_b;
    logic [THREAD_COUNT-1:0][31:0] resp_color_a;
    logic resp_ready;
    
    // Core端口
    modport core (
        input  clk, rst_n,
        output req_valid, req_warp_id, req_mask, req_coords_u, req_coords_v, req_texture_id, req_filter_mode,
        input  req_ready,
        input  resp_valid, resp_warp_id, resp_mask, resp_color_r, resp_color_g, resp_color_b, resp_color_a,
        output resp_ready
    );
    
    // 纹理单元端口
    modport texture (
        input  clk, rst_n,
        input  req_valid, req_warp_id, req_mask, req_coords_u, req_coords_v, req_texture_id, req_filter_mode,
        output req_ready,
        output resp_valid, resp_warp_id, resp_mask, resp_color_r, resp_color_g, resp_color_b, resp_color_a,
        input  resp_ready
    );
endinterface

`endif // INTERFACE_SM_TEXTURE_UNIT_SVH
