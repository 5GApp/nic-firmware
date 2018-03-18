#include <single_ctx_test.uc>
#include <config.h>
#include <global.uc>
#include <pv.uc>
#include <stdmac.uc>

.sig s
.reg addr
.reg value
.reg temp
.reg loop_cntr
.reg expected[PV_SIZE_LW]
.reg volatile read  $nbi_desc_rd[(NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))]
.reg volatile write $nbi_desc_wr[(NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))]
.xfer_order $nbi_desc_rd
.xfer_order $nbi_desc_wr

#define pkt_vec *l$index1

pv_init(pkt_vec, 0)

move(addr, 0x80)


/* Test PV Packet Length, CBS and A fields */

alu[$nbi_desc_wr[0], --, B, 0]
alu[$nbi_desc_wr[1], --, B, 0]
alu[$nbi_desc_wr[2], --, B, 1, <<8] // Seq
alu[$nbi_desc_wr[3], --, B, 0]
alu[$nbi_desc_wr[4], --, B, 0]
alu[$nbi_desc_wr[5], --, B, 0]
alu[$nbi_desc_wr[6], --, B, 0]
alu[$nbi_desc_wr[7], --, B, 0]

move(expected[2], 0x80000088) // A always set, PKT_NBI_OFFSET = 128
move(expected[3], 0x00000100) // Seq
move(expected[4], 0x00003fc0) // Seek
move(expected[5], 0)
move(expected[6], 0)
move(expected[7], 0)

move(loop_cntr, 64)

.while (loop_cntr <= 0x3fff)

    move($nbi_desc_wr[0], loop_cntr)

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd)


    alu[expected[0], loop_cntr, -, MAC_PREPEND_BYTES]

    alu[temp, loop_cntr, +, PKT_NBI_OFFSET]
    .if  (temp > 1024)
        move(expected[1], 0x60000000) // ctm buffer size = 2048
    .elif  (temp > 512)
        move(expected[1], 0x40000000) // ctm buffer size = 1024
    .elif  (temp > 256)
        move(expected[1], 0x20000000) // ctm buffer size = 512
    .else
        move(expected[1], 0x00000000) // ctm buffer size = 256
    .endif


    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= (PV_SIZE_LW-1))

        move(value, pkt_vec++)

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw



/* Test PV BLS field */

alu[$nbi_desc_wr[0], --, B, 0]
alu[$nbi_desc_wr[1], --, B, 0]
alu[$nbi_desc_wr[2], --, B, 1, <<8] // Seq
alu[$nbi_desc_wr[3], --, B, 0]
alu[$nbi_desc_wr[4], --, B, 0]
alu[$nbi_desc_wr[5], --, B, 0]
alu[$nbi_desc_wr[6], --, B, 0]
alu[$nbi_desc_wr[7], --, B, 0]

move(expected[1], 0)
move(expected[2], 0x80000088) // PKT_NBI_OFFSET = 128
move(expected[3], 0x00000100) // Seq
move(expected[4], 0x00003fc0) // Seek
move(expected[5], 0)
move(expected[6], 0)
move(expected[7], 0)

move(loop_cntr, 0)

.while (loop_cntr < 4)

    alu[$nbi_desc_wr[0], 64, OR, loop_cntr, <<14]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd)


    alu[expected[0], (64 - MAC_PREPEND_BYTES), OR, loop_cntr, <<14]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= (PV_SIZE_LW-1))

        move(value, pkt_vec++)

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw



/* Test PV Packet Number field */

alu[$nbi_desc_wr[0], --, B, 0]
alu[$nbi_desc_wr[1], --, B, 0]
alu[$nbi_desc_wr[2], --, B, 1, <<8] // Seq
alu[$nbi_desc_wr[3], --, B, 0]
alu[$nbi_desc_wr[4], --, B, 0]
alu[$nbi_desc_wr[5], --, B, 0]
alu[$nbi_desc_wr[6], --, B, 0]
alu[$nbi_desc_wr[7], --, B, 0]

move(expected[1], 0)
move(expected[3], 0x00000100) // Seq
move(expected[4], 0x00003fc0) // Seek
move(expected[5], 0)
move(expected[6], 0)
move(expected[7], 0)

move(loop_cntr, 0)

