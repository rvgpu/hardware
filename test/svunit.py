#! /usr/bin/env python3

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
