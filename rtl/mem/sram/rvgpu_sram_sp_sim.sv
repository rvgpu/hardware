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

`ifndef RVGPU_SRAM_SP_SIM_SV
`define RVGPU_SRAM_SP_SIM_SV

`include "rvgpu_sram_if.svh"

//=============================================================================
// SRAM Single Port Simulation
//=============================================================================

module rvgpu_sram_sp #(
    parameter int WIDTH        = 64,      // 数据宽度
    parameter int HEIGHT       = 64,      // 深度
    parameter string RAMNAME   = "RVGPU_SRAM_SIM"  // RAM名称
) (
    // SRAM Interface
    rvgpu_sram_if.sram_port sram_if
);

    //=============================================================================
    // 参数计算
    //=============================================================================
    
    localparam int ADDR_WIDTH = $clog2(HEIGHT);
    localparam int DATA_WIDTH = WIDTH;
    localparam int MEM_DEPTH = HEIGHT;
    
    //=============================================================================
    // 内部存储器
    //=============================================================================
    
    reg [DATA_WIDTH-1:0] mem [MEM_DEPTH-1:0] /* synthesis syn_ramstyle = "no_rw_check" */;
    reg [DATA_WIDTH-1:0] rdata_reg;
    
    //=============================================================================
    // 读写逻辑
    //=============================================================================
    
    always_ff @(posedge sram_if.clk) begin
        if (sram_if.ce) begin
            if (sram_if.we) begin
                // 写操作
                mem[sram_if.addr] <= sram_if.wdata;
                rdata_reg <= sram_if.wdata;
            end else begin
                // 读操作
                rdata_reg <= mem[sram_if.addr];
            end
        end
    end
    
    //=============================================================================
    // 输出赋值
    //=============================================================================
    
    assign sram_if.rdata = rdata_reg;

endmodule : rvgpu_sram_sp

`endif // RVGPU_SRAM_SP_SIM_SV 