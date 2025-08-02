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

`ifndef RVGPU_TYPES_CACHE_RESP_SVH
`define RVGPU_TYPES_CACHE_RESP_SVH

//=============================================================================
// 缓存响应状态类型定义
//=============================================================================

typedef enum logic [1:0] {
    CACHE_RESP_OKAY   = 2'b00,  // 正常完成
    CACHE_RESP_SLVERR = 2'b10,  // 从设备错误
    CACHE_RESP_DECERR = 2'b11   // 解码错误
} cache_resp_status_t;

//=============================================================================
// 调试和监控函数
//=============================================================================

// 获取响应状态名称
function automatic string get_resp_name(
    input cache_resp_status_t status
);
    case (status)
        CACHE_RESP_OKAY: return "OKAY";
        CACHE_RESP_SLVERR: return "SLVERR";
        CACHE_RESP_DECERR: return "DECERR";
        default: return "UNKNOWN";
    endcase
endfunction

`endif // RVGPU_TYPES_CACHE_RESP_SVH 