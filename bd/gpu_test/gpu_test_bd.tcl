# Block design: gpu_top with its raster core on the ZCU104, the CPU driving it.
#
#   PS M_AXI_HPM0_FPD ──► sc_ctrl ──► gpu_0 s_axi_ctrl     (4 KiB at 0xA000_0000)
#   gpu_0 m_axi_vb, m_axi_tile ──► sc_mem ──► PS S_AXI_HP0_FPD (PS DDR)
#   gpu_0 m_axi_tri (512-bit, the triangle stream) ──► sc_tri ──► PS S_AXI_HP2_FPD (PS DDR)
#   gpu_0 m_axi_tex0..3 (the threads' texture caches) ──► sc_tex ──► PS S_AXI_HP1_FPD (PS DDR)
#   clk_300mhz (the board's differential 300 MHz) ──► clk_wiz:
#     clk_100 100 MHz: gpu_0's lpd_clk (the control port, its APB registers, the command
#                      processor); HPM0, sc_ctrl
#     clk_300 300 MHz: gpu_0's mem_clk (the DMAs, the frontend); HP0..2, sc_mem, sc_tri, sc_tex's
#                      side to HP1
#     clk_500 500 MHz: gpu_0's core_clk (the orchestrator, the threads, their texture masters);
#                      sc_tex's side from them
#   gpu_0 vis_dma_irq, tile_dma_irq ──► pl_ps_irq0[1:0]
#
# No PS clock reaches the PL; the PS's pl_resetn0 resets the clocking wizard and, with its lock,
# every clock's reset block. The clocking wizard takes the board interface, which places the clock
# pins. The triangles live in PS DDR for now (PL DDR in the full design), through a port of their
# own. The texture caches reach the first 128 MiB of PS DDR (gpu_0's TEXTURE_WINDOW, 0);
# SmartConnect passes addresses on as they are. Every crossing between the clocks in gpu_top has its
# own synchroniser, and sc_tex converts between clk_500 and clk_300.
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
    CONFIG.PSU__USE__S_AXI_GP4 {1} \
    CONFIG.PSU__SAXIGP4__DATA_WIDTH {128} \
    CONFIG.PSU__FPGA_PL0_ENABLE {0} \
    CONFIG.PSU__FPGA_PL1_ENABLE {0} \
    CONFIG.PSU__FPGA_PL2_ENABLE {0} \
    CONFIG.PSU__FPGA_PL3_ENABLE {0} \
    CONFIG.PSU__USE__IRQ0 {1}] $ps

#
# Clocks: the board's 300 MHz into a clocking wizard
#

set clk_wiz [create_bd_cell -type ip -vlnv [ip_vlnv clk_wiz] clk_wiz]
set_property -dict [list \
    CONFIG.CLK_IN1_BOARD_INTERFACE {clk_300mhz} \
    CONFIG.PRIM_SOURCE {Differential_clock_capable_pin} \
    CONFIG.PRIM_IN_FREQ {300.000} \
    CONFIG.PRIMITIVE {Auto} \
    CONFIG.NUM_OUT_CLKS {3} \
    CONFIG.CLK_OUT1_PORT {clk_100} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {100.000} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLK_OUT2_PORT {clk_300} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {300.000} \
    CONFIG.CLKOUT3_USED {true} \
    CONFIG.CLK_OUT3_PORT {clk_500} \
    CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {500.000} \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_RESET {true} \
    CONFIG.RESET_TYPE {ACTIVE_LOW} \
    CONFIG.RESET_PORT {resetn}] $clk_wiz
set clk_300mhz \
    [create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 clk_300mhz]
set_property CONFIG.FREQ_HZ 300000000 $clk_300mhz
connect_bd_intf_net $clk_300mhz [get_bd_intf_pins clk_wiz/CLK_IN1_D]
connect_bd_net [get_bd_pins $ps/pl_resetn0] [get_bd_pins clk_wiz/resetn]

#
# GPU
#

create_bd_cell -type module -reference gpu_top_bd gpu_0

#
# Resets, one per clock, held until the clocking wizard locks
#

