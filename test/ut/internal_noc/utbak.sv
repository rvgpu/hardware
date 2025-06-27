`include "svunit_defines.svh"
`include "clk_and_reset.svh"
`include "rvgpu_internal_noc_pkg.sv"
`include "rvgpu_internal_noc_if.svh"
`include "rvgpu_internal_noc.sv"
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
  localparam noc_config_t noc_config = get_default_noc_config();
  
  // NOC接口实例
  rvgpu_internal_noc_if #(.NOC_CONFIG(noc_config)) control_unit_if();
  rvgpu_internal_noc_if #(.NOC_CONFIG(noc_config)) shader_core_if[noc_config.num_shader_cores]();
  rvgpu_internal_noc_if #(.NOC_CONFIG(noc_config)) l2cache_if();

  // DUT实例
  rvgpu_internal_noc #(
    .NOC_CONFIG(noc_config)
  ) x_rvgpu_internal_noc (
    .clk(clk),
    .rst_n(rst_n),
    .control_unit(control_unit_if),
    .shader_core(shader_core_if),
    .l2cache(l2cache_if)
  );

  //===================================
  // 测试数据结构
  //===================================
  typedef struct {
    logic [47:0]        target_addr;
    noc_msg_type_t      msg_type;
    logic [7:0]         trans_id;
    noc_node_id_t       expected_node;
  } routing_test_data_t;

  // 测试数据队列
  routing_test_data_t routing_test_data[$];

  // 测试消息payload
  logic [255:0] test_payload = 256'hDEADBEEF_CAFEBABE_12345678_9ABCDEF0_FEDCBA98_76543210_ABCDEF01_23456789;

  //===================================
  // Build
  //===================================
  function void build();
    svunit_ut = new(name);
  endfunction

  //===================================
  // Setup
  //===================================
  task setup();
    svunit_ut.setup();
    `ifdef WAVES
      $vcdpluson();
    `endif
    
    // 连接时钟和复位
    control_unit_if.connect_clock(clk, rst_n);
    shader_core_if[0].connect_clock(clk, rst_n);
    shader_core_if[1].connect_clock(clk, rst_n);
    shader_core_if[2].connect_clock(clk, rst_n);
    shader_core_if[3].connect_clock(clk, rst_n);
    l2cache_if.connect_clock(clk, rst_n);    
    // 初始化接口信号
    init_interfaces();
    
    reset();
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
  
  // 初始化所有接口信号
  task init_interfaces();
    // Control Unit接口初始化
    control_unit_if.init_signals();
    shader_core_if[0].init_signals();
    shader_core_if[1].init_signals();
    shader_core_if[2].init_signals();
    shader_core_if[3].init_signals();
    l2cache_if.init_signals();
  endtask

//   // 读取路由测试数据
//   function automatic void read_routing_test_data(output routing_test_data_t test_data[$]);
//     int fd;
//     int ret;
//     string line;
//     string realpath = {`RVGPU_HARDWARE_TOPPATH_STR, "/test/ut/internal_noc/test_data/routing_test_data.hex"};
    
//     $display("Reading test data from: %s", realpath);
    
//     if ((fd = $fopen(realpath, "r")) == 0) begin
//       $display("Error: Unable to open file %s", realpath);
//       return;
//     end

//     while (!$feof(fd)) begin
//       if ($fgets(line, fd)) begin
//         // 跳过注释行和空行
//         if (line[0] == "#" || line.len() == 0) continue;
        
//         routing_test_data_t data;
//         logic [7:0] msg_type_val;
//         logic [3:0] node_id_val;
        
//         ret = $sscanf(line, "%h %h %h %h", 
//                      data.target_addr, 
//                      msg_type_val, 
//                      data.trans_id, 
//                      node_id_val);
//         if (ret == 4) begin
//           data.msg_type = noc_msg_type_t'(msg_type_val);
//           data.expected_node = noc_node_id_t'(node_id_val);
//           test_data.push_back(data);
//         end
//       end
//     end
    
