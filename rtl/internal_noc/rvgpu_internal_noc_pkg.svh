//=============================================================================
// Copyright © 2025 RVGPU Team
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//   
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//=============================================================================

`ifndef RVGPU_INTERNAL_NOC_PKG_SV
`define RVGPU_INTERNAL_NOC_PKG_SV

package rvgpu_internal_noc_pkg;

    //=============================================================================
    // 配置结构体定义
    //=============================================================================
    
    typedef struct packed {
        int unsigned data_width;        // 数据位宽
        int unsigned header_width;      // Header位宽
        int unsigned vc_count;          // 虚拟通道数
        int unsigned buffer_depth;      // 缓冲区深度
        int unsigned num_shader_cores;  // Shader Core数量：1-8
        int unsigned max_pending_trans; // 最大未完成事务数
        logic        debug_enable;      // 调试功能使能
    } noc_config_t;
    
    function automatic noc_config_t get_default_noc_config();
        noc_config_t conf;
        conf.data_width = 256;
        conf.header_width = 32;
        conf.vc_count = 4;
        conf.buffer_depth = 16;
        conf.num_shader_cores = 4;
        conf.max_pending_trans = 16;
        conf.debug_enable = 1'b1;
        return conf;
    endfunction
    
    // 默认配置
    localparam noc_config_t DEFAULT_NOC_CONFIG = get_default_noc_config();
    
    //=============================================================================
    // Header和消息类型定义 
    //=============================================================================
    
    // NOC Header格式 - 32位
    typedef struct packed {
        logic [7:0]   msg_type;        // [31:24] 消息类型
        logic [7:0]   trans_id;        // [23:16] 事务ID
        logic [3:0]   src_node;        // [15:12] 源节点ID
        logic [3:0]   dest_node;       // [11:8]  目标节点ID
        logic [7:0]   local_addr;      // [7:0]   节点内本地地址
    } noc_header_t;
    
    // 消息类型定义
    typedef enum logic [7:0] {
        MSG_MEM_READ_REQ    = 8'h20,    // 内存读请求
        MSG_MEM_READ_RESP   = 8'h21,    // 内存读响应  
        MSG_MEM_WRITE_REQ   = 8'h22,    // 内存写请求
        MSG_MEM_WRITE_RESP  = 8'h23,    // 内存写响应
        MSG_COMPUTE_REQ     = 8'h10,    // 计算请求
        MSG_COMPUTE_RESP    = 8'h11,    // 计算响应
        MSG_SYNC_REQ        = 8'h30,    // 同步请求
        MSG_SYNC_RESP       = 8'h31,    // 同步响应
        MSG_STATUS          = 8'h50,    // 状态报告
        MSG_ERROR           = 8'h51     // 错误报告
    } noc_msg_type_t;
    
    // 节点ID定义 - GPU内部节点
    typedef enum logic [3:0] {
        NODE_CONTROL      = 4'h0,       // 控制单元
        NODE_L2_CACHE     = 4'h1,       // L2 Cache
        NODE_SHADER_0     = 4'h2,       // Shader Core 0
        NODE_SHADER_1     = 4'h3,       // Shader Core 1
        NODE_SHADER_2     = 4'h4,       // Shader Core 2
        NODE_SHADER_3     = 4'h5,       // Shader Core 3
        NODE_SHADER_4     = 4'h6,       // Shader Core 4
        NODE_SHADER_5     = 4'h7,       // Shader Core 5
        NODE_SHADER_6     = 4'h8,       // Shader Core 6
        NODE_SHADER_7     = 4'h9,       // Shader Core 7
        NODE_DEBUG        = 4'hF        // 调试接口
    } noc_node_id_t;
    
    // 响应状态码
    typedef enum logic [1:0] {
        RESP_OKAY    = 2'b00,           // 正常完成
        RESP_EXOKAY  = 2'b01,           // 独占访问正常
        RESP_SLVERR  = 2'b10,           // 从设备错误
        RESP_DECERR  = 2'b11            // 解码错误
    } noc_resp_t;
    
    // 构建NOC header
    function automatic noc_header_t build_noc_header(
        input noc_msg_type_t msg_type,
        input logic [7:0] trans_id,
        input noc_node_id_t src_node,
        input noc_node_id_t dest_node,
        input logic [7:0] local_addr = 8'h00
    );
        noc_header_t header;
        header.msg_type = msg_type;
        header.trans_id = trans_id;
        header.src_node = src_node;
        header.dest_node = dest_node;
        header.local_addr = local_addr;
        return header;
    endfunction
    
    // 解析NOC header
    function automatic void parse_noc_header(
        input noc_header_t header,
        output noc_msg_type_t msg_type,
        output logic [7:0] trans_id,
        output noc_node_id_t src_node,
        output noc_node_id_t dest_node,
        output logic [7:0] local_addr
    );
        msg_type = noc_msg_type_t'(header.msg_type);
        trans_id = header.trans_id;
        src_node = noc_node_id_t'(header.src_node);
        dest_node = noc_node_id_t'(header.dest_node);
        local_addr = header.local_addr;
    endfunction

endpackage : rvgpu_internal_noc_pkg

`endif // RVGPU_INTERNAL_NOC_PKG_SV 