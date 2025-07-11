// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>

`include "register_interface/typedef.svh"
`include "obi/typedef.svh"

package user_pkg;
import croc_pkg::*;

  ////////////////////////////////
  // User Manager Address maps //
  ///////////////////////////////
  
  // None


  /////////////////////////////////////
  // User Subordinate Address maps ////
  /////////////////////////////////////

  localparam int unsigned NumUserDomainSubordinates = 2;

  localparam bit [31:0] UserRomAddrOffset   = croc_pkg::UserBaseAddr; // 32'h2000_0000;
  localparam bit [31:0] UserRomAddrRange    = 32'h0000_1000;          // every subordinate has at least 4KB

  localparam bit [31:0] UserCnnAddrOffset   = croc_pkg::UserBaseAddr + UserRomAddrRange; // 32'h2000_1000;
  localparam bit [31:0] UserCnnAddrRange    = 32'h0001_4000;          // every subordinate has at least 4KB

  localparam int unsigned NumDemuxSbrRules  = NumUserDomainSubordinates; // number of address rules in the decoder
  localparam int unsigned NumDemuxSbr       = NumDemuxSbrRules + 1; // additional OBI error, used for signal arrays

  typedef enum int {
    UserRom   = 0,
    UserCnn   = 1,
    UserError = 2
  } user_demux_outputs_e;

  localparam croc_pkg::addr_map_rule_t [NumDemuxSbrRules-1:0] user_addr_map = '{
    // 0: ROM
    '{ idx:UserRom, start_addr: UserRomAddrOffset, end_addr: UserRomAddrOffset + UserRomAddrRange - 1},
    // 1: CNN
    '{ idx:UserCnn, start_addr: UserCnnAddrOffset, end_addr: UserCnnAddrOffset + UserCnnAddrRange - 1}
  };

endpackage