//     $fclose(fd);
//     $display("Loaded %0d routing test cases", test_data.size());
//   endfunction

//   // 从Control Unit发送请求
//   task send_control_request(
//     input logic [47:0] target_addr,
//     input noc_msg_type_t msg_type,
//     input logic [7:0] trans_id,
//     input logic [255:0] payload_data = test_payload,
//     input logic [31:0] strb = '1
//   );
//     noc_header_t header;
    
//     header = build_noc_header(msg_type, trans_id, target_addr);
    
//     @(posedge clk);
//     control_unit_if.master_port.req_valid <= 4'b0001;
//     control_unit_if.master_port.req_header <= header;
//     control_unit_if.master_port.req_data <= payload_data;
//     control_unit_if.master_port.req_strb <= strb;
//     control_unit_if.master_port.req_last <= 1'b1;
    
//     // 等待ready
//     do @(posedge clk); while (!control_unit_if.master_port.req_ready[0]);
//     control_unit_if.master_port.req_valid <= 4'b0000;
    
//     $display("@%0t Sent REQ from Control: target=0x%h, type=%s, id=0x%h", 
//              $time, target_addr, get_msg_type_name(msg_type), trans_id);
//   endtask

//   // 从Shader Core发送请求
//   task send_shader_request(
//     input int shader_id,
//     input logic [47:0] target_addr,
//     input noc_msg_type_t msg_type,
//     input logic [7:0] trans_id,
//     input logic [255:0] payload_data = test_payload
//   );
//     noc_header_t header;
    
//     header = build_noc_header(msg_type, trans_id, target_addr);
    
//     @(posedge clk);
//     shader_core_if[shader_id].master_port.req_valid <= 4'b0001;
//     shader_core_if[shader_id].master_port.req_header <= header;
//     shader_core_if[shader_id].master_port.req_data <= payload_data;
//     shader_core_if[shader_id].master_port.req_strb <= '1;
//     shader_core_if[shader_id].master_port.req_last <= 1'b1;
    
//     // 等待ready
//     do @(posedge clk); while (!shader_core_if[shader_id].master_port.req_ready[0]);
//     shader_core_if[shader_id].master_port.req_valid <= 4'b0000;
    
//     $display("@%0t Sent REQ from Shader[%0d]: target=0x%h, type=%s, id=0x%h", 
//              $time, shader_id, target_addr, get_msg_type_name(msg_type), trans_id);
//   endtask

//   // 从L2Cache发送响应
//   task send_l2cache_response(
//     input logic [47:0] target_addr,
//     input noc_msg_type_t resp_type,
//     input logic [7:0] trans_id,
//     input noc_resp_t resp_status = RESP_OKAY,
//     input logic [255:0] resp_data = test_payload
//   );
//     noc_header_t header;
    
//     header = build_noc_header(resp_type, trans_id, target_addr);
    
//     @(posedge clk);
//     l2cache_if.master_port.resp_valid <= 4'b0001;
//     l2cache_if.master_port.resp_header <= header;
//     l2cache_if.master_port.resp_data <= resp_data;
//     l2cache_if.master_port.resp_status <= resp_status;
//     l2cache_if.master_port.resp_last <= 1'b1;
    
//     // 等待ready
//     do @(posedge clk); while (!l2cache_if.master_port.resp_ready[0]);
//     l2cache_if.master_port.resp_valid <= 4'b0000;
    
//     $display("@%0t Sent RESP from L2Cache: target=0x%h, type=%s, id=0x%h, status=%s", 
//              $time, target_addr, get_msg_type_name(resp_type), trans_id, 
//              (resp_status == RESP_OKAY) ? "OKAY" : "ERROR");
//   endtask

