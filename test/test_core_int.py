import pytest
import subprocess

from utils import *

@all_files_in_dir('ut/core')
@all_available_simulators()
def test_core_iu(datafiles, simulator):
    with datafiles.as_cwd():
        subprocess.check_call(['runSVUnit', '-s', simulator, '-o', 'out', '-c', '-debug_access+all', '-t', 'ut_alu_int_unit.sv'])
        expect_testrunner_pass('out/run.log')

@all_files_in_dir('ut/core')
@all_available_simulators()
def test_rcore_iu_alu(datafiles, simulator):
    with datafiles.as_cwd():
        subprocess.check_call(['runSVUnit', '-s', simulator, '-o', 'out', '-c', '-debug_access+all', '-t', 'ut_rcore_iu_alu.sv'])
        expect_testrunner_pass('out/run.log')

