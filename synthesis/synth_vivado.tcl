# =============================================================================
# Vivado Non-Project Batch Synthesis Script
# Project: Team Scaler MCA Project - 5-Stage Pipelined RISC-V Processor
# Top Module: cpu (rtl/cpu.v)
# Target Part: xc7a35tcpg236-1 (Xilinx Artix-7 Basys 3)
# =============================================================================

# Set output directory
set outputDir ./synthesis/build
file mkdir $outputDir

# 1. Read Design Sources
read_verilog -vlog05 [glob ./rtl/pipeline_registers/*.v]
read_verilog -vlog05 [glob ./rtl/stages/*.v]
read_verilog -vlog05 ./rtl/cpu.v

# 2. Read Timing Constraints
read_xdc ./synthesis/constraints.xdc

# 3. Run Synthesis
synth_design -top cpu -part xc7a35tcpg236-1 -mode out_of_context

# 4. Write Post-Synthesis Reports
report_utilization -file $outputDir/post_synth_util.rpt
report_timing_summary -file $outputDir/post_synth_timing.rpt

# 5. Run Placement & Routing
opt_design
place_design
route_design

# 6. Write Final Implementation Reports
report_utilization -file $outputDir/post_route_util.rpt
report_timing_summary -file $outputDir/post_route_timing.rpt
report_power -file $outputDir/post_route_power.rpt

# Write Checkpoint
write_checkpoint -force $outputDir/cpu_routed.dcp

puts "================================================================="
puts "Vivado Synthesis and Implementation Complete!"
puts "Reports written to $outputDir"
puts "================================================================="
exit