//   // 验证Shader Core接收到请求
//   task verify_shader_request_received(
//     input int shader_id,
//     input logic [7:0] expected_trans_id,
//     input logic timeout_cycles = 10
//   );
//     logic received = 1'b0;
//     int cycle_count = 0;
    
//     // 设置ready信号
//     shader_core_if[shader_id].slave_port.req_ready <= 4'b0001;
    
//     while (!received && cycle_count < timeout_cycles) begin
//       @(posedge clk);
//       cycle_count++;
      
//       if (shader_core_if[shader_id].slave_port.req_valid[0]) begin
//         noc_header_t received_header = noc_header_t'(shader_core_if[shader_id].slave_port.req_header);
//         `FAIL_IF(received_header.trans_id !== expected_trans_id)
//         received = 1'b1;
//         $display("@%0t Shader[%0d] received REQ: trans_id=0x%h", 
//                  $time, shader_id, received_header.trans_id);
//       end
//     end
    
//     shader_core_if[shader_id].slave_port.req_ready <= 4'b0000;
//     `FAIL_IF(!received)
//   endtask

//   // 验证L2Cache接收到请求
//   task verify_l2cache_request_received(
//     input logic [7:0] expected_trans_id,
//     input logic timeout_cycles = 10
//   );
//     logic received = 1'b0;
//     int cycle_count = 0;
    
//     // 设置ready信号
//     l2cache_if.slave_port.req_ready <= 4'b0001;
    
//     while (!received && cycle_count < timeout_cycles) begin
//       @(posedge clk);
//       cycle_count++;
      
//       if (l2cache_if.slave_port.req_valid[0]) begin
//         noc_header_t received_header = noc_header_t'(l2cache_if.slave_port.req_header);
//         `FAIL_IF(received_header.trans_id !== expected_trans_id)
//         received = 1'b1;
//         $display("@%0t L2Cache received REQ: trans_id=0x%h", 
//                  $time, received_header.trans_id);
//       end
//     end
    
//     l2cache_if.slave_port.req_ready <= 4'b0000;
//     `FAIL_IF(!received)
//   endtask

//   // 验证Control Unit接收到响应
//   task verify_control_response_received(
//     input logic [7:0] expected_trans_id,
//     input logic timeout_cycles = 10
//   );
//     logic received = 1'b0;
//     int cycle_count = 0;
    
//     // 设置ready信号
//     control_unit_if.slave_port.resp_ready <= 4'b0001;
    
//     while (!received && cycle_count < timeout_cycles) begin
//       @(posedge clk);
//       cycle_count++;
      
//       if (control_unit_if.slave_port.resp_valid[0]) begin
//         noc_header_t received_header = noc_header_t'(control_unit_if.slave_port.resp_header);
//         `FAIL_IF(received_header.trans_id !== expected_trans_id)
//         received = 1'b1;
//         $display("@%0t Control received RESP: trans_id=0x%h", 
//                  $time, received_header.trans_id);
//       end
//     end
    
//     control_unit_if.slave_port.resp_ready <= 4'b0000;
//     `FAIL_IF(!received)
//   endtask

  //===================================
  // 测试用例
  //===================================
  `SVUNIT_TESTS_BEGIN
    `SVTEST(test_basic_routing)
      $display("=== Testing Basic Routing ===");
    `SVTEST_END

  //---------------------------------
  // 测试基本路由功能
  //---------------------------------
//   `SVTEST(test_basic_routing)
//     $display("=== Testing Basic Routing ===");
    
//     // 加载测试数据
//     read_routing_test_data(routing_test_data);
    
//     // 测试路由函数
//     foreach (routing_test_data[i]) begin
//       routing_test_data_t test_case = routing_test_data[i];
//       noc_node_id_t actual_route = get_route_target(test_case.target_addr);
      
//       $display("Testing route case %0d: addr=0x%h, expected=%s, actual=%s", 
//                i, test_case.target_addr, 
//                get_node_name(test_case.expected_node),
//                get_node_name(actual_route));
      
