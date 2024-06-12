`include "svunit_defines.svh"
`include "clk_and_reset.svh"
`include "rcore_iu_alu.v"

module iu_alu_unit_test;
  import svunit_pkg::svunit_testcase;

  string name = "ut_iu_alu";
  svunit_testcase svunit_ut;


  //===================================
  // This is the UUT that we're 
  // running the Unit Tests on
  //===================================

  `CLK_RESET_FIXTURE(5, 10)
  logic     [63:0]  alu_rbus_ex1_pipe0_data;
  logic             alu_rbus_ex1_pipe0_data_vld;
  logic     [63:0]  alu_rbus_ex1_pipe0_fwd_data;
  logic             alu_rbus_ex1_pipe0_fwd_vld;
  logic     [6 :0]  alu_rbus_ex1_pipe0_preg;

  logic             cp0_iu_icg_en;   
  logic             cp0_yy_clk_en;

  logic     [63:0]  had_idu_wbbr_data;
  logic             had_idu_wbbr_vld;

  logic             idu_iu_rf_pipe0_alu_short;
  logic     [6 :0]  idu_iu_rf_pipe0_dst_preg;
  logic             idu_iu_rf_pipe0_dst_vld;
  logic     [6 :0]  idu_iu_rf_pipe0_dst_vreg;
  logic             idu_iu_rf_pipe0_dstv_vld;
  logic     [4 :0]  idu_iu_rf_pipe0_func;
  logic             idu_iu_rf_pipe0_gateclk_sel;
  logic     [5 :0]  idu_iu_rf_pipe0_imm;
  logic     [20:0]  idu_iu_rf_pipe0_rslt_sel;
  logic             idu_iu_rf_pipe0_sel;  
  logic     [63:0]  idu_iu_rf_pipe0_src0;
  logic     [63:0]  idu_iu_rf_pipe0_src1;
  logic     [63:0]  idu_iu_rf_pipe0_src2;
  logic     [7 :0]  idu_iu_rf_pipe0_vl;
  logic     [1 :0]  idu_iu_rf_pipe0_vlmul;
  logic     [2 :0]  idu_iu_rf_pipe0_vsew;
  logic     [4 :0]  iu_vfpu_ex1_pipe0_mtvr_inst;
  logic     [7 :0]  iu_vfpu_ex1_pipe0_mtvr_vl;
  logic             iu_vfpu_ex1_pipe0_mtvr_vld;
  logic     [1 :0]  iu_vfpu_ex1_pipe0_mtvr_vlmu;
  logic     [6 :0]  iu_vfpu_ex1_pipe0_mtvr_vreg;
  logic     [2 :0]  iu_vfpu_ex1_pipe0_mtvr_vsew;
  logic     [63:0]  iu_vfpu_ex2_pipe0_mtvr_src0;
  logic             iu_vfpu_ex2_pipe0_mtvr_vld;
  logic             pad_yy_icg_scan_en;
  logic             rtu_yy_xx_flush;

  rcore_iu_alu t_rcore_iu_alu (
    .alu_rbus_ex1_pipex_data      (alu_rbus_ex1_pipe0_data     ),
    .alu_rbus_ex1_pipex_data_vld  (alu_rbus_ex1_pipe0_data_vld ),
    .alu_rbus_ex1_pipex_fwd_data  (alu_rbus_ex1_pipe0_fwd_data ),
    .alu_rbus_ex1_pipex_fwd_vld   (alu_rbus_ex1_pipe0_fwd_vld  ),
    .alu_rbus_ex1_pipex_preg      (alu_rbus_ex1_pipe0_preg     ),
    .cp0_iu_icg_en                (cp0_iu_icg_en               ),
    .cp0_yy_clk_en                (cp0_yy_clk_en               ),
    .cpurst_b                     (rst_n                       ),
    .forever_cpuclk               (clk                         ),
    .had_idu_wbbr_data            (had_idu_wbbr_data           ),
    .had_idu_wbbr_vld             (had_idu_wbbr_vld            ),
    .idu_iu_rf_pipex_alu_short    (idu_iu_rf_pipe0_alu_short   ),
    .idu_iu_rf_pipex_dst_preg     (idu_iu_rf_pipe0_dst_preg    ),
    .idu_iu_rf_pipex_dst_vld      (idu_iu_rf_pipe0_dst_vld     ),
    .idu_iu_rf_pipex_dst_vreg     (idu_iu_rf_pipe0_dst_vreg    ),
    .idu_iu_rf_pipex_dstv_vld     (idu_iu_rf_pipe0_dstv_vld    ),
    .idu_iu_rf_pipex_func         (idu_iu_rf_pipe0_func        ),
    .idu_iu_rf_pipex_gateclk_sel  (idu_iu_rf_pipe0_gateclk_sel ),
    .idu_iu_rf_pipex_imm          (idu_iu_rf_pipe0_imm         ),
    .idu_iu_rf_pipex_rslt_sel     (idu_iu_rf_pipe0_rslt_sel    ),
    .idu_iu_rf_pipex_sel          (idu_iu_rf_pipe0_sel         ),
    .idu_iu_rf_pipex_src0         (idu_iu_rf_pipe0_src0        ),
    .idu_iu_rf_pipex_src1         (idu_iu_rf_pipe0_src1        ),
    .idu_iu_rf_pipex_src2         (idu_iu_rf_pipe0_src2        ),
    .idu_iu_rf_pipex_vl           (idu_iu_rf_pipe0_vl          ),
    .idu_iu_rf_pipex_vlmul        (idu_iu_rf_pipe0_vlmul       ),
    .idu_iu_rf_pipex_vsew         (idu_iu_rf_pipe0_vsew        ),
    .iu_vfpu_ex1_pipex_mtvr_inst  (iu_vfpu_ex1_pipe0_mtvr_inst ),
    .iu_vfpu_ex1_pipex_mtvr_vl    (iu_vfpu_ex1_pipe0_mtvr_vl   ),
    .iu_vfpu_ex1_pipex_mtvr_vld   (iu_vfpu_ex1_pipe0_mtvr_vld  ),
    .iu_vfpu_ex1_pipex_mtvr_vlmul (iu_vfpu_ex1_pipe0_mtvr_vlmul),
    .iu_vfpu_ex1_pipex_mtvr_vreg  (iu_vfpu_ex1_pipe0_mtvr_vreg ),
    .iu_vfpu_ex1_pipex_mtvr_vsew  (iu_vfpu_ex1_pipe0_mtvr_vsew ),
    .iu_vfpu_ex2_pipex_mtvr_src0  (iu_vfpu_ex2_pipe0_mtvr_src0 ),
    .iu_vfpu_ex2_pipex_mtvr_vld   (iu_vfpu_ex2_pipe0_mtvr_vld  ),
    .pad_yy_icg_scan_en           (pad_yy_icg_scan_en          ),
    .rtu_yy_xx_flush              (rtu_yy_xx_flush             )
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
    input [20:0]    rslt_sel,
    input [6 :0]    dst_preg,
    input [63:0]    src0,
    input [64:0]    src1
  );
    // 开始测试前的准备工作  
    $display("@%0t Begin Test", $time);
    idu_iu_rf_pipe0_gateclk_sel = 1'b1;

    idu_iu_rf_pipe0_dst_vld = 1'b1;
    idu_iu_rf_pipe0_func[4:0] = 5'b0_0001;  // no use ??
    idu_iu_rf_pipe0_dst_preg[6:0] = dst_preg;
    idu_iu_rf_pipe0_src0 = src0; // 使用传入的参数
    idu_iu_rf_pipe0_src1 = src1; // 使用传入的参数
    idu_iu_rf_pipe0_src2[63:0] = 64'h00000000_00000000;

    idu_iu_rf_pipe0_sel = 1'b1;
    idu_iu_rf_pipe0_rslt_sel = rslt_sel;
    idu_iu_rf_pipe0_alu_short = 1'b1;

    step();
    // 关闭时钟和其他清理工作
    idu_iu_rf_pipe0_gateclk_sel = 1'b0;
    idu_iu_rf_pipe0_dst_vld = 1'b0;
    // idu_iu_rf_pipe0_sel = 1'b0; 要一直拉高，不然alu_rbus_ex1_pipe0_data_vld信号拉低

    // 等待下一个采样点
    nextSamplePoint();
    $display("@%0t Sample Point\n", $time);
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
    logic[20:0] op = 21'h00001;
    logic[6 :0] dstid = 7'b000_0001;
    logic[63:0] src0 = 64'h12345678_9abcdef0;
    logic[63:0] src1 = 64'h11111111_11111111;
    test_alu_iu_short_register_result(op, dstid, src0, src1);

    `FAIL_IF(alu_rbus_ex1_pipe0_data_vld !== 1'b1)
    `FAIL_IF(alu_rbus_ex1_pipe0_fwd_vld !== 1'b0)
    `FAIL_IF(alu_rbus_ex1_pipe0_preg !== dstid)
    `FAIL_IF(alu_rbus_ex1_pipe0_data !== (src0 + src1))
  `SVTEST_END

  `SVTEST(test_addw)
    logic[20:0] op = 21'h00002;
    logic[6 :0] dstid = 7'b000_0001;
    logic[63:0] src0 = 64'h12345678_9abcdef0;
    logic[63:0] src1 = 64'h11111111_11111111;

    logic[31:0] sum = src0[31:0] + src1[31:0];
    logic[31:0] sext = {32{sum[31]}};
    logic[63:0] res = {sext, sum};
    test_alu_iu_short_register_result(op, dstid, src0, src1);

    `FAIL_IF(alu_rbus_ex1_pipe0_data_vld !== 1'b1)
    `FAIL_IF(alu_rbus_ex1_pipe0_fwd_vld !== 1'b0)
    `FAIL_IF(alu_rbus_ex1_pipe0_preg !== dstid)
    `FAIL_IF(alu_rbus_ex1_pipe0_data !== res)

    $display("@%0t End Test", $time);
  `SVTEST_END

  `SVUNIT_TESTS_END

endmodule
