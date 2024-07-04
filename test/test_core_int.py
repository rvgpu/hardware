import os
import pytest
import subprocess

from utils import *

def svunit_command(simulator, testfile):
    projdir = os.environ.get('RVGPU_HARDWARE')
    svunitfile = projdir + '/test/common/svunit.f'

    command = []
    command.append('runSVUnit')
    command.append('-s')
    command.append(simulator)
    command.append('-f')
    command.append(svunitfile)
    command.append('-o')
    command.append('out')
    command.append('-c')
    command.append('-debug_access+all')
    command.append('-t')
    command.append(testfile)

    return command

def run_testcase(datafiles, simulator, testfile):
    print(testfile)

    with datafiles.as_cwd():
        subprocess.check_call(svunit_command(simulator, testfile))
        expect_testrunner_pass('out/run.log')

@all_files_in_dir('ut/core')
@all_available_simulators()
def test_rcore_iu_alu(datafiles, simulator):
    run_testcase(datafiles, simulator, 'ut_rcore_iu_alu.sv')

@all_files_in_dir('ut/core')
@all_available_simulators()
def test_rcore_iu_top(datafiles, simulator):
    run_testcase(datafiles, simulator, 'ut_rcore_iu_top.sv')
