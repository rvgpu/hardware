//=============================================================================
// Copyright © 2025 RVGPU Team
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//   
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//=============================================================================

`ifndef TYPES_JOB_CLUSTER_SVH
`define TYPES_JOB_CLUSTER_SVH

`include "rvgpu_command_package.svh"

//=============================================================================
// t_job_cluster 结构体定义
//=============================================================================

typedef struct packed {
    job_dimention_t         job_dim;            // [255:160] job_dimention_t (96-bits)
    logic [31:0]            curr_cluster_id;    // [159:128] current cluster global id (32-bits)
    logic [4:0]             arg_size;           // [227:223] current program argument count (5-bits)
    logic [27:0]            reserved;           // [255:228] reserved (28-bits), 28'h0
    logic [63:0]            program_ptr;        // [223:160] program entry address (64-bits), argument list address is program_ptr + 8
} t_job_cluster;

//=============================================================================
// 构建函数
//=============================================================================

function automatic t_job_cluster tf_build_job_cluster(
    input job_dimention_t   job_dim,
    input logic [63:0]      program_ptr,
    input logic [31:0]      curr_cluster_id,
    input logic [4:0]       arg_size
);
    t_job_cluster job_cluster;
    job_cluster.job_dim = job_dim;
    job_cluster.program_ptr = program_ptr;
    job_cluster.curr_cluster_id = curr_cluster_id;
    job_cluster.arg_size = arg_size;
    job_cluster.reserved = 28'h0;
    return job_cluster;
endfunction

//=============================================================================
// 字符串转换函数
//=============================================================================

function automatic string tf_job_cluster_to_string(
    input t_job_cluster job_cluster
);
    return $sformatf("program_ptr: %h, curr_cluster_id: %d, arg_size: %d, dim: {grid: {%d, %d, %d}, cluster: {%d, %d, %d}, block: {%d, %d, %d}}", 
            job_cluster.program_ptr, 
            job_cluster.curr_cluster_id, 
            job_cluster.arg_size,
            job_cluster.job_dim.grid_x, job_cluster.job_dim.grid_y, job_cluster.job_dim.grid_z,
            job_cluster.job_dim.cluster_x, job_cluster.job_dim.cluster_y, job_cluster.job_dim.cluster_z,
            job_cluster.job_dim.block_x, job_cluster.job_dim.block_y, job_cluster.job_dim.block_z);
endfunction

//=============================================================================
// 辅助函数
//=============================================================================

function automatic logic [31:0] tf_get_total_blocks_in_cluster(
    input t_job_cluster job_cluster
);
    return (job_cluster.job_dim.cluster_x * job_cluster.job_dim.cluster_y * job_cluster.job_dim.cluster_z);
endfunction

function automatic logic [31:0] tf_get_total_clusters_in_grid(
    input t_job_cluster job_cluster
);
    return (job_cluster.job_dim.grid_x * job_cluster.job_dim.grid_y * job_cluster.job_dim.grid_z);
endfunction

`endif // TYPES_JOB_CLUSTER_SVH 