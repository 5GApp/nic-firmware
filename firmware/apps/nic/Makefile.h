# Declare the project name as 'basic_nic_h', give its source directory and
# a default config file that will establish definitions for the project
# card type: HYDROGEN
PLATFORM = 0
$(eval $(call nffw.setup,basic_nic_h,apps/nic,config.h))
$(eval $(call nffw.add_include,basic_nic_h,$(NFP_COMMON)/include))
$(eval $(call nffw.add_ppc,basic_nic_h,i8,$(PICOCODE_DIR)/catamaran/catamaran.npfw))

# Add flowenv to the project
$(eval $(call fwdep.add_flowenv,basic_nic_h))
# Add flowenv's NFP initialization routines
$(eval $(call fwdep.add_flowenv_nfp_init_flag,basic_nic_h,-DPLATFORM=$(PLATFORM)))

# Add 1 GRO ME
$(eval $(call fwdep.add_gro_flag,basic_nic_h,ila0.me1,-DPLATFORM=$(PLATFORM)))
#$(eval $(call fwdep.add_gro,basic_nic_h,ila0.me1))

# Add 1 BLM ME
#$(eval $(call fwdep.add_blm,basic_nic_h,ila0.me0))
$(eval $(call fwdep.add_blm_flag,basic_nic_h,ila0.me0,-DPLATFORM=$(PLATFORM)))

# Custom config to give ME list to the app master
define NIC_ISL_ME_DEST
((($(1) + 32) << 4) + ($(2) + 4))
endef

NIC_APP_MES := \
        "$(call NIC_ISL_ME_DEST, 0, 0), \
        $(call NIC_ISL_ME_DEST, 0, 1), \
        $(call NIC_ISL_ME_DEST, 0, 2), \
        $(call NIC_ISL_ME_DEST, 0, 3), \
        $(call NIC_ISL_ME_DEST, 0, 4), \
        $(call NIC_ISL_ME_DEST, 0, 5), \
        $(call NIC_ISL_ME_DEST, 0, 6), \
        $(call NIC_ISL_ME_DEST, 0, 7), \
        \
        $(call NIC_ISL_ME_DEST, 1, 0), \
        $(call NIC_ISL_ME_DEST, 1, 1), \
        $(call NIC_ISL_ME_DEST, 1, 2), \
        $(call NIC_ISL_ME_DEST, 1, 3), \
        $(call NIC_ISL_ME_DEST, 1, 4), \
        $(call NIC_ISL_ME_DEST, 1, 5), \
        $(call NIC_ISL_ME_DEST, 1, 6), \
        $(call NIC_ISL_ME_DEST, 1, 7), \
        \
        $(call NIC_ISL_ME_DEST, 2, 0), \
        $(call NIC_ISL_ME_DEST, 2, 1), \
        $(call NIC_ISL_ME_DEST, 2, 2), \
        $(call NIC_ISL_ME_DEST, 2, 3), \
        $(call NIC_ISL_ME_DEST, 2, 4), \
        $(call NIC_ISL_ME_DEST, 2, 5), \
        $(call NIC_ISL_ME_DEST, 2, 6), \
        $(call NIC_ISL_ME_DEST, 2, 7), \
        \
        $(call NIC_ISL_ME_DEST, 3, 0), \
        $(call NIC_ISL_ME_DEST, 3, 1), \
        $(call NIC_ISL_ME_DEST, 3, 2), \
        $(call NIC_ISL_ME_DEST, 3, 3), \
        $(call NIC_ISL_ME_DEST, 3, 4), \
        $(call NIC_ISL_ME_DEST, 3, 5), \
        $(call NIC_ISL_ME_DEST, 3, 6), \
        $(call NIC_ISL_ME_DEST, 3, 7)"

# Add Global NFD config
$(eval $(call fwdep.add_nfd,basic_nic_h))
$(eval $(call micro_c.add_flags,basic_nic_h,nfd_svc,-DPLATFORM=$(PLATFORM)))
$(eval $(call fwdep.add_nfd_svc,basic_nic_h,apps/nic,app_master_main.c,ila0.me2,ila0.me3))
$(eval $(call micro_c.add_fw_lib,basic_nic_h,nfd_app_master,nic_basic))
$(eval $(call micro_c.add_fw_lib,basic_nic_h,nfd_app_master,link_state))
$(eval $(call micro_c.add_src_lib.abspath,basic_nic_h,nfd_app_master,$(NFD_DIR)/me/blocks/vnic/svc,msix))
$(eval $(call micro_c.add_flags,basic_nic_h,nfd_app_master,-DPLATFORM=$(PLATFORM)))
$(eval $(call micro_c.add_define,basic_nic_h,nfd_app_master,APP_MES_LIST=$(NIC_APP_MES)))

