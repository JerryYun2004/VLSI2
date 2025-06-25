# Synthesis is done with yosys.

# Start a yoys interactive tcl session with: oseda -2025.01 yosys -C
# Source this script using from within this shell: source scripts/main_flow.tcl
# To re-run synthesis do: rm -r tmp/ out/* reports/* *.log

# EASIER
# croc> make ys_clean
# croc> make yosys-flist
# croc> make yosys
# croc> make sta

# This flows assumes it is beign executed in the yosys/ directory
# but just to be sure, we go there
if {[info script] ne ""} {
    cd "[file dirname [info script]]/../"
}

# Set global variables
set netlist_file [lindex $argv 0]
if { $netlist_file eq "" } {
    set netlist_file "../yosys/out/croc.v"
}

# ----------------------------------------------------------------------------------------------
# -------------------- 1. Front-end Preprocessing ----------------------------------------------
# ----------------------------------------------------------------------------------------------

# Read the liberty files
# ----------------------
set tech_cells_lib "../technology/lib/sg13g2_stdcell_typ_1p20V_25C.lib"
set tech_io_lib    "../technology/lib/sg13g2_io_typ_1p2V_3p3V_25C.lib"
set tech_sram_lib  "../technology/lib/RM_IHPSG13_1P_256x64_c2_bm_bist_typ_1p20V_25C.lib"

set lib_list [list $tech_cells_lib $tech_io_lib $tech_sram_lib]

# Load all liberty files
foreach lib $lib_list {
    yosys read_liberty -lib $lib
}

# Read the Verilog Files
# ----------------------

# Enable System-Verilog support through slang plugin
yosys plugin -i slang.so

# Read in the verilog
# --keep-hierachy makes sure that the modules don't get flattened whilst loading
yosys read_slang --top croc_chip -F ../croc.flist \
        --allow-use-before-declare --ignore-unknown-modules \
        --keep-hierarchy --compat-mode

# Now with the whole design loaded and not flattened,
# we preserve the hierarchy of only selected modules/instances
# 't' means type as in select all instances of this type/module
# yosys-slang uniquifies all modules with the naming scheme:
# <module-name>$<instance-name> -> match for t:<module-name>$$
# copied from yosys_synthesis.tcl
yosys setattr -set keep_hierarchy 1 "t:croc_soc$*"
yosys setattr -set keep_hierarchy 1 "t:croc_domain$*"
yosys setattr -set keep_hierarchy 1 "t:user_domain$*"
yosys setattr -set keep_hierarchy 1 "t:core_wrap$*"
yosys setattr -set keep_hierarchy 1 "t:cve2_register_file_ff$*"
yosys setattr -set keep_hierarchy 1 "t:cve2_cs_registers$*"
yosys setattr -set keep_hierarchy 1 "t:dmi_jtag$*"
yosys setattr -set keep_hierarchy 1 "t:dm_top$*"
yosys setattr -set keep_hierarchy 1 "t:gpio$*"
yosys setattr -set keep_hierarchy 1 "t:timer_unit$*"
yosys setattr -set keep_hierarchy 1 "t:reg_uart_wrap$*"
yosys setattr -set keep_hierarchy 1 "t:soc_ctrl_reg_top$*"
yosys setattr -set keep_hierarchy 1 "t:tc_clk*$*"
yosys setattr -set keep_hierarchy 1 "t:tc_sram_impl$*"
yosys setattr -set keep_hierarchy 1 "t:cdc_*$*"
yosys setattr -set keep_hierarchy 1 "t:sync$*"

# map dont_touch attribute commonly applied to output-nets of async regs to keep
yosys attrmap -rename dont_touch keep
# copy the keep attribute to their driving cells (retain on net for debugging)
yosys attrmvcp -copy -attr keep

# Print statistics and save it to a report file
# -width: explicitly state the bit width of each logical block recognized by Yosys in your design
yosys tee -o "reports/croc_parsed.rpt" stat -width

# Generate an intermediate verilog file
yosys write_verilog "out/croc_parsed.v"

# ----------------------------------------------------------------------------------------------
# -------------------- 2. Elaboration ----------------------------------------------------------
# ----------------------------------------------------------------------------------------------

# check, expand, and clean up the design hierarchy
# Slang AST -> internal hierarchical graph representation
yosys hierarchy -check -top croc_chip

# Optimize. Make ready for coarse-grained synthesis.
yosys proc

# Print statistics and save it to a report file
yosys tee -q -o "reports/croc_elaborated.rpt" stat -width

# ----------------------------------------------------------------------------------------------
# -------------------- 3. Coarse-grain Synthesis -----------------------------------------------
# ----------------------------------------------------------------------------------------------

# Early Check the design
yosys check

# First round of optimizations without flipflops, since no fsm yet
yosys opt -noff

# Extract and optimize finite state machines
yosys fsm

# Reduce bit-width of operations if possible
yosys wreduce

# Simplify arithmetic operations and more
yosys peepopt

# Full optimization
yosys opt -full

# Consolidates shareable resources
yosys share

# Infer memory blocks (mostly done for FPGA flows).
# Generate optimized address decoders and registers for large flip-flop arrays for ASIC
yosys memory -nomap

# Explicitly optimize flip-flops again
yosys opt_dff
yosys memory_map

# clean and check
yosys clean
yosys check

# Generate report
yosys tee -q -o "reports/croc_optimized.rpt" stat -width

# ----------------------------------------------------------------------------------------------
# -------------------- 4. Technology Mapping ---------------------------------------------------
# ----------------------------------------------------------------------------------------------

# Setting Constraints
# -------------------

set period_ps 10000
# The other constraints are defined in 'yosys/src/abc.constr'
set abc_comb_script scripts/abc-opt.script

# Mapping to technology
# ---------------------

# replace RTL cells with yosys internal gate-level cells
yosys techmap

# Flatten the design (except marked modules)
yosys flatten
yosys clean -purge
yosys splitnets -format __v
yosys rename -wire -suffix _reg t:*DFF*

# map only the flip flops first
yosys dfflibmap -liberty $tech_cells_lib

yosys abc -liberty $tech_cells_lib \
         -D $period_ps -constr src/abc.constr \
         -script $abc_comb_script

# Generate a tech-mapped netlist
yosys write_verilog "out/croc.techmapped.v"

# ----------------------------------------------------------------------------------------------
# -------------------- 5. Preparing for OpenROAD -----------------------------------------------
# ----------------------------------------------------------------------------------------------
yosys write_verilog -norename -noexpr -attr2comment out/croc_chip_yosys_debug.v

# Split multi-bit nets
yosys splitnets

# Replace undefined constants
yosys setundef -zero

# Replace constant bits with driver cells
set tech_cell_tiehi {sg13g2_tiehi L_HI}
set tech_cell_tielo {sg13g2_tielo L_LO}
yosys hilomap -singleton -hicell {*}$tech_cell_tiehi -locell {*}$tech_cell_tielo

# Final Export
yosys check
yosys stat
yosys tee -q -o "reports/croc_final.rpt" stat -width \
        -liberty ../technology/lib/sg13g2_stdcell_typ_1p20V_25C.lib \
        -liberty ../technology/lib/sg13g2_io_typ_1p2V_3p3V_25C.lib \
        -liberty ../technology/lib/RM_IHPSG13_1P_256x64_c2_bm_bist_typ_1p20V_25C.lib

yosys write_verilog -noattr -noexpr -nohex -nodec -norename out/croc.v

# afterwards run static timing analysis using sta with
# croc> cd sta
# sta> oseda -2025.01 sta scripts/opensta.tcl

exit