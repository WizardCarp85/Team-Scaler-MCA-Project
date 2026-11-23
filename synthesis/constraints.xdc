## =============================================================================
## Xilinx Design Constraints (XDC)
## Project: Team Scaler MCA Project - 5-Stage Pipelined RISC-V Processor
## Target: xc7a35tcpg236-1 (Artix-7 100 MHz Basys 3 Clock)
## =============================================================================

# Primary Clock Constraint (100 MHz oscillator -> 10.0ns period)
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports clk]

# Clock Uncertainty / Jitter
set_clock_uncertainty 0.200 [get_clocks sys_clk_pin]
