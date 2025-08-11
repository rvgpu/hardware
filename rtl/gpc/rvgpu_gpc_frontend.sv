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

`ifndef RVGPU_GPC_FRONTEND_SV
`define RVGPU_GPC_FRONTEND_SV

`include "rvgpu_typedef.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_noc_message.svh"
`include "rvgpu_mmu_if.svh"
`include "interface_gpc_router.svh"

`include "ldst_sm_if.svh"
`include "gpc_block_tpc_if.svh"
`include "gpc_block_raster_if.svh"
`include "rvgpu_gpc_pkg.svh"

`ifndef RVGPU_GPC_PKG_IMPORTED
`define RVGPU_GPC_PKG_IMPORTED
import rvgpu_gpc_pkg::*;
`endif // RVGPU_GPC_PKG_IMPORTED

// GPC前端模块 - 整合所有GPC功能模块和内部路由器
module rvgpu_gpc_frontend #(
    parameter gpc_parameter_t GPC_CONFIG = DEFAULT_GPC_CONFIG,
    parameter int GPC_ID = 0
) (
    input  logic clk,
    input  logic rst_n,
    
    // 外部NOC接口
    rvgpu_internal_noc_if.device noc_if,
    
    // 路由器接口 - 连接TPC0
    interface_gpc_router.down_port router_if
);
    
    // 内部NOC接口
    rvgpu_internal_noc_if    l15_noc_if();                          // L1.5缓存NOC接口
    rvgpu_internal_noc_if    mmu_noc_if();                          // MMU NOC接口
    rvgpu_internal_noc_if    scheduler_noc_if();                    // Scheduler NOC接口
    
    // 内部功能模块接口 - 必须声明以支持模块实例化
    gpc_block_raster_if      block_raster_if();                      // Block Raster接口
    gpc_block_tpc_if         block_tpc_if[GPC_CONFIG.num_tpc]();    // Block TPC接口
    interface_l15cache       l15_cache_if[GPC_CONFIG.num_tpc+2]();  // L1.5 Cache接口
    mmu_if                   gpc_mmu_if[GPC_CONFIG.num_tpc+1]();    // GPC MMU接口
    gpc_tlb_update_if        l0_tlb_if[GPC_CONFIG.num_tpc]();       // L0 TLB更新接口
    
    // NOC Adapter实例化
    rvgpu_gpc_noc_adapter #(.GPC_ID(GPC_ID)) u_noc_adapter (
        .clk(clk),
        .rst_n(rst_n),
        .noc_external_if(noc_if),
        .l15_cache_if(l15_noc_if.noc),
        .mmu_if(mmu_noc_if.noc),
        .scheduler_if(scheduler_noc_if.noc)
    );
    
    // GPC MMU实例
    rvgpu_gpc_mmu #(
        .MAX_REQUESTS(16),  // 使用固定值
        .GPC_ID(GPC_ID)
    ) u_gpc_mmu (
        .clk(clk),
        .rst_n(rst_n),
        .bs_if(gpc_mmu_if[GPC_CONFIG.num_tpc].mmu_port),
        .tpc_if(gpc_mmu_if[0:GPC_CONFIG.num_tpc-1]),
        .l0_tlb_if(l0_tlb_if),
        .noc_if(mmu_noc_if.device)
    );

    // GPC Block Scheduler实例
    rvgpu_gpc_block_scheduler #(
        .GPC_ID(GPC_ID),
        .NUM_TPC(GPC_CONFIG.num_tpc),
        .MAX_WARPS_PER_BLOCK(32),  // 使用固定值
        .ADDR_WIDTH(40)
    ) u_gpc_block_scheduler (
        .clk(clk),
        .rst_n(rst_n),
        .noc_if(scheduler_noc_if.device),
        .tpc_if(block_tpc_if),
        .raster_if(block_raster_if),
        .l15_if(l15_cache_if[GPC_CONFIG.num_tpc].requester),
        .mmu_if(gpc_mmu_if[GPC_CONFIG.num_tpc].requester_port)
    );
    
    // L1.5 Cache实例化
    rvgpu_gpc_l15cache #(
        .GPC_ID(GPC_ID)
    ) u_l15_cache (
        .clk(clk),
        .rst_n(rst_n),
        .noc_if(l15_noc_if.device),
        .requester_if(l15_cache_if)
    );
    
    // Raster Engine实例化
    rvgpu_gpc_raster u_raster (
        .clk(clk),
        .rst_n(rst_n),
        .raster_if(block_raster_if.raster),
        .l15_if(l15_cache_if[GPC_CONFIG.num_tpc+1].requester)
    );
    
    // 消息转换逻辑 - 将功能模块的接口转换为路由器接口
    // 使用优先级逻辑：Block Scheduler > L1.5 Cache > MMU > Raster
    always_comb begin
        // 默认值
        router_if.gpc2sm_valid = 1'b0;
        router_if.gpc2sm_header = '0;
        router_if.gpc2sm_data = '0;
        
        // 优先级：Block Scheduler > L1.5 Cache > MMU > Raster
        if (block_tpc_if[0].warp_valid) begin
            // Block Scheduler消息 - 最高优先级
            router_if.gpc2sm_valid = 1'b1;
            router_if.gpc2sm_header.msg_type = ROUTER_MSG_BLOCK_DISP;
            router_if.gpc2sm_header.dst_id = ROUTER_DST_TPC0_SM0;
            router_if.gpc2sm_header.msg_id = block_tpc_if[0].warp_id;
            router_if.gpc2sm_header.addr = block_tpc_if[0].warp_program_addr;
            router_if.gpc2sm_header.size = {16'h0, block_tpc_if[0].warp_argument_size};
            router_if.gpc2sm_header.is_read = 1'b0;  // Block分发不是读操作
            router_if.gpc2sm_header.mask = block_tpc_if[0].thread_mask[3:0];
            router_if.gpc2sm_data = {224'h0, block_tpc_if[0].warp_arglist_data[31:0]};
        end else if (l15_cache_if[0].req_valid) begin
            // L1.5 Cache消息 - 第二优先级
            router_if.gpc2sm_valid = 1'b1;
            router_if.gpc2sm_header.msg_type = ROUTER_MSG_L15_REQ;
            router_if.gpc2sm_header.dst_id = ROUTER_DST_TPC0_SM0;
            router_if.gpc2sm_header.msg_id = l15_cache_if[0].req_id;
            router_if.gpc2sm_header.addr = l15_cache_if[0].req_paddr;
            router_if.gpc2sm_header.size = {12'h0, l15_cache_if[0].req_size};
            router_if.gpc2sm_header.is_read = l15_cache_if[0].req_is_read;
            router_if.gpc2sm_header.mask = l15_cache_if[0].req_mask[3:0];
            router_if.gpc2sm_data = {224'h0, l15_cache_if[0].req_data[31:0]};
        end else if (gpc_mmu_if[0].req_valid) begin
            // MMU消息 - 第三优先级
            router_if.gpc2sm_valid = 1'b1;
            router_if.gpc2sm_header.msg_type = ROUTER_MSG_MMU_REQ;
            router_if.gpc2sm_header.dst_id = ROUTER_DST_TPC0_SM0;
            router_if.gpc2sm_header.msg_id = 8'h00;  // 简化ID
            router_if.gpc2sm_header.addr = gpc_mmu_if[0].req_vaddr;
            router_if.gpc2sm_header.size = 16'h0;    // 简化大小
            router_if.gpc2sm_header.is_read = (gpc_mmu_if[0].req_type == MMU_READ);
            router_if.gpc2sm_header.mask = 4'h0;     // 简化掩码
            router_if.gpc2sm_data = 256'h0;          // 简化数据
        end else begin
            // 没有消息，保持默认值
            router_if.gpc2sm_valid = 1'b0;
        end
    end

endmodule : rvgpu_gpc_frontend

`endif // RVGPU_GPC_FRONTEND_SV
