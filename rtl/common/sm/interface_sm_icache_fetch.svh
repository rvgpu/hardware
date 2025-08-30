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

`ifndef INTERFACE_SM_ICACHE_FETCH_SVH
`define INTERFACE_SM_ICACHE_FETCH_SVH

`include "rvgpu_typedef.svh"
`include "rvgpu_config.svh"

// 指令缓存接口
// 用于Block Scheduler从指令缓存获取指令
interface interface_sm_icache_fetch;
    // 时钟和复位
    logic clk;
    logic rst_n;
    
    // 指令获取
    function logic [31:0] fetch(logic [63:0] pc);
        // 这是一个任务，实际实现在模块中
        return 32'h00000013; // 默认返回NOP指令
    endfunction
    
    // 预取请求
    logic prefetch_valid;
    logic [63:0] prefetch_addr;
    logic prefetch_ready;
    
    // 缓存控制
    logic flush_valid;
    logic flush_ready;
    
    // 缓存状态
    logic cache_ready;
    logic cache_miss;
    
    // 调度器端口
    modport scheduler (
        import fetch,
        output prefetch_valid, prefetch_addr, flush_valid,
        input  prefetch_ready, flush_ready, cache_ready, cache_miss
    );
    
    // 缓存端口
    modport cache (
        input  prefetch_valid, prefetch_addr, flush_valid,
        output prefetch_ready, flush_ready, cache_ready, cache_miss
    );
endinterface

`endif // INTERFACE_SM_ICACHE_FETCH_SVH