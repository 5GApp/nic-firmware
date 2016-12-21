/**
 * Copyright (C) 2016,  Netronome Systems, Inc.  All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * @file          link_ctrl.c
 * @brief         Code for configuring the Ethernet link.
 */


#include <assert.h>
#include <nfp/xpb.h>
#include <nfp6000/nfp_mac.h>
#include <nfp6000/nfp_nbi_tm.h>

#include <link_state/link_ctrl.h>


/* Maximum Ethernet ports per MAC core */
#define MAX_ETH_PORTS_PER_MAC_CORE 12

/* Maximum number of MAC cores per MAC island */
#define MAX_MAC_CORES_PER_MAC_ISL  2

/* Maximum number of MAC islands supported on the NFP */
#define MAX_MAC_ISLANDS_PER_NFP    2

/* Macro to convert MAC core port to MAC port. */
#define MAC_CORE_PORT_TO_MAC_PORT(_core, _core_port)      \
    ((_core) * MAX_ETH_PORTS_PER_MAC_CORE + (_core_port))


/* Address of the MAC Ethernet port configuration register */
#define MAC_CONF_ADDR(_isl, _core, _core_port)    \
    (NFP_MAC_XPB_OFF(_isl) | NFP_MAC_ETH(_core) | \
     NFP_MAC_ETH_SEG_CMD_CONFIG(_core_port))

/* Addresses of the MAC enqueue inhibit registers */
#define MAC_EQ_INH_ADDR(_isl)                                  \
    (NFP_MAC_XPB_OFF(_isl) | NFP_MAC_CSR | NFP_MAC_CSR_EQ_INH)
#define MAC_EQ_INH_DONE_ADDR(_isl)                                  \
    (NFP_MAC_XPB_OFF(_isl) | NFP_MAC_CSR | NFP_MAC_CSR_EQ_INH_DONE)


/* Maximum number of NBI islands supported on the NFP */
#define MAX_NBI_ISLANDS_PER_NFP    2

/* Maximum number of TM queues per NBI */
#define MAX_TM_QUEUES_PER_NBI_ISL  1024

/* Address of the NBI TM queue configuration register */
#define NBI_TM_Q_CFG_ADDR(_isl, _q)                    \
    (NFP_NBI_TM_XPB_OFF(_isl) | NFP_NBI_TM_QUEUE_REG | \
     NFP_NBI_TM_QUEUE_CONFIG(_q))


/* *** MAC RX Enable/Disable Functions *** */

__intrinsic int
mac_eth_check_rx_enable(unsigned int mac_isl, unsigned int mac_core,
                        unsigned int mac_core_port)
{
    uint32_t mac_conf;
    uint32_t mac_conf_addr;

    /* Check the parameters */
    assert(mac_isl < MAX_MAC_ISLANDS_PER_NFP);
    assert(mac_core < MAX_MAC_CORES_PER_MAC_ISL);
    assert(mac_core_port < MAX_ETH_PORTS_PER_MAC_CORE);

    /* Read the configuration register for the port. */
    mac_conf_addr = MAC_CONF_ADDR(mac_isl, mac_core, mac_core_port);
    mac_conf      = xpb_read(mac_conf_addr);

    return ((mac_conf & NFP_MAC_ETH_SEG_CMD_CONFIG_RX_ENABLE) ? 1 : 0);
}


__intrinsic void
mac_eth_disable_rx(unsigned int mac_isl, unsigned int mac_core,
                   unsigned int mac_core_port, unsigned int num_lanes)
{
    uint32_t mac_conf;
    uint32_t mac_conf_addr;
    uint32_t mac_inhibit;
    uint32_t mac_inhibit_addr;
    uint32_t mac_inhibit_done;
    uint32_t mac_inhibit_done_addr;
    uint32_t mac_port_mask;

    /* Check the parameters */
    assert(mac_isl < MAX_MAC_ISLANDS_PER_NFP);
    assert(mac_core < MAX_MAC_CORES_PER_MAC_ISL);
    assert(mac_core_port < MAX_ETH_PORTS_PER_MAC_CORE);
    assert((mac_core_port + num_lanes - 1) < MAX_ETH_PORTS_PER_MAC_CORE);

    /* Enable the MAC RX enqueue inhibit. */
    mac_inhibit_addr  = MAC_EQ_INH_ADDR(mac_isl);
    mac_port_mask     = (((1 << num_lanes) - 1) <<
                         MAC_CORE_PORT_TO_MAC_PORT(mac_core, mac_core_port));
    mac_inhibit       = xpb_read(mac_inhibit_addr);
    mac_inhibit      |= mac_port_mask;
    xpb_write(mac_inhibit_addr, mac_inhibit);

    /* Poll until the MAC inhibit takes effect. */
    mac_inhibit_done_addr = MAC_EQ_INH_DONE_ADDR(mac_isl);

    do {
        mac_inhibit_done  = xpb_read(mac_inhibit_done_addr);
        mac_inhibit_done &= mac_port_mask;
    } while (mac_inhibit_done != mac_port_mask);

    /* Clear the MAC RX enable for the port. */
    mac_conf_addr  = MAC_CONF_ADDR(mac_isl, mac_core, mac_core_port);
    mac_conf       = xpb_read(mac_conf_addr);
    mac_conf      &= ~NFP_MAC_ETH_SEG_CMD_CONFIG_RX_ENABLE;
    xpb_write(mac_conf_addr, mac_conf);

    /* Disable the MAC RX enqueue inhibit. */
    mac_inhibit &= ~mac_port_mask;
    xpb_write(mac_inhibit_addr, mac_inhibit);

    return;
}


