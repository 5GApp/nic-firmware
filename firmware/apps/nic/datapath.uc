/*
 * Copyright (C) 2017 Netronome Systems, Inc.  All rights reserved.
 *
 * @file   datapath.uc
 * @brief  Main processing loop for general purpose datapath workers.
 */

#include "global.uc"

#include "actions.uc"
#include "pkt_io.uc"

#define pkt_vec *l$index1
.reg act_addr

// kick off processing loop
pkt_io_init(pkt_vec)
br[ingress#]

drop#:
    pkt_io_drop(pkt_vec)

egress#:
    pkt_io_reorder(pkt_vec)

ingress#:
    pkt_io_rx(act_addr, pkt_vec)
    actions_load(act_addr)

actions#:
    actions_execute(pkt_vec, egress#)

ebpf_reentry#:
    ebpf_reentry()

#pragma warning(push)
#pragma warning(disable: 4701)
#pragma warning(disable: 5116)
PV_HDR_PARSE_SUBROUTINE#:
    pv_hdr_parse_subroutine(pkt_vec, port_tun_args)
#pragma warning(pop)

#pragma warning(disable: 4702)
fatal_error("MAIN LOOP EXIT")
