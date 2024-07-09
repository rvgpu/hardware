import os
import pytest
import subprocess

from utils import *

@all_files_in_dir('ut/core')
@all_available_simulators()
def test_core_ifu_icache_tag_array(datafiles, simulator):
    run_testcase(datafiles, simulator, 'ut_rcore_ifu_icache_tag_array.sv')
