#
# Copyright © 2024 Sietium Semiconductor.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#  
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Portions of this file are derived from the following projects:  
#  - svunit (https://github.com/svunit/svunit)  
#    Licensed under the Apache License, Version 2.0
#

import mmap
import os
import re
import shutil
import subprocess
import pathlib
import pytest

def svunit_command(simulator, testfile):
    if os.environ.get('RVGPU_HARDWARE') is None:
        os.environ['RVGPU_HARDWARE'] = '/root/hardware'

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

def all_files_in_dir(dirname):
    dirpath = os.path.join(os.path.dirname(os.path.realpath(__file__)), dirname)
    return pytest.mark.datafiles(*pathlib.Path(dirpath).iterdir(), keep_top_dir=True)

def all_available_simulators():
    simulators = []

    if shutil.which('irun'):
        simulators.append('irun')
    if shutil.which('xrun'):
        simulators.append('xrun')
    if shutil.which('vcs'):
        simulators.append('vcs')
    if shutil.which('vlog'):
        simulators.append('modelsim')
    if shutil.which('dsim'):
        simulators.append('dsim')
    if shutil.which('qrun'):
        simulators.append('qrun')
    if shutil.which('verilator'):
        simulators.append('verilator')
    if shutil.which('xsim'):
        simulators.append('xsim')

    if not simulators:
        warnings.warn('None of irun, modelsim, vcs, dsim, qrun, verilator or xsim are in your path. You need at     least 1 simulator to regress svunit-code!')

    return pytest.mark.parametrize("simulator", simulators)

def expect_testrunner_pass(logfile_path):
    expect_string(br'INFO:  \[.*\]\[testrunner\]: PASSED \(. of . suites passing\) \[.*\]', logfile_path)

def expect_testrunner_fail(logfile_path):
    expect_string(br'INFO:  \[.*\]\[testrunner\]: FAILED', logfile_path)

def expect_string(pattern, logfile_path):
    with open(logfile_path) as file, mmap.mmap(file.fileno(), 0, access=mmap.ACCESS_READ) as log:
        assert re.search(pattern, log), "\"%s\" not found at %s log file" % (pattern, logfile_path)
