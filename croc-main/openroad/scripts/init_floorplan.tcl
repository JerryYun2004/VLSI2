# source scripts/setup_OpenRoad.tcl
#source scripts/init_tech.tcl
#read_verilog ../yosys/out/croc_chip_yosys.v
#link_design croc_chip

set chipW 1995.0
set chipH 1995.0

set padRing 180.0
set coreMargin [expr $padRing + 35];

initialize_floorplan -die_area "0 0 $chipW $chipH" -core_area "$coreMargin $coreMargin [expr $chipW-$coreMargin] [expr $chipH-$coreMargin]" -site "CoreSite"
