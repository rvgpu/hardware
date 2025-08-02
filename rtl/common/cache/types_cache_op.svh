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

`ifndef RVGPU_TYPES_CACHE_OP_SVH
`define RVGPU_TYPES_CACHE_OP_SVH

//=============================================================================
// 缓存操作类型定义
//=============================================================================

typedef enum logic [3:0] {
    CACHE_OP_READ       = 4'h0,  // 读操作
    CACHE_OP_WRITE      = 4'h1,  // 写操作
    CACHE_OP_INVALIDATE = 4'h2,  // 无效化操作
    CACHE_OP_FLUSH      = 4'h3,  // 刷新操作
    CACHE_OP_PREFETCH   = 4'h4,  // 预取操作
    CACHE_OP_EVICT      = 4'h5,  // 驱逐操作
    CACHE_OP_SYNC       = 4'h6,  // 同步操作
    CACHE_OP_DEBUG      = 4'h7   // 调试操作
} cache_op_type_t;

//=============================================================================
// 调试和监控函数
//=============================================================================

// 获取操作类型名称
function automatic string get_op_name(
    input cache_op_type_t op
);
    case (op)
        CACHE_OP_READ: return "READ";
        CACHE_OP_WRITE: return "WRITE";
        CACHE_OP_INVALIDATE: return "INVALIDATE";
        CACHE_OP_FLUSH: return "FLUSH";
        CACHE_OP_PREFETCH: return "PREFETCH";
        CACHE_OP_EVICT: return "EVICT";
        CACHE_OP_SYNC: return "SYNC";
        CACHE_OP_DEBUG: return "DEBUG";
        default: return "UNKNOWN";
    endcase
endfunction

`endif // RVGPU_TYPES_CACHE_OP_SVH 