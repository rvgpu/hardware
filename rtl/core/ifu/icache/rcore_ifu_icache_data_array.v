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

module rcore_ifu_icache_data_array(
  forever_cpuclk,
  icache_data0_dout,
  icache_data1_dout,
  icache_data2_dout,
  icache_data3_dout,
  icache_data_din,
  icache_data_idx,
  icache_data_ren,
  icache_data_wen,
  iop_rd_data,
  iop_rd_way
);

input            forever_cpuclk;      
input   [127:0]  icache_data_din;     
input   [13 :0]  icache_data_idx;     
input   [1  :0]  icache_data_ren;     
input   [1  :0]  icache_data_wen;     
input            iop_rd_data;         
input            iop_rd_way;          
output  [31 :0]  icache_data0_dout;   
output  [31 :0]  icache_data1_dout;   
output  [31 :0]  icache_data2_dout;   
output  [31 :0]  icache_data3_dout;   

wire             forever_cpuclk;      
wire             icache_data0_cen_b;  
wire             icache_data0_clk;    
wire    [31 :0]  icache_data0_din;    
wire    [31 :0]  icache_data0_dout;   
wire             icache_data0_icg_en; 
wire    [10 :0]  icache_data0_idx;    
wire             icache_data1_cen_b;  
wire             icache_data1_clk;    
wire    [31 :0]  icache_data1_din;    
wire    [31 :0]  icache_data1_dout;   
wire             icache_data1_icg_en; 
wire    [10 :0]  icache_data1_idx;    
wire             icache_data2_cen_b;  
wire             icache_data2_clk;    
wire    [31 :0]  icache_data2_din;    
wire    [31 :0]  icache_data2_dout;   
wire             icache_data2_icg_en; 
wire    [10 :0]  icache_data2_idx;    
wire             icache_data3_cen_b;  
wire             icache_data3_clk;    
wire    [31 :0]  icache_data3_din;    
wire    [31 :0]  icache_data3_dout;   
wire             icache_data3_icg_en; 
wire    [10 :0]  icache_data3_idx;    
wire    [31 :0]  icache_data_bwen_b;  
wire    [127:0]  icache_data_din;     
wire             icache_data_gwen_b;  
wire    [13 :0]  icache_data_idx;     
wire    [10 :0]  icache_data_idx_high; 
wire    [10 :0]  icache_data_idx_low; 
wire    [1  :0]  icache_data_ren;     
wire    [1  :0]  icache_data_wen;     
wire             icache_data_wr;      
wire             iop_rd_data;         
wire             iop_rd_way;          

