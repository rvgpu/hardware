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

// 导入控制单元包
import rvgpu_control_unit_pkg::*;

module rvgpu_job_dispatcher #(
    parameter control_unit_config_t CONTROL_UNIT_CONFIG = DEFAULT_CONTROL_UNIT_CONFIG
) (
    // Clock and Reset Interface
    input  logic clk,
    input  logic rst_n,

    // NOC Interface - 读取Command Package
    rvgpu_internal_noc_if.device noc_if,

    // MMU Interface - 地址转换
    mmu_if.master mmu_if,

    // Command Processor Interface
    job_dispatcher_if.master jd_if
);

    //=============================================================================
    // Local Parameters and Types
    //=============================================================================
    
    // Dispatcher状态机
    typedef enum logic [2:0] {
        DISP_IDLE          = 3'b000,   // 空闲状态
        DISP_MMU_CONFIG    = 3'b001,   // MMU配置
        DISP_HEADER_FETCH  = 3'b010,   // 读取Header
        DISP_PAYLOAD_FETCH = 3'b011,   // 读取Payload
        DISP_TASK_DISPATCH = 3'b100,   // 任务分发
        DISP_DONE          = 3'b101,   // 完成状态
        DISP_ERROR         = 3'b110    // 错误状态
    } disp_state_t;
    
    // NOC接口状态机
    typedef enum logic [2:0] {
        NOC_IDLE          = 3'b000,
        NOC_SEND_REQ      = 3'b001,
        NOC_WAIT_RESP     = 3'b010,
        NOC_PROC_RESP     = 3'b011
    } noc_state_t;
    
    //=============================================================================
    // Internal Registers and Signals
    //=============================================================================
    
    // 状态机
    disp_state_t current_state, next_state;
    noc_state_t noc_state, noc_state_next;
    
    // Package处理相关寄存器
    logic [63:0] current_package_addr;   // 当前Package地址
    command_header_t current_header;     // 当前Package Header
    logic [CONTROL_UNIT_CONFIG.max_payload_size*8-1:0] current_payload; // 当前Package Payload
    
    // 内部信号
    logic header_fetch_done;             // Header读取完成
    logic payload_fetch_done;            // Payload读取完成
    logic task_dispatch_done;            // 任务分发完成
    logic error_detected;                // 错误检测
    logic mmu_config_done;               // MMU配置完成
    
    // NOC相关信号
    logic [7:0] noc_transaction_id;      // NOC事务ID
    logic [31:0] noc_read_addr;          // NOC读取地址
    logic [15:0] noc_read_size;          // NOC读取大小
    
    // MMU相关信号
    logic [47:0] mmu_paddr;              // MMU物理地址
    logic mmu_translation_done;          // MMU转换完成
    logic mmu_page_fault;                // MMU页面错误
    
    //=============================================================================
    // Dispatcher Main State Machine
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            current_state <= DISP_IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            DISP_IDLE: begin
                if (jd_if.enable) begin
                    next_state = DISP_MMU_CONFIG;
                end
            end
            
            DISP_MMU_CONFIG: begin
                if (mmu_config_done) begin
                    next_state = DISP_HEADER_FETCH;
                end else if (error_detected) begin
                    next_state = DISP_ERROR;
                end
            end
            
            DISP_HEADER_FETCH: begin
                if (header_fetch_done) begin
                    next_state = DISP_PAYLOAD_FETCH;
                end else if (error_detected) begin
                    next_state = DISP_ERROR;
                end
            end
            
            DISP_PAYLOAD_FETCH: begin
                if (payload_fetch_done) begin
                    next_state = DISP_TASK_DISPATCH;
                end else if (error_detected) begin
                    next_state = DISP_ERROR;
                end
            end
            
            DISP_TASK_DISPATCH: begin
                if (task_dispatch_done) begin
                    next_state = DISP_DONE;
                end else if (error_detected) begin
                    next_state = DISP_ERROR;
                end
            end
            
            DISP_DONE: begin
                next_state = DISP_IDLE;
            end
            
            DISP_ERROR: begin
                next_state = DISP_IDLE;
            end
            
            default: begin
                next_state = DISP_IDLE;
            end
        endcase
    end
    
    //=============================================================================
    // Package Address Management
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            current_package_addr <= 64'h0;
        end else begin
            if (jd_if.enable) begin
                current_package_addr <= jd_if.package_addr;
            end
        end
    end
    
    //=============================================================================
    // NOC Interface State Machine
    //=============================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            noc_state <= NOC_IDLE;
        end else begin
            noc_state <= noc_state_next;
        end
    end
    
    always_comb begin
        noc_state_next = noc_state;
        noc_if.m_req_valid = 1'b0;
        noc_if.m_req_header = 32'h0;
        noc_if.m_req_data = 256'h0;
        noc_if.m_req_strb = 32'h0;
        noc_if.m_req_last = 1'b0;
        noc_if.m_resp_ready = 1'b0;
        
        case (noc_state)
            NOC_IDLE: begin
                // 根据当前状态决定是否发起NOC请求
                if (current_state == DISP_HEADER_FETCH || current_state == DISP_PAYLOAD_FETCH) begin
                    noc_state_next = NOC_SEND_REQ;
                end
            end
            
            NOC_SEND_REQ: begin
                noc_if.m_req_valid = 1'b1;
                noc_if.m_req_header = {8'h02, noc_transaction_id, 4'h0, 4'h1, 8'h00}; // MEM_READ_REQ
                noc_if.m_req_data[63:0] = {noc_read_addr, noc_read_size, 16'h0};
                noc_if.m_req_strb = 32'hFF;
                noc_if.m_req_last = 1'b1;
                
                if (noc_if.m_req_ready) begin
                    noc_state_next = NOC_WAIT_RESP;
                end
            end
            
            NOC_WAIT_RESP: begin
                noc_if.m_resp_ready = 1'b1;
                if (noc_if.m_resp_valid) begin
                    noc_state_next = NOC_PROC_RESP;
                end
            end
            
            NOC_PROC_RESP: begin
                noc_if.m_resp_ready = 1'b1;
                if (noc_if.m_resp_last) begin
                    noc_state_next = NOC_IDLE;
                end
            end
        endcase
    end
    
    //=============================================================================
    // Package Processing Logic
    //=============================================================================
    
    // Header fetch logic
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            header_fetch_done <= 1'b0;
            current_header <= '{default: 1'b0};
        end else begin
            if (current_state == DISP_HEADER_FETCH) begin
                if (noc_state == NOC_PROC_RESP && noc_if.m_resp_valid && noc_if.m_resp_last) begin
                    current_header <= noc_if.m_resp_data[63:0]; // 读取64位Header
                    header_fetch_done <= 1'b1;
                end
            end else begin
                header_fetch_done <= 1'b0;
            end
        end
    end
    
    // Payload fetch logic  
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            payload_fetch_done <= 1'b0;
        end else begin
            if (current_state == DISP_PAYLOAD_FETCH) begin
                if (noc_state == NOC_PROC_RESP && noc_if.m_resp_valid && noc_if.m_resp_last) begin
                    // 存储Payload数据
                    current_payload <= noc_if.m_resp_data[CONTROL_UNIT_CONFIG.max_payload_size*8-1:0];
                    payload_fetch_done <= 1'b1;
                end
            end else begin
                payload_fetch_done <= 1'b0;
            end
        end
    end
    
    // Task dispatch logic
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            task_dispatch_done <= 1'b0;
        end else begin
            if (current_state == DISP_TASK_DISPATCH) begin
                // 简化的任务分发逻辑，实际应该根据命令类型分发到不同单元
                task_dispatch_done <= 1'b1;
            end else begin
                task_dispatch_done <= 1'b0;
            end
        end
    end
    
    //=============================================================================
    // MMU Interface Logic
    //=============================================================================
    
    // MMU请求信号生成
    always_comb begin
        mmu_if.req_valid = 1'b0;
        mmu_if.req_vaddr = 48'h0;
        mmu_if.req_read = 1'b0;
        mmu_if.req_write = 1'b0;
        
        case (current_state)
            DISP_MMU_CONFIG: begin
                if (!mmu_config_done) begin
                    mmu_if.req_valid = 1'b1;
                    mmu_if.req_vaddr = jd_if.mmu_addr[47:0];
                    mmu_if.req_read = 1'b1;
                    mmu_if.req_write = 1'b0;
                end
            end
            
            DISP_HEADER_FETCH: begin
                if (noc_state == NOC_IDLE && !header_fetch_done) begin
                    mmu_if.req_valid = 1'b1;
                    mmu_if.req_vaddr = current_package_addr[47:0];
                    mmu_if.req_read = 1'b1;
                    mmu_if.req_write = 1'b0;
                end
            end
            
            DISP_PAYLOAD_FETCH: begin
                if (noc_state == NOC_IDLE && !payload_fetch_done) begin
                    mmu_if.req_valid = 1'b1;
                    mmu_if.req_vaddr = (current_package_addr + 8)[47:0];
                    mmu_if.req_read = 1'b1;
                    mmu_if.req_write = 1'b0;
                end
            end
        endcase
    end
    
    // MMU响应处理
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mmu_translation_done <= 1'b0;
            mmu_paddr <= 48'h0;
            mmu_page_fault <= 1'b0;
        end else begin
            mmu_if.resp_ready <= 1'b1;
            
            if (mmu_if.resp_valid) begin
                case (current_state)
                    DISP_MMU_CONFIG: begin
                        if (mmu_if.resp_status == 2'b00) begin
                            mmu_config_done <= 1'b1;
                        end else begin
                            mmu_page_fault <= 1'b1;
                        end
                    end
                    
                    DISP_HEADER_FETCH, DISP_PAYLOAD_FETCH: begin
                        if (mmu_if.resp_status == 2'b00) begin
                            mmu_paddr <= mmu_if.resp_paddr;
                            mmu_translation_done <= 1'b1;
                        end else begin
                            mmu_page_fault <= 1'b1;
                        end
                    end
                endcase
            end else begin
                mmu_translation_done <= 1'b0;
                if (current_state == DISP_IDLE) begin
                    mmu_page_fault <= 1'b0;
                    mmu_config_done <= 1'b0;
                end
            end
        end
    end
    
    //=============================================================================
    // NOC Address and Size Logic
    //=============================================================================
    
    always_comb begin
        noc_transaction_id = 8'h00;
        noc_read_addr = 32'h0;
        noc_read_size = 16'h0;
        
        case (current_state)
            DISP_HEADER_FETCH: begin
                if (mmu_translation_done) begin
                    noc_read_addr = mmu_paddr[31:0];  // 使用MMU转换后的物理地址
                    noc_read_size = 16'h8; // 8字节Header
                end
            end
            
            DISP_PAYLOAD_FETCH: begin
                if (mmu_translation_done) begin
                    noc_read_addr = mmu_paddr[31:0];  // 使用MMU转换后的物理地址
                    noc_read_size = current_header.payload_size;
                end
            end
        endcase
    end
    
    //=============================================================================
    // Error Detection Logic
    //=============================================================================
    
    always_comb begin
        error_detected = 1'b0;
        
        // MMU错误检测
        if (mmu_page_fault) begin
            error_detected = 1'b1;
        end
        
        // NOC错误检测  
        if (noc_if.m_resp_valid && noc_if.m_resp_status != 2'b00) begin
            error_detected = 1'b1;
        end
        
        // 非法命令类型检测
        if (current_state == DISP_PAYLOAD_FETCH && header_fetch_done) begin
            if (current_header.command_type != CMD_COMPUTE_JOB && 
                current_header.command_type != CMD_MEMORY_COPY &&
                current_header.command_type != CMD_SYNCHRONIZATION) begin
                error_detected = 1'b1;
            end
        end
        
        // Payload大小检查
        if (current_state == DISP_PAYLOAD_FETCH && header_fetch_done) begin
            if (current_header.payload_size > CONTROL_UNIT_CONFIG.max_payload_size) begin
                error_detected = 1'b1;
            end
        end
    end
    
    //=============================================================================
    // Output Register Logic (简化接口)
    //=============================================================================
    
    // 状态输出寄存器
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            jd_if.busy <= 1'b0;
            jd_if.error <= 1'b0;
            jd_if.complete <= 1'b0;
        end else begin
            // 忙碌状态：不在空闲状态
            jd_if.busy <= (current_state != DISP_IDLE);
            
            // 错误状态：错误状态或有错误检测
            jd_if.error <= (current_state == DISP_ERROR) || error_detected;
            
            // 完成状态：正常完成
            jd_if.complete <= (current_state == DISP_DONE) && !error_detected;
        end
    end

endmodule : rvgpu_job_dispatcher

`endif // RVGPU_JOB_DISPATCHER_SV 