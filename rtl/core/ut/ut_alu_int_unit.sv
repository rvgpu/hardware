`include "svunit_defines.svh"
`include "clk_and_reset.svh"
`include "alu_int_unit.v"

module alu_iu_unit_test;
  import svunit_pkg::svunit_testcase;

  string name = "ut_alu_iu";
  svunit_testcase svunit_ut;


  //===================================
  // This is the UUT that we're 
  // running the Unit Tests on
  //===================================

  `CLK_RESET_FIXTURE(5, 11)

  logic [7:0]   eu_iu_inst_opcode;
  logic [63:0]  eu_iu_inst_src0;
  logic [63:0]  eu_iu_inst_src1;
  logic [63:0]  eu_iu_inst_src2;
  logic [7:0]   eu_iu_inst_dst_id;
  logic [7:0]   iu_rb_dst_id;
  logic [63:0]  iu_rb_data;
  logic         iu_rb_data_valid;

  alu_int_unit my_alu_int_unit(
    .clk(clk),
    .reset_n(rst_n),
    .eu_iu_inst_opcode(eu_iu_inst_opcode),
    .eu_iu_inst_src0(eu_iu_inst_src0),  
    .eu_iu_inst_src1(eu_iu_inst_src1),  
    .eu_iu_inst_src2(eu_iu_inst_src2),
    .eu_iu_inst_dst_id(eu_iu_inst_dst_id),  
    .iu_rb_dst_id(iu_rb_dst_id),  
    .iu_rb_data(iu_rb_data),  
    .iu_rb_data_valid(iu_rb_data_valid)  
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
  `SVTEST(test_op_add)
    $display("@%0t Begin Test", $time);
    eu_iu_inst_opcode = `OPCODE_ADD;
    eu_iu_inst_src0 = 64'h1234_5678_9ABC_DEF0;  
    eu_iu_inst_src1 = 64'h0FED_CBA9_8765_4321;
    eu_iu_inst_src2 = 64'h0000_0000_0000_0000;
    eu_iu_inst_dst_id = 8'h0A;
    step();
    nextSamplePoint();
    $display("@%0t test\n", $time);
    $display("iu_rb_dst_id: %x", iu_rb_dst_id);
    $display("iu_rb_data is: %x", iu_rb_data);
    $display("iu_rb_data_valid: %x", iu_rb_data_valid);

    `FAIL_IF(iu_rb_dst_id !== 8'h0A)
    `FAIL_IF(iu_rb_data !== 64'h2222222222222211)
    `FAIL_IF(iu_rb_data_valid !== 1'b1)

    $display("@%0t End Test", $time);
  `SVTEST_END

  `SVUNIT_TESTS_END

endmodule