//       `FAIL_IF(actual_route !== test_case.expected_node)
//     end
    
//     $display("Basic routing test passed");
//   `SVTEST_END

//   //---------------------------------
//   // 测试Control Unit到Shader Core的请求路由
//   //---------------------------------
//   `SVTEST(test_control_to_shader_request)
//     $display("=== Testing Control Unit to Shader Core Request ===");
    
//     // 测试到Shader Core 0的路由
//     send_control_request(48'h100000000000, MSG_COMPUTE_REQ, 8'h01);
//     verify_shader_request_received(0, 8'h01);
    
//     // 测试到Shader Core 1的路由
//     send_control_request(48'h300000000000, MSG_COMPUTE_REQ, 8'h02);
//     verify_shader_request_received(1, 8'h02);
    
//     // 测试到Shader Core 2的路由
//     send_control_request(48'h400000000000, MSG_COMPUTE_REQ, 8'h03);
//     verify_shader_request_received(2, 8'h03);
    
//     // 测试到Shader Core 3的路由
//     send_control_request(48'h500000000000, MSG_COMPUTE_REQ, 8'h04);
//     verify_shader_request_received(3, 8'h04);
    
//     $display("Control to Shader request routing test passed");
//   `SVTEST_END

//   //---------------------------------
//   // 测试Control Unit到L2Cache的请求路由
//   //---------------------------------
//   `SVTEST(test_control_to_l2cache_request)
//     $display("=== Testing Control Unit to L2Cache Request ===");
    
//     // 测试内存读请求
//     send_control_request(48'h200000000000, MSG_MEM_READ_REQ, 8'h10);
//     verify_l2cache_request_received(8'h10);
    
//     // 测试内存写请求
//     send_control_request(48'h200000001000, MSG_MEM_WRITE_REQ, 8'h11);
//     verify_l2cache_request_received(8'h11);
    
//     $display("Control to L2Cache request routing test passed");
//   `SVTEST_END

// //   //---------------------------------
// //   // 测试Shader Core到L2Cache的请求路由
// //   //---------------------------------
// //   `SVTEST(test_shader_to_l2cache_request)
// //     $display("=== Testing Shader Core to L2Cache Request ===");
    
// //     // Shader Core 1发送内存读请求到L2Cache
// //     send_shader_request(1, 48'h200000000000, MSG_MEM_READ_REQ, 8'h20);
// //     verify_l2cache_request_received(8'h20);
    
// //     // Shader Core 2发送内存写请求到L2Cache
// //     send_shader_request(2, 48'h200000001000, MSG_MEM_WRITE_REQ, 8'h21);
// //     verify_l2cache_request_received(8'h21);
    
// //     $display("Shader to L2Cache request routing test passed");
// //   `SVTEST_END

// // //   //---------------------------------
// // //   // 测试L2Cache到Control Unit的响应路由
// // //   //---------------------------------
// // //   `SVTEST(test_l2cache_to_control_response)
// // //     $display("=== Testing L2Cache to Control Unit Response ===");
    
// // //     // L2Cache发送读响应到Control Unit
// // //     send_l2cache_response(48'h000000000000, MSG_MEM_READ_RESP, 8'h30);
// // //     verify_control_response_received(8'h30);
    
// // //     // L2Cache发送写响应到Control Unit
// // //     send_l2cache_response(48'h000000000000, MSG_MEM_WRITE_RESP, 8'h31);
// // //     verify_control_response_received(8'h31);
    
// // //     $display("L2Cache to Control response routing test passed");
// // //   `SVTEST_END

// // // //   //---------------------------------
// // // //   // 测试L2Cache到Shader Core的响应路由
// // // //   //---------------------------------
// // // //   `SVTEST(test_l2cache_to_shader_response)
// // // //     $display("=== Testing L2Cache to Shader Core Response ===");
    
