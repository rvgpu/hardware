`include "svunit_defines.svh"
`include "clk_and_reset.svh"
`include "rvgpu_internal_noc_pkg.svh"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_internal_noc_2sc.sv"
`include "project.v"

module rvgpu_internal_noc_basic_unit_test;
  import svunit_pkg::svunit_testcase;
  import rvgpu_internal_noc_pkg::*;

  string name = "ut_rvgpu_internal_noc_basic";
  svunit_testcase svunit_ut;

  //===================================
  // 时钟和复位
  //===================================
  `CLK_RESET_FIXTURE(5, 10)        
    
  //===================================
  // NOC配置和接口
  //===================================
  localparam noc_config_t NOC_CONFIG = '{
    data_width: 256,
    header_width: 32,
    vc_count: 4,
    buffer_depth: 16,
    num_shader_cores: 2,
    max_pending_trans: 16,
    debug_enable: 1'b1
  };

  rvgpu_internal_noc_if #(.NOC_CONFIG(NOC_CONFIG)) control_unit_if();
  rvgpu_internal_noc_if #(.NOC_CONFIG(NOC_CONFIG)) shader_core_if[NOC_CONFIG.num_shader_cores]();
  rvgpu_internal_noc_if #(.NOC_CONFIG(NOC_CONFIG)) l2cache_if();

  typedef struct packed {
    logic [31:0] header;
    logic [255:0] data;
  } package_data_t;

  // 声明包数据变量
  package_data_t package_data;

  // 定义虚拟接口类型，用于在task中将真实的接口作为参数传递
  typedef virtual rvgpu_internal_noc_if #(.NOC_CONFIG(NOC_CONFIG)) vif_t;

  // DUT实例
  rvgpu_internal_noc #(
    .NOC_CONFIG(NOC_CONFIG)
  ) x_rvgpu_internal_noc (
    .clk(clk),
    .rst_n(rst_n),
    .control_unit(control_unit_if.noc),
    .shader_core(shader_core_if),
    .l2cache(l2cache_if.noc)
  );


  //===================================
  // Build
  //===================================
  function void build();
    svunit_ut = new(name);
  endfunction

  //===================================
  // 信号初始化任务
  //===================================
  task initialize_signals();
    // 初始化Control Unit接口
    control_unit_if.m_req_valid = 0;
    control_unit_if.m_req_header = 0;
    control_unit_if.m_req_data = 0;
    control_unit_if.m_req_strb = 0;
    control_unit_if.m_req_last = 0;
    control_unit_if.m_resp_ready = 0;
    control_unit_if.s_resp_valid = 0;
    control_unit_if.s_resp_header = 0;
    control_unit_if.s_resp_data = 0;
    control_unit_if.s_resp_status = RESP_OKAY;
    control_unit_if.s_resp_last = 0;
    control_unit_if.s_req_ready = 0;

    // 初始化L2 Cache接口
    l2cache_if.m_req_valid = 0;
    l2cache_if.m_req_header = 0;
    l2cache_if.m_req_data = 0;
    l2cache_if.m_req_strb = 0;
    l2cache_if.m_req_last = 0;
    l2cache_if.m_resp_ready = 0;
    l2cache_if.s_resp_valid = 0;
    l2cache_if.s_resp_header = 0;
    l2cache_if.s_resp_data = 0;
    l2cache_if.s_resp_status = RESP_OKAY;
    l2cache_if.s_resp_last = 0;
    l2cache_if.s_req_ready = 0;

    init_shader_cores();
  endtask

  // 专门的shader core初始化任务
  task init_shader_cores();
    if (NOC_CONFIG.num_shader_cores > 0) begin
      shader_core_if[0].m_req_valid = 0;
      shader_core_if[0].m_req_header = 0;
      shader_core_if[0].m_req_data = 0;
      shader_core_if[0].m_req_strb = 0;
      shader_core_if[0].m_req_last = 0;
      shader_core_if[0].m_resp_ready = 0;
      shader_core_if[0].s_resp_valid = 0;
      shader_core_if[0].s_resp_header = 0;
      shader_core_if[0].s_resp_data = 0;
      shader_core_if[0].s_resp_status = RESP_OKAY;
      shader_core_if[0].s_resp_last = 0;
      shader_core_if[0].s_req_ready = 0;
    end
    if (NOC_CONFIG.num_shader_cores > 1) begin
      shader_core_if[1].m_req_valid = 0;
      shader_core_if[1].m_req_header = 0;
      shader_core_if[1].m_req_data = 0;
      shader_core_if[1].m_req_strb = 0;
      shader_core_if[1].m_req_last = 0;
      shader_core_if[1].m_resp_ready = 0;
      shader_core_if[1].s_resp_valid = 0;
      shader_core_if[1].s_resp_header = 0;
      shader_core_if[1].s_resp_data = 0;
      shader_core_if[1].s_resp_status = RESP_OKAY;
      shader_core_if[1].s_resp_last = 0;
      shader_core_if[1].s_req_ready = 0;
    end
  endtask

  //===================================
  // Setup
  //===================================
  task setup();
    svunit_ut.setup();
    $vcdpluson();
    
    $display("@%0t: Setup starting, current clock = %b", $time, clk);
    initialize_signals();
    $display("@%0t: initialize_signals completed, current clock = %b", $time, clk);
    reset();
    $display("@%0t: reset completed, current clock = %b", $time, clk);
  endtask

  //===================================
  // Teardown
  //===================================
  task teardown();
    svunit_ut.teardown();
  endtask

  //===================================
  // 辅助任务和函数
  //===================================
  
  // 检查所有信号是否正确初始化为默认值
  task check_reset_state();
    $display("@%0t: Starting check_reset_state", $time);

    `FAIL_IF(control_unit_if.m_req_valid !== 1'b0)
    `FAIL_IF(control_unit_if.m_req_header !== 32'h0)
    `FAIL_IF(control_unit_if.m_req_data !== 256'h0)
    `FAIL_IF(control_unit_if.m_req_strb !== 32'h0)
    `FAIL_IF(control_unit_if.m_req_last !== 1'b0)
    `FAIL_IF(control_unit_if.m_resp_ready !== 1'b0)
    `FAIL_IF(control_unit_if.s_resp_valid !== 1'b0)
    `FAIL_IF(control_unit_if.s_resp_header !== 32'h0)
    `FAIL_IF(control_unit_if.s_resp_data !== 256'h0)
    `FAIL_IF(control_unit_if.s_resp_status !== RESP_OKAY)
    `FAIL_IF(control_unit_if.s_resp_last !== 1'b0)
    `FAIL_IF(control_unit_if.s_req_ready !== 1'b0)

    `FAIL_IF(l2cache_if.m_req_valid !== 1'b0)
    `FAIL_IF(l2cache_if.m_req_header !== 32'h0)
    `FAIL_IF(l2cache_if.m_req_data !== 256'h0)
    `FAIL_IF(l2cache_if.m_req_strb !== 32'h0)
    `FAIL_IF(l2cache_if.m_req_last !== 1'b0)
    `FAIL_IF(l2cache_if.m_resp_ready !== 1'b0)
    `FAIL_IF(l2cache_if.s_resp_valid !== 1'b0)
    `FAIL_IF(l2cache_if.s_resp_header !== 32'h0)
    `FAIL_IF(l2cache_if.s_resp_data !== 256'h0)
    `FAIL_IF(l2cache_if.s_resp_status !== RESP_OKAY)
    `FAIL_IF(l2cache_if.s_resp_last !== 1'b0)
    `FAIL_IF(l2cache_if.s_req_ready !== 1'b0)

    `FAIL_IF(shader_core_if[0].m_req_valid !== 1'b0)
    `FAIL_IF(shader_core_if[0].m_req_header !== 32'h0)
    `FAIL_IF(shader_core_if[0].m_req_data !== 256'h0)
    `FAIL_IF(shader_core_if[0].m_req_strb !== 32'h0)
    `FAIL_IF(shader_core_if[0].m_req_last !== 1'b0)
    `FAIL_IF(shader_core_if[0].m_resp_ready !== 1'b0)
    `FAIL_IF(shader_core_if[0].s_resp_valid !== 1'b0)
    `FAIL_IF(shader_core_if[0].s_resp_header !== 32'h0)
    `FAIL_IF(shader_core_if[0].s_resp_data !== 256'h0)
    `FAIL_IF(shader_core_if[0].s_resp_status !== RESP_OKAY)
    `FAIL_IF(shader_core_if[0].s_resp_last !== 1'b0)
    `FAIL_IF(shader_core_if[0].s_req_ready !== 1'b0)

    `FAIL_IF(shader_core_if[1].m_req_valid !== 1'b0)
    `FAIL_IF(shader_core_if[1].m_req_header !== 32'h0)
    `FAIL_IF(shader_core_if[1].m_req_data !== 256'h0)
    `FAIL_IF(shader_core_if[1].m_req_strb !== 32'h0)
    `FAIL_IF(shader_core_if[1].m_req_last !== 1'b0)
    `FAIL_IF(shader_core_if[1].m_resp_ready !== 1'b0)
    `FAIL_IF(shader_core_if[1].s_resp_valid !== 1'b0)
    `FAIL_IF(shader_core_if[1].s_resp_header !== 32'h0)
    `FAIL_IF(shader_core_if[1].s_resp_data !== 256'h0)
    `FAIL_IF(shader_core_if[1].s_resp_status !== RESP_OKAY)
    `FAIL_IF(shader_core_if[1].s_resp_last !== 1'b0)
    `FAIL_IF(shader_core_if[1].s_req_ready !== 1'b0)
    
    $display("@%0t: All interfaces in correct reset state", $time);
  endtask
  
  // 测试端口信号连接的任务
  task test_port_connectivity();
    noc_header_t test_header;
    logic [255:0] test_data;
    logic [31:0] test_strb;
    
    // 构造测试数据
    test_header = build_noc_header(MSG_MEM_READ_REQ, 8'hAB, NODE_CONTROL, NODE_L2_CACHE, 8'h10);
    test_data = 256'hDEADBEEF_CAFEBABE_12345678_9ABCDEF0_FEDCBA98_76543210_ABCDEF01_23456789;
    test_strb = 32'hFFFFFFFF;
    
    // 测试Control Unit Master端口连接
    step(1); // 使用SVUnit的step任务产生一个时钟周期
    control_unit_if.m_req_valid = 1'b1;
    control_unit_if.m_req_header = test_header;
    control_unit_if.m_req_data = test_data;
    control_unit_if.m_req_strb = test_strb;
    control_unit_if.m_req_last = 1'b1;
    
    step(1); // 使用SVUnit的step任务产生一个时钟周期
    // 检查信号是否正确传播到DUT内部端口
    `FAIL_IF(x_rvgpu_internal_noc.port_req_out[NODE_CONTROL].valid !== 1'b1)
    `FAIL_IF(x_rvgpu_internal_noc.port_req_out[NODE_CONTROL].header !== test_header)
    `FAIL_IF(x_rvgpu_internal_noc.port_req_out[NODE_CONTROL].data !== test_data)
    `FAIL_IF(x_rvgpu_internal_noc.port_req_out[NODE_CONTROL].strb !== test_strb)
    `FAIL_IF(x_rvgpu_internal_noc.port_req_out[NODE_CONTROL].last !== 1'b1)
    
    // 复位信号
    control_unit_if.m_req_valid = 1'b0;
    control_unit_if.m_req_header = 32'h0;
    control_unit_if.m_req_data = 256'h0;
    control_unit_if.m_req_strb = 32'h0;
    control_unit_if.m_req_last = 1'b0;
    
    step(1); // 使用SVUnit的step任务产生一个时钟周期
    `FAIL_IF(x_rvgpu_internal_noc.port_req_out[NODE_CONTROL].valid !== 1'b0)
    
    $display("@%0t: Port connectivity test passed", $time);
  endtask
  
  // 测试Ready信号反向传播
  task test_ready_signal_propagation();
    // 设置L2 Cache接口ready信号
    l2cache_if.s_req_ready = 1'b1;
    
    step(1);
    nextSamplePoint();
    
    // 检查ready信号是否正确传播
    // 当从Control Unit发送请求到L2 Cache时，ready信号应该正确传播
    control_unit_if.m_req_valid = 1'b1;
    control_unit_if.m_req_header = build_noc_header(MSG_MEM_READ_REQ, 8'h01, NODE_CONTROL, NODE_L2_CACHE, 8'h00);
    control_unit_if.m_req_data = 256'h12345678;
    control_unit_if.m_req_strb = 32'hFFFFFFFF;
    control_unit_if.m_req_last = 1'b1;
    
    step(1);
    nextSamplePoint();
    
    // 检查ready信号传播
    `FAIL_IF(control_unit_if.m_req_ready !== 1'b1)
    
    // 复位信号
    control_unit_if.m_req_valid = 1'b0;
    l2cache_if.s_req_ready = 1'b0;
    
    $display("@%0t: Ready signal propagation test passed", $time);
  endtask
  
  // 测试响应路径连接
  task test_response_path_connectivity();
    noc_header_t resp_header;
    logic [255:0] resp_data;
    
    // 构造响应数据
    resp_header = build_noc_header(MSG_MEM_READ_RESP, 8'hCD, NODE_L2_CACHE, NODE_CONTROL, 8'h00);
    resp_data = 256'h87654321_FEDCBA98_76543210_ABCDEF01_23456789_DEADBEEF_CAFEBABE_12345678;
    
    // 从L2 Cache发送响应
    step(1); // 使用SVUnit的step任务产生一个时钟周期
    l2cache_if.s_resp_valid = 1'b1;
    l2cache_if.s_resp_header = resp_header;
    l2cache_if.s_resp_data = resp_data;
    l2cache_if.s_resp_status = RESP_OKAY;
    l2cache_if.s_resp_last = 1'b1;
    
    step(1); // 使用SVUnit的step任务产生一个时钟周期
    #1; // 等待组合逻辑稳定
    
    // 检查响应是否正确传播到内部端口
    `FAIL_IF(x_rvgpu_internal_noc.port_resp_out[NODE_L2_CACHE].valid !== 1'b1)
    `FAIL_IF(x_rvgpu_internal_noc.port_resp_out[NODE_L2_CACHE].header !== resp_header)
    `FAIL_IF(x_rvgpu_internal_noc.port_resp_out[NODE_L2_CACHE].data !== resp_data)
    `FAIL_IF(x_rvgpu_internal_noc.port_resp_out[NODE_L2_CACHE].status !== RESP_OKAY)
    `FAIL_IF(x_rvgpu_internal_noc.port_resp_out[NODE_L2_CACHE].last !== 1'b1)
    
    // 复位信号
    l2cache_if.s_resp_valid = 1'b0;
    l2cache_if.s_resp_header = 32'h0;
    l2cache_if.s_resp_data = 256'h0;
    l2cache_if.s_resp_status = RESP_OKAY;
    l2cache_if.s_resp_last = 1'b0;
    
    $display("@%0t: Response path connectivity test passed", $time);
  endtask

  task packet_send(vif_t noc_if, package_data_t package_data);
    noc_if.m_req_valid = 1'b1;
    noc_if.m_req_header = package_data.header;
    noc_if.m_req_data = package_data.data;
    noc_if.m_req_strb = 32'hFFFFFFFF;
    noc_if.m_req_last = 1'b1;
    $display("@%0t: packet_send - Header: 0x%08x, Data: 0x%064x", 
             $time, package_data.header, package_data.data);
  endtask

  task packet_receive_check(vif_t noc_if, package_data_t package_data);
    `FAIL_IF(noc_if.s_req_valid !== 1'b1)
    `FAIL_IF(noc_if.s_req_header !== package_data.header)
    `FAIL_IF(noc_if.s_req_data !== package_data.data)
    `FAIL_IF(noc_if.s_req_strb !== 32'hFFFFFFFF)
    `FAIL_IF(noc_if.s_req_last !== 1'b1)
    $display("@%0t: packet_receive_check passed - Header: 0x%08x, Data: 0x%064x", 
             $time, package_data.header, package_data.data);
  endtask

  // 额外的辅助任务 - 清理发送信号
  task packet_clear_send(vif_t noc_if);
    noc_if.m_req_valid = 1'b0;
    noc_if.m_req_header = 32'h0;
    noc_if.m_req_data = 256'h0;
    noc_if.m_req_strb = 32'h0;
    noc_if.m_req_last = 1'b0;
  endtask

  // 额外的辅助任务 - 设置接收准备状态
  task packet_set_ready(vif_t noc_if, logic ready_state);
    noc_if.s_req_ready = ready_state;
  endtask

  task packend_send_and_receive(vif_t from, vif_t to, package_data_t package_data);
    packet_set_ready(shader_core_if[0], 1'b1);
    package_data.header = build_noc_header(MSG_COMPUTE_REQ, 8'h11, NODE_CONTROL, NODE_SHADER_0, 8'h00);
    package_data.data = 256'hA5A5A5A5_5A5A5A5A_F0F0F0F0_0F0F0F0F_CCCCCCCC_33333333_AAAAAAAA_55555555;
    packet_send(control_unit_if, package_data);
    step(1);
    nextSamplePoint();
    packet_receive_check(shader_core_if[0], package_data);
    // 清理发送信号
    packet_clear_send(control_unit_if);
    packet_set_ready(shader_core_if[0], 1'b0);

    step(10);
  endtask

  //===================================
  // 测试用例
  //===================================
  `SVUNIT_TESTS_BEGIN
    
    //=================================
    // 测试基本复位和初始化
    //=================================
    `SVTEST(test_basic_reset_initialization)
      $display("============== 1. Testing Basic Reset and Initialization ==============");
      initialize_signals();
      step(100);
      
      // 验证复位后所有信号都处于正确的初始状态
      check_reset_state();
      
      // 测试多次复位
      for (int i = 0; i < 3; i++) begin
        reset(); // reset()任务本身会调用step()
        check_reset_state();
        $display("Reset cycle %0d passed", i+1);
      end
      
      // 测试信号稳定性，使用step()产生时钟周期
      $display("@%0t: Testing signal stability...", $time);
      $display("@%0t: Current clock value = %b", $time, clk);
      
      // 等待几个时钟周期
      step(5); // 产生5个时钟周期
      
      $display("@%0t: After step(5), current clock = %b", $time, clk);
      check_reset_state();
      $display("@%0t: Final check_reset_state() completed", $time);
      
      $display("============== 1. Basic reset and initialization test passed ==============");
    `SVTEST_END
    
    //=================================
    // 测试端口信号连接
    //=================================
    `SVTEST(test_port_signal_connectivity)
      $display("============== 2. Testing Port Signal Connectivity ==============");
      initialize_signals();
      step(100);
      
      // 测试请求路径连接
      test_port_connectivity();
      
      // 测试Ready信号传播
      test_ready_signal_propagation();
      
      // 测试响应路径连接
      test_response_path_connectivity();
      
      $display("============== 2. Port signal connectivity test passed ==============");
    `SVTEST_END
    
    //=================================
    // 测试接口modport连接
    //=================================
    `SVTEST(test_interface_modport_connections)
      $display("============== 3. Testing Interface Modport Connections ==============");
      initialize_signals();
      step(100);
      
      // Control Unit -> Shader Core 0
      package_data.header = build_noc_header(MSG_COMPUTE_REQ, 8'h11, NODE_CONTROL, NODE_SHADER_0, 8'h00);
      package_data.data = 256'hA5A5A5A5_5A5A5A5A_F0F0F0F0_0F0F0F0F_CCCCCCCC_33333333_AAAAAAAA_55555555;
      packend_send_and_receive(control_unit_if, shader_core_if[0], package_data);

      // Control Unit -> Shader Core 1
      package_data.header = build_noc_header(MSG_COMPUTE_REQ, 8'h22, NODE_CONTROL, NODE_SHADER_1, 8'h00);
      package_data.data = 256'h1111222233334444_5555666677778888_9999AAAABBBBCCCC_DDDDEEEEFFFFAAAA;
      packend_send_and_receive(control_unit_if, shader_core_if[1], package_data);

      // Control Unit -> L2 Cache
      package_data.header = build_noc_header(MSG_MEM_WRITE_REQ, 8'h33, NODE_CONTROL, NODE_L2_CACHE, 8'h20);
      package_data.data = 256'hFFFFFFFF_00000000_FFFFFFFF_00000000_FFFFFFFF_00000000_FFFFFFFF_00000000;
      packend_send_and_receive(control_unit_if, l2cache_if, package_data);

      // Shader Core 0 -> Control Unit
      package_data.header = build_noc_header(MSG_COMPUTE_RESP, 8'h44, NODE_SHADER_0, NODE_CONTROL, 8'h00);
      package_data.data = 256'h12345678_9ABCDEF0_FEDCBA98_76543210_ABCDEF01_23456789_DEADBEEF_CAFEBABE;
      packend_send_and_receive(shader_core_if[0], control_unit_if, package_data);

      // Shader Core 1 -> Control Unit
      package_data.header = build_noc_header(MSG_COMPUTE_RESP, 8'h55, NODE_SHADER_1, NODE_CONTROL, 8'h00);
      package_data.data = 256'h12345678_9ABCDEF0_FEDCBA98_76543210_ABCDEF01_23456789_DEADBEEF_CAFEBABE;
      packend_send_and_receive(shader_core_if[1], control_unit_if, package_data);

      // L2 Cache -> Control Unit
      package_data.header = build_noc_header(MSG_MEM_WRITE_RESP, 8'h66, NODE_L2_CACHE, NODE_CONTROL, 8'h00);
      package_data.data = 256'h12345678_9ABCDEF0_FEDCBA98_76543210_ABCDEF01_23456789_DEADBEEF_CAFEBABE;
      packend_send_and_receive(l2cache_if, control_unit_if, package_data);

      // L2 Cache -> Shader Core 0
      package_data.header = build_noc_header(MSG_MEM_READ_RESP, 8'h77, NODE_L2_CACHE, NODE_SHADER_0, 8'h00);
      package_data.data = 256'h12345678_9ABCDEF0_FEDCBA98_76543210_ABCDEF01_23456789_DEADBEEF_CAFEBABE;
      packend_send_and_receive(l2cache_if, shader_core_if[0], package_data);

      // L2 Cache -> Shader Core 1
      package_data.header = build_noc_header(MSG_MEM_READ_RESP, 8'h88, NODE_L2_CACHE, NODE_SHADER_1, 8'h00);
      package_data.data = 256'h12345678_9ABCDEF0_FEDCBA98_76543210_ABCDEF01_23456789_DEADBEEF_CAFEBABE;
      packend_send_and_receive(l2cache_if, shader_core_if[1], package_data);

      // Shader Core 0 -> Shader Core 1
      package_data.header = build_noc_header(MSG_COMPUTE_REQ, 8'h99, NODE_SHADER_0, NODE_SHADER_1, 8'h00);
      package_data.data = 256'h12345678_9ABCDEF0_FEDCBA98_76543210_ABCDEF01_23456789_DEADBEEF_CAFEBABE;
      packend_send_and_receive(shader_core_if[0], shader_core_if[1], package_data);

      // Shader Core 1 -> Shader Core 0
      package_data.header = build_noc_header(MSG_COMPUTE_REQ, 8'hAA, NODE_SHADER_1, NODE_SHADER_0, 8'h00);
      package_data.data = 256'h12345678_9ABCDEF0_FEDCBA98_76543210_ABCDEF01_23456789_DEADBEEF_CAFEBABE;
      packend_send_and_receive(shader_core_if[1], shader_core_if[0], package_data);

      // Shader Core 0 -> L2 Cache
      package_data.header = build_noc_header(MSG_MEM_WRITE_REQ, 8'hBB, NODE_SHADER_0, NODE_L2_CACHE, 8'h20);
      package_data.data = 256'hFFFFFFFF_00000000_FFFFFFFF_00000000_FFFFFFFF_00000000_FFFFFFFF_00000000;
      packend_send_and_receive(shader_core_if[0], l2cache_if, package_data);

      $display("============== 3. Interface modport connections test passed ==============");
    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule 
