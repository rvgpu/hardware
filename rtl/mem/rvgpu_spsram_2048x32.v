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

module rvgpu_spsram_2048x32(
  A,
  CEN,
  CLK,
  D,
  GWEN,
  Q,
  WEN
);

input   [10:0]  A;           
input           CEN;         
input           CLK;         
input   [31:0]  D;           
input           GWEN;        
input   [31:0]  WEN;         
output  [31:0]  Q;           

reg     [10:0]  addr_holding; 

wire    [10:0]  A;           
wire            CEN;         
wire            CLK;         
wire    [31:0]  D;           
wire            GWEN;        
wire    [31:0]  Q;           
wire    [31:0]  WEN;         
wire    [10:0]  addr;        
wire    [7 :0]  ram0_din;    
wire    [7 :0]  ram0_dout;   
wire            ram0_wen;    
wire    [7 :0]  ram1_din;    
wire    [7 :0]  ram1_dout;   
wire            ram1_wen;    
wire    [7 :0]  ram2_din;    
wire    [7 :0]  ram2_dout;   
wire            ram2_wen;    
wire    [7 :0]  ram3_din;    
wire    [7 :0]  ram3_dout;   
wire            ram3_wen;    


parameter ADDR_WIDTH = 11;
parameter WRAP_SIZE  = 8;

assign ram0_wen = !CEN && !WEN[ 7] && !GWEN;
assign ram1_wen = !CEN && !WEN[15] && !GWEN;
assign ram2_wen = !CEN && !WEN[23] && !GWEN;
assign ram3_wen = !CEN && !WEN[31] && !GWEN;

assign ram0_din[WRAP_SIZE-1:0] = D[WRAP_SIZE-1:0];
assign ram1_din[WRAP_SIZE-1:0] = D[2*WRAP_SIZE-1:WRAP_SIZE];
assign ram2_din[WRAP_SIZE-1:0] = D[3*WRAP_SIZE-1:2*WRAP_SIZE];
assign ram3_din[WRAP_SIZE-1:0] = D[4*WRAP_SIZE-1:3*WRAP_SIZE];

always@(posedge CLK)
begin
  if(!CEN) begin
    addr_holding[ADDR_WIDTH-1:0] <= A[ADDR_WIDTH-1:0];
  end
end

assign addr[ADDR_WIDTH-1:0] = CEN ? addr_holding[ADDR_WIDTH-1:0]
                                  : A[ADDR_WIDTH-1:0];

assign Q[WRAP_SIZE-1:0]             = ram0_dout[WRAP_SIZE-1:0];
assign Q[2*WRAP_SIZE-1:WRAP_SIZE]   = ram1_dout[WRAP_SIZE-1:0];
assign Q[3*WRAP_SIZE-1:2*WRAP_SIZE] = ram2_dout[WRAP_SIZE-1:0];
assign Q[4*WRAP_SIZE-1:3*WRAP_SIZE] = ram3_dout[WRAP_SIZE-1:0];


sim_ram #(WRAP_SIZE,ADDR_WIDTH) ram0(
  .PortAClk (CLK),
  .PortAAddr(addr),
  .PortADataIn (ram0_din),
  .PortAWriteEnable(ram0_wen),
  .PortADataOut(ram0_dout));

sim_ram #(WRAP_SIZE,ADDR_WIDTH) ram1(
  .PortAClk (CLK),
  .PortAAddr(addr),
  .PortADataIn (ram1_din),
  .PortAWriteEnable(ram1_wen),
  .PortADataOut(ram1_dout));

sim_ram #(WRAP_SIZE,ADDR_WIDTH) ram2(
  .PortAClk (CLK),
  .PortAAddr(addr),
  .PortADataIn (ram2_din),
  .PortAWriteEnable(ram2_wen),
  .PortADataOut(ram2_dout));

sim_ram #(WRAP_SIZE,ADDR_WIDTH) ram3(
  .PortAClk (CLK),
  .PortAAddr(addr),
  .PortADataIn (ram3_din),
  .PortAWriteEnable(ram3_wen),
  .PortADataOut(ram3_dout));

endmodule





