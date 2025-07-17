`ifndef RVGPU_CLK_RST_SVH
`define RVGPU_CLK_RST_SVH

//=============================================================================
// RVGPU Unified Clock and Reset Infrastructure
// 
// This file contains:
// - Clock/Reset interface definition
// - Clock generator module
// - Clock manager class (main API)
//=============================================================================

//-----------------------------------------------------------------------------
// Clock and Reset Interface
//-----------------------------------------------------------------------------
interface clk_rst_if;
  logic clk;
  logic rst_n;
  
  // Modports for proper signal direction
  modport master (output clk, output rst_n);
  modport slave (input clk, input rst_n);
  
  // Basic interface tasks
  task automatic wait_clk(int cycles = 1);
    repeat(cycles) @(posedge clk);
  endtask
  
  task automatic assert_reset(int cycles = 10);
    rst_n = 1'b0;
    repeat(cycles) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
  endtask
endinterface

//-----------------------------------------------------------------------------
// Clock Generator Module
//-----------------------------------------------------------------------------
module rvgpu_clk_rst_gen #(
  parameter real CLK_PERIOD_NS = 10.0,
  parameter int RST_CYCLES = 10
)(
  clk_rst_if.master clk_rst_if
);

  // Internal clock generation
  logic internal_clk = 1'b0;
  logic internal_rst_n = 1'b1;
  
  // Connect to interface
  assign clk_rst_if.clk = internal_clk;
  assign clk_rst_if.rst_n = internal_rst_n;
  
  // Automatic clock generation
  initial begin
    internal_clk = 1'b0;
    forever #(CLK_PERIOD_NS/2) internal_clk = ~internal_clk;
  end
  
  // Initial reset sequence
  initial begin
    internal_rst_n = 1'b1;
    #1;
    internal_rst_n = 1'b0;
    repeat(RST_CYCLES) @(posedge internal_clk);
    internal_rst_n = 1'b1;
  end
  
endmodule

