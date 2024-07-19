`include "svunit_defines.svh"
`include "clk_and_reset.svh"
`include "project.v"

`include "sim_ram.v"
`include "gated_clk_cell.v"

`include "rvgpu_spsram_2048x32.v"
`include "rvgpu_spsram_256x59.v"
`include "rcore_ifu_icache_tag_array.v"
`include "rcore_ifu_icache_data_array.v"
`include "rcore_ifu_icache.v"

module icache_unit_test;
  import svunit_pkg::svunit_testcase;

  string name = "ut_icache";
  svunit_testcase svunit_ut;


  //===================================
  // This is the UUT that we're 
  // running the Unit Tests on
  //===================================

  `CLK_RESET_FIXTURE(5, 10)

  logic            biu_ifu_arready;             
  logic   [127:0]  biu_ifu_rdata;               
  logic            biu_ifu_rid;                 
  logic            biu_ifu_rlast;               
  logic   [1  :0]  biu_ifu_rresp;               
  logic            biu_ifu_rvalid;              
  logic            cp0_ifu_icache_en;           
  logic   [63 :0]  cp0_ifu_icache_inv_addr;     
  logic            cp0_ifu_icache_inv_req;      
  logic   [1  :0]  cp0_ifu_icache_inv_type;     
  logic            cp0_ifu_icache_pref_en;      
  logic   [13 :0]  cp0_ifu_icache_read_index;   
  logic            cp0_ifu_icache_read_req;     
  logic            cp0_ifu_icache_read_tag;     
  logic            cp0_ifu_icache_read_way;     
  logic            cp0_ifu_iwpe;                
  logic            cp0_ifu_lpmd_req;            
  logic            cpurst_b;                    
  logic            ctrl_icache_abort;           
  logic            ctrl_icache_req_vld;         
  logic            forever_cpuclk;              
  logic            hpcp_ifu_cnt_en;             
  logic            mmu_ifu_access_fault;        
  logic   [27 :0]  mmu_ifu_pa;                  
  logic            mmu_ifu_pa_vld;              
  logic   [4  :0]  mmu_ifu_prot;                
  logic            pcgen_icache_chgflw_vld;     
  logic   [33 :0]  pcgen_icache_seq_tag;        
  logic   [63 :0]  pcgen_icache_va;             
  logic            icache_btb_grant;            
  logic            icache_ctrl_stall;           
  logic            icache_ipack_acc_err;        
  logic   [31 :0]  icache_ipack_inst;           
  logic            icache_ipack_inst_vld;       
  logic            icache_ipack_inst_vld_gate;  
  logic            icache_ipack_pgflt;          
  logic            icache_ipack_unalign;        
  logic   [39 :0]  icache_pcgen_addr;           
  logic            icache_pcgen_grant;          
  logic            icache_pcgen_grant_gate;     
  logic            icache_pcgen_inst_vld;       
  logic            icache_pcgen_inst_vld_gate;  
  logic            icache_pred_inst_vld;        
  logic            icache_pred_inst_vld_gate;   
  logic            icache_top_abort;            
  logic   [1  :0]  icache_top_inv_st;           
  logic            icache_top_rd_vld;           
  logic   [1  :0]  icache_top_ref_st;           
  logic   [39 :0]  ifu_biu_araddr;              
  logic   [1  :0]  ifu_biu_arburst;             
  logic   [3  :0]  ifu_biu_arcache;             
  logic            ifu_biu_arid;                
  logic   [1  :0]  ifu_biu_arlen;               
  logic   [2  :0]  ifu_biu_arprot;              
  logic   [2  :0]  ifu_biu_arsize;              
  logic            ifu_biu_arvalid;             
  logic            ifu_cp0_icache_inv_done;     
  logic   [127:0]  ifu_cp0_icache_read_data;    
  logic            ifu_cp0_icache_read_data_vld; 
  logic            ifu_hpcp_icache_access;      
  logic            ifu_hpcp_icache_miss;        
  logic            ifu_mmu_abort;               
  logic   [51 :0]  ifu_mmu_va;                  
  logic            ifu_mmu_va_vld;              
  logic            ifu_yy_xx_no_op;             

  rcore_ifu_icache x_rcore_ifu_icache(
    .biu_ifu_arready(biu_ifu_arready),
    .biu_ifu_rdata(biu_ifu_rdata),
    .biu_ifu_rid(biu_ifu_rid),
    .biu_ifu_rlast(biu_ifu_rlast),
    .biu_ifu_rresp(biu_ifu_rresp),
    .biu_ifu_rvalid(biu_ifu_rvalid),
    .cp0_ifu_icache_en(cp0_ifu_icache_en),
    .cp0_ifu_icache_inv_addr(cp0_ifu_icache_inv_addr),
    .cp0_ifu_icache_inv_req(cp0_ifu_icache_inv_req),
    .cp0_ifu_icache_inv_type(cp0_ifu_icache_inv_type),
    .cp0_ifu_icache_pref_en(cp0_ifu_icache_pref_en),
    .cp0_ifu_icache_read_index(cp0_ifu_icache_read_index),
    .cp0_ifu_icache_read_req(cp0_ifu_icache_read_req),
    .cp0_ifu_icache_read_tag(cp0_ifu_icache_read_tag),
    .cp0_ifu_icache_read_way(cp0_ifu_icache_read_way),
    .cp0_ifu_iwpe(cp0_ifu_iwpe),
    .cp0_ifu_lpmd_req(cp0_ifu_lpmd_req),
    .cpurst_b(rst_n),
    .ctrl_icache_abort(ctrl_icache_abort),
    .ctrl_icache_req_vld(ctrl_icache_req_vld),
    .forever_cpuclk(clk),
    .hpcp_ifu_cnt_en(hpcp_ifu_cnt_en),
    .icache_btb_grant(icache_btb_grant),
    .icache_ctrl_stall(icache_ctrl_stall),
    .icache_ipack_acc_err(icache_ipack_acc_err),
    .icache_ipack_inst(icache_ipack_inst),
    .icache_ipack_inst_vld(icache_ipack_inst_vld),
    .icache_ipack_inst_vld_gate(icache_ipack_inst_vld_gate),
    .icache_ipack_pgflt(icache_ipack_pgflt),
    .icache_ipack_unalign(icache_ipack_unalign),
    .icache_pcgen_addr(icache_pcgen_addr),
    .icache_pcgen_grant(icache_pcgen_grant),
    .icache_pcgen_grant_gate(icache_pcgen_grant_gate),
    .icache_pcgen_inst_vld(icache_pcgen_inst_vld),
    .icache_pcgen_inst_vld_gate(icache_pcgen_inst_vld_gate),
    .icache_pred_inst_vld(icache_pred_inst_vld),
    .icache_pred_inst_vld_gate(icache_pred_inst_vld_gate),
    .icache_top_abort(icache_top_abort),
    .icache_top_inv_st(icache_top_inv_st),
    .icache_top_rd_vld(icache_top_rd_vld),
    .icache_top_ref_st(icache_top_ref_st),
    .ifu_biu_araddr(ifu_biu_araddr),
    .ifu_biu_arburst(ifu_biu_arburst),
    .ifu_biu_arcache(ifu_biu_arcache),
    .ifu_biu_arid(ifu_biu_arid),
    .ifu_biu_arlen(ifu_biu_arlen),
    .ifu_biu_arprot(ifu_biu_arprot),
    .ifu_biu_arsize(ifu_biu_arsize),
    .ifu_biu_arvalid(ifu_biu_arvalid),
    .ifu_cp0_icache_inv_done(ifu_cp0_icache_inv_done),
    .ifu_cp0_icache_read_data(ifu_cp0_icache_read_data),
    .ifu_cp0_icache_read_data_vld(ifu_cp0_icache_read_data_vld),
    .ifu_hpcp_icache_access(ifu_hpcp_icache_access),
    .ifu_hpcp_icache_miss(ifu_hpcp_icache_miss),
    .ifu_mmu_abort(ifu_mmu_abort),
    .ifu_mmu_va(ifu_mmu_va),
    .ifu_mmu_va_vld(ifu_mmu_va_vld),
    .ifu_yy_xx_no_op(ifu_yy_xx_no_op),
    .mmu_ifu_access_fault(mmu_ifu_access_fault),
    .mmu_ifu_pa(mmu_ifu_pa),
    .mmu_ifu_pa_vld(mmu_ifu_pa_vld),
    .mmu_ifu_prot(mmu_ifu_prot),
    .pcgen_icache_chgflw_vld(pcgen_icache_chgflw_vld),
    .pcgen_icache_seq_tag(pcgen_icache_seq_tag),
    .pcgen_icache_va(pcgen_icache_va)
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

  task reset_input();
    // Reset for CP0
    cp0_ifu_icache_en         = 1'b0;

    cp0_ifu_icache_inv_req    = 1'b0;
    cp0_ifu_icache_inv_type   = 2'b00;
    cp0_ifu_icache_inv_addr   = {64{1'b0}};

    cp0_ifu_icache_pref_en    = 1'b0;
    cp0_ifu_icache_read_index = {14{1'b0}};   
    cp0_ifu_icache_read_req   = 1'b0;
    cp0_ifu_icache_read_tag   = 1'b0;
    cp0_ifu_icache_read_way   = 1'b0; 

    cp0_ifu_iwpe              = 1'b0;
    cp0_ifu_lpmd_req          = 1'b0;

    // Reset for ctrl
    ctrl_icache_req_vld       = 1'b0;
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
  `SVTEST(test_icache_clean)
    integer i;
    $display("@%d begin", $time);
    reset_input();
    step(10);

    @(posedge clk); 
    #1;
    // cp0_ifu_icache_inv_addr[63:0] = {64{1'b0}};
    cp0_ifu_icache_inv_req = 1'b1;
    cp0_ifu_icache_inv_type = 2'b00;

    step();

    $display("@%d xxx1", $time);

    while(1) begin
      @(posedge clk);
      if (ifu_cp0_icache_inv_done == 1'b1) break;

      step();
    end

    cp0_ifu_icache_inv_req = 1'b0;
    $display("@%d end", $time);

    step(10);
    // read icache tag for test
    for (i=0; i<256; i=i+1) begin
      @(posedge clk);
      #1;
      cp0_ifu_icache_read_index = i;
      cp0_ifu_icache_read_req   = 1'b1;
      cp0_ifu_icache_read_tag   = 1'b1;
      cp0_ifu_icache_read_way   = 1'b0; 

      step();

      if (ifu_cp0_icache_read_data_vld) begin
        `FAIL_IF(ifu_cp0_icache_read_data[58:0] != 59'b0)
      end
    end

    @(posedge clk);
    #1;
    cp0_ifu_icache_read_index = 14'b0;
    cp0_ifu_icache_read_req   = 1'b0;
    cp0_ifu_icache_read_tag   = 1'b0;
    cp0_ifu_icache_read_way   = 1'b0;

    nextSamplePoint();

    step(10);
  `SVTEST_END

  `SVUNIT_TESTS_END

endmodule