// // // //     // L2Cache发送响应到Shader Core 0
// // // //     send_l2cache_response(48'h100000000000, MSG_MEM_READ_RESP, 8'h40);
    
// // // //     // 验证Shader Core 0接收到响应
// // // //     logic received = 1'b0;
// // // //     int cycle_count = 0;
    
// // // //     shader_core_if[0].slave_port.resp_ready <= 4'b0001;
    
// // // //     while (!received && cycle_count < 10) begin
// // // //       @(posedge clk);
// // // //       cycle_count++;
      
// // // //       if (shader_core_if[0].slave_port.resp_valid[0]) begin
// // // //         noc_header_t received_header = noc_header_t'(shader_core_if[0].slave_port.resp_header);
// // // //         `FAIL_IF(received_header.trans_id !== 8'h40)
// // // //         received = 1'b1;
// // // //         $display("@%0t Shader[0] received RESP: trans_id=0x%h", 
// // // //                  $time, received_header.trans_id);
// // // //       end
// // // //     end
    
// // // //     shader_core_if[0].slave_port.resp_ready <= 4'b0000;
// // // //     `FAIL_IF(!received)
    
// // // //     $display("L2Cache to Shader response routing test passed");
// // // //   `SVTEST_END

// // // // //   //---------------------------------
// // // // //   // 测试多拍传输
// // // // //   //---------------------------------
// // // // //   `SVTEST(test_multi_beat_transmission)
// // // // //     $display("=== Testing Multi-beat Transmission ===");
    
// // // // //     // 发送第一拍
// // // // //     @(posedge clk);
// // // // //     control_unit_if.master_port.req_valid <= 4'b0001;
// // // // //     control_unit_if.master_port.req_header <= build_noc_header(MSG_MEM_WRITE_REQ, 8'h50, 48'h200000000000);
// // // // //     control_unit_if.master_port.req_data <= 256'h1111111111111111111111111111111111111111111111111111111111111111;
// // // // //     control_unit_if.master_port.req_strb <= '1;
// // // // //     control_unit_if.master_port.req_last <= 1'b0;  // 不是最后一拍
    
// // // // //     do @(posedge clk); while (!control_unit_if.master_port.req_ready[0]);
    
// // // // //     // 发送第二拍
// // // // //     @(posedge clk);
// // // // //     control_unit_if.master_port.req_data <= 256'h2222222222222222222222222222222222222222222222222222222222222222;
// // // // //     control_unit_if.master_port.req_last <= 1'b1;  // 最后一拍
    
// // // // //     do @(posedge clk); while (!control_unit_if.master_port.req_ready[0]);
// // // // //     control_unit_if.master_port.req_valid <= 4'b0000;
    
// // // // //     // 验证L2Cache接收到多拍数据
// // // // //     verify_l2cache_request_received(8'h50);
    
// // // // //     $display("Multi-beat transmission test passed");
// // // // //   `SVTEST_END

// // // // // //   //---------------------------------
// // // // // //   // 测试错误响应状态
// // // // // //   //---------------------------------
// // // // // //   `SVTEST(test_error_response_status)
// // // // // //     $display("=== Testing Error Response Status ===");
    
// // // // // //     // L2Cache发送错误响应
// // // // // //     send_l2cache_response(48'h000000000000, MSG_MEM_READ_RESP, 8'h60, RESP_SLVERR);
    
// // // // // //     // 验证Control Unit接收到错误响应
// // // // // //     logic received = 1'b0;
// // // // // //     int cycle_count = 0;
    
// // // // // //     control_unit_if.slave_port.resp_ready <= 4'b0001;
    
// // // // // //     while (!received && cycle_count < 10) begin
// // // // // //       @(posedge clk);
// // // // // //       cycle_count++;
      
