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

`ifndef RVGPU_COMMAND_PROCESSOR_SV
`define RVGPU_COMMAND_PROCESSOR_SV

`include "rvgpu_control_unit_pkg.svh"
`include "rvgpu_control_unit_if.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_job_dispatcher.sv"

module rvgpu_command_processor #(
    parameter control_unit_config_t CONTROL_UNIT_CONFIG = DEFAULT_CONTROL_UNIT_CONFIG
) (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // Host Interface (Host IF -> AXI adpater -> Command Processor)
    control_if.cp_port ctrl_cp,

    // NOC Interface  
    rvgpu_internal_noc_if.device noc_if,

    // MMU Interface
    mmu_if.cp_port mmu_if,

    // Interrupt Output
    output logic                           gpu_irq
);
    //=============================================================================
    // Internal Registers and Signals
    //=============================================================================
    
    // 控制和状态寄存器
    logic [63:0] mmu_pagetable_addr;     // MMU页表基地址
    logic [63:0] command_packet_addr;    // Command Package数组基地址
    control_reg_t control_reg;           // 控制寄存器
    status_reg_t status_reg;             // 状态寄存器
    
    // Flag 表示CP处于运行状态，由Job Dispatcher的完成和错误信号控制
    logic cp_running;
    
    // Job Dispatcher Interface
    job_dispatcher_if cp_jd();

    //=============================================================================
    // Slave Interface Assignment (CP不作为slave使用)
    //=============================================================================
    
    // Command Processor不支持slave访问，设置appropriate默认值
    assign noc_if.s_req_ready = 1'b0;      // 不准备接收slave请求
    assign noc_if.s_resp_valid = 1'b0;     // 不发送slave响应
    assign noc_if.s_resp_header = '0;
    assign noc_if.s_resp_data = '0;
    assign noc_if.s_resp_status = 2'b00;   // RESP_OKAY
    assign noc_if.s_resp_last = 1'b0;
    
    //=============================================================================
    // Job Dispatcher Instance
    //=============================================================================
    
    rvgpu_job_dispatcher #(
        .CONTROL_UNIT_CONFIG(CONTROL_UNIT_CONFIG)
    ) u_job_dispatcher (
        .clk(clk),
        .rst_n(rst_n),
        .noc_if(noc_if),
        .mmu_if(mmu_if),
        .jd_if(cp_jd.jd_port)
    );
    
    //=============================================================================
    // 控制CP的运行状态
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cp_running <= 1'b0;
        end else begin
            // 如果CP正在运行，则根据Job Dispatcher的完成和错误信号更新运行状态
            // 如果CP未运行，则根据控制寄存器的START信号更新运行状态
            logic next_cp_running;
            next_cp_running = cp_running ? !(cp_jd.complete || cp_jd.error) : control_reg.start;
            cp_running <= next_cp_running;
        end
    end
    
    //=============================================================================
    // 控制信号生成
    //=============================================================================
    
    // 使能Job Dispatcher，复位Job Dispatcher，设置Package和MMU基地址
    assign cp_jd.enable = cp_running;
    assign cp_jd.reset = control_reg.reset;
    assign cp_jd.package_addr = command_packet_addr;
    assign cp_jd.mmu_addr = mmu_pagetable_addr;
    
    // 中断生成：基于完成或错误状态
    assign gpu_irq = control_reg.irq_en && (cp_jd.complete || cp_jd.error);
    
    //=============================================================================
    // 寄存器读写逻辑
    //=============================================================================
    
    // 组合逻辑 - 读数据生成（使用assign语句，更高效）
    assign ctrl_cp.ctrl_rdata = (
        (ctrl_cp.ctrl_addr[15:0] == REG_MMU_PAGETABLE_LO) ? {32'h0, mmu_pagetable_addr[31:0]} :
        (ctrl_cp.ctrl_addr[15:0] == REG_MMU_PAGETABLE_HI) ? {32'h0, mmu_pagetable_addr[63:32]} :
        (ctrl_cp.ctrl_addr[15:0] == REG_COMMAND_PACKET_LO) ? {32'h0, command_packet_addr[31:0]} :
        (ctrl_cp.ctrl_addr[15:0] == REG_COMMAND_PACKET_HI) ? {32'h0, command_packet_addr[63:32]} :
        (ctrl_cp.ctrl_addr[15:0] == REG_CONTROL) ? {32'h0, control_reg.irq_en, control_reg.reset, control_reg.start} :
        (ctrl_cp.ctrl_addr[15:0] == REG_STATUS) ? {32'h0, status_reg.mmu_ready, status_reg.error, status_reg.complete, status_reg.idle} :
        64'h0
    );
    
    //=============================================================================
    // 寄存器初始化和写入逻辑
    //=============================================================================
    
    always_ff @(posedge clk) begin : register_logic
        if (!rst_n) begin
            // 初始化寄存器
            mmu_pagetable_addr <= 64'h0;
            command_packet_addr <= 64'h0;
            control_reg <= '{default: 1'b0};
        end else begin
            // 寄存器写入逻辑
            if (ctrl_cp.ctrl_we) begin
                case (ctrl_cp.ctrl_addr[15:0])
                    REG_MMU_PAGETABLE_LO: mmu_pagetable_addr[31:0] <= ctrl_cp.ctrl_wdata[31:0];
                    REG_MMU_PAGETABLE_HI: mmu_pagetable_addr[63:32] <= ctrl_cp.ctrl_wdata[31:0];
                    REG_COMMAND_PACKET_LO: command_packet_addr[31:0] <= ctrl_cp.ctrl_wdata[31:0];
                    REG_COMMAND_PACKET_HI: command_packet_addr[63:32] <= ctrl_cp.ctrl_wdata[31:0];
                    REG_CONTROL: begin
                        control_reg.start <= ctrl_cp.ctrl_wdata[0];
                        control_reg.reset <= ctrl_cp.ctrl_wdata[1];
                        control_reg.irq_en <= ctrl_cp.ctrl_wdata[2];
                    end
                    default: ; // 忽略未知地址
                endcase
            end else begin
                // 自动清除START位（单脉冲）
                if (cp_jd.complete || cp_jd.error) begin
                    control_reg.start <= 1'b0;
                end
            end
        end
    end
    
    //=============================================================================
    // 状态寄存器更新逻辑
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            status_reg <= '{idle: 1'b1, default: 1'b0};
        end else begin
            // IDLE状态：不运行且未完成
            status_reg.idle <= !cp_running && !cp_jd.complete && !cp_jd.error;
            
            // COMPLETE状态：完成且无错误
            status_reg.complete <= cp_jd.complete && !cp_jd.error;
            
            // ERROR状态：有错误
            status_reg.error <= cp_jd.error;
            
            // MMU_READY状态：Job Dispatcher内部管理
            status_reg.mmu_ready <= 1'b1;
        end
    end

endmodule : rvgpu_command_processor

`endif // RVGPU_COMMAND_PROCESSOR_SV 