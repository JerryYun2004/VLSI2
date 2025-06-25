# report_checks -path_group clk_sys > reports/clock_delays.rpt

#Adding clock delays
estimate_parasitics -placement
set_propagated_clock [all_clocks]
report_checks -path_group clk_sys > reports/clock_delays.rpt

#Timing fix
repair_design -verbose
repair_timing -setup -skip_pin_swap -verbose

#lacing Buffers
detailed_placement
check_placement -verbose