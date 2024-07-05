`include "svunit_defines.svh"
`include "clk_and_reset.svh"
`include "project.v"

module spsram_256x59_unit_test;
  import svunit_pkg::svunit_testcase;

  string name = "ut_spsram_256x59";
  svunit_testcase svunit_ut;


  //===================================
  // This is the UUT that we're 
  // running the Unit Tests on
  //===================================
  localparam integer ADDRW = 8;
  localparam integer DATAW = 59;
  localparam integer WEW   = 59;

  `CLK_RESET_FIXTURE(5, 10)

  logic [ADDRW-1:0] addr;
  logic [DATAW-1:0] datain;
  logic [DATAW-1:0] dataout;
  logic [WEW-1:0]   wen;
  logic             cen;

  rvgpu_spsram_256x59 x_rvgpu_spsram_256x59 (
    .A    (addr),
    .CEN  (cen),
    .CLK  (clk),
    .D    (datain),
    .GWEN (1'b0),
    .Q    (dataout),
    .WEN  (wen)
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

  @(posedge clk);
  #1;
  cen     = 1'b1;
  wen     = '1;

  step(10);

  for (i=0; i<(2**ADDRW); i=i+1) begin
    @(posedge clk);
    #1;
    addr    = i;
    datain  = 59'h1234567_87654321 + i;
    wen     = '0;
    cen     = 1'b0;

    step();
  end

  @(posedge clk);
  #1;
  cen     = 1'b1;
  wen     = '1;

  step(10);
  
  for (i=0; i<(2**ADDRW); i=i+1) begin
    @(posedge clk);
    #1;
    addr    = i;
    wen     = '1;
    cen     = 1'b0;

    step();

    if (i >= 1) begin
      `FAIL_IF(dataout != 59'h1234567_87654321 + i - 1)
    end
  end

  @(posedge clk);
  #1;
  cen     = 1'b1;

  // 等待下一个采样点
  nextSamplePoint();
  `FAIL_IF(dataout != 59'h1234567_87654321 + i - 1)

  `SVTEST_END

  `SVUNIT_TESTS_END

endmodule
