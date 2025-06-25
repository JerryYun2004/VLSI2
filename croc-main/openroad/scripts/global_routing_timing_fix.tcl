estimate_parasitics -global_routing
repair_timing -setup -repair_tns 100
repair_timing -hold -hold_margin 0.05 -repair_tns 100
global_route -start_incremental
detailed_placement
global_route -end_incremental
check_placement
estimate_parasitics -global_routing