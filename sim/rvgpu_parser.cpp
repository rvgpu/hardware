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

#include "rvgpu_parser.hpp"
#include <fstream>
#include <sstream>
#include <iostream>
#include <algorithm>
#include <cctype>

//=============================================================================
// Utility Functions Implementation
//=============================================================================

// 去除字符串两端的空白字符
std::string strip(const std::string& str) {
    size_t start = str.find_first_not_of(" \t\n\r");
    if (start == std::string::npos) {
        return ""; // 字符串只包含空白字符
    }
    size_t end = str.find_last_not_of(" \t\n\r");
    return str.substr(start, end - start + 1);
}

// 去除字符串左端的空白字符
std::string lstrip(const std::string& str) {
    size_t start = str.find_first_not_of(" \t\n\r");
    if (start == std::string::npos) {
        return ""; // 字符串只包含空白字符
    }
    return str.substr(start);
}

// 去除字符串右端的空白字符
std::string rstrip(const std::string& str) {
    size_t end = str.find_last_not_of(" \t\n\r");
    if (end == std::string::npos) {
        return ""; // 字符串只包含空白字符
    }
    return str.substr(0, end + 1);
}

std::string build_tc_path(const std::string& filename, const std::string& default_filename) {
    const char* tc_env = std::getenv("TC");
    
    if (tc_env != nullptr && std::string(tc_env).length() > 0) {
        // 使用TC环境变量构建路径: ${PWD}/TC/filename
        const char* pwd_env = std::getenv("PWD");
        std::string actual_filename = filename.empty() ? default_filename : filename;
        
        if (pwd_env != nullptr) {
            return std::string(pwd_env) + "/" + std::string(tc_env) + "/" + actual_filename;
        } else {
            // 如果PWD不可用，使用当前目录
            return "./" + std::string(tc_env) + "/" + actual_filename;
        }
    } else {
        // 如果没有TC环境变量，使用提供的文件名或默认文件名
        return filename.empty() ? default_filename : filename;
    }
}

//=============================================================================
// RVGPUParseCommand Class Implementation
//=============================================================================

RVGPUParseCommand::RVGPUParseCommand() : end_of_file(true) {
    // 构造函数不打开文件，等待显式调用open()
}

RVGPUParseCommand::~RVGPUParseCommand() {
    if (file.is_open()) {
        file.close();
    }
}

bool RVGPUParseCommand::open(const std::string& filename) {
    // 如果已经打开文件，先关闭
    if (file.is_open()) {
        file.close();
    }
    
    // 构建文件路径
    file_path = build_tc_path(filename, "command.txt");
    
    file.open(file_path);    
    if (!file.is_open()) {
        end_of_file = true;
        return false;
    }

    end_of_file = false;
    return true;
}

bool RVGPUParseCommand::empty() const {
    return end_of_file;
}

sim_command RVGPUParseCommand::get_command() {
    sim_command cmd = {RVGPU_COMMAND_ERROR, 0, 0, ""};  // 提供默认初始化
    
    // 循环读取，直到找到有效命令或到达文件末尾
    while (std::getline(file, current_line)) {
        // 去除行首行尾的空白字符
        current_line = strip(current_line);
        
        // 跳过空行
        if (current_line.empty()) {
            continue;  // 继续读取下一行
        }

        // 跳过注释行
        if (current_line[0] == '#') {
            continue;  // 继续读取下一行
        }

        // 找到有效行，开始解析命令
        std::istringstream iss(current_line);
        std::string command_str;
        iss >> command_str;

        if (command_str == "write_reg") {
            cmd.command = RVGPU_COMMAND_WRITE_REG;
            iss >> std::hex >> cmd.reg_addr >> std::hex >> cmd.data;
        } else if (command_str == "check_reg") {
            cmd.command = RVGPU_COMMAND_CHECK_REG;
            iss >> std::hex >> cmd.reg_addr >> std::hex >> cmd.data;
        } else if (command_str == "load_mem") {
            cmd.command = RVGPU_LOAD_MEMORY;
            iss >> cmd.filename;
        } else if (command_str == "wait_gpu_done") {
            cmd.command = RVGPU_WAIT_GPU_DONE;
        }
        
        // 找到有效命令，返回
        return cmd;
    }
    
    // 如果到达这里，说明文件已经结束
    end_of_file = true;
    return cmd;
}

//=============================================================================
// RVGPUParseHex Class Implementation
//=============================================================================

RVGPUParseHex::RVGPUParseHex() {
    // 构造函数不打开文件，等待显式调用open()
}

RVGPUParseHex::~RVGPUParseHex() {
    if (file.is_open()) {
        file.close();
    }
}

bool RVGPUParseHex::open(const std::string& filename) {
    // 如果已经打开文件，先关闭
    if (file.is_open()) {
        file.close();
    }
    
    file_path = filename;
    file.open(file_path);
    
    return file.is_open();
}

bool RVGPUParseHex::next_line() {
    while (std::getline(file, current_line)) {
        // 去除行首行尾的空白字符
        current_line = strip(current_line);
        
        // 跳过空行和注释行
        if (!current_line.empty() && current_line[0] != '#') {
            return true; // 找到有效行
        }
    }
    return false; // 文件结束
}

std::vector<uint64_t> RVGPUParseHex::get_memdata() {
    std::vector<uint64_t> memdata;
    
    // 移除行尾的注释（从#开始到行尾）
    size_t comment_pos = current_line.find('#');
    if (comment_pos != std::string::npos) {
        current_line = current_line.substr(0, comment_pos);
    }
    
    // 去除行尾的空白字符
    current_line = rstrip(current_line);
    
    // 如果处理后的行为空，返回空数据
    if (current_line.empty()) {
        return memdata;
    }
    
    std::istringstream iss(current_line);
    
    std::string addr_str;
    iss >> addr_str;
    
    // 解析地址
    if (addr_str.find(':') != std::string::npos) {
        try {
            addr_str = addr_str.substr(0, addr_str.find(':'));
            uint64_t addr = std::stoull(addr_str, nullptr, 16);
            memdata.push_back(addr);
            
            // 解析数据
            uint64_t data;
            while (iss >> std::hex >> data) {
                memdata.push_back(data);
            }
        } catch (const std::exception& e) {
            // 如果解析失败，返回空数据
            return std::vector<uint64_t>();
        }
    }
    
    return memdata;
} 