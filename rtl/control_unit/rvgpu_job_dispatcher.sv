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
`include "rvgpu_job_block.svh"

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
    typedef enum logic [2:0] {
        STATE_IDLE = 3'd0,
        STATE_MMU_REQ = 3'd1,
        STATE_MMU_WAIT = 3'd2,
        STATE_NOC_REQ = 3'd3,
        STATE_NOC_WAIT = 3'd4,
        STATE_BLOCK_DISPATCH = 3'd5,
        STATE_DISPATCH_WAIT = 3'd6,
        STATE_DONE = 3'd7
    } main_state_e;

    typedef struct packed {
        logic [3:0] core_id;
        logic [15:0] block_id;
    } block_core_entry_t;

    //==================== 状态寄存器段 ====================
    main_state_e state_r, state_n;
    logic [`SHADER_CORE_NUMBER-1:0] shadercore_busy_r, shadercore_busy_n;
    logic [$clog2(`SHADER_CORE_NUMBER)-1:0] shadercore_sel_r, shadercore_sel_n;
    command_t command_r, command_n;
    logic [63:0] command_addr_r, command_addr_n;
    logic [15:0] total_blocks_r, total_blocks_n;
    logic [15:0] block_idx_r, block_idx_n;
    job_block_t job_block_r, job_block_n;
    block_core_entry_t block_core_fifo_r [7:0], block_core_fifo_n [7:0];
    logic [2:0] fifo_head_r, fifo_head_n, fifo_tail_r, fifo_tail_n;
    logic [7:0] error_status_r, error_status_n;
    logic [63:0] package_addr_r, package_addr_n;
    logic [63:0] mmu_base_r, mmu_base_n;
    logic [47:0] mmu_paddr_r, mmu_paddr_n;

    //==================== 组合逻辑段 ====================
    // FIFO状态
    logic fifo_full_n, fifo_empty_n;
    assign fifo_full_n = ((fifo_tail_r + 1) % 8) == fifo_head_r;
    assign fifo_empty_n = fifo_head_r == fifo_tail_r;

    // arglist_ptr
    logic [63:0] arglist_ptr_n;
    assign arglist_ptr_n = command_addr_r + 64'd32;

    // 错误状态位定义
    localparam ERROR_BIT_MMU_FAULT     = 0;
    localparam ERROR_BIT_NOC_ERROR     = 1;
    localparam ERROR_BIT_INVALID_CMD   = 2;
    localparam ERROR_BIT_PAYLOAD_SIZE  = 3;
    localparam ERROR_BIT_ADDR_ALIGN    = 4;
    localparam ERROR_BIT_PHASE_ERROR   = 5;
    localparam ERROR_BIT_TIMEOUT       = 6;
    localparam ERROR_BIT_UNKNOWN       = 7;

    // next_shadercore_sel函数
    function automatic noc_node_id_t next_shadercore_sel(input logic [`SHADER_CORE_NUMBER-1:0] busy_vec, input int last_sel);
        int i;
        for (i = 1; i <= `SHADER_CORE_NUMBER; i++) begin
            int idx = (last_sel + i) % `SHADER_CORE_NUMBER;
            if (!busy_vec[idx]) begin
                return noc_node_id_t'(2 + idx); // NODE_SHADER_0 = 2
            end
        end
        return noc_node_id_t'(2 + last_sel); // fallback
    endfunction

    always_comb begin
        // 默认赋值
        state_n = state_r;
        shadercore_busy_n = shadercore_busy_r;
        shadercore_sel_n = shadercore_sel_r;
        command_n = command_r;
        command_addr_n = command_addr_r;
        total_blocks_n = total_blocks_r;
        block_idx_n = block_idx_r;
        job_block_n = job_block_r;
        block_core_fifo_n = block_core_fifo_r;
        fifo_head_n = fifo_head_r;
        fifo_tail_n = fifo_tail_r;
        error_status_n = error_status_r;
        package_addr_n = package_addr_r;
        mmu_base_n = mmu_base_r;
        mmu_paddr_n = mmu_paddr_r;

        // MMU/NOC接口默认
        mmu_if.req_valid = 1'b0;
        mmu_if.req_vaddr = package_addr_r[47:0];
        mmu_if.req_read = 1'b1;
        mmu_if.req_write = 1'b0;
        mmu_if.resp_ready = 1'b0;
        mmu_if.cfg_en = 1'b0;
        mmu_if.cfg_base_addr = jd_if.mmu_addr[47:0];
        noc_if.m_req_valid  = 1'b0;
        noc_if.m_req_header = '0;
        noc_if.m_req_data   = '0;
        noc_if.m_req_strb   = 32'h0;
        noc_if.m_req_last   = 1'b0;

        // 状态机
        case (state_r)
            STATE_IDLE: begin
                if (jd_if.enable) begin
                    state_n = STATE_MMU_REQ;
                    package_addr_n = jd_if.package_addr;
                    mmu_base_n = jd_if.mmu_addr;
                    mmu_if.cfg_en = 1'b1;
                    mmu_if.cfg_base_addr = jd_if.mmu_addr[47:0];
                    `DEBUG_PRINT("JD", $sformatf("JD enable, package_addr: 0x%h, mmu_addr: 0x%h", jd_if.package_addr, jd_if.mmu_addr));
                end
            end
            STATE_MMU_REQ: begin
                mmu_if.req_valid = 1'b1;
                mmu_if.req_vaddr = package_addr_r[47:0];
                mmu_if.req_read = 1'b1;
                mmu_if.req_write = 1'b0;
                if (mmu_if.req_valid && mmu_if.req_ready) begin
                    state_n = STATE_MMU_WAIT;
                end
            end
            STATE_MMU_WAIT: begin
                mmu_if.resp_ready = 1'b1;
                if (mmu_if.resp_valid && mmu_if.resp_ready) begin
                    if (mmu_if.resp_status == 2'b00) begin
                        mmu_paddr_n = mmu_if.resp_paddr;
                        state_n = STATE_NOC_REQ;
                    end else begin
                        state_n = STATE_IDLE;
                        error_status_n[ERROR_BIT_MMU_FAULT] = 1'b1;
                    end
                end
            end
            STATE_NOC_REQ: begin
                noc_if.m_req_valid  = 1'b1;
                noc_if.m_req_header = build_noc_header_mem_request(8'h01, NODE_CONTROL, NOC_NODE_CONTROL_JD);
                noc_if.m_req_data   = build_noc_payload_request_mem_read(mmu_paddr_r, NOC_SIZE_8B);
                noc_if.m_req_strb   = 32'hFF;
                noc_if.m_req_last   = 1'b1;
                if (noc_if.m_req_valid && noc_if.m_req_ready) begin
                    state_n = STATE_NOC_WAIT;
                end
            end
            STATE_NOC_WAIT: begin
                if (noc_if.m_resp_valid && noc_if.m_resp_ready) begin
                    if (noc_if.m_resp_status == 2'b00) begin
                        command_n = noc_if.m_resp_data;
                        total_blocks_n = command_get_block_count(noc_if.m_resp_data);
                        block_idx_n = 0;
                        state_n = STATE_BLOCK_DISPATCH;
                        `DEBUG_PRINT("JD", $sformatf("NOC Response: %s", command_to_string(noc_if.m_resp_data)));
                    end else begin
                        state_n = STATE_IDLE;
                        error_status_n[ERROR_BIT_NOC_ERROR] = 1'b1;
                    end
                end
            end
            STATE_BLOCK_DISPATCH: begin
                if (block_idx_r < total_blocks_r && (|(~shadercore_busy_r)) && !fifo_full_n) begin
                    noc_node_id_t selected_core;
                    selected_core = next_shadercore_sel(shadercore_busy_r, shadercore_sel_r);
                    job_block_n = build_job_block(arglist_ptr_n, command_r.prog.argument_size, command_r.prog.program_addr,block_idx_r);
                    noc_if.m_req_valid  = 1'b1;
                    noc_if.m_req_header = build_noc_header_jobblock_dispatch(8'h01, selected_core);
                    noc_if.m_req_data   = job_block_n;
                    noc_if.m_req_strb   = 32'hFF;
                    noc_if.m_req_last   = 1'b1;
                    shadercore_busy_n[selected_core - 2] = 1'b1;
                    block_core_fifo_n = block_core_fifo_r;
                    block_core_fifo_n[fifo_tail_r].core_id = selected_core;
                    block_core_fifo_n[fifo_tail_r].block_id = block_idx_r;
                    fifo_tail_n = (fifo_tail_r + 1) % 8;
                    `DEBUG_PRINT("JD", $sformatf("Dispatch block %0d to core %0d", block_idx_r, selected_core));
                    state_n = STATE_DISPATCH_WAIT;
                end else if (block_idx_r >= total_blocks_r) begin
                    state_n = STATE_DONE;
                end
            end
            STATE_DISPATCH_WAIT: begin
                if (noc_if.m_resp_valid && noc_if.m_resp_ready && noc_if.m_resp_status == 2'b00 && !fifo_empty_n) begin
                    logic [3:0] resp_core_id;
                    resp_core_id = block_core_fifo_r[fifo_head_r].core_id;
                    shadercore_busy_n[resp_core_id - 2] = 1'b0;
                    block_idx_n = block_idx_r + 1;
                    fifo_head_n = (fifo_head_r + 1) % 8;
                    `DEBUG_PRINT("JD", $sformatf("Core %0d finished block %0d", resp_core_id, block_core_fifo_r[fifo_head_r].block_id));
                    if ((block_idx_r + 1) < total_blocks_r) begin
                        state_n = STATE_BLOCK_DISPATCH;
                    end else begin
                        state_n = STATE_DONE;
                    end
                end
            end
            STATE_DONE: begin
                state_n = STATE_IDLE;
            end
            default: begin
                state_n = STATE_IDLE;
            end
        endcase

        // 错误检测
        error_status_n[ERROR_BIT_MMU_FAULT] = mmu_if.resp_valid && (mmu_if.resp_status != 2'b00);
        error_status_n[ERROR_BIT_NOC_ERROR] = noc_if.m_resp_valid && (noc_if.m_resp_status != 2'b00);
    end

    //==================== 时序逻辑：寄存器更新 ====================
    always_ff @(posedge clk) begin
        if (!rst_n || jd_if.reset) begin
            state_r <= STATE_IDLE;
            shadercore_busy_r <= '0;
            shadercore_sel_r <= 0;
            command_r <= '0;
            command_addr_r <= 64'h0;
            total_blocks_r <= 0;
            block_idx_r <= 0;
            job_block_r <= '0;
            block_core_fifo_r <= '{default: '0};
            fifo_head_r <= 0;
            fifo_tail_r <= 0;
            error_status_r <= 8'h0;
            package_addr_r <= 64'h0;
            mmu_base_r <= 64'h0;
            mmu_paddr_r <= 48'h0;
        end else begin
            state_r <= state_n;
            shadercore_busy_r <= shadercore_busy_n;
            shadercore_sel_r <= shadercore_sel_n;
            command_r <= command_n;
            command_addr_r <= command_addr_n;
            total_blocks_r <= total_blocks_n;
            block_idx_r <= block_idx_n;
            job_block_r <= job_block_n;
            block_core_fifo_r <= block_core_fifo_n;
            fifo_head_r <= fifo_head_n;
            fifo_tail_r <= fifo_tail_n;
            error_status_r <= error_status_n;
            package_addr_r <= package_addr_n;
            mmu_base_r <= mmu_base_n;
            mmu_paddr_r <= mmu_paddr_n;
        end
    end

    //==================== 输出段 ====================
    logic busy_o, complete_o, error_o;
    logic [7:0] error_status_o;
    assign busy_o = (state_r != STATE_IDLE) || (state_r == STATE_BLOCK_DISPATCH);
    assign complete_o = (state_r == STATE_DONE) && (error_status_r == 8'h00);
    assign error_o = (error_status_r != 8'h00);
    assign error_status_o = error_status_r;

    assign jd_if.busy = busy_o;
    assign jd_if.error = error_o;
    assign jd_if.error_status = error_status_o;
    assign jd_if.complete = complete_o;

    //==================== 调试输出 ====================
    generate
    if (CU_CONFIG.debug) begin : gen_debug
        always_ff @(posedge clk) begin
            if (state_r == STATE_MMU_WAIT && mmu_if.resp_valid && mmu_if.resp_ready) begin
                `DEBUG_PRINT("JD", $sformatf("MMU Wait accept, pa is: 0x%h", mmu_if.resp_paddr));
            end
            if (state_r == STATE_NOC_WAIT && noc_if.m_resp_valid && noc_if.m_resp_ready) begin
                `DEBUG_PRINT("JD", $sformatf("NOC Wait, Noc response: %s", noc_response_mem_read_to_string(noc_if.m_resp_header, noc_if.m_resp_data)));
            end
        end
    end
    endgenerate

endmodule : rvgpu_job_dispatcher

`endif // RVGPU_JOB_DISPATCHER_SV 