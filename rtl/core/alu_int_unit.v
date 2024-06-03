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

module alu_int_unit(
    clk,
    reset_n,
    eu_iu_inst_opcode,
    eu_iu_inst_src0,
    eu_iu_inst_src1,
    eu_iu_inst_src2,
    eu_iu_inst_dst_id,
    iu_rb_dst_id,
    iu_rb_data,
    iu_rb_data_valid
);

input                       clk;
input                       reset_n;
input           [7  :0]     eu_iu_inst_opcode;
input           [63 :0]     eu_iu_inst_src0;
input           [63 :0]     eu_iu_inst_src1;
input           [63 :0]     eu_iu_inst_src2;
input           [7  :0]     eu_iu_inst_dst_id;
output  reg     [7  :0]     iu_rb_dst_id;
output  reg     [63 :0]     iu_rb_data;
output  reg                 iu_rb_data_valid;   

reg [63:0]  result_data;

always @(posedge clk or negedge reset_n)
begin
    if (!reset_n) begin
        iu_rb_dst_id[7:0]   <= 8'h00;
        iu_rb_data[63:0]    <= 64'h0000000000000000;
        iu_rb_data_valid    <= 0;
        result_data[63:0]   <= 64'h0000000000000000;
    end
    else begin
        iu_rb_data_valid    <= 0;
        iu_rb_dst_id[7:0]   <= eu_iu_inst_dst_id;

        case (eu_iu_inst_opcode)
            `OPCODE_ADD: begin
                result_data <= eu_iu_inst_src0 + eu_iu_inst_src1;  
                iu_rb_data_valid <= 1; 
            end
            `OPCODE_SUB: begin
                result_data         <= eu_iu_inst_src0 - eu_iu_inst_src1;
                iu_rb_data_valid    <= 1;
            end
            default:
                iu_rb_data_valid    <= 0;
        endcase
    end

    $display("@%0t ADD: data is: %x = %x + %x", $time, result_data, eu_iu_inst_src0, eu_iu_inst_src1);
    iu_rb_data <= result_data;
end


endmodule