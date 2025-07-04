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

@all_files_in_dir('ut/control_unit')
@all_available_simulators()
def test_control_unit_rvgpu_axi_adapter_basic(datafiles, simulator):
    """
    Basic functionality test for RVGPU AXI Adapter.
    Tests fundamental AXI4-Lite protocol compliance, state machine transitions,
    write/read operations, and basic control interface conversion.
    
    Test Coverage:
    - Reset and initialization
    - Write state machine (W_IDLE → W_ADDR → W_DATA → W_CTRL_REQ → W_CTRL_RESP → W_BRESP)
    - Read state machine (R_IDLE → R_ADDR → R_CTRL_REQ → R_CTRL_RESP → R_DATA)
    - Concurrent read/write operations with arbitration
    - Error response handling (SLVERR, DECERR)
    - AXI protocol compliance verification
    """
    run_testcase(datafiles, simulator, 'ut_rvgpu_axi_adapter_basic.sv')

@all_files_in_dir('ut/control_unit')
@all_available_simulators()
def test_control_unit_rvgpu_axi_adapter_data_tests(datafiles, simulator):
    """
    Comprehensive data integrity test for RVGPU AXI Adapter.
    Tests data transmission accuracy across all data patterns, address ranges,
    and strobe configurations to ensure end-to-end data integrity.
    
    Test Coverage:
    - Comprehensive data patterns (8x4x4 = 128 combinations)
    - Write data integrity (4x8x8 = 256 combinations)
    - Read data integrity (8x8 = 64 combinations)
    - Concurrent transaction data integrity
    - Strobe pattern handling (8 different patterns)
    - Address range data integrity (8 boundary conditions)
    - Error response data handling (4x3 = 12 combinations)
    """
    run_testcase(datafiles, simulator, 'ut_rvgpu_axi_adapter_data_tests.sv')

@all_files_in_dir('ut/control_unit')
@all_available_simulators()
def test_control_unit_rvgpu_command_processor_basic(datafiles, simulator):
    """
    Basic functionality test for RVGPU Command Processor.
    Tests fundamental command processing logic, register access,
    Job Dispatcher interface, and basic state management.
    
    Test Coverage:
    - Reset state verification
    - Register read/write operations (MMU pagetable, Command packet, Control, Status)
    - CP-JD handshake protocol (enable, reset, address passing)
    - Error handling and interrupt generation
    - State machine transitions (IDLE → RUNNING → IDLE)
    - Automatic control signal management (start bit auto-clear)
    - Status register updates based on JD feedback
    """
    run_testcase(datafiles, simulator, 'ut_rvgpu_command_processor_basic.sv')

@all_files_in_dir('ut/control_unit')
@all_available_simulators()
def test_control_unit_rvgpu_job_dispatcher_basic(datafiles, simulator):
    """
    Basic functionality test for RVGPU Job Dispatcher (Optimized Version).
    Tests fundamental job dispatching logic, interface management,
    state machine transitions, and basic Package processing.
    
    Test Coverage:
    - Reset behavior verification
    - Enable/disable operations
    - MMU interface communication (address translation requests/responses)
    - NOC interface communication (memory read requests/responses)
    - Complete workflow simulation (Header fetch → Payload fetch → Task dispatch)
    - Error handling (MMU page faults, NOC errors, retry mechanism)
    - Multiple operations support
    - Busy state management
    - Timeout handling
    - Interface monitoring and verification
    - Retry mechanism testing
    - Performance monitoring validation
    """
    run_testcase(datafiles, simulator, 'ut_rvgpu_job_dispatcher_basic.sv')

