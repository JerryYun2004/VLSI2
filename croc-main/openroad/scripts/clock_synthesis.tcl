set clock_nets [get_nets -of_objects [get_pins -of_objects "*_reg" -filter "name == CLK"]]
set_wire_rc -clock -layer Metal4
set_wire_rc -signal -layer Metal4
estimate_parasitics -placement
unset_dont_touch $clock_nets
repair_clock_inverters
clock_tree_synthesis -buf_list $ctsBuf -root_buf $ctsBufRoot -sink_clustering_enable -balance_levels -obstruction_aware

# Fixing root buffers (optional)
repair_clock_nets

#Generate Report
#Report cts not save automatically
report_cts
report_clock_latency -clock clk_sys > reports/clock_latency4.rpt
