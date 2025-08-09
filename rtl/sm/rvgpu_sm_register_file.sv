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

`ifndef RVGPU_SM_REGISTER_FILE_SV
`define RVGPU_SM_REGISTER_FILE_SV

`include "rvgpu_typedef.svh"

// SM寄存器文件
// 支持多个warp的寄存器存储和多端口访问
module rvgpu_sm_register_file #(
    parameter int WARP_COUNT = 32,              // 支持的warp数量
    parameter int THREAD_COUNT = 32,            // 每个warp的线程数
    parameter int REG_COUNT = 32,               // 每个线程的寄存器数量
    parameter int READ_PORTS = 3,               // 读端口数量
    parameter int WRITE_PORTS = 2               // 写端口数量
) (
    input  logic clk,
    input  logic rst_n,
    
    // 读端口
    input  logic [READ_PORTS-1:0]                    read_enable,
    input  logic [$clog2(WARP_COUNT)-1:0]            read_warp_id[READ_PORTS],
    input  logic [4:0]                               read_reg_addr[READ_PORTS],
    output logic [31:0]                              read_data[READ_PORTS][THREAD_COUNT],
    
    // 写端口
    input  logic [WRITE_PORTS-1:0]                   write_enable,
    input  logic [$clog2(WARP_COUNT)-1:0]            write_warp_id[WRITE_PORTS],
    input  logic [4:0]                               write_reg_addr[WRITE_PORTS],
    input  logic [31:0]                              write_data[WRITE_PORTS][THREAD_COUNT],
    input  logic [THREAD_COUNT-1:0]                  write_mask[WRITE_PORTS],
    
    // Warp管理
    input  logic                                     warp_alloc_valid,
    input  logic [$clog2(WARP_COUNT)-1:0]            warp_alloc_id,
    output logic                                     warp_alloc_ready,
    
    input  logic                                     warp_dealloc_valid,
    input  logic [$clog2(WARP_COUNT)-1:0]            warp_dealloc_id,
    
    // 状态输出
    output logic [WARP_COUNT-1:0]                    warp_allocated,
    output logic [$clog2(WARP_COUNT):0]              allocated_warp_count
);
    
    // 寄存器存储器
    // 组织方式：[warp_id][thread_id][reg_addr]
    logic [31:0] register_memory[WARP_COUNT][THREAD_COUNT][REG_COUNT];
    
    // Warp分配状态
    logic [WARP_COUNT-1:0] warp_valid;
    
    // 读操作 - 组合逻辑
    always_comb begin
        for (int p = 0; p < READ_PORTS; p++) begin
            if (read_enable[p] && warp_valid[read_warp_id[p]]) begin
                for (int t = 0; t < THREAD_COUNT; t++) begin
                    if (read_reg_addr[p] == 5'b00000) begin
                        // x0寄存器总是返回0
                        read_data[p][t] = 32'h0;
                    end else begin
                        read_data[p][t] = register_memory[read_warp_id[p]][t][read_reg_addr[p]];
                    end
                end
            end else begin
                for (int t = 0; t < THREAD_COUNT; t++) begin
                    read_data[p][t] = '0;
                end
            end
        end
    end
    
    // 写操作 - 时序逻辑
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            warp_valid <= '0;
            
            // 初始化寄存器
            for (int w = 0; w < WARP_COUNT; w++) begin
                for (int t = 0; t < THREAD_COUNT; t++) begin
                    for (int r = 0; r < REG_COUNT; r++) begin
                        register_memory[w][t][r] <= '0;
                    end
                end
            end
        end else begin
            // Warp分配
            if (warp_alloc_valid && warp_alloc_ready) begin
                warp_valid[warp_alloc_id] <= 1'b1;
                
                // 初始化新分配的warp的寄存器
                for (int t = 0; t < THREAD_COUNT; t++) begin
                    for (int r = 0; r < REG_COUNT; r++) begin
                        register_memory[warp_alloc_id][t][r] <= '0;
                    end
                end
            end
            
            // Warp释放
            if (warp_dealloc_valid) begin
                warp_valid[warp_dealloc_id] <= 1'b0;
            end
            
            // 写操作
            for (int p = 0; p < WRITE_PORTS; p++) begin
                if (write_enable[p] && warp_valid[write_warp_id[p]] && 
                    write_reg_addr[p] != 5'b00000) begin // 不能写x0寄存器
                    for (int t = 0; t < THREAD_COUNT; t++) begin
                        if (write_mask[p][t]) begin
                            register_memory[write_warp_id[p]][t][write_reg_addr[p]] <= 
                                write_data[p][t];
                        end
                    end
                end
            end
        end
    end
    
    // Warp分配准备信号
    assign warp_alloc_ready = ~warp_valid[warp_alloc_id];
    
    // 状态输出
    assign warp_allocated = warp_valid;
    
    // 计算已分配的warp数量
    always_comb begin
        allocated_warp_count = '0;
        for (int i = 0; i < WARP_COUNT; i++) begin
            if (warp_valid[i]) begin
                allocated_warp_count = allocated_warp_count + 1;
            end
        end
    end

endmodule : rvgpu_sm_register_file

`endif // RVGPU_SM_REGISTER_FILE_SV 