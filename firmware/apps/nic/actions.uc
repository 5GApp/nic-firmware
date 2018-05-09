/*
 * Copyright (C) 2017 Netronome Systems, Inc.  All rights reserved.
 *
 * @file   action.uc
 * @brief  Action interpreter and core NIC data plane actions.
 */

#ifndef _ACTIONS_UC
#define _ACTIONS_UC

#include <kernel/nfp_net_ctrl.h>
#include <nic_basic/nic_stats.h>

#include "app_config_instr.h"
#include "protocols.h"

#include <passert.uc>

#include "pv.uc"
#include "pkt_io.uc"
#include "ebpf.uc"

.reg volatile read $__actions[NIC_MAX_INSTR]
.addr $__actions[0] 32
.xfer_order $__actions
.reg volatile __actions_t_idx

#macro __actions_read(out_data, in_mask, in_shf)
    #if (streq('in_mask', '--'))
        #if (streq('in_shf', '--'))
            alu[out_data, --, B, *$index++]
        #else
            alu[out_data, --, B, *$index++, in_shf]
        #endif
    #else
        #if (streq('in_shf', '--'))
            #if (is_ct_const(in_mask) && in_mask == 0xffff)
                alu[out_data, 0, +16, *$index++]
            #else
                alu[out_data, in_mask, AND, *$index++]
            #endif
        #else
            alu[out_data, in_mask, AND, *$index++, in_shf]
        #endif
    #endif
    alu[__actions_t_idx, __actions_t_idx, +, 4]
#endm

#macro __actions_read(out_data, in_mask)
    __actions_read(out_data, in_mask, --)
#endm

#macro __actions_read(out_data)
    __actions_read(out_data, --, --)
#endm


#macro __actions_read()
    __actions_read(--, --, --)
#endm


#macro __actions_restore_t_idx()
    local_csr_wr[T_INDEX, __actions_t_idx]
    nop
    nop
    nop
#endm


