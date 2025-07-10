#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# SConstruct - 顶层SCons入口
import os

# 获取安装前缀 - 使用 SCons 的 GetOption 或环境变量
INSTALL_PREFIX = os.environ.get('RVGPU_INSTALL_PREFIX', os.path.join(os.getcwd(), 'install'))
INSTALL_INCLUDE = os.path.join(INSTALL_PREFIX, 'include')
INSTALL_LIB64 = os.path.join(INSTALL_PREFIX, 'lib64')
INSTALL_BIN = os.path.join(INSTALL_PREFIX, 'bin')

print(f"RVGPU: 安装前缀 = {INSTALL_PREFIX}")

# 全局环境
env = Environment(
    CXX='g++',
    CXXFLAGS='-Wall -Wextra -O2 -g -fPIC -std=c++17',
    CPPPATH=['simtop', 'csim', 'rtlsim'],
    LIBPATH=['lib'],
    RPATH=['lib'],
    INSTALL_PREFIX=INSTALL_PREFIX,
    INSTALL_INCLUDE=INSTALL_INCLUDE,
    INSTALL_LIB64=INSTALL_LIB64,
    INSTALL_BIN=INSTALL_BIN,
)

# 使用VariantDir指定构建目录
VariantDir('build', '.', duplicate=0)

# 递归包含各子目录
SConscript('build/simtop/SConscript', exports='env')
SConscript('build/csim/SConscript', exports='env')
SConscript('build/rtlsim/SConscript', exports='env')
SConscript('build/examples/SConscript', exports='env')

# 全局安装别名
env.Alias('install', [INSTALL_INCLUDE, INSTALL_LIB64, INSTALL_BIN]) 