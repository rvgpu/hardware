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
    
    // 内部FIFO接口
    interface_gpc_router up_fifo_if();         // 上游FIFO接口
    interface_gpc_router down_fifo_if();       // 下游FIFO接口
    
    // 消息解析和路由逻辑
    always_comb begin
        up_fifo_if.gpc2sm_valid = 1'b0;
        up_fifo_if.gpc2sm_msg = build_router_message_raw();
        
        down_fifo_if.gpc2sm_valid = 1'b0;
        down_fifo_if.gpc2sm_msg = build_router_message_raw();
        
        // 根据消息类型和来源进行路由
        case (1'b1)
            // L1.5 Cache消息
            l15_if.gpc2sm_valid: begin
                if (l15_if.gpc2sm_msg.msg_type == ROUTER_MSG_L15_REQ) begin
                    // 缓存请求 - 转发到TPC路由器
                    down_fifo_if.gpc2sm_msg = l15_if.gpc2sm_msg;
                    down_fifo_if.gpc2sm_valid = l15_if.gpc2sm_valid;
                end else begin
                    // 缓存响应 - 转发到上游FIFO
                    up_fifo_if.gpc2sm_msg = l15_if.gpc2sm_msg;
                    up_fifo_if.gpc2sm_valid = l15_if.gpc2sm_valid;
                end
            end
            
            // MMU消息
            mmu_if.gpc2sm_valid: begin
                if (mmu_if.gpc2sm_msg.msg_type == ROUTER_MSG_MMU_REQ) begin
                    // MMU请求 - 转发到TPC路由器
                    down_fifo_if.gpc2sm_msg = mmu_if.gpc2sm_msg;
                    down_fifo_if.gpc2sm_valid = mmu_if.gpc2sm_valid;
                end else begin
                    // MMU响应 - 转发到上游FIFO
                    up_fifo_if.gpc2sm_msg = mmu_if.gpc2sm_msg;
                    up_fifo_if.gpc2sm_valid = mmu_if.gpc2sm_valid;
                end
            end
            
            // Block Scheduler消息
            block_if.gpc2sm_valid: begin
                if (block_if.gpc2sm_msg.msg_type == ROUTER_MSG_BLOCK_DISP) begin
                    // Block分发 - 转发到TPC路由器
                    down_fifo_if.gpc2sm_msg = block_if.gpc2sm_msg;
                    down_fifo_if.gpc2sm_valid = block_if.gpc2sm_valid;
                end else begin
                    // Block完成 - 转发到上游FIFO
                    up_fifo_if.gpc2sm_msg = block_if.gpc2sm_msg;
                    up_fifo_if.gpc2sm_valid = block_if.gpc2sm_valid;
                end
            end
            
            // Raster消息
            raster_if.gpc2sm_valid: begin
                if (raster_if.gpc2sm_msg.msg_type == ROUTER_MSG_TLB_UPDATE) begin
                    // TLB更新 - 转发到TPC路由器
                    down_fifo_if.gpc2sm_msg = raster_if.gpc2sm_msg;
                    down_fifo_if.gpc2sm_valid = raster_if.gpc2sm_valid;
                end else begin
                    // 其他Raster消息 - 转发到上游FIFO
                    up_fifo_if.gpc2sm_msg = raster_if.gpc2sm_msg;
                    up_fifo_if.gpc2sm_valid = raster_if.gpc2sm_valid;
                end
            end
        endcase
    end
    
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
    
    // FIFO接口连接逻辑
    always_comb begin
        // 上游FIFO连接
        up_fifo_basic_if.write_en = up_fifo_if.gpc2sm_valid;
        up_fifo_basic_if.write_data = up_fifo_if.gpc2sm_msg;  // 直接传递整个结构体
        up_fifo_if.gpc2sm_ready = !up_fifo_basic_if.full;
        
        // 下游FIFO连接
        down_fifo_basic_if.write_en = down_fifo_if.gpc2sm_valid;
        down_fifo_basic_if.write_data = down_fifo_if.gpc2sm_msg;  // 直接传递整个结构体
        down_fifo_if.gpc2sm_ready = !down_fifo_basic_if.full;
        
        // 从FIFO读取数据
        up_fifo_basic_if.read_en = 1'b0;  // 暂时不使用
        down_fifo_basic_if.read_en = 1'b0; // 暂时不使用
    end
    
    // 将FIFO输出连接到TPC路由器接口
    always_comb begin
        // 下游FIFO -> TPC路由器（现在可以驱动tpc_router_if的信号）
        tpc_router_if.gpc2sm_msg = down_fifo_basic_if.read_data;  // 从FIFO读取数据
        tpc_router_if.gpc2sm_valid = !down_fifo_basic_if.empty;   // FIFO非空时有效
        down_fifo_basic_if.read_en = tpc_router_if.gpc2sm_ready;  // TPC准备好时读取
        
        // 上游FIFO -> 功能模块（通过ready信号控制）
        up_fifo_if.gpc2sm_ready = 1'b1; // 简化处理，实际可能需要更复杂的控制逻辑
    end

endmodule : rvgpu_gpc_router

`endif // RVGPU_GPC_ROUTER_SV
