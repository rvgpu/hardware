#! /usr/bin/env python3

import sys
import os
import subprocess

from utils import *

def run_case(testfile):
    subprocess.check_call(svunit_command('vcs', testfile))  

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: ./svunit.py testcase.sv")
        sys.exit(-1)

    run_case(sys.argv[1])
