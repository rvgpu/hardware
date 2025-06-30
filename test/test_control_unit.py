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

import os
import pytest
import subprocess

from utils import *

@all_files_in_dir('ut/control_unit')
@all_available_simulators()
def test_control_unit_rvgpu_noc_arbiter_basic(datafiles, simulator):
    """
    Basic functionality test for RVGPU NOC Arbiter.
    Tests fundamental arbitration logic, state machine transitions, 
    and basic data forwarding capabilities.
    """
    run_testcase(datafiles, simulator, 'ut_rvgpu_noc_arbiter_basic.sv')

@all_files_in_dir('ut/control_unit')
@all_available_simulators()
def test_control_unit_rvgpu_noc_arbiter_data_tests(datafiles, simulator):
    """
    Data pattern testing for RVGPU NOC Arbiter.
    Tests comprehensive data patterns, strobe configurations,
    and data integrity during arbitration and transmission.
    """
    run_testcase(datafiles, simulator, 'ut_rvgpu_noc_arbiter_data_tests.sv')


