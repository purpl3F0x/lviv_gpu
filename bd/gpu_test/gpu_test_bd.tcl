# Block design: gpu_top with its raster core on the ZCU104, the CPU driving it.
#
#   PS M_AXI_HPM0_FPD ──► sc_ctrl ──► gpu_0 s_axi_ctrl     (4 KiB at 0xA000_0000)
#   gpu_0 m_axi_vb, m_axi_tri, m_axi_tile ──► sc_mem ──► PS S_AXI_HP0_FPD (PS DDR)
#   gpu_0 m_axi_tex0..3 (the threads' texture caches) ──► sc_tex ──► PS S_AXI_HP1_FPD (PS DDR)
#   pl_clk0 100 MHz: everything, gpu_0's aclk, frontend_clk and thread_clk included (its clock
#                    crossings work with equal clocks too)
#   gpu_0 vis_dma_irq, tile_dma_irq ──► pl_ps_irq0[1:0]
#
# The triangles live in PS DDR for now: the GPU's triangle master (PL DDR in the full design) is
# just a third master on the memory SmartConnect. The texture caches reach the first 128 MiB of PS
# DDR (gpu_0's TEXTURE_WINDOW, 0); SmartConnect passes addresses on as they are.
#
# Sourced by scripts/vivado/bd_create.tcl into a project that already holds the RTL and the IP.
# `make export_bd` replaces this file with Vivado's own Tcl of the design as edited in the GUI.

set design_name gpu_test

# Latest version of a Xilinx catalog IP.
proc ip_vlnv {name} {
  set defs [get_ipdefs -all -filter "NAME == $name"]
  if {[llength $defs] == 0} { error "IP $name is not in the catalog" }
  return [lindex [lsort -dictionary $defs] end]
}

create_bd_design $design_name

#
# Processing system
#

set ps [create_bd_cell -type ip -vlnv [ip_vlnv zynq_ultra_ps_e] zynq_ultra_ps_e_0]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} $ps
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__MAXIGP0__DATA_WIDTH {32} \
    CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__USE__M_AXI_GP2 {0} \
    CONFIG.PSU__USE__S_AXI_GP2 {1} \
    CONFIG.PSU__SAXIGP2__DATA_WIDTH {128} \
    CONFIG.PSU__USE__S_AXI_GP3 {1} \
    CONFIG.PSU__SAXIGP3__DATA_WIDTH {128} \
    CONFIG.PSU__FPGA_PL0_ENABLE {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
    CONFIG.PSU__FPGA_PL1_ENABLE {0} \
    CONFIG.PSU__FPGA_PL2_ENABLE {0} \
    CONFIG.PSU__FPGA_PL3_ENABLE {0} \
    CONFIG.PSU__USE__IRQ0 {1}] $ps

#
# GPU
#

create_bd_cell -type module -reference gpu_top_bd gpu_0

#
# Reset
#

create_bd_cell -type ip -vlnv [ip_vlnv proc_sys_reset] rst_pl_clk0
connect_bd_net [get_bd_pins $ps/pl_resetn0] [get_bd_pins rst_pl_clk0/ext_reset_in]

#
# Interconnect
#

set sc_ctrl [create_bd_cell -type ip -vlnv [ip_vlnv smartconnect] sc_ctrl]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $sc_ctrl
connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_HPM0_FPD] [get_bd_intf_pins sc_ctrl/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_ctrl/M00_AXI] [get_bd_intf_pins gpu_0/s_axi_ctrl]

set sc_mem [create_bd_cell -type ip -vlnv [ip_vlnv smartconnect] sc_mem]
set_property -dict [list CONFIG.NUM_SI {3} CONFIG.NUM_MI {1}] $sc_mem
connect_bd_intf_net [get_bd_intf_pins gpu_0/m_axi_vb] [get_bd_intf_pins sc_mem/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins gpu_0/m_axi_tri] [get_bd_intf_pins sc_mem/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins gpu_0/m_axi_tile] [get_bd_intf_pins sc_mem/S02_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_mem/M00_AXI] [get_bd_intf_pins $ps/S_AXI_HP0_FPD]

set sc_tex [create_bd_cell -type ip -vlnv [ip_vlnv smartconnect] sc_tex]
set_property -dict [list CONFIG.NUM_SI {4} CONFIG.NUM_MI {1}] $sc_tex
for {set n 0} {$n < 4} {incr n} {
  connect_bd_intf_net [get_bd_intf_pins gpu_0/m_axi_tex$n] [get_bd_intf_pins sc_tex/S0${n}_AXI]
}
connect_bd_intf_net [get_bd_intf_pins sc_tex/M00_AXI] [get_bd_intf_pins $ps/S_AXI_HP1_FPD]

#
# Clocks and resets
#

connect_bd_net [get_bd_pins $ps/pl_clk0] [get_bd_pins gpu_0/aclk] \
    [get_bd_pins gpu_0/frontend_clk] [get_bd_pins gpu_0/thread_clk] \
    [get_bd_pins $ps/maxihpm0_fpd_aclk] [get_bd_pins $ps/saxihp0_fpd_aclk] \
    [get_bd_pins $ps/saxihp1_fpd_aclk] [get_bd_pins sc_ctrl/aclk] [get_bd_pins sc_mem/aclk] \
    [get_bd_pins sc_tex/aclk] [get_bd_pins rst_pl_clk0/slowest_sync_clk]

connect_bd_net [get_bd_pins rst_pl_clk0/peripheral_aresetn] [get_bd_pins gpu_0/aresetn] \
    [get_bd_pins gpu_0/frontend_rst_n] [get_bd_pins gpu_0/thread_rst_n] \
    [get_bd_pins sc_ctrl/aresetn] [get_bd_pins sc_mem/aresetn] [get_bd_pins sc_tex/aresetn]

#
# Interrupts
#

set irq [create_bd_cell -type ip -vlnv [ip_vlnv xlconcat] irq_concat]
set_property CONFIG.NUM_PORTS {2} $irq
connect_bd_net [get_bd_pins gpu_0/vis_dma_irq] [get_bd_pins irq_concat/In0]
connect_bd_net [get_bd_pins gpu_0/tile_dma_irq] [get_bd_pins irq_concat/In1]
connect_bd_net [get_bd_pins irq_concat/dout] [get_bd_pins $ps/pl_ps_irq0]

#
# Address map
#

assign_bd_address
set ctrl_seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces $ps/Data] -filter {NAME =~ *gpu_0*}]
set_property -dict [list offset 0xA0000000 range 4K] $ctrl_seg

validate_bd_design
save_bd_design