// Go past size of Packet Number field to test CTM Number doesn't leak into PV Packet Number
.while (loop_cntr <= 0x400)

    alu[temp, 64, OR, loop_cntr, <<16]
    .if (loop_cntr == 0x400)
        alu[temp, temp, OR, 0x3f, <<26] // Set all CTM Number bits
    .endif
    move($nbi_desc_wr[0], temp)

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd)


    move(temp, 0x3ff)
    alu[temp, temp, AND, loop_cntr] // mask off CTM Number bits

    alu[expected[0], (64 - MAC_PREPEND_BYTES), OR, temp, <<16]
    move(expected[2], 0x80000088) // PKT_NBI_OFFSET = 128
    alu[expected[2], expected[2], OR, temp, <<16]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= (PV_SIZE_LW-1))

        move(value, pkt_vec++)

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw



/* Test PV MU Buffer Address [39:11] field */
/* Can't brute force it, get timeout */

alu[$nbi_desc_wr[0], --, B, 64]
alu[$nbi_desc_wr[1], --, B, 0]
alu[$nbi_desc_wr[2], --, B, 1, <<8] // Seq
alu[$nbi_desc_wr[3], --, B, 0]
alu[$nbi_desc_wr[4], --, B, 0]
alu[$nbi_desc_wr[5], --, B, 0]
alu[$nbi_desc_wr[6], --, B, 0]
alu[$nbi_desc_wr[7], --, B, 0]

move(expected[0], (64 - MAC_PREPEND_BYTES))
move(expected[2], 0x80000088) // PKT_NBI_OFFSET = 128
move(expected[3], 0x00000100) // Seq
move(expected[4], 0x00003fc0) // Seek
move(expected[5], 0)
move(expected[6], 0)
move(expected[7], 0)

move(loop_cntr, 0)

// Go past end of field to test all 1s */
.while (loop_cntr <= 0x20000000)

    .if (loop_cntr == 0x20000000)
        move($nbi_desc_wr[1], 0x1fffffff) // Test all 1s
    .else
        move($nbi_desc_wr[1], loop_cntr)
    .endif

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd)


    .if (loop_cntr == 0x20000000)
        move(expected[1], 0x1fffffff)
    .else
        move(expected[1], loop_cntr)
    .endif

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= (PV_SIZE_LW-1))

        move(value, pkt_vec++)

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    .if (loop_cntr == 0)
        move(loop_cntr, 1)
    .else
        alu[loop_cntr, --, B, loop_cntr, <<1]
    .endif

.endw



/* Test Packet Metadata Rsv field don't leak into PV CBS field */

alu[$nbi_desc_wr[0], --, B, 64]
alu[$nbi_desc_wr[1], --, B, 0]
alu[$nbi_desc_wr[2], --, B, 1, <<8] // Seq
alu[$nbi_desc_wr[3], --, B, 0]
alu[$nbi_desc_wr[4], --, B, 0]
alu[$nbi_desc_wr[5], --, B, 0]
alu[$nbi_desc_wr[6], --, B, 0]
alu[$nbi_desc_wr[7], --, B, 0]

move(expected[0], (64 - MAC_PREPEND_BYTES))
move(expected[1], 0)
move(expected[2], 0x80000088) // PKT_NBI_OFFSET = 128
move(expected[3], 0x00000100) // Seq
move(expected[4], 0x00003fc0) // Seek
move(expected[5], 0)
move(expected[6], 0)
move(expected[7], 0)

move(loop_cntr, 1)

.while (loop_cntr <= 0x3)

    alu[$nbi_desc_wr[1], --, B, loop_cntr, <<29]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd)


    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= (PV_SIZE_LW-1))

        move(value, pkt_vec++)

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw



/* Test PV S field */

alu[$nbi_desc_wr[0], --, B, 64]
alu[$nbi_desc_wr[1], --, B, 0]
alu[$nbi_desc_wr[2], --, B, 1, <<8] // Seq
alu[$nbi_desc_wr[3], --, B, 0]
alu[$nbi_desc_wr[4], --, B, 0]
alu[$nbi_desc_wr[5], --, B, 0]
alu[$nbi_desc_wr[6], --, B, 0]
alu[$nbi_desc_wr[7], --, B, 0]

move(expected[0], (64 - MAC_PREPEND_BYTES))
move(expected[2], 0x80000088) // PKT_NBI_OFFSET = 128
move(expected[3], 0x00000100) // Seq
move(expected[4], 0x00003fc0) // Seek
move(expected[5], 0)
move(expected[6], 0)
move(expected[7], 0)

move(loop_cntr, 0)

.while (loop_cntr < 2)

    alu[$nbi_desc_wr[1], --, B, loop_cntr, <<31]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd)


    alu[expected[1], --, B, loop_cntr, <<31]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= (PV_SIZE_LW-1))

        move(value, pkt_vec++)

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw



test_pass()

rx_discards_proto#:
rx_errors_parse#:

test_fail()
