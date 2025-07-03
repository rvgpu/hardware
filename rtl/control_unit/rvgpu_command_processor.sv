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
`include "rvgpu_job_dispatcher.sv"

module rvgpu_command_processor #(
    parameter control_unit_config_t CONTROL_UNIT_CONFIG = DEFAULT_CONTROL_UNIT_CONFIG
) (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // Host Interface (Host IF -> AXI adpater -> Command Processor)
    control_if.slave ctrl_if,

    // NOC Interface  
    rvgpu_internal_noc_if.device noc_if,

    // MMU Interface
    mmu_if.master mmu_if,

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
        .jd_if(cp_jd.slave)
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
            cp_running <= cp_running ? !(cp_jd.complete || cp_jd.error) : control_reg.start;
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
    // 寄存器访问逻辑（组合逻辑，无状态机）
    //=============================================================================
    
    always_comb begin
        // 默认值
        ctrl_if.req_ready = 1'b1;  // 总是准备好接收请求
        ctrl_if.resp_valid = 1'b0;
        ctrl_if.resp_data = 64'h0;
        ctrl_if.resp_status = 2'b00;  // STATUS_OK
        
        // 处理请求
        if (ctrl_if.req_valid) begin
            if (ctrl_if.req_we) begin
                // 写操作：直接处理，无需状态机
                ctrl_if.resp_valid = 1'b1;
                ctrl_if.resp_data = 64'h0;
                ctrl_if.resp_status = 2'b00;  // STATUS_OK
            end else begin
                // 读操作：直接响应
                ctrl_if.resp_valid = 1'b1;
                case (ctrl_if.req_addr[15:0])
                    REG_MMU_PAGETABLE_LO: ctrl_if.resp_data = mmu_pagetable_addr[31:0];
                    REG_MMU_PAGETABLE_HI: ctrl_if.resp_data = mmu_pagetable_addr[63:32];
                    REG_COMMAND_PACKET_LO: ctrl_if.resp_data = command_packet_addr[31:0];
                    REG_COMMAND_PACKET_HI: ctrl_if.resp_data = command_packet_addr[63:32];
                    REG_CONTROL: ctrl_if.resp_data = {28'h0, control_reg.irq_en, control_reg.reset, control_reg.start};
                    REG_STATUS: ctrl_if.resp_data = {28'h0, status_reg.mmu_ready, status_reg.error, status_reg.complete, status_reg.idle};
                    default: begin
                        ctrl_if.resp_data = 64'h0;
                        ctrl_if.resp_status = 2'b01; // STATUS_ERROR
                    end
                endcase
            end
        end
    end
    
    //=============================================================================
    // 寄存器写入逻辑
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mmu_pagetable_addr <= 64'h0;
            command_packet_addr <= 64'h0;
            control_reg <= '{default: 1'b0};
        end else begin
            // 处理寄存器写入
            if (ctrl_if.req_valid && ctrl_if.req_we) begin
                case (ctrl_if.req_addr[15:0])
                    REG_MMU_PAGETABLE_LO: begin
                        if (ctrl_if.req_strb[3:0] != 4'b0000) begin
                            mmu_pagetable_addr[31:0] <= ctrl_if.req_data[31:0];
                        end
                    end
                    REG_MMU_PAGETABLE_HI: begin
                        if (ctrl_if.req_strb[3:0] != 4'b0000) begin
                            mmu_pagetable_addr[63:32] <= ctrl_if.req_data[31:0];
                        end
                    end
                    REG_COMMAND_PACKET_LO: begin
                        if (ctrl_if.req_strb[3:0] != 4'b0000) begin
                            command_packet_addr[31:0] <= ctrl_if.req_data[31:0];
                        end
                    end
                    REG_COMMAND_PACKET_HI: begin
                        if (ctrl_if.req_strb[3:0] != 4'b0000) begin
                            command_packet_addr[63:32] <= ctrl_if.req_data[31:0];
                        end
                    end
                    REG_CONTROL: begin
                        if (ctrl_if.req_strb[0]) begin
                            control_reg.start <= ctrl_if.req_data[0];
                            control_reg.reset <= ctrl_if.req_data[1];
                            control_reg.irq_en <= ctrl_if.req_data[2];
                        end
                    end
                endcase
            end
            
            // 自动清除START位（单脉冲）
            if (cp_jd.complete || cp_jd.error) begin
                control_reg.start <= 1'b0;
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