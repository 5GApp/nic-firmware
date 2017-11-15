#include <single_ctx_test.uc>

#include "pkt_inc_pat_64B_x80.uc"

#include <config.h>
#include <gro_cfg.uc>
#include <global.uc>
#include <pv.uc>
#include <stdmac.uc>

.reg expected
.reg tested

move(expected, 0x0f101112)

// 16th byte should be word aligned
pv_seek(pkt_vec, 14, PV_SEEK_CTM_ONLY)
move(tested, *$index)
test_assert_equal(tested, expected)

// byte_aligned T_INDEX should agree
byte_align_be[--, *$index++]
byte_align_be[tested, *$index]
test_assert_equal(tested, expected)

test_pass()
