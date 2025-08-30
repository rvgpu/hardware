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

`ifndef TYPES_SM_WARP_SVH
`define TYPES_SM_WARP_SVH

`include "rvgpu_typedef.svh"
`include "rvgpu_config.svh"

// Warp状态定义
typedef enum logic [2:0] {
    e_WARP_IDLE,       // 空闲
    e_WARP_READY,      // 就绪，等待调度
    e_WARP_RUNNING,    // 正在运行
    e_WARP_STALLED,    // 暂停 (等待内存或同步)
    e_WARP_FINISHED    // 已完成
} e_warp_state_t;

// Warp控制块
typedef struct packed {
    logic [$clog2(`CONFIG_SM_WARP_COUNT)-1:0] warp_id;     // Warp ID
    logic [31:0] block_id;                                 // 所属Block ID
    logic [31:0] thread_count;                             // 线程数量
    logic [`CONFIG_WARP_THREAD_NUMBER-1:0] active_mask;    // 活跃线程掩码
    logic [63:0] pc;                                       // 程序计数器
    e_warp_state_t state;                                  // Warp状态
    logic [$clog2(`CONFIG_SM_CUDA_CORE_COUNT)-1:0] core_id; // 分配的CUDA Core ID
} t_warp_control_block;

// 纹理过滤模式
typedef enum logic [2:0] {
    e_FILTER_NEAREST,       // 最近邻过滤
    e_FILTER_LINEAR,        // 线性过滤
    e_FILTER_ANISOTROPIC,   // 各向异性过滤
    e_FILTER_MIPMAP_NEAREST, // 最近邻MIP映射
    e_FILTER_MIPMAP_LINEAR   // 线性MIP映射
} e_filter_mode_t;

// 纹理描述符
typedef struct packed {
    logic [63:0] base_addr;      // 纹理基址
    logic [31:0] width;          // 纹理宽度
    logic [31:0] height;         // 纹理高度
    logic [31:0] depth;          // 纹理深度 (3D纹理)
    logic [3:0]  format;         // 纹理格式
    logic [2:0]  filter_mode;    // 默认过滤模式
    logic        is_valid;       // 纹理是否有效
} t_texture_descriptor;

// 类型相关函数

// 检查Warp是否可用
function automatic logic tf_is_warp_available(e_warp_state_t state);
    return (state == e_WARP_IDLE);
endfunction

// 检查Warp是否已完成
function automatic logic tf_is_warp_finished(e_warp_state_t state);
    return (state == e_WARP_FINISHED);
endfunction

// 检查Warp是否可调度
function automatic logic tf_is_warp_schedulable(e_warp_state_t state);
    return (state == e_WARP_READY);
endfunction

`endif // TYPES_SM_WARP_SVH
