#=============================================================================
# Copyright © 2025 RVGPU Team
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#   
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#=============================================================================

# RTL文件目录
RTL_DIR := $(RVGPU_HARDWARE)/rtl

# 仿真文件目录
SIM_DIR := $(shell pwd)

# 输出目录
OUT_DIR := $(SIM_DIR)/out

# 编译器设置
CC := g++
CXX := g++
VCS := vcs

# 编译选项
CXXFLAGS := -std=c++11 -O2 -Wall -Wextra
VCS_FLAGS := -full64 -sverilog +v2k -debug_acc+all -debug_region+cell+encrypt \
	-Mdir=$(OUT_DIR)/csrc \
	-full64 \
	+define+RVGPU_HARDWARE=$(RVGPU_HARDWARE) \
	-o $(OUT_DIR)/rvgpu_tb_vcs \
	-work $(OUT_DIR)/work \
	-cm_dir $(OUT_DIR)/cm \
	-cm_name $(OUT_DIR)/coverage \
	-debug_access+all \
	-debug_region+cell+encrypt \
	+define+RVGPU_HARDWARE=$(RVGPU_HARDWARE)

# 文件列表和包含目录
RTL_FILELIST := $(RTL_DIR)/filelists/rvgpu_rtl.fl
INCDIR_FILE := $(RTL_DIR)/filelists/rvgpu_incdir.f

# 仿真源文件
SIM_SOURCES := \
	$(SIM_DIR)/rvgpu_memory.cpp \
	$(SIM_DIR)/rvgpu_simulator.cpp \
	$(SIM_DIR)/rvgpu_simulator_test.cpp \
	$(SIM_DIR)/rvgpu_sim_dpi.cpp \
	$(SIM_DIR)/rvgpu_parser.cpp \
	$(SIM_DIR)/rvgpu_toplevel_tb.sv

# 默认目标
.PHONY: all clean help

all: vcs

# 检查环境、工具和文件
check:
	@echo "检查RVGPU测试框架环境..."
	@echo "================================"
	@echo ""
	
	@echo "1. 检查环境变量..."
	@if [ -z "$(RVGPU_HARDWARE)" ]; then \
		echo "✗ 错误: RVGPU_HARDWARE环境变量未设置"; \
		echo "   请设置RVGPU_HARDWARE环境变量指向项目根目录"; \
		echo "   例如: export RVGPU_HARDWARE=/path/to/rvgpu/hardware"; \
		echo ""; \
		exit 1; \
	fi
	@echo "✓ RVGPU_HARDWARE环境变量已设置: $(RVGPU_HARDWARE)"
	@if [ -n "$(TC)" ]; then \
		echo "✓ TC环境变量已设置: $(TC)"; \
		echo "  测试用例目录: $(shell pwd)/$(TC)"; \
		if [ ! -d "$(shell pwd)/$(TC)" ]; then \
			echo "⚠ 警告: TC目录不存在: $(shell pwd)/$(TC)"; \
			echo "   请确保测试用例目录存在"; \
		fi; \
	else \
		echo "⚠ TC环境变量未设置，将使用默认文件路径"; \
		echo "   建议设置TC环境变量指定测试用例，例如: TC=dump_array_mul"; \
	fi
	@echo ""
	
	@echo "2. 检查仿真工具可用性..."
	@if which $(VCS) >/dev/null 2>&1; then \
		echo "✓ VCS: $(shell which $(VCS))"; \
	else \
		echo "✗ VCS: 未找到"; \
	fi
	@if which $(CC) >/dev/null 2>&1; then \
		echo "✓ GCC: $(shell which $(CC))"; \
	else \
		echo "✗ GCC: 未找到"; \
	fi
	@if which $(CXX) >/dev/null 2>&1; then \
		echo "✓ G++: $(shell which $(CXX))"; \
	else \
		echo "✗ G++: 未找到"; \
	fi
	@echo ""
	
	@echo "3. 检查文件列表..."
	@if [ -f "$(RTL_FILELIST)" ]; then \
		echo "✓ RTL文件列表存在: $(RTL_FILELIST)"; \
	else \
		echo "✗ RTL文件列表不存在: $(RTL_FILELIST)"; \
		echo "   请检查RVGPU_HARDWARE环境变量设置"; \
		echo ""; \
		exit 1; \
	fi
	@if [ -f "$(INCDIR_FILE)" ]; then \
		echo "✓ 包含目录文件存在: $(INCDIR_FILE)"; \
	else \
		echo "✗ 包含目录文件不存在: $(INCDIR_FILE)"; \
		echo "   请检查RVGPU_HARDWARE环境变量设置"; \
		echo ""; \
		exit 1; \
	fi
	@echo ""
	@echo "✓ 所有检查通过，环境配置正确！"