parameter DATA_INDEX = `ICACHE_DATA_INDEX_WIDTH;

//==========================================================
// Icache Data Array Module
// 1. Instance ICG Cell
// 2. Transmit Port Signals
// 3. Instance Memory Cell 
//==========================================================

//------------------------------------------------
// 1. Instance ICG Cell
//------------------------------------------------
assign icache_data3_icg_en = !icache_data3_cen_b;
assign icache_data2_icg_en = !icache_data2_cen_b;
assign icache_data1_icg_en = !icache_data1_cen_b;
assign icache_data0_icg_en = !icache_data0_cen_b;

gated_clk_cell  x_icache_data3_icg_cell (
  .clk_in               (forever_cpuclk      ),
  .clk_out              (icache_data3_clk    ),
  .external_en          (1'b0                ),
  .global_en            (1'b0                ),
  .local_en             (icache_data3_icg_en ),
  .module_en            (1'b0                ),
  .pad_yy_icg_scan_en   (1'b0                )
);

gated_clk_cell  x_icache_data2_icg_cell (
  .clk_in               (forever_cpuclk      ),
  .clk_out              (icache_data2_clk    ),
  .external_en          (1'b0                ),
  .global_en            (1'b0                ),
  .local_en             (icache_data2_icg_en ),
  .module_en            (1'b0                ),
  .pad_yy_icg_scan_en   (1'b0                )
);

gated_clk_cell  x_icache_data1_icg_cell (
  .clk_in               (forever_cpuclk      ),
  .clk_out              (icache_data1_clk    ),
  .external_en          (1'b0                ),
  .global_en            (1'b0                ),
  .local_en             (icache_data1_icg_en ),
  .module_en            (1'b0                ),
  .pad_yy_icg_scan_en   (1'b0                )
);

gated_clk_cell  x_icache_data0_icg_cell (
  .clk_in               (forever_cpuclk      ),
  .clk_out              (icache_data0_clk    ),
  .external_en          (1'b0                ),
  .global_en            (1'b0                ),
  .local_en             (icache_data0_icg_en ),
  .module_en            (1'b0                ),
  .pad_yy_icg_scan_en   (1'b0                )
);

assign icache_data_wr                    = |icache_data_wen[1:0];
assign icache_data_gwen_b                = !icache_data_wr;
assign icache_data_bwen_b[31:0]          = ~{32{icache_data_wr}};
assign icache_data_idx_high[DATA_INDEX-1:0] = {icache_data_idx[DATA_INDEX:2],
                                              !icache_data_wen[1] && icache_data_idx[1] && !iop_rd_data
                                            || iop_rd_data && iop_rd_way
                                            || icache_data_wen[1]};
assign icache_data_idx_low[DATA_INDEX-1:0]  = {icache_data_idx[DATA_INDEX:2],
                                              !icache_data_wen[0] && icache_data_idx[1] && !iop_rd_data
                                            || iop_rd_data && !iop_rd_way
                                            || icache_data_wen[0]};

// data 3 2 1 0
assign icache_data3_cen_b  = !(icache_data_ren[1] && icache_data_idx[1:0] == 2'b11
                            || icache_data_ren[0] && icache_data_idx[1:0] == 2'b01
                            || icache_data_wr
                            || iop_rd_data);
assign icache_data3_idx[DATA_INDEX-1:0] = icache_data_idx_high[DATA_INDEX-1:0];
assign icache_data3_din[31:0] = icache_data_wen[1] ? icache_data_din[127:96]
                                                   : icache_data_din[63:32];

assign icache_data2_cen_b  = !(icache_data_ren[1] && icache_data_idx[1:0] == 2'b10
                            || icache_data_ren[0] && icache_data_idx[1:0] == 2'b00
                            || icache_data_wr
                            || iop_rd_data);
assign icache_data2_idx[DATA_INDEX-1:0] = icache_data_idx_high[DATA_INDEX-1:0];
assign icache_data2_din[31:0] = icache_data_wen[1] ? icache_data_din[95:64]
                                                   : icache_data_din[31:0];

assign icache_data1_cen_b  = !(icache_data_ren[1] && icache_data_idx[1:0] == 2'b01
                            || icache_data_ren[0] && icache_data_idx[1:0] == 2'b11
                            || icache_data_wr
                            || iop_rd_data);
assign icache_data1_idx[DATA_INDEX-1:0] = icache_data_idx_low[DATA_INDEX-1:0];
assign icache_data1_din[31:0] = icache_data_wen[0] ? icache_data_din[127:96]
                                                   : icache_data_din[63:32];

assign icache_data0_cen_b  = !(icache_data_ren[1] && icache_data_idx[1:0] == 2'b00
                            || icache_data_ren[0] && icache_data_idx[1:0] == 2'b10
                            || icache_data_wr
                            || iop_rd_data);
assign icache_data0_idx[DATA_INDEX-1:0] = icache_data_idx_low[DATA_INDEX-1:0];
assign icache_data0_din[31:0] = icache_data_wen[0] ? icache_data_din[95:64]
                                                   : icache_data_din[31:0];

rvgpu_spsram_2048x32  x_rvgpu_spsram_2048x32_3 (
  .A                  (icache_data3_idx  ),
  .CEN                (icache_data3_cen_b),
  .CLK                (icache_data3_clk  ),
  .D                  (icache_data3_din  ),
  .GWEN               (icache_data_gwen_b),
  .Q                  (icache_data3_dout ),
  .WEN                (icache_data_bwen_b)
);

rvgpu_spsram_2048x32  x_rvgpu_spsram_2048x32_2 (
  .A                  (icache_data2_idx  ),
  .CEN                (icache_data2_cen_b),
  .CLK                (icache_data2_clk  ),
  .D                  (icache_data2_din  ),
  .GWEN               (icache_data_gwen_b),
  .Q                  (icache_data2_dout ),
  .WEN                (icache_data_bwen_b)
);

rvgpu_spsram_2048x32  x_rvgpu_spsram_2048x32_1 (
  .A                  (icache_data1_idx  ),
  .CEN                (icache_data1_cen_b),
  .CLK                (icache_data1_clk  ),
  .D                  (icache_data1_din  ),
  .GWEN               (icache_data_gwen_b),
  .Q                  (icache_data1_dout ),
  .WEN                (icache_data_bwen_b)
);

rvgpu_spsram_2048x32  x_rvgpu_spsram_2048x32_0 (
  .A                  (icache_data0_idx  ),
  .CEN                (icache_data0_cen_b),
  .CLK                (icache_data0_clk  ),
  .D                  (icache_data0_din  ),
  .GWEN               (icache_data_gwen_b),
  .Q                  (icache_data0_dout ),
  .WEN                (icache_data_bwen_b)
);

endmodule
