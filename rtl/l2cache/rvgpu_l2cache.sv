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

`ifndef RVGPU_L2CACHE_SV
`define RVGPU_L2CACHE_SV

`include "rvgpu_l2cache_pkg.svh"
`include "rvgpu_debug.svh"
`include "rvgpu_l2cache_if.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_interface_axi.svh"

`ifndef RVGPU_L2CACHE_PKG_IMPORTED
`define RVGPU_L2CACHE_PKG_IMPORTED
import rvgpu_l2cache_pkg::*;
`endif // RVGPU_L2CACHE_PKG_IMPORTED

`ifndef RVGPU_INTERNAL_NOC_PKG_IMPORTED
`define RVGPU_INTERNAL_NOC_PKG_IMPORTED
import rvgpu_internal_noc_pkg::*;
`endif // RVGPU_INTERNAL_NOC_PKG_IMPORTED

//=============================================================================
// RVGPU L2 Cache Top Module
// 
// 主要功能：
// 1. 缓存控制器管理
// 2. Tag和数据数组访问
// 3. AXI内存接口适配
// 4. NOC通信接口
// 5. 缓存一致性和替换策略
//=============================================================================

module rvgpu_l2cache #(
    parameter l2cache_config_t L2CACHE_CONFIG = DEFAULT_L2CACHE_CONFIG
) (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // NOC Interface - GPU内部通信
    rvgpu_internal_noc_if.device noc_if,
    
    // Memory Interface - 外部内存访问
    memory_if.master mem_if
);

    //=============================================================================
    // Internal Interface Instances
    //=============================================================================
    
    // 控制器与子模块的接口
    l2cache_tag_if #(.L2CACHE_CONFIG(L2CACHE_CONFIG)) controller_tag();
    l2cache_data_if #(.L2CACHE_CONFIG(L2CACHE_CONFIG)) controller_data();
    l2cache_axi_if #(.L2CACHE_CONFIG(L2CACHE_CONFIG)) controller_axi();
    l2cache_noc_if #(.L2CACHE_CONFIG(L2CACHE_CONFIG)) controller_noc();
    l2cache_debug_if #(.L2CACHE_CONFIG(L2CACHE_CONFIG)) controller_debug();

    //=============================================================================
    // L2 Cache Controller Instance
    //=============================================================================
    
    rvgpu_l2cache_controller #(
        .L2CACHE_CONFIG(L2CACHE_CONFIG)
    ) u_l2cache_controller (
        .clk(clk),
        .rst_n(rst_n),
        
        // NOC Interface
        .noc_if(controller_noc.controller),
        
        // Tag Array Interface
        .tag_if(controller_tag.controller),
        
        // Data Array Interface
        .data_if(controller_data.controller),
        
        // AXI Interface
        .axi_if(controller_axi.controller),
        
        // Debug Interface
        .debug_if(controller_debug.controller)
    );

    //=============================================================================
    // L2 Cache Tag Array Instance
    //=============================================================================
    
    rvgpu_l2cache_tag_array #(
        .L2CACHE_CONFIG(L2CACHE_CONFIG)
    ) u_l2cache_tag_array (
        .clk(clk),
        .rst_n(rst_n),
        
        // Controller Interface
        .tag_if(controller_tag.tag_array)
    );

    //=============================================================================
    // L2 Cache Data Array Instance
    //=============================================================================
    
    rvgpu_l2cache_data_array #(
        .L2CACHE_CONFIG(L2CACHE_CONFIG)
    ) u_l2cache_data_array (
        .clk(clk),
        .rst_n(rst_n),
        
        // Controller Interface
        .data_if(controller_data.data_array)
    );

    //=============================================================================
    // L2 Cache AXI Adapter Instance
    //=============================================================================
    
    rvgpu_l2cache_axi_adapter #(
        .L2CACHE_CONFIG(L2CACHE_CONFIG)
    ) u_l2cache_axi_adapter (
        .clk(clk),
        .rst_n(rst_n),
        
        // Controller Interface
        .axi_if(controller_axi.axi_adapter),
        
        // Memory Interface
        .mem_if(mem_if)
    );

    //=============================================================================
    // L2 Cache NOC Adapter Instance
    //=============================================================================
    
    rvgpu_l2cache_noc_adapter #(
        .L2CACHE_CONFIG(L2CACHE_CONFIG)
    ) u_l2cache_noc_adapter (
        .clk(clk),
        .rst_n(rst_n),
        
        // Controller Interface
        .noc_if(controller_noc.noc_adapter),
        
        // NOC Interface
        .noc_external_if(noc_if)
    );

    //=============================================================================
    // Debug Interface (Optional)
    //=============================================================================
    
    generate
    if (L2CACHE_CONFIG.debug_enable) begin : gen_debug
        // TODO: rvgpu_l2cache_debug_interface 未实现，后续补全
        /*
        rvgpu_l2cache_debug_interface #(.L2CACHE_CONFIG(L2CACHE_CONFIG)) u_l2cache_debug_interface (
            .clk(clk),
            .rst_n(rst_n),
            .debug_if(controller_debug.debug_interface)
        );
        */
    end
    endgenerate

    //=============================================================================
    // Performance Monitoring (Optional)
    //=============================================================================
    
    generate
    if (L2CACHE_CONFIG.debug_enable) begin : gen_perf_monitor
        // TODO: rvgpu_l2cache_perf_monitor 未实现，后续补全
        /*
        rvgpu_l2cache_perf_monitor #(.L2CACHE_CONFIG(L2CACHE_CONFIG)) u_l2cache_perf_monitor (
            .clk(clk),
            .rst_n(rst_n),
            .debug_if(controller_debug.debug_interface)
        );
        */
    end
    endgenerate

    //=============================================================================
    // 调试输出 (仅在仿真时)
    //=============================================================================
    
    generate
    if (L2CACHE_CONFIG.debug_enable) begin : gen_debug_output
        // 状态监控寄存器
        l2cache_state_t prev_state;
        l2cache_perf_counters_t prev_perf_counters;
        
        always_ff @(posedge clk) begin
            if (!rst_n) begin
                prev_state <= L2_STATE_IDLE;
                prev_perf_counters <= '0;
            end else begin
                // 监控缓存状态变化
                if (controller_debug.current_state != prev_state) begin
                    `DEBUG_PRINT("L2CACHE", $sformatf("State transition: %s -> %s", get_state_name(prev_state), get_state_name(controller_debug.current_state)));
                    prev_state <= controller_debug.current_state;
                end
                
                // 监控性能计数器变化
                if (controller_debug.perf_counters.hit_count != prev_perf_counters.hit_count ||
                    controller_debug.perf_counters.miss_count != prev_perf_counters.miss_count) begin
                    `DEBUG_PRINT("L2CACHE", $sformatf("Performance - Hits: %0d, Misses: %0d, Hit Rate: %.2f%%", controller_debug.perf_counters.hit_count, controller_debug.perf_counters.miss_count, 
                        (controller_debug.perf_counters.hit_count + controller_debug.perf_counters.miss_count > 0) ? 
                        (real'(controller_debug.perf_counters.hit_count) * 100.0 / real'(controller_debug.perf_counters.hit_count + controller_debug.perf_counters.miss_count)) : 0.0));
                    prev_perf_counters <= controller_debug.perf_counters;
                end
                
                // 监控缓存忙状态
                if (controller_debug.cache_busy) begin
                    // `DEBUG_PRINT("L2CACHE", $sformatf("Cache busy: addr=0x%h, trans_id=%0d", controller_debug.current_addr, controller_debug.current_trans_id));
                end
                
                // 监控读写操作统计
                if (controller_debug.perf_counters.read_count != prev_perf_counters.read_count) begin
                    `DEBUG_PRINT("L2CACHE", $sformatf("Read operations: %0d", controller_debug.perf_counters.read_count));
                end
                
                if (controller_debug.perf_counters.write_count != prev_perf_counters.write_count) begin
                    `DEBUG_PRINT("L2CACHE", $sformatf("Write operations: %0d", controller_debug.perf_counters.write_count));
                end
                
                // 监控错误计数
                if (controller_debug.perf_counters.error_count != prev_perf_counters.error_count) begin
                    `DEBUG_PRINT("L2CACHE", $sformatf("Error count: %0d", controller_debug.perf_counters.error_count));
                end
            end
        end
        
        // 状态名称函数
        function automatic string get_state_name(input l2cache_state_t state);
            case (state)
                L2_STATE_IDLE: return "IDLE";
                L2_STATE_TAG_LOOKUP: return "TAG_LOOKUP";
                L2_STATE_DATA_ACCESS: return "DATA_ACCESS";
                L2_STATE_MISS_HANDLE: return "MISS_HANDLE";
                L2_STATE_MEMORY_ACCESS: return "MEMORY_ACCESS";
                L2_STATE_WRITE_BACK: return "WRITE_BACK";
                L2_STATE_EVICT: return "EVICT";
                L2_STATE_SYNC: return "SYNC";
                L2_STATE_ERROR: return "ERROR";
                default: return "UNKNOWN";
            endcase
        endfunction
        
    end
    endgenerate

endmodule : rvgpu_l2cache

`endif // RVGPU_L2CACHE_SV 