# 创建输出目录
$(OUT_DIR):
	mkdir -p $(OUT_DIR)

# VCS仿真
vcs: check $(OUT_DIR)
	@echo "使用VCS编译和仿真..."
	@echo "RVGPU_HARDWARE = $(RVGPU_HARDWARE)"
	@echo "RTL_FILELIST = $(RTL_FILELIST)"
	@echo "INCDIR_FILE = $(INCDIR_FILE)"
	$(VCS) $(VCS_FLAGS) \
		-f $(RTL_FILELIST) \
		-f $(INCDIR_FILE) \
		$(SIM_SOURCES)
	@echo "VCS编译完成"

# 运行VCS仿真
run-vcs: vcs
	@echo "运行VCS仿真..."
	$(OUT_DIR)/rvgpu_tb_vcs
	@echo "VCS仿真完成"

# 生成波形文件
wave-vcs: run-vcs
	@echo "生成VCS波形文件..."
	# VCS使用-vcd选项生成波形

# 清理
clean:
	@echo "清理输出文件..."
	rm -rf $(OUT_DIR)
	rm -f *.vcd *.vpd *.log *.key *.h5 *.h5.fast *.h5.slow
	@echo "清理完成"

# 帮助信息
help:
	@echo "RVGPU测试框架Makefile (VCS版本)"
	@echo ""
	@echo "环境变量要求:"
	@echo "  RVGPU_HARDWARE  - 必须设置，指向项目根目录"
	@echo "  TC              - 可选设置，指定测试用例目录"
	@echo ""
	@echo "可用目标:"
	@echo "  all              - 默认目标，使用VCS编译"
	@echo "  check            - 检查环境、工具和文件配置"
	@echo "  vcs              - 使用VCS编译"
	@echo "  run-vcs          - 运行VCS仿真"
	@echo "  wave-vcs         - 生成VCS波形"
	@echo "  clean            - 清理输出文件"
	@echo "  help             - 显示此帮助信息"
	@echo ""
	@echo "环境变量:"
	@echo "  CC               - C编译器 (默认: gcc)"
	@echo "  CXX              - C++编译器 (默认: g++)"
	@echo "  VCS              - VCS路径 (默认: vcs)"
	@echo "  RVGPU_HARDWARE  - 项目根目录 (必须设置)"
	@echo "  TC               - 测试用例目录 (可选设置)"
	@echo ""
	@echo "文件列表:"
	@echo "  RTL_FILELIST     - RTL文件列表: $(RTL_FILELIST)"
	@echo "  INCDIR_FILE      - 包含目录文件: $(INCDIR_FILE)"
	@echo ""
	@echo "示例:"
	@echo "  export RVGPU_HARDWARE=/path/to/rvgpu/hardware"
	@echo "  export TC=dump_array_mul"
	@echo "  make check       - 检查环境配置"
	@echo "  make vcs         - 使用VCS编译"
	@echo "  make run-vcs     - 使用VCS运行仿真"
	@echo "  TC=dump_array_mul make run-vcs  - 指定测试用例运行"
	@echo "  make clean       - 清理所有输出文件"

# 显示项目信息
info: check
	@echo "RVGPU测试框架项目信息"
	@echo "========================"
	@echo "项目根目录: $(RVGPU_HARDWARE)"
	@echo "RTL目录: $(RTL_DIR)"
	@echo "仿真目录: $(SIM_DIR)"
	@echo "输出目录: $(OUT_DIR)"
	@if [ -n "$(TC)" ]; then \
		echo "测试用例目录: $(shell pwd)/$(TC)"; \
	else \
		echo "测试用例目录: 未设置TC环境变量"; \
	fi
	@echo ""
	@echo "文件列表:"
	@echo "  RTL文件列表: $(RTL_FILELIST)"
	@echo "  包含目录文件: $(INCDIR_FILE)"
	@echo ""
	@echo "仿真源文件:"
	@for file in $(SIM_SOURCES); do \
		echo "  $$file"; \
	done

# 显示VCS编译命令
show-vcs-command: check
	@echo "VCS编译命令:"
	@echo "$(VCS) $(VCS_FLAGS) \\"
	@echo "  -f $(RTL_FILELIST) \\"
	@echo "  -f $(INCDIR_FILE) \\"
	@echo "  -o $(OUT_DIR)/rvgpu_tb_vcs \\"
	@echo "  $(SIM_SOURCES) \\"
	@echo "  +define+RVGPU_HARDWARE=$(RVGPU_HARDWARE)" 