foreach clk {100 300 500} {
  create_bd_cell -type ip -vlnv [ip_vlnv proc_sys_reset] rst_clk_$clk
  connect_bd_net [get_bd_pins $ps/pl_resetn0] [get_bd_pins rst_clk_$clk/ext_reset_in]
  connect_bd_net [get_bd_pins clk_wiz/locked] [get_bd_pins rst_clk_$clk/dcm_locked]
}

#
# Interconnect
#

set sc_ctrl [create_bd_cell -type ip -vlnv [ip_vlnv smartconnect] sc_ctrl]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $sc_ctrl
connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_HPM0_FPD] [get_bd_intf_pins sc_ctrl/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_ctrl/M00_AXI] [get_bd_intf_pins gpu_0/s_axi_ctrl]

set sc_mem [create_bd_cell -type ip -vlnv [ip_vlnv smartconnect] sc_mem]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] $sc_mem
connect_bd_intf_net [get_bd_intf_pins gpu_0/m_axi_vb] [get_bd_intf_pins sc_mem/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins gpu_0/m_axi_tile] [get_bd_intf_pins sc_mem/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_mem/M00_AXI] [get_bd_intf_pins $ps/S_AXI_HP0_FPD]

set sc_tri [create_bd_cell -type ip -vlnv [ip_vlnv smartconnect] sc_tri]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $sc_tri
connect_bd_intf_net [get_bd_intf_pins gpu_0/m_axi_tri] [get_bd_intf_pins sc_tri/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_tri/M00_AXI] [get_bd_intf_pins $ps/S_AXI_HP2_FPD]

set sc_tex [create_bd_cell -type ip -vlnv [ip_vlnv smartconnect] sc_tex]
set_property -dict [list CONFIG.NUM_SI {4} CONFIG.NUM_MI {1} CONFIG.NUM_CLKS {2}] $sc_tex
for {set n 0} {$n < 4} {incr n} {
  connect_bd_intf_net [get_bd_intf_pins gpu_0/m_axi_tex$n] [get_bd_intf_pins sc_tex/S0${n}_AXI]
}
connect_bd_intf_net [get_bd_intf_pins sc_tex/M00_AXI] [get_bd_intf_pins $ps/S_AXI_HP1_FPD]

#
# Clock and reset nets
#

# clk_100: lpd_clk, the control port
connect_bd_net [get_bd_pins clk_wiz/clk_100] [get_bd_pins gpu_0/lpd_clk] \
    [get_bd_pins $ps/maxihpm0_fpd_aclk] [get_bd_pins sc_ctrl/aclk] \
    [get_bd_pins rst_clk_100/slowest_sync_clk]
connect_bd_net [get_bd_pins rst_clk_100/peripheral_aresetn] [get_bd_pins gpu_0/lpd_rst_n] \
    [get_bd_pins sc_ctrl/aresetn]

# clk_300: mem_clk (the DMAs, the frontend), the HP ports and their SmartConnects (sc_tex's side to
# HP1)
connect_bd_net [get_bd_pins clk_wiz/clk_300] [get_bd_pins gpu_0/mem_clk] \
    [get_bd_pins $ps/saxihp0_fpd_aclk] [get_bd_pins $ps/saxihp1_fpd_aclk] \
    [get_bd_pins $ps/saxihp2_fpd_aclk] [get_bd_pins sc_mem/aclk] [get_bd_pins sc_tri/aclk] \
    [get_bd_pins sc_tex/aclk] [get_bd_pins rst_clk_300/slowest_sync_clk]
connect_bd_net [get_bd_pins rst_clk_300/peripheral_aresetn] [get_bd_pins gpu_0/mem_rst_n] \
    [get_bd_pins sc_mem/aresetn] [get_bd_pins sc_tri/aresetn] [get_bd_pins sc_tex/aresetn]

# clk_500: core_clk (the orchestrator, the threads), and sc_tex's side from their texture masters
connect_bd_net [get_bd_pins clk_wiz/clk_500] [get_bd_pins gpu_0/core_clk] \
    [get_bd_pins sc_tex/aclk1] [get_bd_pins rst_clk_500/slowest_sync_clk]
connect_bd_net [get_bd_pins rst_clk_500/peripheral_aresetn] [get_bd_pins gpu_0/core_rst_n]

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