// // // // // //       if (control_unit_if.slave_port.resp_valid[0]) begin
// // // // // //         noc_header_t received_header = noc_header_t'(control_unit_if.slave_port.resp_header);
// // // // // //         noc_resp_t received_status = noc_resp_t'(control_unit_if.slave_port.resp_status);
        
// // // // // //         `FAIL_IF(received_header.trans_id !== 8'h60)
// // // // // //         `FAIL_IF(received_status !== RESP_SLVERR)
        
// // // // // //         received = 1'b1;
// // // // // //         $display("@%0t Control received ERROR RESP: trans_id=0x%h, status=SLVERR", 
// // // // // //                  $time, received_header.trans_id);
// // // // // //       end
// // // // // //     end
    
// // // // // //     control_unit_if.slave_port.resp_ready <= 4'b0000;
// // // // // //     `FAIL_IF(!received)
    
// // // // // //     $display("Error response status test passed");
// // // // // //   `SVTEST_END

// // // // // // //   //---------------------------------
// // // // // // //   // 测试Header构建和解析
// // // // // // //   //---------------------------------
// // // // // // //   `SVTEST(test_header_build_parse)
// // // // // // //     $display("=== Testing Header Build and Parse ===");
    
// // // // // // //     // 测试Header构建
// // // // // // //     noc_header_t header = noc_header_t'(build_noc_header(MSG_MEM_READ_REQ, 8'hAB, 48'h123456789ABC));
    
// // // // // // //     `FAIL_IF(header.msg_type !== MSG_MEM_READ_REQ)
// // // // // // //     `FAIL_IF(header.trans_id !== 8'hAB)
    
// // // // // // //     // 测试Header解析
// // // // // // //     noc_msg_type_t parsed_msg_type;
// // // // // // //     logic [7:0] parsed_trans_id;
// // // // // // //     noc_node_id_t parsed_src_node;
// // // // // // //     noc_node_id_t parsed_dest_node;
// // // // // // //     logic [7:0] parsed_local_addr;
    
// // // // // // //     parse_noc_header(header, parsed_msg_type, parsed_trans_id, parsed_src_node, parsed_dest_node, parsed_local_addr);
    
// // // // // // //     `FAIL_IF(parsed_msg_type !== MSG_MEM_READ_REQ)
// // // // // // //     `FAIL_IF(parsed_trans_id !== 8'hAB)
// // // // // // //     `FAIL_IF(parsed_src_node !== NODE_CONTROL)
    
// // // // // // //     $display("Header build and parse test passed");
// // // // // // //   `SVTEST_END

//   //---------------------------------
//   // 测试NOC配置验证
//   //---------------------------------
//   `SVTEST(test_noc_config_validation)
//     $display("=== Testing NOC Config Validation ===");
    
//     noc_config_t valid_config = get_default_noc_config();
//     `FAIL_IF(!validate_noc_config(valid_config))
    
//     // 测试无效的数据位宽
//     noc_config_t invalid_config = valid_config;
//     invalid_config.data_width = 32;  // 太小
//     `FAIL_IF(validate_noc_config(invalid_config))
    
//     invalid_config.data_width = 1024;  // 太大
//     `FAIL_IF(validate_noc_config(invalid_config))
    
//     // 测试无效的虚拟通道数
//     invalid_config = valid_config;
//     invalid_config.vc_count = 1;  // 太小
//     `FAIL_IF(validate_noc_config(invalid_config))
    
//     invalid_config.vc_count = 16;  // 太大
//     `FAIL_IF(validate_noc_config(invalid_config))
    
//     // 测试无效的Shader Core数量
//     invalid_config = valid_config;
//     invalid_config.num_shader_cores = 0;  // 太小
//     `FAIL_IF(validate_noc_config(invalid_config))
    
//     invalid_config.num_shader_cores = 16;  // 太大
//     `FAIL_IF(validate_noc_config(invalid_config))
    
//     $display("NOC config validation test passed");
//   `SVTEST_END

  `SVUNIT_TESTS_END

endmodule 