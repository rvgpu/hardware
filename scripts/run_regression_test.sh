#!/bin/bash

#=============================================================================
# RVGPU Regression Test Script
# Copyright © 2025 RVGPU Team
# 
# 功能：
# 1. 设置项目路径为脚本所在目录的父目录
# 2. 加载环境变量
# 3. 运行pytest测试
# 4. 运行仿真测试
# 5. 错误处理和报告
#=============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# 粗体颜色
BOLD_RED='\033[1;31m'
BOLD_GREEN='\033[1;32m'
BOLD_YELLOW='\033[1;33m'
BOLD_BLUE='\033[1;34m'

# 背景颜色
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'

#=============================================================================
# 函数定义
#=============================================================================

# 打印带颜色的消息
print_info() {
    echo -e "${BOLD_BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${BOLD_GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${BOLD_YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${BOLD_RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BG_BLUE}${WHITE}================================================${NC}"
    echo -e "${BG_BLUE}${WHITE}  $1${NC}"
    echo -e "${BG_BLUE}${WHITE}================================================${NC}"
}

print_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${BG_GREEN}${WHITE}================================================${NC}"
        echo -e "${BG_GREEN}${WHITE}  ✅ $2 SUCCESSFUL${NC}"
        echo -e "${BG_GREEN}${WHITE}================================================${NC}"
    else
        echo -e "${BG_RED}${WHITE}================================================${NC}"
        echo -e "${BG_RED}${WHITE}  ❌ $2 FAILED${NC}"
        echo -e "${BG_RED}${WHITE}================================================${NC}"
        return 1
    fi
}

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "Command '$1' not found. Please install it first."
        exit 1
    fi
}

# 获取CPU核心数
get_cpu_count() {
    if command -v nproc &> /dev/null; then
        echo $(nproc)
    elif command -v sysctl &> /dev/null; then
        echo $(sysctl -n hw.ncpu)
    else
        echo 4  # 默认值
    fi
}

# 初始化项目环境
init_project() {
    print_info "Initializing project environment..."
    
    # 设置项目路径
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_PATH="$(dirname "$SCRIPT_DIR")"
    print_info "Script directory: $SCRIPT_DIR"
    print_info "Project path: $PROJECT_PATH"

    # 检查项目路径是否存在
    if [ ! -d "$PROJECT_PATH" ]; then
        print_error "Project path does not exist: $PROJECT_PATH"
        exit 1
    fi

    # 切换到项目目录
    cd "$PROJECT_PATH"
    print_info "Changed to project directory: $(pwd)"
    
    print_success "Project environment initialized"
}

# 检查依赖
check_dependencies() {
    print_info "Checking dependencies..."
    
    # 检查必要文件
    if [ ! -f "source.me" ]; then
        print_error "source.me file not found in project root"
        exit 1
    fi

    if [ ! -d "test" ]; then
        print_error "test directory not found"
        exit 1
    fi

    if [ ! -d "sim" ]; then
        print_error "sim directory not found"
        exit 1
    fi

    # 检查必要命令
    check_command "pytest"
    check_command "make"
    
    print_success "All dependencies satisfied"
}

# 加载环境
load_environment() {
    print_header "Loading Environment"
    print_info "Sourcing source.me..."
    source source.me
    if [ $? -ne 0 ]; then
        print_error "Failed to source source.me"
        exit 1
    fi
    print_success "Environment loaded successfully"
}

# 运行pytest测试
run_pytest_tests() {
    print_header "Running Pytest Tests"
    print_info "Changing to test directory..."
    cd test

    CPU_COUNT=$(get_cpu_count)
    # 计算70%的CPU核心数，最少使用1个核心
    PYTEST_CPU_COUNT=$(( (CPU_COUNT * 70) / 100 ))
    if [ $PYTEST_CPU_COUNT -lt 1 ]; then
        PYTEST_CPU_COUNT=1
    fi
    
    print_info "Detected CPU cores: $CPU_COUNT"
    print_info "Using 70%% of CPU cores: $PYTEST_CPU_COUNT"
    print_info "Running pytest with $PYTEST_CPU_COUNT parallel processes..."
    
    pytest -n $PYTEST_CPU_COUNT -v
    local result=$?

    if [ $result -ne 0 ]; then
        print_error "Pytest tests failed with exit code $result"
        print_result $result "PYTEST TESTS"
        exit 1
    fi

    print_success "Pytest tests completed successfully"
    print_result $result "PYTEST TESTS"
}

# 清理DVE进程
cleanup_dve_processes() {
    print_info "Checking for running DVE processes..."
    local dve_pids=$(ps aux | grep dve | grep -v grep | awk '{print $2}')
    if [ ! -z "$dve_pids" ]; then
        print_info "Found DVE processes: $dve_pids"
        print_info "Killing DVE processes..."
        kill -9 $dve_pids
        print_success "DVE processes killed."
    else
        print_info "No DVE processes found."
    fi
}

# 运行仿真测试
run_simulation_tests() {
    print_header "Running Simulation Tests"
    print_info "Changing to sim directory..."
    cd ../sim

    # 清理DVE进程
    cleanup_dve_processes

    print_info "Cleaning build files..."
    make clean

    print_info "Running VCS simulation with TC=dump_array_mul..."
    TC=dump_array_mul make run-vcs
    local result=$?

    if [ $result -ne 0 ]; then
        print_error "Simulation tests failed with exit code $result"
        print_result $result "SIMULATION TESTS"
        exit 1
    fi

    print_success "Simulation tests completed successfully"
    print_result $result "SIMULATION TESTS"
}

# 生成最终报告
generate_final_report() {
    print_header "Regression Test Summary"
    echo ""
    print_success "🎉 ALL TESTS PASSED SUCCESSFULLY! 🎉"
    echo ""
    echo -e "${BOLD_GREEN}Test Results Summary:${NC}"
    echo -e "  ✅ Pytest Tests:    PASSED"
    echo -e "  ✅ Simulation Tests: PASSED"
    echo ""
    echo -e "${BOLD_GREEN}Regression test completed at: $(date)${NC}"
    echo ""
}

#=============================================================================
# 主脚本开始
#=============================================================================

print_header "RVGPU Regression Test Suite"
echo ""

# 1. 初始化项目环境
init_project

# 2. 检查依赖
check_dependencies

# 3. 加载环境
load_environment

# 4. 运行pytest测试
run_pytest_tests

# 5. 运行仿真测试
run_simulation_tests

# 6. 生成最终报告
generate_final_report

# 返回成功
exit 0 