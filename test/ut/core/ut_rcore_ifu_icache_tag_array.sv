`include "svunit_defines.svh"
`include "clk_and_reset.svh"
`include "project.v"

`include "sim_ram.v"
`include "gated_clk_cell.v"

`include "rvgpu_spsram_256x59.v"
`include "rcore_ifu_icache_tag_array.v"

module icache_tag_array_unit_test;
  import svunit_pkg::svunit_testcase;

  string name = "ut_icache_tag_array";
  svunit_testcase svunit_ut;


  //===================================
  // This is the UUT that we're 
  // running the Unit Tests on
  //===================================
  localparam integer ADDRW = 9;
  localparam integer DATAW = 59;
  localparam integer ICADDR = `ICACHE_TAG_INDEX_WIDTH;

  `CLK_RESET_FIXTURE(5, 10)

  logic                 cp0_yy_clk_en;
  logic                 icache_tag_cen;
  logic   [DATAW-1:0]   icache_tag_din;
  logic   [ADDRW-1 :0]  icache_tag_idx;
  logic   [2 :0]        icache_tag_wen;
  logic                 pad_yy_icg_scan_en;
  logic   [DATAW-1:0]   icache_tag_dout;

  rcore_ifu_icache_tag_array x_rcore_ifu_icache_tag_array (
    .cp0_yy_clk_en(cp0_yy_clk_en),
    .forever_cpuclk(clk),
    .icache_tag_cen(icache_tag_cen),
    .icache_tag_din(icache_tag_din),
    .icache_tag_dout(icache_tag_dout),
    .icache_tag_idx(icache_tag_idx),
    .icache_tag_wen(icache_tag_wen),
    .pad_yy_icg_scan_en(pad_yy_icg_scan_en)
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
  `SVTEST(test_spsram_read_write)
  integer i;
  cp0_yy_clk_en = 1'b0;
  pad_yy_icg_scan_en = 1'b0;

  @(posedge clk);
  #1;
  icache_tag_cen        = 1'b0;
  icache_tag_wen[2:0]   = 3'b000;
  icache_tag_idx[8:0]   = 8'h00;

  step(10);

  for (i=0; i<(2**ICADDR); i=i+1) begin
    @(posedge clk);
    #1;
    icache_tag_idx        = i;
    icache_tag_din[58:0]  = 59'h1234567_87654321 + i;
    icache_tag_cen        = 1'b1;
    icache_tag_wen        = '1;

    step();
  end

  @(posedge clk);
  #1;
  icache_tag_cen        = 1'b0;
  icache_tag_wen[2:0]   = 3'b000;
  icache_tag_idx[8:0]   = 8'h00;

  step(10);
  
  for (i=0; i<(2**ICADDR); i=i+1) begin
    @(posedge clk);
    #1;
    icache_tag_idx        = i;
    icache_tag_cen        = 1'b1;
    icache_tag_wen[2:0]   = 3'b000;

    step();

    if (i >= 1) begin
      `FAIL_IF(icache_tag_dout != 59'h1234567_87654321 + i - 1)
    end
  end

  @(posedge clk);
  #1;
  icache_tag_cen          = 1'b1;

  // 等待下一个采样点
  nextSamplePoint();
  `FAIL_IF(icache_tag_dout != 59'h1234567_87654321 + i - 1)

  `SVTEST_END

  `SVUNIT_TESTS_END

endmodule
