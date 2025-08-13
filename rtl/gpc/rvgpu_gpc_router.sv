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

`ifndef RVGPU_GPC_ROUTER_SV
`define RVGPU_GPC_ROUTER_SV

`include "rvgpu_typedef.svh"
`include "interface_gpc_router.svh"
`include "rvgpu_gpc_pkg.svh"
`include "rvgpu_fifo_if.svh"

`ifndef RVGPU_GPC_PKG_IMPORTED
`define RVGPU_GPC_PKG_IMPORTED
import rvgpu_gpc_pkg::*;
`endif // RVGPU_GPC_PKG_IMPORTED

module rvgpu_gpc_router #(
    parameter gpc_parameter_t GPC_CONFIG = DEFAULT_GPC_CONFIG,
    parameter int GPC_ID = 0
) (
    input  logic clk,
    input  logic rst_n,
    
    // 功能模块接口 - 使用up_port modport，因为它们发送消息给路由器
    interface_gpc_router.up_port l15_if,
    interface_gpc_router.up_port mmu_if,
    interface_gpc_router.up_port block_if,
    interface_gpc_router.up_port raster_if,
    
    // TPC路由器接口 - 使用down_port modport，因为路由器发送消息给它
    interface_gpc_router.down_port tpc_router_if
);
    // 上游FIFO - 缓存来自TPC的响应消息
    rvgpu_fifo_basic_if #(
        .DATA_WIDTH($bits(t_router_message)),  // 268位 = 4+8+256
        .INDEX_BITS(5)  // 深度32
    ) up_fifo_basic_if();
    
    rvgpu_fifo_basic #(
        .DATA_WIDTH($bits(t_router_message)),
        .INDEX_BITS(5)
    ) u_up_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .fifo_if(up_fifo_basic_if.fifo_port)
    );
    
    // 下游FIFO - 缓存发往TPC的请求消息
    rvgpu_fifo_basic_if #(
        .DATA_WIDTH($bits(t_router_message)),
        .INDEX_BITS(5)
    ) down_fifo_basic_if();
    
    rvgpu_fifo_basic #(
        .DATA_WIDTH($bits(t_router_message)),
        .INDEX_BITS(5)
    ) u_down_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .fifo_if(down_fifo_basic_if.fifo_port)
    );
    
    //=============================================================================
    // 消息路由逻辑和流控制逻辑 - 优先级仲裁
    //=============================================================================
    
    always_comb begin
        // 默认值
        up_fifo_basic_if.write_en = 1'b0;
        up_fifo_basic_if.write_data = build_router_message_raw();
        
        down_fifo_basic_if.write_en = 1'b0;
        down_fifo_basic_if.write_data = build_router_message_raw();
        
        // 默认ready信号 - 默认为低，只有被选中的模块才能握手
        l15_if.gpc2sm_ready = 1'b0;
        mmu_if.gpc2sm_ready = 1'b0;
        block_if.gpc2sm_ready = 1'b0;
        raster_if.gpc2sm_ready = 1'b0;
        
        // 优先级仲裁：Block Scheduler > L1.5 Cache > MMU > Raster
        // 所有gpc2sm消息都直接写入下游FIFO，发送到TPC
        if (block_if.gpc2sm_valid && !down_fifo_basic_if.full) begin
            // Block Scheduler消息 - 最高优先级
            down_fifo_basic_if.write_data = block_if.gpc2sm_msg;
            down_fifo_basic_if.write_en = block_if.gpc2sm_valid;
            // 只有Block的ready为高，其他模块的ready为低
            block_if.gpc2sm_ready = 1'b1;
        end
        // L1.5 Cache消息 - 第二优先级
        else if (l15_if.gpc2sm_valid && !down_fifo_basic_if.full) begin
            down_fifo_basic_if.write_data = l15_if.gpc2sm_msg;
            down_fifo_basic_if.write_en = l15_if.gpc2sm_valid;
            // 只有L1.5 Cache的ready为高，其他模块的ready为低
            l15_if.gpc2sm_ready = 1'b1;
        end
        // MMU消息 - 第三优先级
        else if (mmu_if.gpc2sm_valid && !down_fifo_basic_if.full) begin
            down_fifo_basic_if.write_data = mmu_if.gpc2sm_msg;
            down_fifo_basic_if.write_en = mmu_if.gpc2sm_valid;
            // 只有MMU的ready为高，其他模块的ready为低
            mmu_if.gpc2sm_ready = 1'b1;
        end
        // Raster消息 - 最低优先级
        else if (raster_if.gpc2sm_valid && !down_fifo_basic_if.full) begin
            down_fifo_basic_if.write_data = raster_if.gpc2sm_msg;
            down_fifo_basic_if.write_en = raster_if.gpc2sm_valid;
            // 只有Raster的ready为高，其他模块的ready为低
            raster_if.gpc2sm_ready = 1'b1;
        end
    end
    
    //=============================================================================
    // FIFO读取和输出连接逻辑
    //=============================================================================
    always_comb begin
        // 从FIFO读取数据
        up_fifo_basic_if.read_en = 1'b0;  // 暂时不使用
        down_fifo_basic_if.read_en = tpc_router_if.gpc2sm_ready;  // TPC准备好时读取
        
        // 将FIFO输出连接到TPC路由器接口
        tpc_router_if.gpc2sm_msg = down_fifo_basic_if.read_data;  // 从FIFO读取数据
        tpc_router_if.gpc2sm_valid = !down_fifo_basic_if.empty;   // FIFO非空时有效
    end

endmodule : rvgpu_gpc_router

`endif // RVGPU_GPC_ROUTER_SV
