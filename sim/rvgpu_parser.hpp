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

#ifndef RVGPU_PARSER_HPP
#define RVGPU_PARSER_HPP

#include <string>
#include <vector>
#include <cstdint>
#include <fstream>

//=============================================================================
// Utility Functions
//=============================================================================

// 工具函数：构建TC环境变量下的文件路径
std::string build_tc_path(const std::string& filename, const std::string& default_filename = "");

//=============================================================================
// Command Types Enumeration
//=============================================================================

enum RVGPUCommandType {
    RVGPU_COMMAND_WRITE_REG = 1,
    RVGPU_COMMAND_CHECK_REG = 2,
    RVGPU_LOAD_MEMORY = 3,
    RVGPU_WAIT_GPU_DONE = 4
};

//=============================================================================
// Command Structure
//=============================================================================

struct sim_command {
    RVGPUCommandType command;
    uint64_t reg_addr;
    uint64_t data;
    std::string filename;
};

//=============================================================================
// Command Parser Class Declaration
//=============================================================================

class RVGPUParseCommand {
private:
    std::ifstream file;
    std::string current_line;
    bool end_of_file;
    std::string file_path;

public:
    // 构造函数 - 不打开文件
    RVGPUParseCommand();
    
    // 析构函数
    ~RVGPUParseCommand();
    
    // 打开文件
    bool open(const std::string& filename = "");
    
    // 解析器方法（open的别名）
    bool parser(const std::string& filename = "") { return open(filename); }
    
    // 检查是否到达文件末尾
    bool empty() const;
    
    // 获取下一个命令
    sim_command get_command();
    
    // 获取当前文件路径
    const std::string& get_file_path() const { return file_path; }
    
    // 检查文件是否打开
    bool is_open() const { return file.is_open(); }
};

//=============================================================================
// Hex Parser Class Declaration
//=============================================================================

class RVGPUParseHex {
private:
    std::ifstream file;
    std::string current_line;
    std::string file_path;

public:
    // 构造函数 - 不打开文件
    RVGPUParseHex();
    
    // 析构函数
    ~RVGPUParseHex();
    
    // 打开文件
    bool open(const std::string& filename);
    
    // 读取下一行
    bool next_line();
    
    // 获取内存数据
    std::vector<uint64_t> get_memdata();
    
    // 获取当前文件路径
    const std::string& get_file_path() const { return file_path; }
    
    // 检查文件是否打开
    bool is_open() const { return file.is_open(); }
};

#endif // RVGPU_PARSER_HPP 