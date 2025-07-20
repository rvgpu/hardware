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

`ifndef RVGPU_L2CACHE_TYPES_SVH
`define RVGPU_L2CACHE_TYPES_SVH

typedef struct packed {
    logic [`RVGPU_CONST_L2CACHE_TAG_BITS-1:0]       tag;
    logic [`RVGPU_CONST_L2CACHE_INDEX_BITS-1:0]     index;
    logic [`RVGPU_CONST_L2CACHE_OFFSET_BITS-1:0]    offset;
} cache_addr_t;

function automatic logic [63:0] cache_addr_to_addr64(cache_addr_t addr);
    return {addr.tag, addr.index, addr.offset};
endfunction

function automatic cache_addr_t addr64_to_cache_addr(logic [63:0] addr64);
    localparam int OFFSET_LO = 0;
    localparam int OFFSET_HI = `RVGPU_CONST_L2CACHE_OFFSET_BITS - 1;
    localparam int INDEX_LO = OFFSET_HI + 1;
    localparam int INDEX_HI = INDEX_LO + `RVGPU_CONST_L2CACHE_INDEX_BITS - 1;
    localparam int TAG_LO = INDEX_HI + 1;
    localparam int TAG_HI = TAG_LO + `RVGPU_CONST_L2CACHE_TAG_BITS - 1;

    cache_addr_t addr;
    addr.tag = addr64[TAG_HI:TAG_LO];
    addr.index = addr64[INDEX_HI:INDEX_LO];
    addr.offset = addr64[OFFSET_HI:OFFSET_LO];
    return addr;
endfunction

`endif // RVGPU_L2CACHE_TYPES_SVH