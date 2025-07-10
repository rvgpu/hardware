#!/bin/bash

#=============================================================================
# RVGPU仿真平台构建脚本 (SCons版本)
#=============================================================================

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查依赖
check_dependencies() {
    print_info "检查构建依赖..."
    
    # 检查SCons
    if ! command -v scons &> /dev/null; then
        print_error "SCons未找到，请安装SCons: pip install scons"
        exit 1
    fi
    
    # 检查编译器
    if ! command -v g++ &> /dev/null; then
        print_error "G++编译器未找到，请安装G++"
        exit 1
    fi
    
    # 检查VCS (可选)
    if ! command -v vcs &> /dev/null; then
        print_warning "VCS未找到，SystemVerilog仿真功能将不可用"
    else
        print_success "VCS已找到"
    fi
    
    print_success "依赖检查完成"
}

# 构建项目
build_project() {
    print_info "使用SCons构建项目..."
    
    # 获取CPU核心数
    CPU_CORES=$(nproc)
    print_info "使用 $CPU_CORES 个CPU核心进行构建"
    
    # 构建参数
    BUILD_ARGS="-j$CPU_CORES"
    
    # 如果设置了安装前缀，通过环境变量传递
    if [ -n "$RVGPU_INSTALL_PREFIX" ]; then
        export RVGPU_INSTALL_PREFIX="$RVGPU_INSTALL_PREFIX"
        print_info "使用安装前缀: $RVGPU_INSTALL_PREFIX"
    else
        # 默认安装到当前目录下的 install 文件夹
        export RVGPU_INSTALL_PREFIX="$(pwd)/install"
        print_info "使用默认安装路径: $(pwd)/install"
    fi
    
    # 直接运行scons，VariantDir会自动处理构建目录
    scons $BUILD_ARGS
    
    print_success "项目构建完成"
}

# 安装项目
install_project() {
    print_info "安装RVGPU仿真平台..."
    
    # 安装参数
    INSTALL_ARGS="install"
    
    # 如果设置了安装前缀，通过环境变量传递
    if [ -n "$RVGPU_INSTALL_PREFIX" ]; then
        export RVGPU_INSTALL_PREFIX="$RVGPU_INSTALL_PREFIX"
        print_info "使用安装前缀: $RVGPU_INSTALL_PREFIX"
    else
        # 默认安装到当前目录下的 install 文件夹
        export RVGPU_INSTALL_PREFIX="$(pwd)/install"
        print_info "使用默认安装路径: $(pwd)/install"
    fi
    
    # 运行安装
    scons $INSTALL_ARGS
    
    print_success "安装完成"
}

# 运行测试
run_tests() {
    print_info "运行测试程序..."
    
    if [ -f "build/examples/rvgpu_test_array_add" ]; then
        print_info "运行 rvgpu_test_array_add..."
        ./build/examples/rvgpu_test_array_add
        print_success "数组加法测试程序运行完成"
    else
        print_warning "rvgpu_test_array_add程序未找到"
    fi
}

# 清理构建
clean_build() {
    print_info "清理构建文件..."
    
    # 清理主项目
    scons -c
    
    # 删除构建目录
    if [ -d "build" ]; then
        rm -rf build
        print_success "构建目录已删除"
    fi
    
    # 删除安装目录
    if [ -d "install" ]; then
        rm -rf install
        print_success "安装目录已删除"
    fi
    
    print_success "所有构建文件已清理"
}

# 显示帮助信息
show_help() {
    echo "RVGPU仿真平台构建脚本 (SCons版本)"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  -c, --clean    清理构建文件"
    echo "  -t, --test     构建并运行测试"
    echo "  -i, --install  构建并安装到系统"
    echo "  -j N           使用N个并行任务 (默认: 自动检测)"
    echo ""
    echo "环境变量:"
    echo "  RVGPU_INSTALL_PREFIX  安装路径前缀 (默认: ./install)"
    echo ""
    echo "示例:"
    echo "  $0              # 构建所有组件"
    echo "  $0 -c           # 清理构建文件"
    echo "  $0 -t           # 构建并运行测试"
    echo "  $0 -i           # 构建并安装到 ./install"
    echo "  RVGPU_INSTALL_PREFIX=/opt/rvgpu $0 -i  # 安装到自定义路径"
    echo "  $0 -j 8         # 使用8个并行任务构建"
    echo ""
}

# 主函数
main() {
    local clean_flag=false
    local test_flag=false
    local install_flag=false
    local jobs=$(nproc)
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--clean)
                clean_flag=true
                shift
                ;;
            -t|--test)
                test_flag=true
                shift
                ;;
            -i|--install)
                install_flag=true
                shift
                ;;
            -j)
                jobs="$2"
                shift 2
                ;;
            *)
                print_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 执行清理
    if [ "$clean_flag" = true ]; then
        clean_build
        exit 0
    fi

    # 执行安装
    if [ "$install_flag" = true ]; then
        build_project
        install_project
        exit 0
    fi
    
    # 检查依赖
    check_dependencies
    
    # 构建项目
    build_project
    
    # 运行测试
    if [ "$test_flag" = true ]; then
        run_tests
    fi
    
    print_success "构建完成！"
}

# 运行主函数
main "$@" 