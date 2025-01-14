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

`include "rvgpu_config.vh"

module rcore_ifu_icache_tag_array(
  forever_cpuclk,
  icache_tag_cen,
  icache_tag_din,
  icache_tag_dout,
  icache_tag_idx,
  icache_tag_wen
);

input           forever_cpuclk;    
input           icache_tag_cen;    
input   [58:0]  icache_tag_din;    
input   [8 :0]  icache_tag_idx;    
input   [2 :0]  icache_tag_wen;    
output  [58:0]  icache_tag_dout;   

wire            forever_cpuclk;    
wire    [58:0]  icache_tag_bwen_b; 
wire            icache_tag_cen;    
wire            icache_tag_cen_b;  
wire            icache_tag_clk;    
wire    [58:0]  icache_tag_din;    
wire    [58:0]  icache_tag_dout;   
wire            icache_tag_gwen_b; 
wire            icache_tag_icg_en; 
wire    [8 :0]  icache_tag_idx;    
wire    [7 :0]  icache_tag_index;  
wire    [2 :0]  icache_tag_wen;    


parameter TAG_INDEX = `ICACHE_TAG_INDEX_WIDTH;

//==========================================================
// Icache Tag Array Module
// 1. Instance ICG Cell
// 2. Transmit Port Signals
// 3. Instance Memory Cell 
//==========================================================

//------------------------------------------------
// 1. Instance ICG Cell
//------------------------------------------------
assign icache_tag_icg_en = icache_tag_cen;
gated_clk_cell  x_icache_tag_icg_cell (
  .clk_in             (forever_cpuclk    ),
  .clk_out            (icache_tag_clk    ),
  .external_en        (1'b0              ),
  .global_en          (1'b0              ),
  .local_en           (icache_tag_icg_en ),
  .module_en          (1'b0              ),
  .pad_yy_icg_scan_en (1'b0              )
);

//------------------------------------------------
// 2. Transmit Port Signals
//------------------------------------------------
// reverse the negtive effect signals
assign icache_tag_cen_b  = !icache_tag_cen;
assign icache_tag_gwen_b = !(|icache_tag_wen[2:0]);

assign icache_tag_bwen_b[58:0] = ~{icache_tag_wen[2],  //fifo
                                  {29{icache_tag_wen[1]}},  //way1
                                  {29{icache_tag_wen[0]}}   //way0
                                  };

assign icache_tag_index[TAG_INDEX-1:0] = icache_tag_idx[TAG_INDEX-1:0];

//------------------------------------------------
// 3. Instance Memory Cell 
//------------------------------------------------
rvgpu_spsram_256x59  x_rvgpu_spsram_256x59 (
  .A                 (icache_tag_index ),
  .CEN               (icache_tag_cen_b ),
  .CLK               (icache_tag_clk   ),
  .D                 (icache_tag_din   ),
  .GWEN              (icache_tag_gwen_b),
  .Q                 (icache_tag_dout  ),
  .WEN               (icache_tag_bwen_b)
);

endmodule


