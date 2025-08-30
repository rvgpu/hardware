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

`ifndef TYPES_SM_TEXTURE_SVH
`define TYPES_SM_TEXTURE_SVH

`include "rvgpu_typedef.svh"

// 纹理格式定义
typedef enum logic [3:0] {
    e_TEX_FORMAT_RGBA8,     // 8位RGBA格式
    e_TEX_FORMAT_RGBA16F,   // 16位浮点RGBA格式
    e_TEX_FORMAT_RGBA32F,   // 32位浮点RGBA格式
    e_TEX_FORMAT_R8,        // 8位R格式
    e_TEX_FORMAT_R16F,      // 16位浮点R格式
    e_TEX_FORMAT_R32F,      // 32位浮点R格式
    e_TEX_FORMAT_BC1,       // BC1压缩格式
    e_TEX_FORMAT_BC2,       // BC2压缩格式
    e_TEX_FORMAT_BC3,       // BC3压缩格式
    e_TEX_FORMAT_BC4,       // BC4压缩格式
    e_TEX_FORMAT_BC5,       // BC5压缩格式
    e_TEX_FORMAT_BC6H,      // BC6H压缩格式
    e_TEX_FORMAT_BC7        // BC7压缩格式
} e_texture_format_t;

// 纹理寻址模式
typedef enum logic [1:0] {
    e_TEX_ADDR_WRAP,        // 环绕模式
    e_TEX_ADDR_MIRROR,      // 镜像模式
    e_TEX_ADDR_CLAMP,       // 夹取模式
    e_TEX_ADDR_BORDER       // 边界模式
} e_texture_address_mode_t;

// 纹理缓存行
typedef struct packed {
    logic valid;                // 有效位
    logic [31:0] tag;          // 标签
    logic [31:0] texture_id;   // 纹理ID
    logic [31:0] u;            // U坐标
    logic [31:0] v;            // V坐标
    logic [31:0] data_r;       // R分量
    logic [31:0] data_g;       // G分量
    logic [31:0] data_b;       // B分量
    logic [31:0] data_a;       // A分量
} t_texture_cache_line;

// 类型相关函数

// 获取纹理格式的字节数
function automatic int tf_texture_format_bytes(e_texture_format_t format);
    case (format)
        e_TEX_FORMAT_RGBA8:    return 4;
        e_TEX_FORMAT_RGBA16F:  return 8;
        e_TEX_FORMAT_RGBA32F:  return 16;
        e_TEX_FORMAT_R8:       return 1;
        e_TEX_FORMAT_R16F:     return 2;
        e_TEX_FORMAT_R32F:     return 4;
        e_TEX_FORMAT_BC1:      return 8;  // 每16个像素8字节
        e_TEX_FORMAT_BC2:      return 16; // 每16个像素16字节
        e_TEX_FORMAT_BC3:      return 16; // 每16个像素16字节
        e_TEX_FORMAT_BC4:      return 8;  // 每16个像素8字节
        e_TEX_FORMAT_BC5:      return 16; // 每16个像素16字节
        e_TEX_FORMAT_BC6H:     return 16; // 每16个像素16字节
        e_TEX_FORMAT_BC7:      return 16; // 每16个像素16字节
        default:               return 4;
    endcase
endfunction

// 检查纹理格式是否为压缩格式
function automatic logic tf_is_compressed_format(e_texture_format_t format);
    return (format >= e_TEX_FORMAT_BC1 && format <= e_TEX_FORMAT_BC7);
endfunction

`endif // TYPES_SM_TEXTURE_SVH