__intrinsic void
mac_eth_enable_rx(unsigned int mac_isl, unsigned int mac_core,
                  unsigned int mac_core_port)
{
    uint32_t mac_conf;
    uint32_t mac_conf_addr;

    /* Check the parameters */
    assert(mac_isl < MAX_MAC_ISLANDS_PER_NFP);
    assert(mac_core < MAX_MAC_CORES_PER_MAC_ISL);
    assert(mac_core_port < MAX_ETH_PORTS_PER_MAC_CORE);

    /* Set the MAC RX enable for the port. */
    mac_conf_addr  = MAC_CONF_ADDR(mac_isl, mac_core, mac_core_port);
    mac_conf       = xpb_read(mac_conf_addr);
    mac_conf      |= NFP_MAC_ETH_SEG_CMD_CONFIG_RX_ENABLE;
    xpb_write(mac_conf_addr, mac_conf);

    return;
}


/* *** MAC TX Flush Enable/Disable Functions *** */

__intrinsic int
mac_eth_check_tx_flush_enable(unsigned int mac_isl, unsigned int mac_core,
                              unsigned int mac_core_port)
{
    uint32_t mac_conf;
    uint32_t mac_conf_addr;

    /* Check the parameters */
    assert(mac_isl < MAX_MAC_ISLANDS_PER_NFP);
    assert(mac_core < MAX_MAC_CORES_PER_MAC_ISL);
    assert(mac_core_port < MAX_ETH_PORTS_PER_MAC_CORE);

    /* Read the configuration register for the port. */
    mac_conf_addr = MAC_CONF_ADDR(mac_isl, mac_core, mac_core_port);
    mac_conf      = xpb_read(mac_conf_addr);

    return ((mac_conf & NFP_MAC_ETH_SEG_CMD_CONFIG_TX_FLUSH) ? 1 : 0);
}


__intrinsic void
mac_eth_disable_tx_flush(unsigned int mac_isl, unsigned int mac_core,
                         unsigned int mac_core_port)
{
    uint32_t mac_conf;
    uint32_t mac_conf_addr;

    /* Check the parameters */
    assert(mac_isl < MAX_MAC_ISLANDS_PER_NFP);
    assert(mac_core < MAX_MAC_CORES_PER_MAC_ISL);
    assert(mac_core_port < MAX_ETH_PORTS_PER_MAC_CORE);

    /* Clear the MAC TX flush enable for the port. */
    mac_conf_addr  = MAC_CONF_ADDR(mac_isl, mac_core, mac_core_port);
    mac_conf       = xpb_read(mac_conf_addr);
    mac_conf      &= ~NFP_MAC_ETH_SEG_CMD_CONFIG_TX_FLUSH;
    xpb_write(mac_conf_addr, mac_conf);

    return;
}


__intrinsic void
mac_eth_enable_tx_flush(unsigned int mac_isl, unsigned int mac_core,
                        unsigned int mac_core_port)
{
    uint32_t mac_conf;
    uint32_t mac_conf_addr;

    /* Check the parameters */
    assert(mac_isl < MAX_MAC_ISLANDS_PER_NFP);
    assert(mac_core < MAX_MAC_CORES_PER_MAC_ISL);
    assert(mac_core_port < MAX_ETH_PORTS_PER_MAC_CORE);

    /* Set the MAC TX flush enable for the port. */
    mac_conf_addr  = MAC_CONF_ADDR(mac_isl, mac_core, mac_core_port);
    mac_conf       = xpb_read(mac_conf_addr);
    mac_conf      |= NFP_MAC_ETH_SEG_CMD_CONFIG_TX_FLUSH;
    xpb_write(mac_conf_addr, mac_conf);

    return;
}


/* *** NBI TM Queue Enable/Disable Functions *** */

__intrinsic void
nbi_tm_disable_queue(unsigned int nbi_isl, unsigned int tm_q)
{
    uint32_t tm_q_cfg;
    uint32_t tm_q_cfg_addr;

    /* Check the parameters */
    assert(nbi_isl < MAX_NBI_ISLANDS_PER_NFP);
    assert(tm_q < MAX_TM_QUEUES_PER_NBI_ISL);

    /* Clear the NBI TM queue enable. */
    tm_q_cfg_addr  = NBI_TM_Q_CFG_ADDR(nbi_isl, tm_q);
    tm_q_cfg       = xpb_read(tm_q_cfg_addr);
    tm_q_cfg      &= ~NFP_NBI_TM_QUEUE_CONFIG_QUEUEENABLE;
    xpb_write(tm_q_cfg_addr, tm_q_cfg);
}


__intrinsic void
nbi_tm_enable_queue(unsigned int nbi_isl, unsigned int tm_q)
{
    uint32_t tm_q_cfg;
    uint32_t tm_q_cfg_addr;

    /* Check the parameters */
    assert(nbi_isl < MAX_NBI_ISLANDS_PER_NFP);
    assert(tm_q < MAX_TM_QUEUES_PER_NBI_ISL);

    /* Set the NBI TM queue enable. */
    tm_q_cfg_addr  = NBI_TM_Q_CFG_ADDR(nbi_isl, tm_q);
    tm_q_cfg       = xpb_read(tm_q_cfg_addr);
    tm_q_cfg      |= NFP_NBI_TM_QUEUE_CONFIG_QUEUEENABLE;
    xpb_write(tm_q_cfg_addr, tm_q_cfg);
}

