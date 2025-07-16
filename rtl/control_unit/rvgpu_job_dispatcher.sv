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

`ifndef RVGPU_JOB_DISPATCHER_SV
`define RVGPU_JOB_DISPATCHER_SV

`include "rvgpu_control_unit_pkg.svh"
`include "rvgpu_control_unit_if.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_debug.svh"

`ifndef RVGPU_CONTROL_UNIT_PKG_IMPORTED
`define RVGPU_CONTROL_UNIT_PKG_IMPORTED
import rvgpu_control_unit_pkg::*;
`endif // RVGPU_CONTROL_UNIT_PKG_IMPORTED

module rvgpu_job_dispatcher #(
    parameter control_unit_config_t CU_CONFIG = DEFAULT_CONTROL_UNIT_CONFIG
) (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // NOC Interface - 读取Command Package
    rvgpu_internal_noc_if.device noc_if,

    // MMU Interface - 地址转换
    mmu_if.cp_port mmu_if,

    // Command Processor Interface
    job_dispatcher_if.jd_port jd_if
);

    //=============================================================================
    // Local Parameters and Types
    //=============================================================================
    
    // 状态位编码
    // 每个位对应一个操作阶段，简化状态机逻辑
    localparam STATE_BITS = 4;
    localparam STATE_IDLE      = 4'b0000;  // 空闲状态
    localparam STATE_MMU_REQ   = 4'b0001;  // MMU请求阶段
    localparam STATE_MMU_WAIT  = 4'b0010;  // MMU等待响应
    localparam STATE_NOC_REQ   = 4'b0100;  // NOC请求阶段
    localparam STATE_NOC_WAIT  = 4'b1000;  // NOC等待响应
    
    // 状态位定义
    localparam STATE_BIT_MMU_REQ  = 0;  // MMU请求有效
    localparam STATE_BIT_MMU_WAIT = 1;  // MMU等待响应
    localparam STATE_BIT_NOC_REQ  = 2;  // NOC请求有效
    localparam STATE_BIT_NOC_WAIT = 3;  // NOC等待响应
    
    // 阶段类型编码：用来区分当前处理的是哪个阶段
    localparam PHASE_HEADER  = 2'b00;  // 读取Header阶段
    localparam PHASE_PAYLOAD = 2'b01;  // 读取Payload阶段
    localparam PHASE_DISPATCH = 2'b10; // 分发阶段
    localparam PHASE_DONE    = 2'b11;  // 完成阶段
    
    //=============================================================================
    // Internal Registers and Signals
    //=============================================================================
    
    // 状态机寄存器
    logic [STATE_BITS-1:0] state_r, state_nxt;
    logic [1:0] phase_r, phase_nxt;
    
    // 地址和数据寄存器
    logic [63:0] package_addr_r, package_addr_nxt;
    logic [63:0] mmu_base_r, mmu_base_nxt;
    logic [47:0] mmu_paddr_r, mmu_paddr_nxt;
    command_header_t header_r, header_nxt;
    logic [CU_CONFIG.job_dispatcher_parameter.max_payload_size*8-1:0] payload_r, payload_nxt;
    

    
    // 控制信号 - 使用assign简化
    logic mmu_req_valid, mmu_req_ready;
    logic noc_req_valid, noc_req_ready;
    logic phase_done, phase_error;
    logic last_package, dispatch_done;
    
    // 错误和状态信号 - 扩展错误状态位
    logic [7:0] error_status;  // 8位错误状态，支持多种错误类型
    logic [7:0] error_status_r, error_status_nxt;  // 错误状态寄存器
    logic busy_flag, complete_flag;
    
    // 错误状态位定义
    localparam ERROR_BIT_MMU_FAULT     = 0;  // MMU页面错误
    localparam ERROR_BIT_NOC_ERROR     = 1;  // NOC通信错误
    localparam ERROR_BIT_INVALID_CMD   = 2;  // 非法命令类型
    localparam ERROR_BIT_PAYLOAD_SIZE  = 3;  // Payload大小超限
    localparam ERROR_BIT_ADDR_ALIGN    = 4;  // 地址未对齐
    localparam ERROR_BIT_PHASE_ERROR   = 5;  // 阶段错误
    localparam ERROR_BIT_TIMEOUT       = 6;  // 超时错误
    localparam ERROR_BIT_UNKNOWN       = 7;  // 未知错误
    
    //=============================================================================
    // 握手信号定义
    //=============================================================================
    
    wire mmu_accept = mmu_if.req_valid && mmu_if.req_ready;
    wire mmu_resp_accept = mmu_if.resp_valid && mmu_if.resp_ready;
    wire noc_accept = noc_if.m_req_valid && noc_if.m_req_ready;
    wire noc_resp_accept = noc_if.m_resp_valid && noc_if.m_resp_ready;
    
    //=============================================================================
    // 组合逻辑 - 状态机和输出控制
    //=============================================================================
    
    always_comb begin : comb_logic
        logic [63:0] mmu_vaddr_tmp;

        // 默认值
        state_nxt = state_r;
        phase_nxt = phase_r;
        package_addr_nxt = package_addr_r;
        mmu_base_nxt = mmu_base_r;
        mmu_paddr_nxt = mmu_paddr_r;
        header_nxt = header_r;
        payload_nxt = payload_r;

        
        // 控制信号默认值
        mmu_req_valid = 1'b0;
        noc_req_valid = 1'b0;
        phase_done = 1'b0;
        phase_error = 1'b0;
        last_package = 1'b0;
        dispatch_done = 1'b0;
        
        // MMU接口输出（基于状态位）
        mmu_if.req_valid = state_r[STATE_BIT_MMU_REQ];
        mmu_vaddr_tmp = package_addr_r + 8'h8;
        mmu_if.req_vaddr = (phase_r == PHASE_HEADER) ? package_addr_r[47:0] : mmu_vaddr_tmp[47:0];
        mmu_if.req_read = 1'b1;
        mmu_if.req_write = 1'b0;
        mmu_if.resp_ready = state_r[STATE_BIT_MMU_WAIT];
        
        // MMU配置信号 - 在同一个cycle生效
        mmu_if.cfg_en = (state_r == STATE_IDLE) && jd_if.enable;
        mmu_if.cfg_base_addr = jd_if.mmu_addr[47:0];  // 直接使用输入信号
        
        // NOC接口输出（基于状态位）
        noc_if.m_req_valid = state_r[STATE_BIT_NOC_REQ];
        noc_if.m_req_header = {8'h02, 8'h00, 4'h0, 4'h1, 8'h00}; // MEM_READ_REQ
        noc_if.m_req_data[63:0] = {mmu_paddr_r[31:0], 
                                   (phase_r == PHASE_HEADER) ? 16'h8 : header_r.payload_size, 
                                   16'h0};
        noc_if.m_req_strb = 32'hFF;
        noc_if.m_req_last = 1'b1;
        noc_if.m_resp_ready = state_r[STATE_BIT_NOC_WAIT];
        
        case (state_r)
            STATE_IDLE: begin
                if (jd_if.enable) begin
                    state_nxt = STATE_MMU_REQ;
                    phase_nxt = PHASE_HEADER;
                    package_addr_nxt = jd_if.package_addr;
                    mmu_base_nxt = jd_if.mmu_addr;
                    `DEBUG_PRINT("JD", $sformatf("JD enable, package_addr: 0x%h, mmu_addr: 0x%h", jd_if.package_addr, jd_if.mmu_addr));
                end
            end
            
            STATE_MMU_REQ: begin
                if (mmu_accept) begin
                    state_nxt = STATE_MMU_WAIT;
                end
            end
            
            STATE_MMU_WAIT: begin
                if (mmu_resp_accept) begin
                    if (mmu_if.resp_status == 2'b00) begin
                        mmu_paddr_nxt = mmu_if.resp_paddr;
                        state_nxt = STATE_NOC_REQ;
                    end else begin
                        phase_error = 1'b1;
                        state_nxt = STATE_IDLE;
                    end
                end
            end
            
            STATE_NOC_REQ: begin
                if (noc_accept) begin
                    state_nxt = STATE_NOC_WAIT;
                end
            end
            
            STATE_NOC_WAIT: begin
                if (noc_resp_accept) begin
                    if (noc_if.m_resp_status == 2'b00) begin
                        if (phase_r == PHASE_HEADER) begin
                            header_nxt = noc_if.m_resp_data[63:0];
                            phase_nxt = PHASE_PAYLOAD;
                            state_nxt = STATE_MMU_REQ;
                        end else begin
                            payload_nxt = noc_if.m_resp_data[255:0];
                            phase_nxt = PHASE_DISPATCH;
                            state_nxt = STATE_IDLE; // 进入分发阶段
                        end
                    end else begin
                        phase_error = 1'b1;
                        state_nxt = STATE_IDLE;
                    end
                end
            end
            
            default: begin
                state_nxt = STATE_IDLE;
            end
        endcase
        
        // 分发阶段逻辑（在IDLE状态处理）
        if (phase_r == PHASE_DISPATCH && state_r == STATE_IDLE) begin
            dispatch_done = 1'b1;
            last_package = header_r.flags[0];
            
            if (!last_package) begin
                // 计算下一个Package地址
                logic [63:0] next_addr;
                next_addr = package_addr_r + 8'h8 + {48'h0, header_r.payload_size};
                package_addr_nxt = (next_addr + 7) & ~7; // 64位对齐
                state_nxt = STATE_MMU_REQ;
                phase_nxt = PHASE_HEADER;
            end else begin
                phase_nxt = PHASE_DONE;
            end
        end
        
    end
    
    //=============================================================================
    // 错误检测逻辑 
    //=============================================================================
    
    always_comb begin : error_detection_logic
        // 错误状态位检测 - 精简设计，使用assign和条件表达式
        error_status[ERROR_BIT_MMU_FAULT] = mmu_if.resp_valid && (mmu_if.resp_status != 2'b00);
        error_status[ERROR_BIT_NOC_ERROR] = noc_if.m_resp_valid && (noc_if.m_resp_status != 2'b00);
        error_status[ERROR_BIT_INVALID_CMD] = (phase_r == PHASE_HEADER && state_r == STATE_NOC_WAIT) && 
                                             (noc_if.m_resp_data[7:0] != 8'h01 && 
                                              noc_if.m_resp_data[7:0] != 8'h02 && 
                                              noc_if.m_resp_data[7:0] != 8'h03);
        error_status[ERROR_BIT_PAYLOAD_SIZE] = (phase_r == PHASE_HEADER && state_r == STATE_NOC_WAIT) && 
                                              (noc_if.m_resp_data[31:16] > CU_CONFIG.job_dispatcher_parameter.max_payload_size);
        error_status[ERROR_BIT_ADDR_ALIGN] = (phase_r == PHASE_HEADER && state_r == STATE_MMU_REQ) && 
                                            (package_addr_r[2:0] != 3'b000);
        error_status[ERROR_BIT_PHASE_ERROR] = phase_error;
        error_status[ERROR_BIT_TIMEOUT] = 1'b0;      // 预留
        error_status[ERROR_BIT_UNKNOWN] = 1'b0;      // 预留
        
        // 错误状态更新逻辑 - 保持错误状态直到复位
        error_status_nxt = error_status_r;
        if (error_status != 8'h00) begin
            error_status_nxt = error_status_r | error_status;  // 累积错误状态
        end
    end
    
    //=============================================================================
    // 时序逻辑 - 寄存器更新
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n || jd_if.reset) begin
            state_r <= STATE_IDLE;
            phase_r <= PHASE_HEADER;
            package_addr_r <= 64'h0;
            mmu_base_r <= 64'h0;
            mmu_paddr_r <= 48'h0;
            header_r <= '{default: 1'b0};
            payload_r <= '0;
            error_status_r <= 8'h0;  // 复位错误状态寄存器

        end else begin
            state_r <= state_nxt;
            phase_r <= phase_nxt;
            package_addr_r <= package_addr_nxt;
            mmu_base_r <= mmu_base_nxt;
            mmu_paddr_r <= mmu_paddr_nxt;
            header_r <= header_nxt;
            payload_r <= payload_nxt;
            error_status_r <= error_status_nxt;  // 更新错误状态寄存器

        end
    end
    
    //=============================================================================
    // 输出逻辑
    //=============================================================================
    
    // 忙碌状态：非空闲或正在分发（正常工作时）
    assign busy_flag = (state_r != STATE_IDLE) || (phase_r == PHASE_DISPATCH);
    
    // 完成状态：分发阶段完成且无错误
    assign complete_flag = (phase_r == PHASE_DONE) && (error_status_r == 8'h00);
    
    // 输出赋值 - 扩展错误状态输出
    assign jd_if.busy = busy_flag;
    assign jd_if.error = (error_status_r != 8'h00);  // 使用错误状态寄存器
    assign jd_if.error_status = error_status_r;      // 输出详细错误状态（需要接口支持）
    assign jd_if.complete = complete_flag;

endmodule : rvgpu_job_dispatcher

`endif // RVGPU_JOB_DISPATCHER_SV 