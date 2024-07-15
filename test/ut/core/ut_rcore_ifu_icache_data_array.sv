`include "svunit_defines.svh"
`include "clk_and_reset.svh"
`include "project.v"

`include "sim_ram.v"
`include "gated_clk_cell.v"

`include "rvgpu_spsram_2048x32.v"
`include "rcore_ifu_icache_data_array.v"

module icache_tag_array_unit_test;
  import svunit_pkg::svunit_testcase;

  string name = "ut_icache_tag_array";
  svunit_testcase svunit_ut;


  //===================================
  // This is the UUT that we're 
  // running the Unit Tests on
  //===================================
  localparam integer ADDRW = 14;
  localparam integer DATAW = 32;
  localparam integer ICADDR = `ICACHE_DATA_INDEX_WIDTH;

  `CLK_RESET_FIXTURE(5, 10)

  logic   [127:0]  icache_data_din;     
  logic   [13 :0]  icache_data_idx;     
  logic   [1  :0]  icache_data_ren;     
  logic   [1  :0]  icache_data_wen;     
  logic            iop_rd_data;         
  logic            iop_rd_way;          
  logic   [31 :0]  icache_data0_dout;   
  logic   [31 :0]  icache_data1_dout;   
  logic   [31 :0]  icache_data2_dout;   
  logic   [31 :0]  icache_data3_dout;   

  rcore_ifu_icache_data_array x_rcore_ifu_icache_data_array (
    .forever_cpuclk(clk),
    .icache_data0_dout(icache_data0_dout),
    .icache_data1_dout(icache_data1_dout),
    .icache_data2_dout(icache_data2_dout),
    .icache_data3_dout(icache_data3_dout),
    .icache_data_din(icache_data_din),
    .icache_data_idx(icache_data_idx),
    .icache_data_ren(icache_data_ren),
    .icache_data_wen(icache_data_wen),
    .iop_rd_data(iop_rd_data),
    .iop_rd_way(iop_rd_way)
  );

  //===================================
  // Build
  //===================================
  function void build();
    svunit_ut = new(name);
  endfunction


  //===================================
  // Setup for running the Unit Tests
  //===================================
  task setup();
    svunit_ut.setup();
    /* Place Setup Code Here */
    $vcdpluson();

    reset();
  endtask


  //===================================
  // Here we deconstruct anything we 
  // need after running the Unit Tests
  //===================================
  task teardown();
    svunit_ut.teardown();
    /* Place Teardown Code Here */

  endtask

  task data_array_clean(input [1:0] wen,  input [127:0] data);
    integer i;

    @(posedge clk);
    #1;
    icache_data_ren[1:0]      = 2'b00;
    icache_data_wen[1:0]      = 2'b00;
    icache_data_idx[13:0]     = 14'b00_0000_0000_0000;
    iop_rd_data               = 1'b0;
    iop_rd_way                = 1'b0;

    step();

    for (i=0; i<(2**ICADDR); i=i+4) begin
      @(posedge clk);
      #1;
      icache_data_idx         = i;
      icache_data_din[127:0]  = data;
      icache_data_ren[1:0]    = 2'b00;
      icache_data_wen[1:0]    = wen;

      step();
    end

    @(posedge clk);
    #1;
    icache_data_ren[1:0]      = 2'b00;
    icache_data_wen[1:0]      = 2'b00;
    icache_data_idx[13:0]     = 14'b00_0000_0000_0000;
    iop_rd_data               = 1'b0;
    iop_rd_way                = 1'b0;

    step(10);
  endtask

  task data_array_write(input [1:0] wen);
    integer i;

    @(posedge clk);
    #1;
    icache_data_ren[1:0]      = 2'b00;
    icache_data_wen[1:0]      = 2'b00;
    icache_data_idx[13:0]     = 14'b00_0000_0000_0000;
    iop_rd_data               = 1'b0;
    iop_rd_way                = 1'b0;

    step(10);

    for (i=0; i<(2**ICADDR); i=i+4) begin
      @(posedge clk);
      #1;
      icache_data_idx         = i;
      icache_data_din[127:0]  = {32'h32345678 + i, 32'h22345678 + i, 32'h12345678 + i, 32'h02345678 + i};
      icache_data_ren[1:0]    = 2'b00;
      icache_data_wen[1:0]    = wen;

      step();
    end

    @(posedge clk);
    #1;
    icache_data_ren[1:0]      = 2'b00;
    icache_data_wen[1:0]      = 2'b00;
    icache_data_idx[13:0]     = 14'b00_0000_0000_0000;
    iop_rd_data               = 1'b0;
    iop_rd_way                = 1'b0;

    step(10);
  endtask

  task data_array_read_and_check(input rd_way);
    integer i;
    integer data0;
    integer data1;
    integer data2;
    integer data3;

    if (rd_way == 1'b1) begin
      data0 = 32'h02345678;
      data1 = 32'h12345678;
      data2 = 32'h22345678;
      data3 = 32'h32345678;
    end
    else begin
      data0 = 32'h22345678;
      data1 = 32'h32345678;
      data2 = 32'h02345678;
      data3 = 32'h12345678;
    end

    step(10);

    for (i=0; i<(2**ICADDR); i=i+4) begin
      @(posedge clk);
      #1;
      icache_data_idx         = i;
      icache_data_ren[1:0]    = 2'b00;
      icache_data_wen[1:0]    = 2'b00;
      iop_rd_data             = 1'b1;
      iop_rd_way              = rd_way;

      step();

      if (i >= 1) begin
        $display("data0: %x", icache_data0_dout[31:0]);
        $display("data1: %x", icache_data1_dout[31:0]);
        $display("data2: %x", icache_data2_dout[31:0]);
        $display("data3: %x", icache_data3_dout[31:0]);
        `FAIL_IF(icache_data0_dout[31:0] != data0 + i - 4)
        `FAIL_IF(icache_data1_dout[31:0] != data1 + i - 4)
        `FAIL_IF(icache_data2_dout[31:0] != data2 + i - 4)
        `FAIL_IF(icache_data3_dout[31:0] != data3 + i - 4)
      end
    end

    @(posedge clk);
    #1;
    icache_data_ren[1:0]      = 2'b00;
    icache_data_wen[1:0]      = 2'b00;
    icache_data_idx[13:0]     = 14'b00_0000_0000_0000;
    iop_rd_data               = 1'b0;
    iop_rd_way                = 1'b0;

    // 等待下一个采样点
    nextSamplePoint();
    $display("last data:");
    $display("data0: %x", icache_data0_dout[31:0]);
    $display("data1: %x", icache_data1_dout[31:0]);
    $display("data2: %x", icache_data2_dout[31:0]);
    $display("data3: %x", icache_data3_dout[31:0]);
    `FAIL_IF(icache_data0_dout[31:0] != data0 + i - 4)
    `FAIL_IF(icache_data1_dout[31:0] != data1 + i - 4)
    `FAIL_IF(icache_data2_dout[31:0] != data2 + i - 4)
    `FAIL_IF(icache_data3_dout[31:0] != data3 + i - 4)
  endtask
  //===================================
  // All tests are defined between the
  // SVUNIT_TESTS_BEGIN/END macros
  //
  // Each individual test must be
  // defined between `SVTEST(_NAME_)
  // `SVTEST_END
  //
  // i.e.
  //   `SVTEST(mytest)
  //     <test code>
  //   `SVTEST_END
  //===================================
  `SVUNIT_TESTS_BEGIN

  //---------------------------------
  // verify the combinational output
  //---------------------------------
  `SVTEST(test_icache_data_array_write_1234)
    data_array_clean(2'b10, {32'hdeaddead, 32'hdeaddead, 32'hdeaddead, 32'hdeaddead});
    data_array_clean(2'b01, {32'hdeaddead, 32'hdeaddead, 32'hdeaddead, 32'hdeaddead});

    data_array_write(2'b10);
    data_array_read_and_check(1'b1);
  `SVTEST_END

  `SVTEST(test_icache_data_array_write_3412)
    data_array_clean(2'b10, {32'hdeaddead, 32'hdeaddead, 32'hdeaddead, 32'hdeaddead});
    data_array_clean(2'b01, {32'hdeaddead, 32'hdeaddead, 32'hdeaddead, 32'hdeaddead});

    data_array_write(2'b01);
    data_array_read_and_check(1'b0);
  `SVTEST_END

  `SVUNIT_TESTS_END

endmodule
