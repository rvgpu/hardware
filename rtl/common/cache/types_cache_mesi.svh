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

`ifndef RVGPU_TYPES_CACHE_MESI_SVH
`define RVGPU_TYPES_CACHE_MESI_SVH

//=============================================================================
// MESI状态类型定义
//=============================================================================

typedef enum logic [1:0] {
    CACHE_MESI_INVALID   = 2'b00,  //无效状态
    CACHE_MESI_EXCLUSIVE = 2'b01,  //独占状态
    CACHE_MESI_SHARED    = 2'b10,  //共享状态
    CACHE_MESI_MODIFIED  = 2'b11   //修改状态
} cache_mesi_state_t;

//=============================================================================
// MESI状态管理函数
//=============================================================================

// 检查是否为有效状态
function automatic logic is_valid_state(
    input cache_mesi_state_t state
);
    return (state != CACHE_MESI_INVALID);
endfunction

// 检查是否为独占状态
function automatic logic is_exclusive_state(
    input cache_mesi_state_t state
);
    return (state == CACHE_MESI_EXCLUSIVE || state == CACHE_MESI_MODIFIED);
endfunction

// 检查是否为修改状态
function automatic logic is_modified_state(
    input cache_mesi_state_t state
);
    return (state == CACHE_MESI_MODIFIED);
endfunction

// 检查是否为共享状态
function automatic logic is_shared_state(
    input cache_mesi_state_t state
);
    return (state == CACHE_MESI_SHARED);
endfunction

// 状态转换函数
function automatic cache_mesi_state_t next_mesi_state(
    input cache_mesi_state_t current_state,
    input logic is_read,
    input logic is_write,
    input logic is_remote_access
);
    case (current_state)
        CACHE_MESI_INVALID: begin
            if (is_read && !is_remote_access)
                return CACHE_MESI_EXCLUSIVE;
            else if (is_read && is_remote_access)
                return CACHE_MESI_SHARED;
            else if (is_write)
                return CACHE_MESI_MODIFIED;
            else
                return CACHE_MESI_INVALID;
        end
        CACHE_MESI_EXCLUSIVE: begin
            if (is_write)
                return CACHE_MESI_MODIFIED;
            else if (is_remote_access)
                return CACHE_MESI_SHARED;
            else
                return CACHE_MESI_EXCLUSIVE;
        end
        CACHE_MESI_SHARED: begin
            if (is_write)
                return CACHE_MESI_MODIFIED;
            else
                return CACHE_MESI_SHARED;
        end
        CACHE_MESI_MODIFIED: begin
            if (is_remote_access)
                return CACHE_MESI_SHARED;
            else
                return CACHE_MESI_MODIFIED;
        end
        default: return CACHE_MESI_INVALID;
    endcase
endfunction

//=============================================================================
// 调试和监控函数
//=============================================================================

// 获取MESI状态名称
function automatic string get_mesi_name(
    input cache_mesi_state_t state
);
    case (state)
        CACHE_MESI_INVALID: return "INVALID";
        CACHE_MESI_SHARED: return "SHARED";
        CACHE_MESI_EXCLUSIVE: return "EXCLUSIVE";
        CACHE_MESI_MODIFIED: return "MODIFIED";
        default: return "UNKNOWN";
    endcase
endfunction

`endif // RVGPU_TYPES_CACHE_MESI_SVH 