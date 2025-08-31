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
`include "interface_fifo_stream.svh"

`ifndef RVGPU_GPC_PKG_IMPORTED
`define RVGPU_GPC_PKG_IMPORTED
import rvgpu_gpc_pkg::*;
`endif // RVGPU_GPC_PKG_IMPORTED

module rvgpu_gpc_router #(
    parameter int GPC_ID = 0
) (
    input  logic clk,
    input  logic rst_n,
    
    // 功能模块接口
    interface_gpc_router.left_port l15_if,
    interface_gpc_router.left_port mmu_if,
    interface_gpc_router.left_port block_if,
    interface_gpc_router.left_port raster_if,
    
    // TPC路由器接口
    interface_gpc_router.right_port right_if
);
    localparam int ROUTER_MESSAGE_WIDTH = $bits(t_router_message);

    // 上游FIFO - 缓存来自TPC的响应消息
    interface_fifo_stream #(
        .DATA_WIDTH(ROUTER_MESSAGE_WIDTH),  // 268位 = 4+8+256
        .FIFO_DEPTH(32)  // 深度32
    ) up_fifo_stream_if();
    
    rvgpu_fifo_stream #(
        .DATA_WIDTH(ROUTER_MESSAGE_WIDTH),
        .FIFO_DEPTH(32)
    ) u_up_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .fifo_if(up_fifo_stream_if.fifo_port)
    );
    
    // 下游FIFO - 缓存发往TPC的请求消息
    interface_fifo_stream #(
        .DATA_WIDTH(ROUTER_MESSAGE_WIDTH),
        .FIFO_DEPTH(32)
    ) down_fifo_stream_if();
    
    rvgpu_fifo_stream #(
        .DATA_WIDTH(ROUTER_MESSAGE_WIDTH),
        .FIFO_DEPTH(32)
    ) u_down_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .fifo_if(down_fifo_stream_if.fifo_port)
    );
    
    //=============================================================================
    // 消息路由逻辑和流控制逻辑 - 优先级仲裁
    //=============================================================================
    
    always_comb begin
        // 默认值
        down_fifo_stream_if.wr_valid = 1'b0;
        down_fifo_stream_if.wr_data = build_router_message_raw();
        
        // 默认ready信号 - 默认为低，只有被选中的模块才能握手
        l15_if.down_ready = 1'b0;
        mmu_if.down_ready = 1'b0;
        block_if.down_ready = 1'b0;
        raster_if.down_ready = 1'b0;
        
        // 优先级仲裁：Block Scheduler > L1.5 Cache > MMU > Raster
        // 所有down消息都直接写入下游FIFO，发送到TPC
        if (block_if.down_valid && down_fifo_stream_if.wr_ready) begin
            // Block Scheduler消息 - 最高优先级
            down_fifo_stream_if.wr_data = block_if.down_msg;
            down_fifo_stream_if.wr_valid = block_if.down_valid;
            // 只有Block的ready为高，其他模块的ready为低
            block_if.down_ready = 1'b1;
        end
        // L1.5 Cache消息 - 第二优先级
        else if (l15_if.down_valid && down_fifo_stream_if.wr_ready) begin
            down_fifo_stream_if.wr_data = l15_if.down_msg;
            down_fifo_stream_if.wr_valid = l15_if.down_valid;
            // 只有L1.5 Cache的ready为高，其他模块的ready为低
            l15_if.down_ready = 1'b1;
        end
        // MMU消息 - 第三优先级
        else if (mmu_if.down_valid && down_fifo_stream_if.wr_ready) begin
            down_fifo_stream_if.wr_data = mmu_if.down_msg;
            down_fifo_stream_if.wr_valid = mmu_if.down_valid;
            // 只有MMU的ready为高，其他模块的ready为低
            mmu_if.down_ready = 1'b1;
        end
        // Raster消息 - 最低优先级
        else if (raster_if.down_valid && down_fifo_stream_if.wr_ready) begin
            down_fifo_stream_if.wr_data = raster_if.down_msg;
            down_fifo_stream_if.wr_valid = raster_if.down_valid;
            // 只有Raster的ready为高，其他模块的ready为低
            raster_if.down_ready = 1'b1;
        end
    end
    
    //=============================================================================
    // FIFO读取和输出连接逻辑
    //=============================================================================
    always_comb begin
        // 从down_fifo读取数据到right_if
        down_fifo_stream_if.rd_ready = right_if.down_ready;  // TPC准备好时读取
        
        // 将down_fifo输出连接到TPC路由器接口
        right_if.down_msg = down_fifo_stream_if.rd_data;     // 从FIFO读取数据
        right_if.down_valid = down_fifo_stream_if.rd_valid;  // FIFO有数据时有效
        
        // 上游FIFO暂时不使用，但保持接口完整性
        up_fifo_stream_if.rd_ready = 1'b0;  // 暂时不使用
    end

endmodule : rvgpu_gpc_router

`endif // RVGPU_GPC_ROUTER_SV
