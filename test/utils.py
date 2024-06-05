import mmap
import os
import re
import shutil
import subprocess
import pathlib
import pytest

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
