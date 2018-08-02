/*
 * CMSG receive handler main function
 */


#define NUM_CONTEXT 4
.num_contexts 4

#ifndef PKT_COUNTER_ENABLE
    #define PKT_COUNTER_ENABLE
    #include "pkt_counter.uc"
	pkt_counter_init()
#endif

#define DEBUG_TRACE
#define CMSG_UNITTEST_CODE
#define JOURNAL_ENABLE 1

#define CMSG_MAP_PROC 1
#include "hashmap.uc"
#include "cmsg_map.uc"
#include "app_mac_vlan_config_cmsg.h"
hashmap_init()
cmsg_init()

#ifdef DEBUG_TRACE
	#include "map_debug_config.h"
    __hashmap_journal_init()
#endif  /* DEBUG_TRACE */

#macro ctx_sig_next()
	local_csr_wr[SAME_ME_SIGNAL, ((&g_ordersig<<3)|(1<<7))]
#endm

.begin
    .reg my_act_ctx
	.reg @cmsg_rx_cntr
	.reg @cmsg_rx_init
	.sig volatile g_ordersig

	.if (ctx() == 0)
		move(@cmsg_rx_init, 0)
		move(@cmsg_rx_cntr, 0)
		local_csr_wr[MAILBOX0, 0]
		local_csr_wr[MAILBOX1, 0]
		local_csr_wr[MAILBOX2, 0]
		ctx_sig_next()
	.else
		ctx_arb[g_ordersig]
		ctx_sig_next()
    .endif

    local_csr_rd[ACTIVE_CTX_STS]
    immed[my_act_ctx, 0]
    alu[my_act_ctx, my_act_ctx, and, 7]

    .if (ctx() == 0)
	        hashmap_alloc_fd(SRIOV_TID, 8, 32, NIC_MAC_VLAN_TABLE__NUM_ENTRIES, --, swap, BPF_MAP_TYPE_HASH)
    .endif

main_loop#:
	ctx_sig_next()
    cmsg_rx()
	alu[@cmsg_rx_cntr, 1, +, @cmsg_rx_cntr]
    local_csr_wr[MAILBOX0, @cmsg_rx_cntr]
		//__hashmap_dbg_print(0x1002, 0, ctx_num)

	ctx_arb[g_ordersig]
    br[main_loop#]

done#:
#pragma warning(disable: 4702)
ctx_arb[kill]

.end
