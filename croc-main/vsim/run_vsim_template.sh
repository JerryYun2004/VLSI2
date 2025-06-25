# remove the existing library
rm -rf work
# create the library
questa-2019.3 vlib work
questa-2019.3 vlog -work work ../openroad/out/croc.v
# compile the source codes described in the file list
questa-2019.3 vlog -f croc_postlayout.f
# optimize the design.
# Notice here we include the technology libraries, which are needed for
# the SoC design
# sg13g2_stdcell standard cells
# sg13g2_io IO cell library
# RM_IHPSG13 sram cells
questa-2019.3 vopt -work work \
  -L sg13g2_stdcell \
  -L sg13g2_io \
  -L RM_IHPSG13_v2.1 \
  -sdfmin tb_croc_soc/i_croc_soc=../openroad/out/croc.sdf +sdf_verbose \
  -o tb_croc_opt tb_croc_soc
# run the simulation
# 3009 is complaining the missing timeunit/timeprecision for the SRAM
# behavior model
# We can suppress it as we are using SDF to replace the delay there
# 12088 and 12090 complains some path specified in SDF cannot be found in
# the verilog behavior model
# This is because of the incomplete behavior model of SRAM and Pad cells
# We have contacted the PDK manufactuer about it and they are working on
# fixing it
# Currently, we suppress these error message
questa-2019.3 vsim -t 1ps -lib work \
  -L sg13g2_stdcell \
  -L sg13g2_io \
  -L RM_IHPSG13_v2.0 \
  -sdfmin tb_croc_soc/i_croc_soc=../openroad/out/croc.sdf +sdf_verbose \
  -suppress vsim-3009 \
  -suppress vsim-3250 \
  -suppress vsim-3262 \
  -suppress vsim-12088 \
  -suppress vsim-12090 \
  tb_croc_opt \
  -do disable_cdc_check.tcl
# The disable_cdc_check.tcl suppress the timing checks on the JTAG CDC
# registers
# The Clock Domain Crossing (CDC) circuit moves signals between asynchronous
# clock domains
# which often causes intentionally setup/hold violations.
# The setup/hold assertion will cause x into the circuit (metalstablity)
# and make simulation failed, so we disable checks on these registers.