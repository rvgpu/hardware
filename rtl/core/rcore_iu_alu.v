/*
Copyright © 2023 Sietium Semiconductor.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0
  
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

`include "opcode.vh"

module rcore_iu_alu(
    clk,
    rst_n,
    idu_iu_pipe_sel,
    idu_iu_inst_opcode,
    idu_iu_inst_src0,
    idu_iu_inst_src1,
    idu_iu_inst_src2,
    idu_iu_inst_dstid,
    iu_rb_dstid,
    iu_rb_data_vld,
    iu_rb_data
);

input                       clk;
input                       rst_n;
input                       idu_iu_pipe_sel;
input           [7  :0]     idu_iu_inst_opcode;
input           [63 :0]     idu_iu_inst_src0;
input           [63 :0]     idu_iu_inst_src1;
input           [63 :0]     idu_iu_inst_src2;
input           [7  :0]     idu_iu_inst_dstid;
output          [7  :0]     iu_rb_dstid;
output          [63 :0]     iu_rb_data;
output                      iu_rb_data_vld;  

wire                        idu_iu_pipe_sel;
wire            [7  :0]     idu_iu_inst_opcode;
wire            [63 :0]     idu_iu_inst_src0;
wire            [63 :0]     idu_iu_inst_src1;
wire            [63 :0]     idu_iu_inst_src2;
wire            [7  :0]     idu_iu_inst_dstid;
wire            [7  :0]     iu_rb_dstid;
wire            [63 :0]     iu_rb_data;
wire                        iu_rb_data_vld;  

// Register
reg             [7  :0]     inst_opcode_r;
reg             [63 :0]     inst_src0_r;
reg             [63 :0]     inst_src1_r;
reg             [63 :0]     inst_src2_r;
reg             [7  :0]     inst_dstid_r;
reg             [63 :0]     result_data_r;
reg                         result_data_vld_r;

wire            [63:0]      adder_dataout_add64;
wire            [63:0]      adder_dataout_sub64;
wire            [31:0]      adder_dataout_add32;
wire            [31:0]      adder_dataout_sub32;

reg             [63:0]      result_data_adder;

always @(posedge clk or negedge rst_n)
begin
    if (!rst_n) begin
        result_data_vld_r       <= 1'b0;
    end
    else begin
        result_data_vld_r       <= idu_iu_pipe_sel;
    end
end

// Instruction Data
always @(posedge clk or negedge rst_n)
begin
    if (!rst_n) begin
        inst_opcode_r[7:0]      <= 8'b0;
        inst_src0_r[63:0]       <= 64'b0;
        inst_src1_r[63:0]       <= 64'b0;
        inst_src2_r[63:0]       <= 64'b0;
        inst_dstid_r[7:0]       <= 8'b0;
    end
    else if (idu_iu_pipe_sel) begin
        inst_opcode_r[7:0]      <= idu_iu_inst_opcode[7:0];
        inst_src0_r[63:0]       <= idu_iu_inst_src0[63:0];
        inst_src1_r[63:0]       <= idu_iu_inst_src1[63:0];
        inst_src2_r[63:0]       <= idu_iu_inst_src2[63:0];
        inst_dstid_r[7:0]       <= idu_iu_inst_dstid[7:0];
    end
    else begin
        inst_opcode_r[7:0]      <= inst_opcode_r[7:0];
        inst_src0_r[63:0]       <= inst_src0_r[63:0];
        inst_src1_r[63:0]       <= inst_src1_r[63:0];
        inst_src2_r[63:0]       <= inst_src2_r[63:0];
        inst_dstid_r[7:0]       <= inst_dstid_r[7:0];
    end
end

// ADD/SUB
assign adder_dataout_add64[63:0]    = inst_src0_r[63:0] + inst_src1_r[63:0];
assign adder_dataout_add32[31:0]    = inst_src0_r[31:0] + inst_src1_r[31:0];
assign adder_dataout_sub64[63:0]    = inst_src0_r[63:0] - inst_src1_r[63:0];
assign adder_dataout_sub32[31:0]    = inst_src0_r[31:0] - inst_src1_r[31:0];

always @( inst_opcode_r[3:0]
       or adder_dataout_add64[63:0]
       or adder_dataout_add32[31:0]
       or adder_dataout_sub64[63:0]
       or adder_dataout_sub32[31:0])
begin
    case (inst_opcode_r[3:0])
    4'h1:       result_data_adder[63:0] = adder_dataout_add64[63:0];
    4'h2:       result_data_adder[63:0] = {{32{adder_dataout_add32[31]}}, adder_dataout_add32[31:0]};
    4'h4:       result_data_adder[63:0] = adder_dataout_sub64[63:0];
    4'h8:       result_data_adder[63:0] = {{32{adder_dataout_sub32[31]}}, adder_dataout_add32[31:0]};
    default:    result_data_adder[63:0] = {64{1'bx}};
    endcase
end

assign result_data_r[63:0]      = result_data_adder[63:0];

assign iu_rb_data_vld           = result_data_vld_r;
assign iu_rb_dstid[7:0]         = inst_dstid_r;
assign iu_rb_data[63:0]         = result_data_r[63:0];

endmodule