#macro __actions_next()
    br_bclr[*$index, INSTR_PIPELINE_BIT, next#]
#endm


#macro __actions_rx_wire(out_pkt_vec, DROP_MTU_LABEL, DROP_PROTO_LABEL, ERROR_PARSE_LABEL)
.begin
    .reg mtu

    __actions_read(mtu, 0xffff)
    pkt_io_rx_wire(out_pkt_vec, mtu, DROP_MTU_LABEL, DROP_PROTO_LABEL, ERROR_PARSE_LABEL)
    __actions_restore_t_idx()
.end
#endm


#macro __actions_rx_host(out_pkt_vec, ERROR_MTU_LABEL, ERROR_PCI_LABEL)
.begin
    .reg mtu

    __actions_read(mtu, 0xffff)
    pkt_io_rx_host(out_pkt_vec, mtu, ERROR_MTU_LABEL, ERROR_PCI_LABEL)
    __actions_restore_t_idx()
.end
#endm


#macro __actions_check_mac(in_pkt_vec, DROP_LABEL)
.begin
    .reg mac[2]
    .reg tmp

    __actions_read(mac[0], 0xffff)
    __actions_read(mac[1])

    pv_seek(in_pkt_vec, 0, PV_SEEK_CTM_ONLY)

    // permit multicast and broadcast addresses to pass
    br_bset[*$index, BF_L(MAC_MULTICAST_bf), pass#]

    alu[tmp, mac[0], XOR, *$index++]
    alu[--, --, B, tmp, <<16]
    bne[DROP_LABEL]

    alu[--, mac[1], XOR, *$index++]
    bne[DROP_LABEL]

pass#:
    __actions_restore_t_idx()
.end
#endm


#macro __actions_rss(in_pkt_vec)
.begin
    .reg args[3]
    .reg cfg_proto
    .reg col_msk
    .reg data
    .reg hash
    .reg hash_type
    .reg l3_offset
    .reg l4_offset
    .reg max_queue
    .reg proto_delta
    .reg proto_shf
    .reg queue
    .reg queue_msk
    .reg queue_shf
    .reg row_msk
    .reg rss_table_addr
    .reg rss_table_idx
    .reg write $metadata

    __actions_read(args[0])
    __actions_read(args[1])
    __actions_read(args[2])

    br_bset[BF_AL(in_pkt_vec, PV_QUEUE_SELECTED_bf), queue_selected#]

begin#:
    bitfield_extract__sz1(l3_offset, BF_AML(in_pkt_vec, PV_HEADER_OFFSET_L3_bf)) ; PV_HEADER_OFFSET_L3_bf
    beq[end#] // unknown L3

    // seek to IP source address
    alu[l3_offset, l3_offset, +, (8 + 2)] // 8 bytes of IP header, 2 bytes seek align
    alu[proto_delta, (1 << 2), AND, BF_A(in_pkt_vec, PV_PROTO_bf), <<1] // 4 bytes extra for IPv4
    alu[l3_offset, l3_offset, +, proto_delta]
    pv_seek(in_pkt_vec, l3_offset, (PV_SEEK_CTM_ONLY | PV_SEEK_PAD_INCLUDED))

    local_csr_wr[CRC_REMAINDER, BF_A(args, INSTR_RSS_KEY_bf)]
    immed[hash_type, 1]
    byte_align_be[--, *$index++]
    byte_align_be[data, *$index++]
    br_bset[BF_A(in_pkt_vec, PV_PROTO_bf), 1, check_l4#], defer[3] // branch if IPv4, 2 words hashed
        crc_be[crc_32, --, data]
        byte_align_be[data, *$index++]
        crc_be[crc_32, --, data]

    // hash 6 more words for IPv6
    #define_eval LOOP (0)
    #while (LOOP < 6)
        byte_align_be[data, *$index++]
        crc_be[crc_32, --, data]
        #define_eval LOOP (LOOP + 1)
    #endloop
    #undef LOOP

    alu[hash_type, hash_type, +, 1]

check_l4#:
    // skip L4 if RSS not configured for protocol (this will also skip fragments)
    bitfield_extract(cfg_proto, BF_AML(args, INSTR_RSS_CFG_PROTO_bf)) ; INSTR_RSS_CFG_PROTO_bf
    alu[--, BF_A(in_pkt_vec, PV_PROTO_bf), OR, 0] ; PV_PROTO_bf
    alu[--, cfg_proto, AND, 1, <<indirect]
    beq[skip_l4#], defer[1]
        bitfield_extract__sz1(rss_table_addr, BF_AML(args, INSTR_RSS_TABLE_ADDR_bf)) ; INSTR_RSS_TABLE_ADDR_bf

    bitfield_extract__sz1(l4_offset, BF_AML(in_pkt_vec, PV_HEADER_OFFSET_L4_bf)) ; PV_HEADER_OFFSET_L4_bf
    beq[end#] // unknown L4

    pv_seek(in_pkt_vec, l4_offset, PV_SEEK_T_INDEX_ONLY, process_l4#)

queue_selected#:
    bitfield_extract__sz1(max_queue, BF_AML(args, INSTR_RSS_MAX_QUEUE_bf))
    bitfield_extract__sz1(queue, BF_AML(in_pkt_vec, PV_QUEUE_OFFSET_bf))
    alu[--, max_queue, -, queue]
    bhs[end#]

    br[begin#], defer[1]
        pv_set_queue_offset__sz1(in_pkt_vec, 0)

process_l4#:
    byte_align_be[--, *$index++]
    byte_align_be[data, *$index++]
    crc_be[crc_32, --, data]

    alu[proto_shf, BF_A(in_pkt_vec, PV_PROTO_bf), AND, 1]
    alu[proto_delta, proto_shf, B, 3]
    alu[proto_delta, --, B, proto_delta, <<indirect]
    alu[hash_type, hash_type, +, proto_delta]

skip_l4#:
    br_bset[BF_AL(args, INSTR_RSS_V1_META_bf), skip_meta_type#], defer[3]
        pv_meta_push_type__sz1(in_pkt_vec, hash_type)
        local_csr_rd[CRC_REMAINDER]
        immed[hash, 0]

    pv_meta_push_type__sz1(in_pkt_vec, NFP_NET_META_HASH)

skip_meta_type#:
    // index into RSS table rows
    bitfield_extract__sz1(row_msk, BF_AML(args, INSTR_RSS_ROW_MASK_bf)) ; INSTR_RSS_ROW_MASK_bf
    alu[--, BF_A(args, INSTR_RSS_ROW_SHIFT_bf), OR, 0]
    alu[rss_table_idx, row_msk, AND, hash, >>indirect]
    alu[rss_table_addr, rss_table_addr, +, rss_table_idx]
    local_csr_wr[NN_GET, rss_table_addr]

    // index into RSS table column
    bitfield_extract__sz1(col_msk, BF_AML(args, INSTR_RSS_COL_MASK_bf)) ; INSTR_RSS_COL_MASK_bf
    alu[$metadata, BF_A(args, INSTR_RSS_COL_SHIFT_bf), B, hash]
    alu[queue_shf, col_msk, AND, hash, <<indirect]
    passert(BF_M(INSTR_RSS_QUEUE_MASK_bf), "EQ", 31)
    alu[queue_msk, queue_shf, B, BF_A(args, INSTR_RSS_QUEUE_MASK_bf), >>BF_L(INSTR_RSS_QUEUE_MASK_bf)]
    alu[queue, queue_msk, AND, *n$index, >>indirect]
    pv_set_queue_offset__sz1(in_pkt_vec, queue)

    pv_meta_prepend(in_pkt_vec, $metadata, 4)

    __actions_restore_t_idx()
end#:
.end
#endm


#macro __actions_checksum_complete(in_pkt_vec)
.begin
    .reg available_words
    .reg carries
    .reg checksum
    .reg data_len
    .reg idx
    .reg include_mask
    .reg iteration_bytes
    .reg iteration_words
    .reg last_bits
    .reg offset
    .reg pkt_len
    .reg remaining_words
    .reg shift
    .reg zero_padded
    .reg write $metadata

    .sig sig_read

    __actions_read()

    immed[checksum, 0]
    immed[carries, 0]

    pv_get_length(pkt_len, in_pkt_vec)

    alu[data_len, pkt_len, -, 14]
    bgt[start#], defer[3]
        alu[remaining_words, --, B, data_len, >>2]
        immed[iteration_words, 0]
        immed[offset, (14 + 2)]

    br[skip_checksum#]

#define_eval LOOP_UNROLL (0)
#while (LOOP_UNROLL < 32)
w/**/LOOP_UNROLL#:
    alu[checksum, checksum, +carry, *$index++]
    #define_eval LOOP_UNROLL (LOOP_UNROLL + 1)
#endloop
#undef LOOP_UNROLL

    alu[carries, carries, +carry, 0] // accumulate carries that would be lost to looping construct alu[]s

start#:
    pv_seek(idx, in_pkt_vec, offset, --, PV_SEEK_PAD_INCLUDED, --)

    alu[remaining_words, remaining_words, -, iteration_words]
    beq[last_bits#]

    alu[available_words, 32, -, idx]
    alu[--, available_words, -, remaining_words]
    bmi[consume_available#]

    alu[idx, 32, -, remaining_words]

consume_available#:
    jump[idx, w0#], targets[w0#,  w1#,  w2#,  w3#,  w4#,  w5#,  w6#,  w7#,
                            w8#,  w9#,  w10#, w11#, w12#, w13#, w14#, w15#,
                            w16#, w17#, w18#, w19#, w20#, w21#, w22#, w23#,
                            w24#, w25#, w26#, w27#, w28#, w29#, w30#, w31#], defer[3]
        alu[iteration_words, 32, -, idx]
        alu[iteration_bytes, --, B, iteration_words, <<2]
        alu[offset, offset, +, iteration_bytes]

last_bits#:
    pv_meta_push_type__sz1(in_pkt_vec, NFP_NET_META_CSUM)
    alu[last_bits, (3 << 3), AND, data_len, <<3]
    beq[finalize#]

    alu[shift, 32, -, last_bits]
    alu[include_mask, shift, ~B, 0]
    alu[include_mask, --, B, include_mask, <<indirect]
    alu[zero_padded, include_mask, AND, *$index]
    alu[checksum, checksum, +, zero_padded]

finalize#:
    alu[checksum, checksum, +carry, carries]
    alu[$metadata, checksum, +carry, 0] // adding carries might cause another carry

    pv_meta_prepend(in_pkt_vec, $metadata, 4)

    __actions_restore_t_idx()

skip_checksum#:
.end
#endm


#macro actions_load(io_pkt_vec, in_addr)
.begin
    .sig sig_actions

    ov_start(OV_LENGTH)
    ov_set_use(OV_LENGTH, 16, OVF_SUBTRACT_ONE)
    ov_clean()
    cls[read, $__actions[0], 0, in_addr, max_16], indirect_ref, defer[2], ctx_swap[sig_actions]
        .reg_addr __actions_t_idx 28 B
        alu[__actions_t_idx, t_idx_ctx, OR, &$__actions[0], <<2]
        pv_set_ingress_queue__sz1(io_pkt_vec, in_addr, (NIC_MAX_INSTR * 4))

    local_csr_wr[T_INDEX, __actions_t_idx]
    nop
    nop
    nop
.end
#endm


#macro actions_execute(io_pkt_vec, EGRESS_LABEL)
.begin
    .reg ebpf_addr
    .reg jump_idx
    .reg egress_q_base

next#:
    alu[jump_idx, --, B, *$index, >>INSTR_OPCODE_LSB]
    jump[jump_idx, ins_0#], targets[ins_0#, ins_1#, ins_2#, ins_3#, ins_4#, ins_5#, ins_6#, ins_7#, ins_8#, ins_9#]

    ins_0#: br[drop_act#]
    ins_1#: br[rx_wire#]
    ins_2#: br[mac#]
    ins_3#: br[rss#]
    ins_4#: br[checksum_complete#]
    ins_5#: br[tx_host#]
    ins_6#: br[rx_host#]
    ins_7#: br[tx_wire#]
    ins_8#: br[cmsg#]
    ins_9#: br[ebpf#]

drop_proto#:
    // invalid protocols have no sequencer, must not go to reorder
    pkt_io_drop(pkt_vec)
    pv_stats_update(io_pkt_vec, RX_DISCARD_PROTO, ingress#)

error_parse#:
    pv_stats_update(io_pkt_vec, RX_ERROR_PARSE, drop#)

error_pci#:
    pv_stats_update(io_pkt_vec, TX_ERROR_PCI, drop#)

error_mtu#:
    pv_stats_update(io_pkt_vec, TX_ERROR_MTU, drop#)

drop_mtu#:
    pv_stats_update(io_pkt_vec, RX_DISCARD_MTU, drop#)

drop_addr#:
    pv_stats_update(io_pkt_vec, RX_DISCARD_ADDR, drop#)

drop_act#:
    pv_stats_update(io_pkt_vec, RX_DISCARD_ACT, drop#)

rx_wire#:
    __actions_rx_wire(io_pkt_vec, drop_mtu#, drop_proto#, error_parse#)
    __actions_next()

mac#:
    __actions_check_mac(io_pkt_vec, drop_addr#)
    __actions_next()

rss#:
    __actions_rss(io_pkt_vec)
    __actions_next()

checksum_complete#:
    __actions_checksum_complete(io_pkt_vec)
    __actions_next()

tx_host#:
    __actions_read(egress_q_base, 0xffff)
    pkt_io_tx_host(io_pkt_vec, egress_q_base, EGRESS_LABEL)

rx_host#:
    __actions_rx_host(io_pkt_vec, error_mtu#, error_pci#)
    __actions_next()

tx_wire#:
    __actions_read(egress_q_base, 0xffff)
    pkt_io_tx_wire(io_pkt_vec, egress_q_base, EGRESS_LABEL)

cmsg#:
    cmsg_desc_workq($__pkt_io_gro_meta, io_pkt_vec, EGRESS_LABEL)

ebpf#:
    __actions_read(ebpf_addr, 0xffff)
    ebpf_call(io_pkt_vec, ebpf_addr)

.end
#endm

#endif
