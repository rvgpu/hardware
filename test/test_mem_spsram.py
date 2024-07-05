import os
import pytest
import subprocess

from utils import *

@all_files_in_dir('ut/mem')
@all_available_simulators()
def test_rvgpu_mem_spsram_256x59(datafiles, simulator):
    run_testcase(datafiles, simulator, 'ut_rvgpu_spsram_256x59.sv')

@all_files_in_dir('ut/mem')
@all_available_simulators()
def test_rvgpu_mem_spsram_2048x32(datafiles, simulator):
    run_testcase(datafiles, simulator, 'ut_rvgpu_spsram_2048x32.sv')
