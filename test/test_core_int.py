import os
import pytest
import subprocess

from utils import *

@all_files_in_dir('ut/core')
@all_available_simulators()
def test_rcore_iu_alu(datafiles, simulator):
    run_testcase(datafiles, simulator, 'ut_rcore_iu_alu.sv')

@all_files_in_dir('ut/core')
@all_available_simulators()
def test_rcore_iu_top(datafiles, simulator):
    run_testcase(datafiles, simulator, 'ut_rcore_iu_top.sv')
