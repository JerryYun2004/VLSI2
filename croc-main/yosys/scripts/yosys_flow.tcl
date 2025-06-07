# Copyright (c) 2025 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Synthesis script template for VLSI-2 EX04     
# To use this script in Yosys (from the `yosys` directory):                  
# % > source scripts/yosys_flow.tcl
#
# Authors:
# - Bowen Wang      <bowwang@iis.ee.ethz.ch>
# - Enrico Zelioli  <ezelioli@iis.ee.ethz.ch>
# Last Modification: 09.03.2025

set top    "croc_chip"
set repdir "./reports"
set libdir "../technology/lib"

#######################################
###### Read Technology Libraries ######
#######################################

# TODO: student task 2
# Read liberty files for standard cells, SRAM macros, and I/O pads

yosys read_liberty -lib ${libdir}/sg13g2_stdcell_typ_1p20V_25C.lib
yosys read_liberty -lib ${libdir}/RM_IHPSG13_1P_256x64_c2_bm_bist_typ_1p20V_25C.lib
yosys read_liberty -lib ${libdir}/sg13g2_io_typ_1p2V_3p3V_25C.lib

#########################
###### Load Design ######
#########################

# TODO: student task 3 & 4
# 3.1: Enable Yosys SystemVerilog frontend
# 3.2: Load Croc chip design

yosys plugin -i slang.so
yosys read_slang --top ${top} -F ../croc.flist --keep-hierarchy --allow-use-before-declare --ignore-unknown-modules

# --no-proc
yosys tee -q -o "${repdir}/00_${top}_parsed.rpt" stat

#########################
###### Elaboration ######
#########################

# TODO: student task 5
# 5.1 Resolve design hierarchy 
# 5.2 Convert processes to netlists
# 5.3 Export report and netlist

yosys hierarchy -check -top ${top}
yosys proc
yosys tee -q -o "${repdir}/01_${top}_elaborated.rpt" stat
yosys write_verilog -norename -noexpr -attr2comment out/${top}_yosys_elaborated.v

####################################
###### Coarse-grain Synthesis ######
####################################

# TODO: student task 6
# 6.1 Early-stage design check
yosys check
# 6.2 First opt pass (no FF)
yosys opt -noff
# 6.3 Extract FSM and write report
yosys fsm
yosys tee -q -o "${repdir}/02_${top}_initial_opt.rpt" stat
# 6.4 Perform wreduce
yosys wreduce

yosys peepopt
yosys opt -full
# 6.3 Infer memories and optimize register-files
yosys memory
yosys tee -q -o "${repdir}/03_${top}_memories.rpt" stat
yosys opt -fast
# 6.4 Optimize flip-flops
yosys opt_dff
yosys tee -q -o "reports/04_croc.postoptdff.rpt" stat

###########################################
###### Define target clock frequency ######
###########################################

# TODO: student task 7
# 7.1 Define clock period variable

set period_ps 10000

##################################
###### Fine-grain synthesis ######
##################################

# TODO: student task 9
# 9.1 Generic cell substitution
# 9.2 Generate report
yosys techmap
yosys tee -q -o "reports/05_croc.posttechmap.rpt" stat

############################
###### Flatten design ######
############################

# preserve hierarchy of selected modules/instances
# 't' means type as in select all instances of this type/module
# yosys-slang uniquifies all modules with the naming scheme:
# <module-name>$<instance-name> -> match for t:<module-name>$$
yosys setattr -set keep_hierarchy 1 "t:croc_soc$*"
yosys setattr -set keep_hierarchy 1 "t:croc_domain$*"
yosys setattr -set keep_hierarchy 1 "t:user_domain$*"
yosys setattr -set keep_hierarchy 1 "t:core_wrap$*"
yosys setattr -set keep_hierarchy 1 "t:gpio$*"
yosys setattr -set keep_hierarchy 1 "t:timer_unit$*"
yosys setattr -set keep_hierarchy 1 "t:reg_uart_wrap$*"
yosys setattr -set keep_hierarchy 1 "t:soc_ctrl_reg_top$*"
yosys setattr -set keep_hierarchy 1 "t:tc_clk*$*"
yosys setattr -set keep_hierarchy 1 "t:tc_sram$*"
yosys setattr -set keep_hierarchy 1 "t:cdc_*$*"
yosys setattr -set keep_hierarchy 1 "t:sync$*"

# TODO: student task 12 & 13
# 12.1 Flatten design
yosys flatten

## Reenaming

# Retain ff names
# rename DFFs from the driven signal
yosys rename -wire -suffix _reg t:*DFF*

################################
###### Technology Mapping ######
################################

# TODO: student task 10
# 10.1 Register mapping
# 10.2 Generate a report
# 10.3 Combinational logic mapping
# 10.4 Export netlist

yosys dfflibmap -liberty ../technology/lib/sg13g2_stdcell_typ_1p20V_25C.lib
yosys tee -q -o "reports/06_croc.postlibmap.rpt" stat \
    -liberty ${libdir}/sg13g2_stdcell_typ_1p20V_25C.lib \
    -liberty ${libdir}/RM_IHPSG13_1P_256x64_c2_bm_bist_typ_1p20V_25C.lib \
    -liberty ${libdir}/sg13g2_io_typ_1p2V_3p3V_25C.lib

yosys abc -liberty ../technology/lib/sg13g2_stdcell_typ_1p20V_25C.lib -D ${period_ps} -constr src/yosys_abc.constr -script scripts/abc-opt.script -showtmp
yosys tee -q -o "reports/07_croc.postabc.rpt" stat \
    -liberty ${libdir}/sg13g2_stdcell_typ_1p20V_25C.lib \
    -liberty ${libdir}/RM_IHPSG13_1P_256x64_c2_bm_bist_typ_1p20V_25C.lib \
    -liberty ${libdir}/sg13g2_io_typ_1p2V_3p3V_25C.lib

yosys write_verilog "out/croc.postabc.v"

#######################################
###### Prepare for OpenROAD flow ######
#######################################

# TODO: student task 14

# Export netlist before last changes for debugging
yosys write_verilog -norename -noexpr -attr2comment out/${top}_yosys_debug.v

# 14.1 Split multi-bit nets
yosys splitnets -ports -format __v
# 14.2 Replace undefined constants
yosys setundef -zero
yosys clean -purge
# 14.3 Replace constant bits with driver cells
yosys hilomap -singleton -hicell {sg13g2_tiehi L_HI} -locell {sg13g2_tielo L_LO}
# 14.4 Export
# final reports
yosys tee -q -o "reports/${top}_synth.rpt" check
yosys tee -q -o "reports/${top}_area.rpt" stat -top $top
yosys tee -q -o "reports/${top}_area_logic.rpt" stat -top $top \
    -liberty ${libdir}/sg13g2_stdcell_typ_1p20V_25C.lib \
    -liberty ${libdir}/RM_IHPSG13_1P_256x64_c2_bm_bist_typ_1p20V_25C.lib \
    -liberty ${libdir}/sg13g2_io_typ_1p2V_3p3V_25C.lib

# Final netlist
yosys write_verilog -noattr -noexpr -nohex -nodec out/${top}_yosys.v

exit

