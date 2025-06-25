# Copyright 2024 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Authors:
# - Philippe Sauter   <phsauter@iis.ee.ethz.ch>


##########################################################################
# Global Connections
##########################################################################

# std cells
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VDD} -power
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {VSS} -ground
# pads
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {vdd} -power
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {vss} -ground
# fix for bondpad/port naming
add_global_connection -net {VDDIO} -inst_pattern {.*} -pin_pattern {.*vdd_RING} -power
add_global_connection -net {VSSIO} -inst_pattern {.*} -pin_pattern {.*vss_RING} -ground
# rams
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VDDARRAY} -power
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VDDARRAY!} -power
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VDD!} -power
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {VSS!} -ground

# pads
add_global_connection -net {VDDIO} -inst_pattern {.*} -pin_pattern {iovdd} -power
add_global_connection -net {VSSIO} -inst_pattern {.*} -pin_pattern {iovss} -ground
# fix for bondpad/port naming
add_global_connection -net {VDDIO} -inst_pattern {.*} -pin_pattern {.*iovdd_RING} -power
add_global_connection -net {VSSIO} -inst_pattern {.*} -pin_pattern {.*iovss_RING} -ground

# connection
global_connect

# voltage domains
set_voltage_domain -name {CORE} -power {VDD} -ground {VSS}

#set variables
set macro RM_IHPSG13_1P_256x64_c2_bm_bist
set sram  [[ord::get_db] findMaster $macro]
set sramHeight  [ord::dbu_to_microns [$sram getHeight]]
set stripe_dist [expr $sramHeight - 50]
if {$stripe_dist > 100} {set stripe_dist [expr $stripe_dist/2]}

# standard cell grid and rings
define_pdn_grid -name {core_grid} -voltage_domains {CORE}

#macros power grid
define_pdn_grid -macro -cells $macro -name sram_256x64_grid -orient "R0 R180 MY MX" \
        -grid_over_boundary -voltage_domains {CORE} \
        -halo {1 1}

add_pdn_ring -grid {core_grid}   \
   -layer        {TopMetal1 TopMetal2}       \
   -widths       "10 10"                     \
   -spacings     "6 6"                       \
   -pad_offsets  "6 6"                       \
   -add_connect                              \
   -connect_to_pads                          \
   -connect_to_pad_layers TopMetal2

add_pdn_stripe -grid {core_grid} \
  -layer {Metal1}                            \
  -width {0.44}                              \
  -offset {0}                                \
  -followpins                                \
  -extend_to_core_ring


#power stripe to reduce resistance
add_pdn_stripe -grid {core_grid} -layer {TopMetal2} -width "6" \
               -pitch "204" -spacing "60" -offset "97" \
               -extend_to_core_ring -snap_to_grid -number_of_straps 7


add_pdn_connect -grid {core_grid} -layers {Metal1 TopMetal2}
add_pdn_connect -grid {core_grid} -layers {TopMetal2 Metal2}
add_pdn_connect -grid {core_grid} -layers {TopMetal2 Metal4}
# add_pdn_connect -grid {core_grid} -layers {TopMetal2 TopMetal1}
# power ring to standard cell rails
add_pdn_connect -grid {core_grid} -layers {Metal3 Metal1}
add_pdn_connect -grid {core_grid} -layers {Metal3 Metal2}

add_pdn_ring -grid sram_256x64_grid \
        -layer        {Metal3 Metal4} \
        -widths       "2 2" \
        -spacings     "0.6 0.6" \
        -core_offsets "2.4 0.6" \
        -add_connect

add_pdn_stripe -grid sram_256x64_grid -layer {TopMetal1} -width "6" -spacing "4" \
                   -pitch $stripe_dist -offset "20" -extend_to_core_ring -snap_to_grid

# Connection of Macro Power Ring to standard-cell rails
add_pdn_connect -grid sram_256x64_grid -layers {Metal3 Metal1}
# Connection of Stripes on Macro to Macro Power Ring
add_pdn_connect -grid sram_256x64_grid -layers {TopMetal1 Metal3}
add_pdn_connect -grid sram_256x64_grid -layers {TopMetal1 Metal4}
# Connection of Stripes on Macro to Core Power Stripes
add_pdn_connect -grid sram_256x64_grid -layers {TopMetal2 TopMetal1}

pdngen -failed_via_report ${report_dir}/croc_pdngen.rpt