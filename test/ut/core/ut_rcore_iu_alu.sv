`include "svunit_defines.svh"
`include "clk_and_reset.svh"
`include "rcore_iu_alu.v"
`include "project.v"

module iu_alu_unit_test;
  import svunit_pkg::svunit_testcase;

  string name = "ut_iu_alu";
  svunit_testcase svunit_ut;


  //===================================
  // This is the UUT that we're 
  // running the Unit Tests on
  //===================================

  `CLK_RESET_FIXTURE(5, 10)
    
  logic         idu_iu_pipe_sel;
  logic [7:0]   idu_iu_inst_opcode;
  logic [63:0]  idu_iu_inst_src0;
  logic [63:0]  idu_iu_inst_src1;
  logic [63:0]  idu_iu_inst_src2;
  logic [7:0]   idu_iu_inst_dstid;
  logic [7:0]   iu_rb_dstid;
  logic [63:0]  iu_rb_data;
  logic         iu_rb_data_vld;

  rcore_iu_alu x_rcore_iu_alu(
    .clk(clk),
    .rst_n(rst_n),
    .idu_iu_pipe_sel(idu_iu_pipe_sel),
    .idu_iu_inst_opcode(idu_iu_inst_opcode),
    .idu_iu_inst_src0(idu_iu_inst_src0),  
    .idu_iu_inst_src1(idu_iu_inst_src1),  
    .idu_iu_inst_src2(idu_iu_inst_src2),
    .idu_iu_inst_dstid(idu_iu_inst_dstid),  
    .iu_rb_dstid(iu_rb_dstid),  
    .iu_rb_data(iu_rb_data),  
    .iu_rb_data_vld(iu_rb_data_vld)  
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

  // test the register result
  task test_alu_iu_short_register_result(
    input [7 :0]    opcode,
    input [7 :0]    dst_preg,
    input [63:0]    src0,
    input [63:0]    src1,
    input [63:0]    result
  );
    // 开始测试前的准备工作  
    $display("@%0t Begin Test", $time);
    
    @(posedge clk);
    idu_iu_pipe_sel          <= 1'b1;
    idu_iu_inst_opcode       <= opcode;
    idu_iu_inst_src0         <= src0;
    idu_iu_inst_src1         <= src1;
    idu_iu_inst_src2         <= 64'h00000000_00000000;
    idu_iu_inst_dstid        <= dst_preg;

    step();
    // 关闭时钟和其他清理工作
    @(posedge clk);
    idu_iu_pipe_sel          <= 1'b0;
      
    // 等待下一个采样点
    nextSamplePoint();
    $display("@%0t Sample Point", $time);

    `FAIL_IF(iu_rb_data_vld     !== 1'b1)
    `FAIL_IF(iu_rb_dstid        !== dst_preg)
    `FAIL_IF(iu_rb_data         !== result) 

  endtask

  // 定义结构体和函数声明
  typedef struct {
    logic[63:0] src0;
    logic[63:0] src1;
    logic[63:0] result;
  } test_data_t;

  function automatic read_test_data(input string filename, output test_data_t test_data[$]);
    int fd;
    int ret;
    string realpath = {`RVGPU_HARDWARE_TOPPATH_STR, "/test/ut/core/basic_testdata/", filename};
    $display(realpath);
    if ((fd = $fopen(realpath, "r")) == 0) begin
      $display("Error: Unable to open file %s", realpath);
    end

    while (!$feof(fd)) begin
      string line;
      if ($fgets(line, fd)) begin
        test_data_t data;
        ret = $sscanf(line, "%h %h %h", data.src0, data.src1, data.result);
        if (ret == 3) begin
          test_data.push_back(data);
        end
      end
    end
   
  endfunction

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
  `SVTEST(test_add_u64)
    string filename = "alu_add_u64.hex";

    test_data_t test_data[$];
    read_test_data(filename, test_data);

    foreach (test_data[i]) begin
      $display("test_data[%0d]: 0x%h 0x%h 0x%h", i, test_data[i].src0, test_data[i].src1, test_data[i].result);
      test_alu_iu_short_register_result(`OPCODE_ADD64, 8'h01, test_data[i].src0, test_data[i].src1, test_data[i].result);
      reset();
    end
  `SVTEST_END

  `SVTEST(test_add)
    string filename = "alu_sub64.hex";

    test_data_t test_data[$];
    read_test_data(filename, test_data);

    foreach (test_data[i]) begin
      $display("test_data[%0d]: 0x%h 0x%h 0x%h", i, test_data[i].src0, test_data[i].src1, test_data[i].result);
      test_alu_iu_short_register_result(`OPCODE_SUB64, 8'h01, test_data[i].src0, test_data[i].src1, test_data[i].result);
      reset();
    end
  `SVTEST_END

  `SVUNIT_TESTS_END

endmodule
