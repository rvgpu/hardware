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

`ifndef RVGPU_GPC_RASTER_SV
`define RVGPU_GPC_RASTER_SV

`include "rvgpu_typedef.svh"
`include "gpc_block_raster_if.svh"
`include "interface_l15cache.svh"

// GPC Raster Engine模块
// 负责图形光栅化操作
module rvgpu_gpc_raster #(
    parameter int ADDR_WIDTH = 40,       // 地址宽度
    parameter int MAX_TRIANGLES = 64     // 最大三角形数量
) (
    input  logic clk,
    input  logic rst_n,
    
    // Block Scheduler接口
    gpc_block_raster_if.raster raster_if,
    
    // L1.5 Cache接口
    interface_l15cache.requester l15_if
);
    // 状态机状态
    typedef enum logic [3:0] {
        IDLE,
        FETCH_CMD,
        PARSE_CMD,
        SETUP_TRIANGLE,
        RASTERIZE,
        FETCH_TEXTURE,
        WAIT_TEXTURE,
        PIXEL_SHADER,
        DEPTH_TEST,
        WRITE_COLOR,
        WAIT_WRITE,
        COMPLETE
    } raster_state_t;
    
    // 命令类型
    typedef enum logic [3:0] {
        CMD_CLEAR,
        CMD_TRIANGLE,
        CMD_TRIANGLE_STRIP,
        CMD_TRIANGLE_FAN,
        CMD_TEXTURE_LOAD,
        CMD_SET_VIEWPORT,
        CMD_SET_SCISSOR
    } cmd_type_t;
    
    // 三角形顶点定义
    typedef struct packed {
        logic [31:0] x, y, z;    // 位置
        logic [31:0] r, g, b, a; // 颜色
        logic [31:0] u, v;       // 纹理坐标
    } vertex_t;
    
    // 内部信号
    raster_state_t state;
    logic [63:0] cmd_addr;
    logic [63:0] cmd_data;
    logic [31:0] cmd_size;
    logic [31:0] cmd_index;
    cmd_type_t cmd_type;
    
    // 三角形数据
    vertex_t triangle[3];
    logic [31:0] triangle_count;
    logic [31:0] current_triangle;
    
    // 光栅化数据
    logic [31:0] min_x, max_x, min_y, max_y;
    logic [31:0] current_x, current_y;
    
    // 纹理和帧缓冲数据
    logic [63:0] texture_addr;
    logic [63:0] framebuffer_addr;
    logic [31:0] viewport_width, viewport_height;
    logic [31:0] texture_width, texture_height;
    logic [511:0] texture_data;
    logic [31:0] color_data;
    
    // 请求ID计数器
    logic [31:0] req_id_counter;
    
    // 主状态机
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            cmd_addr <= '0;
            cmd_data <= '0;
            cmd_size <= '0;
            cmd_index <= '0;
            cmd_type <= CMD_CLEAR;
            triangle_count <= '0;
            current_triangle <= '0;
            min_x <= '0;
            max_x <= '0;
            min_y <= '0;
            max_y <= '0;
            current_x <= '0;
            current_y <= '0;
            texture_addr <= '0;
            framebuffer_addr <= '0;
            viewport_width <= 1920;
            viewport_height <= 1080;
            texture_width <= '0;
            texture_height <= '0;
            req_id_counter <= '0;
            
            // 初始化接口信号
            raster_if.cmd_ready <= 1'b0;
            raster_if.complete_valid <= 1'b0;
            l15_if.req_valid <= 1'b0;
            l15_if.resp_ready <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    // 接收来自Block Scheduler的命令
                    raster_if.cmd_ready <= 1'b1;
                    
                    if (raster_if.cmd_valid && raster_if.cmd_ready) begin
                        cmd_addr <= raster_if.cmd_addr;
                        cmd_data <= raster_if.cmd_data;
                        cmd_size <= raster_if.cmd_size;
                        cmd_index <= '0;
                        raster_if.cmd_ready <= 1'b0;
                        state <= FETCH_CMD;
                    end
                end
                
                FETCH_CMD: begin
                    // 从L1.5 Cache获取命令数据
                    l15_if.req_valid <= 1'b1;
                    l15_if.req_is_read <= 1'b1;
                    l15_if.req_paddr <= cmd_data + (cmd_index << 2);   // 假设每个命令是4字节
                    l15_if.req_size <= 2;    // 4字节
                    l15_if.req_type <= CACHE_OP_READ;
                    l15_if.req_data <= '0;
                    l15_if.req_mask <= '0;
                    l15_if.req_id <= req_id_counter;
                    
                    if (l15_if.req_ready) begin
                        l15_if.req_valid <= 1'b0;
                        req_id_counter <= req_id_counter + 1;
                        state <= PARSE_CMD;
                    end
                end
                
                PARSE_CMD: begin
                    // 等待L1 Cache响应
                    l15_if.resp_ready <= 1'b1;
                    
                    if (l15_if.resp_valid) begin
                        l15_if.resp_ready <= 1'b0;
                        
                        // 解析命令
                        cmd_type <= cmd_type_t'(l15_if.resp_data[3:0]);
                        
                        case (cmd_type_t'(l15_if.resp_data[3:0]))
                            CMD_CLEAR: begin
                                // 清除帧缓冲
                                framebuffer_addr <= l15_if.resp_data[63:0];
                                state <= WRITE_COLOR;
                            end
                            
                            CMD_TRIANGLE: begin
                                // 处理单个三角形
                                triangle_count <= 1;
                                current_triangle <= 0;
                                state <= SETUP_TRIANGLE;
                            end
                            
                            CMD_TRIANGLE_STRIP: begin
                                // 处理三角形条带
                                triangle_count <= l15_if.resp_data[35:4];
                                current_triangle <= 0;
                                state <= SETUP_TRIANGLE;
                            end
                            
                            CMD_TRIANGLE_FAN: begin
                                // 处理三角形扇形
                                triangle_count <= l15_if.resp_data[35:4];
                                current_triangle <= 0;
                                state <= SETUP_TRIANGLE;
                            end
                            
                            CMD_TEXTURE_LOAD: begin
                                // 加载纹理
                                texture_addr <= l15_if.resp_data[95:32];
                                texture_width <= l15_if.resp_data[127:96];
                                texture_height <= l15_if.resp_data[159:128];
                                state <= FETCH_TEXTURE;
                            end
                            
                            CMD_SET_VIEWPORT: begin
                                // 设置视口
                                viewport_width <= l15_if.resp_data[35:4];
                                viewport_height <= l15_if.resp_data[67:36];
                                cmd_index <= cmd_index + 1;
                                state <= (cmd_index + 1 < cmd_size) ? FETCH_CMD : COMPLETE;
                            end
                            
                            CMD_SET_SCISSOR: begin
                                // 设置裁剪区域
                                cmd_index <= cmd_index + 1;
                                state <= (cmd_index + 1 < cmd_size) ? FETCH_CMD : COMPLETE;
                            end
                            
                            default: begin
                                // 未知命令，跳过
                                cmd_index <= cmd_index + 1;
                                state <= (cmd_index + 1 < cmd_size) ? FETCH_CMD : COMPLETE;
                            end
                        endcase
                    end
                end
                
                SETUP_TRIANGLE: begin
                    // 设置三角形数据
                    // 简化实现：假设三角形数据已经在命令中提供
                    
                    // 计算三角形边界框
                    min_x <= 0;
                    max_x <= viewport_width;
                    min_y <= 0;
                    max_y <= viewport_height;
                    current_x <= 0;
                    current_y <= 0;
                    
                    state <= RASTERIZE;
                end
                
                RASTERIZE: begin
                    // 光栅化三角形
                    // 简化实现：假设所有像素都在三角形内
                    
                    if (current_y < max_y) begin
                        if (current_x < max_x) begin
                            // 处理当前像素
                            state <= PIXEL_SHADER;
                        end else begin
                            // 移动到下一行
                            current_x <= 0;
                            current_y <= current_y + 1;
                        end
                    end else begin
                        // 当前三角形处理完成
                        current_triangle <= current_triangle + 1;
                        
                        if (current_triangle + 1 < triangle_count) begin
                            // 处理下一个三角形
                            state <= SETUP_TRIANGLE;
                        end else begin
                            // 所有三角形处理完成
                            state <= COMPLETE;
                        end
                    end
                end
                
                FETCH_TEXTURE: begin
                    // 获取纹理数据
                    l15_if.req_valid <= 1'b1;
                    l15_if.req_is_read <= 1'b1;
                    l15_if.req_paddr <= texture_addr;
                    l15_if.req_size <= 6; // 64字节
                    l15_if.req_type <= CACHE_OP_READ;
                    l15_if.req_data <= '0;
                    l15_if.req_mask <= '0;
                    l15_if.req_id <= req_id_counter;
                    
                    if (l15_if.req_ready) begin
                        l15_if.req_valid <= 1'b0;
                        req_id_counter <= req_id_counter + 1;
                        state <= WAIT_TEXTURE;
                    end
                end
                
                WAIT_TEXTURE: begin
                    // 等待纹理数据
                    l15_if.resp_ready <= 1'b1;
                    
                    if (l15_if.resp_valid) begin
                        l15_if.resp_ready <= 1'b0;
                        texture_data <= l15_if.resp_data;
                        cmd_index <= cmd_index + 1;
                        state <= (cmd_index + 1 < cmd_size) ? FETCH_CMD : COMPLETE;
                    end
                end
                
                PIXEL_SHADER: begin
                    // 执行像素着色器
                    // 简化实现：生成固定颜色
                    color_data <= 32'hFF0000FF; // 红色
                    
                    state <= DEPTH_TEST;
                end
                
                DEPTH_TEST: begin
                    // 执行深度测试
                    // 简化实现：总是通过深度测试
                    
                    state <= WRITE_COLOR;
                end
                
                WRITE_COLOR: begin
                    // 写入颜色缓冲区
                    l15_if.req_valid <= 1'b1;
                    l15_if.req_is_read <= 1'b0;
                    l15_if.req_paddr <= framebuffer_addr + ((current_y * viewport_width + current_x) << 2);
                    l15_if.req_size <= 2; // 4字节
                    l15_if.req_type <= CACHE_OP_WRITE;
                    l15_if.req_data <= {15{color_data}}; // 重复颜色数据填充
                    l15_if.req_mask <= 4'hF; // 写入所有字节
                    l15_if.req_id <= req_id_counter;
                    
                    if (l15_if.req_ready) begin
                        l15_if.req_valid <= 1'b0;
                        req_id_counter <= req_id_counter + 1;
                        state <= WAIT_WRITE;
                    end
                end
                
                WAIT_WRITE: begin
                    // 等待写入完成
                    l15_if.resp_ready <= 1'b1;
                    
                    if (l15_if.resp_valid) begin
                        l15_if.resp_ready <= 1'b0;
                        
                        if (cmd_type == CMD_CLEAR) begin
                            // 清除操作完成
                            cmd_index <= cmd_index + 1;
                            state <= (cmd_index + 1 < cmd_size) ? FETCH_CMD : COMPLETE;
                        end else begin
                            // 移动到下一个像素
                            current_x <= current_x + 1;
                            state <= RASTERIZE;
                        end
                    end
                end
                
                COMPLETE: begin
                    // 完成光栅化操作
                    raster_if.complete_valid <= 1'b1;
                    raster_if.complete_id <= 0; // 简化实现：使用固定ID
                    raster_if.complete_status <= 1'b0; // 0表示成功
                    
                    if (raster_if.complete_ready) begin
                        raster_if.complete_valid <= 1'b0;
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule : rvgpu_gpc_raster

`endif // RVGPU_GPC_RASTER_SV 