
+define+TARGET_RTL
+define+TARGET_NETLIST_YOSYS
+define+TARGET_SYNTHESIS
+define+SYNTHESIS
../rtl/common_verification/clk_rst_gen.sv

+define+TARGET_RTL
+define+TARGET_NETLIST_YOSYS
+define+TARGET_SYNTHESIS
+define+SYNTHESIS
+incdir+../rtl/common_cells/include
../rtl/common_cells/cb_filter_pkg.sv
../rtl/common_cells/cc_onehot.sv
../rtl/common_cells/cf_math_pkg.sv

+define+TARGET_RTL
+define+TARGET_NETLIST_YOSYS
+define+TARGET_SYNTHESIS
+define+SYNTHESIS
+incdir+../rtl/apb/include
+incdir+../rtl/common_cells/include
../rtl/apb/apb_pkg.sv


+define+TARGET_RTL
+define+TARGET_NETLIST_YOSYS
+define+TARGET_SYNTHESIS
+define+SYNTHESIS
+incdir+../rtl/common_cells/include
+incdir+../rtl/obi/include
../rtl/obi/obi_pkg.sv


+define+TARGET_RTL
+define+TARGET_NETLIST_YOSYS
+define+TARGET_SYNTHESIS
+define+SYNTHESIS
+incdir+../rtl/common_cells/include
../rtl/riscv-dbg/dm_pkg.sv
../rtl/riscv-dbg/debug_rom/debug_rom.sv
../rtl/riscv-dbg/debug_rom/debug_rom_one_scratch.sv
../rtl/riscv-dbg/dm_csrs.sv
../rtl/riscv-dbg/dm_mem.sv
../rtl/riscv-dbg/dmi_cdc.sv

+define+TARGET_RTL
+define+TARGET_NETLIST_YOSYS
+define+TARGET_SYNTHESIS
+define+SYNTHESIS
+incdir+../rtl/common_cells/include
../rtl/riscv-dbg/dmi_jtag_tap.sv

+define+TARGET_RTL
+define+TARGET_NETLIST_YOSYS
+define+TARGET_SYNTHESIS
+define+SYNTHESIS
+incdir+../rtl/common_cells/include
../rtl/riscv-dbg/dm_sba.sv
../rtl/riscv-dbg/dm_top.sv
../rtl/riscv-dbg/dmi_jtag.sv
../rtl/riscv-dbg/dm_obi_top.sv

+define+TARGET_RTL
+define+TARGET_NETLIST_YOSYS
+define+TARGET_SYNTHESIS
+define+SYNTHESIS
+incdir+../rtl/common_cells/include
../rtl/riscv-dbg/tb/jtag_test_simple.sv

+define+TARGET_RTL
+define+TARGET_NETLIST_YOSYS
+define+TARGET_SYNTHESIS
+define+SYNTHESIS
../rtl/timer_unit/timer_unit_counter.sv
../rtl/timer_unit/timer_unit_counter_presc.sv
../rtl/timer_unit/apb_timer_unit.sv
../rtl/timer_unit/timer_unit.sv

+define+TARGET_RTL
+define+TARGET_NETLIST_YOSYS
+define+TARGET_SYNTHESIS
+define+SYNTHESIS
+incdir+../rtl/apb/include
+incdir+../rtl/common_cells/include
+incdir+../rtl/obi/include
+incdir+../rtl/register_interface/include
../rtl/croc_pkg.sv
../rtl/user_pkg.sv
../rtl/soc_ctrl/soc_ctrl_reg_pkg.sv
../rtl/gpio/gpio_reg_pkg.sv

# Add Netlist here
../openroad/out/croc.v

+define+TARGET_RTL
+define+TARGET_POSTLAYOUT
+define+TARGET_SYNTHESIS
+define+SYNTHESIS
+incdir+../rtl/apb/include
+incdir+../rtl/common_cells/include
+incdir+../rtl/obi/include
+incdir+../rtl/register_interface/include
../rtl/tb_croc_soc.sv


../ihp13/bondpad/verilog/bondpad_70x70.v
