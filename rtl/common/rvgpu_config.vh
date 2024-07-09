/*
Copyright © 2023 Sietium Semiconductor.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0
  
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

`define ICACHE_32K

// ICACHE CONFIG
`ifdef ICACHE_32K
  `define ICACHE_TAG_INDEX_WIDTH        8
  `define ICACHE_DATA_INDEX_WIDTH       11
`endif