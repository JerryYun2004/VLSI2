#################
##   Helpers   ##
#################

proc disable_tchecks_off { path } {
    set instance [find instance -arch $path]
    if {[llength $instance] == 0} {
        error "No cell found for timing check expression ${path}"
    }
    echo "\tDisable timing on ${instance}"
    tcheck_set $path OFF
}

##############################
##   Disable Sync TChecks   ##
##############################
# JTAG CDC
disable_tchecks_off {sim:/tb_croc_soc/i_croc_soc/\i_croc_soc/i_croc/i_dmi_jtag/i_dmi_cdc.i_cdc_req/i_dst/i_sync/reg_q_0__reg }
disable_tchecks_off {sim:/tb_croc_soc/i_croc_soc/\i_croc_soc/i_croc/i_dmi_jtag/i_dmi_cdc.i_cdc_resp/i_dst/i_sync/reg_q_0__reg }
disable_tchecks_off {sim:/tb_croc_soc/i_croc_soc/\i_croc_soc/i_croc/i_dmi_jtag/i_dmi_cdc.i_cdc_req/i_src/i_sync/reg_q_0__reg }
disable_tchecks_off {sim:/tb_croc_soc/i_croc_soc/\i_croc_soc/i_croc/i_dmi_jtag/i_dmi_cdc.i_cdc_resp/i_src/i_sync/reg_q_0__reg }
disable_tchecks_off {sim:/tb_croc_soc/i_croc_soc/\i_croc_soc/i_croc/i_dmi_jtag/i_dmi_cdc.i_cdc_resp/i_cdc_reset_ctrlr/i_cdc_reset_ctrlr_half_a/i_state_transition_cdc_src/i_sync/reg_q_0__reg }
disable_tchecks_off {sim:/tb_croc_soc/i_croc_soc/\i_croc_soc/i_croc/i_dmi_jtag/i_dmi_cdc.i_cdc_req/i_cdc_reset_ctrlr/i_cdc_reset_ctrlr_half_b/i_state_transition_cdc_src/i_sync/reg_q_0__reg }