//-----------------------------------------------------------------------------
// Clock Manager Class (Main API)
//-----------------------------------------------------------------------------
class rvgpu_clk_manager;
  
  // Configuration
  local string manager_name;
  local real clock_period_ns;
  local int reset_cycles;
  
  // Virtual interface handle
  virtual clk_rst_if clk_rst_vif;
  
  // Cycle counter
  local int unsigned cycle_count;
  
  // Constructor
  function new(string name = "clk_manager", 
               real clk_period_ns = 10.0, 
               int rst_cycles = 10);
    this.manager_name = name;
    this.clock_period_ns = clk_period_ns;
    this.reset_cycles = rst_cycles;
    this.cycle_count = 0;
  endfunction

  // Cycle counter logic (to be called from testbench initial block)
  task automatic start_cycle_counting();
    forever @(posedge clk_rst_vif.clk) begin
      this.cycle_count++;
    end
  endtask

  // Get current cycle count
  virtual function int unsigned get_cycle_count();
    return this.cycle_count;
  endfunction
  
  // Initialize with interface
  virtual function void initialize(virtual clk_rst_if vif);
    this.clk_rst_vif = vif;
    $display("@%0t: Clock manager '%s' initialized - Period: %0.1f ns (%0.1f MHz)", 
             $time, manager_name, clock_period_ns, 1000.0/clock_period_ns);
  endfunction
  
  //===========================================================================
  // Basic Clock Control API
  //===========================================================================
  
  // Wait for specified number of clock cycles
  virtual task automatic wait_clks(int cycles = 1);
    repeat(cycles) @(posedge clk_rst_vif.clk);
  endtask
  
  // Wait for positive clock edge
  virtual task automatic wait_posedge();
    @(posedge clk_rst_vif.clk);
  endtask
  
  // Wait for negative clock edge
  virtual task automatic wait_negedge();
    @(negedge clk_rst_vif.clk);
  endtask
  
  // Wait for a specific time in ns
  virtual task automatic wait_ns(real time_ns);
    #(time_ns);
  endtask
  
  // Hold time (alias for wait_ns)
  virtual task automatic hold_time(int time_ns = 1);
    #(time_ns);
  endtask

  // Wait for posedge and delay
  virtual task automatic wait_posedge_and_delay_ns(int delay_ns = 1);
    wait_posedge();
    #(delay_ns);
  endtask

  virtual task automatic delay_ns(int delay_ns = 1);
    #(delay_ns);
  endtask
  
  //===========================================================================
  // Reset Control API
  //===========================================================================
  
  // Apply reset for specified cycles
  virtual task automatic apply_reset(int cycles = -1);
    int rst_cycles = (cycles == -1) ? reset_cycles : cycles;
    clk_rst_vif.rst_n = 1'b0;
    repeat(rst_cycles) @(posedge clk_rst_vif.clk);
    clk_rst_vif.rst_n = 1'b1;
    @(posedge clk_rst_vif.clk);
    $display("@%0t: %s - Reset applied for %0d cycles", $time, manager_name, rst_cycles);
  endtask
  
  // Wait until reset is released
  virtual task automatic wait_reset_release();
    while (!clk_rst_vif.rst_n) @(posedge clk_rst_vif.clk);
    $display("@%0t: %s - Reset released", $time, manager_name);
  endtask
  
  // Wait for stable clock (useful after reset)
  virtual task automatic wait_clock_stable(int stable_cycles = 5);
    $display("@%0t: %s - Waiting for clock to stabilize (%0d cycles)", $time, manager_name, stable_cycles);
    wait_reset_release();
    wait_clks(stable_cycles);
    $display("@%0t: %s - Clock stabilized", $time, manager_name);
  endtask
  
  //===========================================================================
  // Query Functions
  //===========================================================================
  
  // Get clock signal (for DUT connection)
  virtual function logic get_clk();
    return clk_rst_vif.clk;
  endfunction
  
  // Get reset signal (for DUT connection)  
  virtual function logic get_rst_n();
    return clk_rst_vif.rst_n;
  endfunction
  
  // Check if currently in reset
  virtual function bit is_in_reset();
    return !clk_rst_vif.rst_n;
  endfunction
  
  // Get current clock period in ns
  virtual function real get_clock_period_ns();
    return clock_period_ns;
  endfunction
  
  // Get current clock frequency in MHz
  virtual function real get_clock_freq_mhz();
    return 1000.0 / clock_period_ns;
  endfunction
  
  //===========================================================================
  // SVUnit Compatibility API
  //===========================================================================
  
  virtual task automatic step(int cycles = 1);
    wait_clks(cycles);
  endtask
  
  virtual task automatic nextSamplePoint();
    wait_posedge();
  endtask
  
  virtual task automatic reset();
    apply_reset();
  endtask
  
  virtual task automatic pause();
    #0;
  endtask
  
  //===========================================================================
  // Advanced Features
  //===========================================================================
  
  // Conditional wait with timeout
  virtual task automatic wait_condition(ref logic condition, int timeout_cycles = 100);
    int cycle_count = 0;
    while (!condition && cycle_count < timeout_cycles) begin
      wait_posedge();
      cycle_count++;
    end
    if (cycle_count >= timeout_cycles) begin
      $error("@%0t: %s - Timeout waiting for condition after %0d cycles", $time, manager_name, timeout_cycles);
    end else begin
      $display("@%0t: %s - Condition met after %0d cycles", $time, manager_name, cycle_count);
    end
  endtask
  
  // Measure actual clock period
  virtual task automatic measure_clock_period();
    realtime start_time, end_time;
    real measured_period;
    start_time = $realtime;
    wait_posedge();
    wait_posedge();
    end_time = $realtime;
    measured_period = end_time - start_time;
    $display("@%0t: %s - Measured clock period: %0.3f ns (Expected: %0.3f ns)", 
             $time, manager_name, measured_period, clock_period_ns);
  endtask
  
  // Start performance monitoring in background
  virtual task automatic start_performance_monitor();
    fork
      begin
        realtime last_edge = $realtime;
        realtime current_edge;
        real period;
        forever begin
          wait_posedge();
          current_edge = $realtime;
          period = current_edge - last_edge;
          if (period > clock_period_ns * 1.1 || period < clock_period_ns * 0.9) begin
            $warning("@%0t: %s - Clock period deviation: %0.3f ns (expected %0.3f ns)", 
                     $time, manager_name, period, clock_period_ns);
          end
          last_edge = current_edge;
        end
      end
    join_none
  endtask
  
  // Display comprehensive status
  virtual function void display_status();
    $display("=== %s Status ===", manager_name);
    $display("Clock Period: %0.3f ns", clock_period_ns);
    $display("Clock Frequency: %0.1f MHz", get_clock_freq_mhz());
    $display("Reset Cycles: %0d", reset_cycles);
    $display("Current Reset State: %s", is_in_reset() ? "ACTIVE" : "INACTIVE");
    $display("Current Time: %0t", $time);
    $display("=========================");
  endfunction

endclass

`endif // RVGPU_CLK_RST_SVH 