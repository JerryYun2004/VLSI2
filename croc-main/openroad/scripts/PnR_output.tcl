#used to generate gds file for drc/lvs
write_def out/croc.def
#netlist for post-layout simulations
write_verilog out/croc.v
#lvs netlist
write_verilog -include_pwr_gnd out/croc_lvs.v
#sdc constraints
write_sdc out/croc.sdc
#used to reload design
write_db out/croc.odb