# Add NFD for PCIE0
$(eval $(call micro_c.add_flags,basic_nic_h,nfd_pcie0_issue0,-DPLATFORM=$(PLATFORM)))
$(eval $(call micro_c.add_flags,basic_nic_h,nfd_pcie0_issue1,-DPLATFORM=$(PLATFORM)))
$(eval $(call micro_c.add_flags,basic_nic_h,nfd_pcie0_gather,-DPLATFORM=$(PLATFORM)))
$(eval $(call micro_c.add_flags,basic_nic_h,nfd_pcie0_notify,-DPLATFORM=$(PLATFORM)))
$(eval $(call fwdep.add_nfd_in,basic_nic_h,0,mei4.me0)) # specify Notify ME
$(eval $(call micro_c.add_flags,basic_nic_h,nfd_pcie0_cache,-DPLATFORM=$(PLATFORM)))
$(eval $(call microcode.add_flags,basic_nic_h,nfd_pcie0_sb,-DPLATFORM=$(PLATFORM)))
$(eval $(call microcode.add_flags,basic_nic_h,nfd_pcie0_pd,-DPLATFORM=$(PLATFORM)))
$(eval $(call fwdep.add_nfd_out,basic_nic_h,0,mei4.me1,mei4.me2 mei4.me3)) # Stage batch, then packet DMA MEs

# Add a microcoengine named 'nic_rx' written in microC
# Make sure it gets linked with flownenv and GRO.
$(eval $(call micro_c.compile_liveinfo,basic_nic_h,nic_rx,apps/nic,nic_rx_main.c))
$(eval $(call micro_c.add_src_lib,basic_nic_h,nic_rx,apps/nic,pkt_hdrs_cache))
$(eval $(call micro_c.add_src_lib,basic_nic_h,nic_rx,apps/nic,rx_offload))
$(eval $(call micro_c.add_src_lib,basic_nic_h,nic_rx,apps/nic,tx_offload))
$(eval $(call fwdep.micro_c.add_flowenv_lib,basic_nic_h,nic_rx,pkt))
$(eval $(call fwdep.micro_c.add_flowenv_lib,basic_nic_h,nic_rx,std))
$(eval $(call fwdep.micro_c.add_flowenv_lib,basic_nic_h,nic_rx,net))
$(eval $(call fwdep.micro_c.add_flowenv_lib,basic_nic_h,nic_rx,lu))
$(eval $(call fwdep.micro_c.add_gro_lib,basic_nic_h,nic_rx))
$(eval $(call fwdep.micro_c.add_blm_lib,basic_nic_h,nic_rx))
$(eval $(call fwdep.micro_c.add_nfd_lib,basic_nic_h,nic_rx))
$(eval $(call micro_c.add_fw_lib,basic_nic_h,nic_rx,infra_basic))
$(eval $(call micro_c.add_fw_lib,basic_nic_h,nic_rx,nic_basic))
$(eval $(call micro_c.add_define,basic_nic_h,nic_rx,FWNAME='"nic"'))
$(eval $(call micro_c.add_flags,basic_nic_h,nic_rx,-Qnn_mode=1))
$(eval $(call micro_c.add_flags,basic_nic_h,nic_rx,-DPLATFORM=$(PLATFORM)))
$(eval $(call nffw.add_obj,basic_nic_h,nic_rx,\
	mei2.me0 mei2.me1 mei2.me2 mei2.me3 mei2.me4 mei2.me5  \
	mei2.me6 mei2.me7 \
	mei3.me0 mei3.me1 mei3.me2 mei3.me3 mei3.me4 mei3.me5  \
	mei3.me6 mei3.me7 \
	))

# Add a microcoengine named 'nic_tx' written in microC
# Make sure it gets linked with flownenv.
$(eval $(call micro_c.compile_liveinfo,basic_nic_h,nic_tx,apps/nic,nic_tx_main.c))
$(eval $(call micro_c.add_src_lib,basic_nic_h,nic_tx,apps/nic,pkt_hdrs_cache))
$(eval $(call micro_c.add_src_lib,basic_nic_h,nic_tx,apps/nic,tx_offload))
$(eval $(call fwdep.micro_c.add_flowenv_lib,basic_nic_h,nic_tx,pkt))
$(eval $(call fwdep.micro_c.add_flowenv_lib,basic_nic_h,nic_tx,std))
$(eval $(call fwdep.micro_c.add_flowenv_lib,basic_nic_h,nic_tx,net))
$(eval $(call fwdep.micro_c.add_flowenv_lib,basic_nic_h,nic_tx,lu))
$(eval $(call fwdep.micro_c.add_gro_lib,basic_nic_h,nic_tx))
$(eval $(call fwdep.micro_c.add_blm_lib,basic_nic_h,nic_tx))
$(eval $(call fwdep.micro_c.add_nfd_lib,basic_nic_h,nic_tx))
$(eval $(call micro_c.add_fw_lib,basic_nic_h,nic_tx,infra_basic))
$(eval $(call micro_c.add_fw_lib,basic_nic_h,nic_tx,nic_basic))
$(eval $(call micro_c.add_define,basic_nic_h,nic_tx,FWNAME='"nic"'))
$(eval $(call micro_c.add_flags,basic_nic_h,nic_tx,-Qnn_mode=1))
$(eval $(call micro_c.add_flags,basic_nic_h,nic_tx,-DPLATFORM=$(PLATFORM)))
$(eval $(call nffw.add_obj,basic_nic_h,nic_tx,\
	mei0.me0 mei0.me1 mei0.me2 mei0.me3 mei0.me4 mei0.me5  \
	mei0.me6 mei0.me7 \
	mei1.me0 mei1.me1 mei1.me2 mei1.me3 mei1.me4 mei1.me5  \
	mei1.me6 mei1.me7 \
	))

# Link
$(eval $(call nffw.add_rtsyms,basic_nic_h))
$(eval $(call nffw.link_w_analysis,basic_nic_h,nic_rx,nic_tx))
