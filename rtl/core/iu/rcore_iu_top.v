/*
Copyright © 2024 Sietium Semiconductor.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0
  
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Portions of this file are derived from the following projects:  
 - openc906 (https://github.com/XUANTIE-RV/openc906)  
   Licensed under the Apache License, Version 2.0 
*/

module rcore_iu_top(
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
input           [4  :0]     idu_iu_pipe_sel;
input           [7  :0]     idu_iu_inst_opcode;
input           [63 :0]     idu_iu_inst_src0;
input           [63 :0]     idu_iu_inst_src1;
input           [63 :0]     idu_iu_inst_src2;
input           [7  :0]     idu_iu_inst_dstid;
output          [7  :0]     iu_rb_dstid;
output          [63 :0]     iu_rb_data;
output                      iu_rb_data_vld;

wire            [7  :0]     idu_iu_inst_opcode_w;
wire            [63 :0]     idu_iu_inst_src0_w;
wire            [63 :0]     idu_iu_inst_src1_w;
wire            [63 :0]     idu_iu_inst_src2_w;
wire            [7  :0]     idu_iu_inst_dstid_w;
wire                        idu_iu_pipe_sel_alu;

rcore_iu_alu x_rcore_iu_alu (
  .clk                      (clk),
  .rst_n                    (rst_n),
  .idu_iu_pipe_sel          (idu_iu_pipe_sel_alu),
  .idu_iu_inst_opcode       (idu_iu_inst_opcode_w),
  .idu_iu_inst_src0         (idu_iu_inst_src0_w),
  .idu_iu_inst_src1         (idu_iu_inst_src1_w),
  .idu_iu_inst_src2         (idu_iu_inst_src2_w),
  .idu_iu_inst_dstid        (idu_iu_inst_dstid_w),
  .iu_rb_dstid              (iu_rb_dstid),
  .iu_rb_data_vld           (iu_rb_data_vld),
  .iu_rb_data               (iu_rb_data)
);

assign idu_iu_inst_opcode_w[7:0] = idu_iu_inst_opcode[7:0];
assign idu_iu_inst_src0_w[63:0]  = idu_iu_inst_src0[63 :0];
assign idu_iu_inst_src1_w[63:0]  = idu_iu_inst_src1[63:0];
assign idu_iu_inst_src2_w[63:0]  = idu_iu_inst_src2[63:0];
assign idu_iu_inst_dstid_w[7:0]  = idu_iu_inst_dstid[7:0];
assign idu_iu_pipe_sel_alu       = idu_iu_pipe_sel[0];

endmodule
