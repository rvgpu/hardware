`include "svunit_defines.svh"
`include "clk_and_reset.svh"

module soc_unit_test;
  import svunit_pkg::svunit_testcase;

  string name = "ut_soc";
  svunit_testcase svunit_ut;


  //===================================
  // This is the UUT that we're 
  // running the Unit Tests on
  //===================================

  `CLK_RESET_FIXTURE(5, 10)
  // clk and reset 
  logic                   jclk;
  logic                   jtg_tdi;
  logic                   jtg_tms;
  logic                   jtrst_b;
  logic                   jnrst_b;

  logic                   uart0_sin;
  logic                   jtg_tdo;
  logic                   uart0_sout;
  wire    [7  :0]         b_pad_gpio_porta;

  soc x_soc(
    .i_pad_clk           ( clk                  ),
    .b_pad_gpio_porta    ( b_pad_gpio_porta     ),
    .i_pad_jtg_trst_b    ( jtrst_b              ),
    .i_pad_jtg_nrst_b    ( jnrst_b              ),
    .i_pad_jtg_tclk      ( jclk                 ),
    .i_pad_jtg_tdi       ( jtg_tdi              ),
    .i_pad_jtg_tms       ( jtg_tms              ),
    .i_pad_uart0_sin     ( uart0_sin            ),
    .o_pad_jtg_tdo       ( jtg_tdo              ),
    .o_pad_uart0_sout    ( uart0_sout           ),
    .i_pad_rst_b         ( rst_n                )
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
  `SVTEST(test_add)
  	$display("XXXXXXXXXXXXXXXXXXXXX");
  `SVTEST_END

  `SVUNIT_TESTS_END

endmodule
