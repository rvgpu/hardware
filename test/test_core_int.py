import pytest
import subprocess

from utils import *

def run_testcase(datafiles, simulator, testfile):
    print(testfile)
    with datafiles.as_cwd():
        subprocess.check_call(['runSVUnit', '-s', simulator, '-o', 'out', '-c', '-debug_access+all', '-t', testfile])
        expect_testrunner_pass('out/run.log')

@all_files_in_dir('ut/core')
@all_available_simulators()
def test_rcore_iu_alu(datafiles, simulator):
    run_testcase(datafiles, simulator, 'ut_rcore_iu_alu.sv')
