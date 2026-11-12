# Block design: gpu_top with its raster core on the ZCU104, the CPU driving it.
#
#   PS M_AXI_HPM0_FPD ──► ctrl_xbar ──► gpu_0 s_axi_ctrl   (4 KiB at 0xA000_0000)
#                                   ──► L2Cache_0 s_axil   (4 KiB at 0xA000_1000)
#   gpu_0 m_axi_vb (the visibility words)  ──► PS S_AXI_HP0_FPD (PS DDR)
#   gpu_0 m_axi_tile (the tile write-back) ──► PS S_AXI_HP1_FPD (PS DDR)
#   gpu_0 m_axi_tex0..3 (the threads' texture caches) ──► L2Cache_0 s_axi_0..3
#   gpu_0 m_axi_tri (512-bit, the triangle stream) ──► ddr_xbar s00 ──► ddr4_0 (PL DDR4, 4 GiB at 0)
#   L2Cache_0 m_axi (512-bit)                      ──► ddr_xbar s01 (port 0: wins ties)
#   PS M_AXI_HPM1_FPD (the CPU's DMA)              ──► ddr_xbar s02 (PL DDR4 at 0x5_0000_0000)
#   clk_300mhz (the board's differential 300 MHz) ──► ddr4_0 (its MMCM):
#     clk_100 100 MHz: gpu_0's lpd_clk (the control port, its APB registers, the command
#                      processor); the L2's axil_clk; HPM0, ctrl_xbar
#     clk_300 300 MHz (the DDR's UI clock): gpu_0's mem_clk (the DMAs, the frontend); the L2's
#                      mem_clk (its DDR master); HP0, HP1, HPM1, ddr_xbar
#     clk_500 500 MHz: gpu_0's core_clk (the orchestrator, the threads, their texture masters);
#                      the L2's core_clk (the cache)
#   gpu_0 vis_dma_irq, tile_dma_irq ──► pl_ps_irq0[1:0]
#
# No PS clock reaches the PL; the PS's pl_resetn0 (inverted) resets the DDR controller, and every
# clock's reset block waits for its calibration. ddr4_0 takes the board interfaces, which place
# the clock and memory pins, with the SODIMM's own part (ddr4_samsung_d_die.csv). The texture caches
# reach the first 128 MiB of PL DDR (gpu_0's TEXTURE_WINDOW, 0); the L2 and ddr_xbar pass
# addresses on as they are. ddr_xbar (ddr_xbar.sv: taxi's crossbar) arbitrates round robin, the L2
# winning ties; the DDR controller answers in order. Every crossing between the clocks in gpu_top
# and the L2 has its own synchroniser.
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
# The PS DDR4 at its parts' speed (MT40A256M16GE-083E, DDR4-2400) instead of the board preset's 2133P:
# Vivado's DDR preset, which also re-solves the clocks
set_property CONFIG.SUBPRESET1 {DDR4_MICRON_MT40A256M16GE_083E} $ps
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__MAXIGP0__DATA_WIDTH {32} \
    CONFIG.PSU__USE__M_AXI_GP1 {1} \
    CONFIG.PSU__MAXIGP1__DATA_WIDTH {128} \
    CONFIG.PSU__USE__M_AXI_GP2 {0} \
    CONFIG.PSU__USE__S_AXI_GP2 {1} \
    CONFIG.PSU__SAXIGP2__DATA_WIDTH {128} \
    CONFIG.PSU__USE__S_AXI_GP3 {1} \
    CONFIG.PSU__SAXIGP3__DATA_WIDTH {128} \
    CONFIG.PSU__USE__S_AXI_GP4 {0} \
    CONFIG.PSU__FPGA_PL0_ENABLE {0} \
    CONFIG.PSU__FPGA_PL1_ENABLE {0} \
    CONFIG.PSU__FPGA_PL2_ENABLE {0} \
    CONFIG.PSU__FPGA_PL3_ENABLE {0} \
    CONFIG.PSU__USE__IRQ0 {1}] $ps

#
# PL DDR4 and the clocks: the board's 300 MHz into the DDR controller, whose MMCM also makes
# 100 and 500 MHz (from its 1500 MHz VCO)
#

# The SODIMM's part first: the board interfaces then lock it (the board's preset, bd/boards, has the
# speed and input clock but no part); the extra clocks last, their choices following from those.
# DDR4-2666, past the SODIMM's 2400 limit for DIMMs: as its eight x8 components (CL19), with
# 3334 ps the input period nearest the board's 300 MHz
set ddr4 [create_bd_cell -type ip -vlnv [ip_vlnv ddr4] ddr4_0]
set sodimm [file join [file dirname [file normalize [info script]]] ddr4_samsung_d_die.csv]
set_property -dict [list \
    CONFIG.C0.DDR4_TimePeriod {750} \
    CONFIG.C0.DDR4_InputClockPeriod {3334} \
    CONFIG.C0.DDR4_MemoryType {Components} \
    CONFIG.C0.DDR4_DataWidth {64} \
    CONFIG.C0.DDR4_isCustom {true} \
    CONFIG.C0.DDR4_CustomParts $sodimm \
    CONFIG.C0.DDR4_MemoryPart {SAMSUNG_2666}] $ddr4
# Or DDR4-2400, its rated speed (CL17, a 300 MHz UI clock), with preset.xml's 2400 values:
# set_property -dict [list \
#     CONFIG.C0.DDR4_TimePeriod {833} \
#     CONFIG.C0.DDR4_InputClockPeriod {3331} \
#     CONFIG.C0.DDR4_MemoryType {Components} \
#     CONFIG.C0.DDR4_DataWidth {64} \
#     CONFIG.C0.DDR4_isCustom {true} \
#     CONFIG.C0.DDR4_CustomParts $sodimm \
#     CONFIG.C0.DDR4_MemoryPart {SAMSUNG_2400}] $ddr4
set_property -dict [list \
    CONFIG.C0_CLOCK_BOARD_INTERFACE {clk_300mhz} \
    CONFIG.C0_DDR4_BOARD_INTERFACE {ddr4_sdram} \
    CONFIG.RESET_BOARD_INTERFACE {Custom}] $ddr4
set_property -dict [list CONFIG.ADDN_UI_CLKOUT1_FREQ_HZ {100} CONFIG.ADDN_UI_CLKOUT2_FREQ_HZ {500}] $ddr4
# Its AXI port as ddr_xbar's m00: no narrow bursts, 6-bit IDs
set_property -dict [list \
    CONFIG.C0.DDR4_AxiNarrowBurst {false} \
    CONFIG.C0.DDR4_AxiIDWidth {6}] $ddr4
set clk_300mhz \
    [create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 clk_300mhz]
set_property CONFIG.FREQ_HZ 300000000 $clk_300mhz
connect_bd_intf_net $clk_300mhz [get_bd_intf_pins ddr4_0/C0_SYS_CLK]
set ddr4_sdram [create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 ddr4_sdram]
connect_bd_intf_net $ddr4_sdram [get_bd_intf_pins ddr4_0/C0_DDR4]
# Its reset is active high
set pl_reset [create_bd_cell -type ip -vlnv [ip_vlnv util_vector_logic] pl_reset]
set_property -dict [list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {1}] $pl_reset
connect_bd_net [get_bd_pins $ps/pl_resetn0] [get_bd_pins pl_reset/Op1]
connect_bd_net [get_bd_pins pl_reset/Res] [get_bd_pins ddr4_0/sys_rst]

#
# GPU
#

create_bd_cell -type module -reference gpu_top_bd gpu_0
create_bd_cell -type module -reference L2Cache L2Cache_0
create_bd_cell -type module -reference ddr_xbar_bd ddr_xbar
create_bd_cell -type module -reference ctrl_xbar_bd ctrl_xbar

#
# Resets, one per clock, held until the DDR is calibrated
#

foreach clk {100 333 500} {
  create_bd_cell -type ip -vlnv [ip_vlnv proc_sys_reset] rst_clk_$clk
  connect_bd_net [get_bd_pins ddr4_0/c0_ddr4_ui_clk_sync_rst] [get_bd_pins rst_clk_$clk/ext_reset_in]
}

#
# Interconnect
#

# The control ports through ctrl_xbar (ctrl_xbar.sv: taxi's AXI to AXI-Lite adapter and crossbar)
connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_HPM0_FPD] [get_bd_intf_pins ctrl_xbar/s00_axi]
connect_bd_intf_net [get_bd_intf_pins ctrl_xbar/m00_axi] [get_bd_intf_pins gpu_0/s_axi_ctrl]
connect_bd_intf_net [get_bd_intf_pins ctrl_xbar/m01_axil] [get_bd_intf_pins L2Cache_0/s_axil]

# The visibility DMA only reads and the tile DMA only writes: an HP port each, no interconnect
connect_bd_intf_net [get_bd_intf_pins gpu_0/m_axi_vb] [get_bd_intf_pins $ps/S_AXI_HP0_FPD]
connect_bd_intf_net [get_bd_intf_pins gpu_0/m_axi_tile] [get_bd_intf_pins $ps/S_AXI_HP1_FPD]

for {set n 0} {$n < 4} {incr n} {
  connect_bd_intf_net [get_bd_intf_pins gpu_0/m_axi_tex$n] [get_bd_intf_pins L2Cache_0/s_axi_$n]
}

# PL DDR4 through ddr_xbar: the L2 with 8 lines in flight, the triangle DMA 32 bursts, the CPU one
connect_bd_intf_net [get_bd_intf_pins gpu_0/m_axi_tri] [get_bd_intf_pins ddr_xbar/s00_axi]
connect_bd_intf_net [get_bd_intf_pins L2Cache_0/m_axi] [get_bd_intf_pins ddr_xbar/s01_axi]
connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_HPM1_FPD] [get_bd_intf_pins ddr_xbar/s02_axi]
connect_bd_intf_net [get_bd_intf_pins ddr_xbar/m00_axi] [get_bd_intf_pins ddr4_0/C0_DDR4_S_AXI]

#
# Clock and reset nets
#

# The nets keep these names: gpu_test.xdc finds the clocks by them

# clk_100: lpd_clk, the control port; the L2's register port
connect_bd_net -net clk_100 [get_bd_pins ddr4_0/addn_ui_clkout1] [get_bd_pins gpu_0/lpd_clk] \
    [get_bd_pins L2Cache_0/axil_clk] [get_bd_pins $ps/maxihpm0_fpd_aclk] [get_bd_pins ctrl_xbar/aclk] \
    [get_bd_pins rst_clk_100/slowest_sync_clk]
connect_bd_net [get_bd_pins rst_clk_100/peripheral_aresetn] [get_bd_pins gpu_0/lpd_rst_n] \
    [get_bd_pins L2Cache_0/axil_resetn] [get_bd_pins ctrl_xbar/aresetn]

# clk_333: mem_clk (the DMAs, the frontend), the L2's DDR master, HP0, HP1, HPM1, ddr_xbar
# and the DDR controller's AXI port
connect_bd_net -net clk_333 [get_bd_pins ddr4_0/c0_ddr4_ui_clk] [get_bd_pins gpu_0/mem_clk] \
    [get_bd_pins L2Cache_0/mem_clk] [get_bd_pins $ps/saxihp0_fpd_aclk] \
    [get_bd_pins $ps/saxihp1_fpd_aclk] [get_bd_pins $ps/maxihpm1_fpd_aclk] \
    [get_bd_pins ddr_xbar/aclk] [get_bd_pins rst_clk_333/slowest_sync_clk]
connect_bd_net [get_bd_pins rst_clk_333/peripheral_aresetn] [get_bd_pins gpu_0/mem_rst_n] \
    [get_bd_pins L2Cache_0/mem_resetn] [get_bd_pins ddr_xbar/aresetn] \
    [get_bd_pins ddr4_0/c0_ddr4_aresetn]

# clk_300: mem_clk (the DMAs, the frontend), the L2's DDR master, HP0, HP1, HPM1, ddr_xbar
# and the DDR controller's AXI port
# connect_bd_net -net clk_300 [get_bd_pins ddr4_0/c0_ddr4_ui_clk] [get_bd_pins gpu_0/mem_clk] \
#     [get_bd_pins L2Cache_0/mem_clk] [get_bd_pins $ps/saxihp0_fpd_aclk] \
#     [get_bd_pins $ps/saxihp1_fpd_aclk] [get_bd_pins $ps/maxihpm1_fpd_aclk] \
#     [get_bd_pins ddr_xbar/aclk] [get_bd_pins rst_clk_300/slowest_sync_clk]
# connect_bd_net [get_bd_pins rst_clk_300/peripheral_aresetn] [get_bd_pins gpu_0/mem_rst_n] \
#     [get_bd_pins L2Cache_0/mem_resetn] [get_bd_pins ddr_xbar/aresetn] \
#     [get_bd_pins ddr4_0/c0_ddr4_aresetn]

# clk_500: core_clk (the orchestrator, the threads), the L2
connect_bd_net -net clk_500 [get_bd_pins ddr4_0/addn_ui_clkout2] [get_bd_pins gpu_0/core_clk] \
    [get_bd_pins L2Cache_0/core_clk] [get_bd_pins rst_clk_500/slowest_sync_clk]
connect_bd_net [get_bd_pins rst_clk_500/peripheral_aresetn] [get_bd_pins gpu_0/core_rst_n] \
    [get_bd_pins L2Cache_0/core_resetn]

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

# The control window first, at a fixed address (gpu_0's 4 KiB, then the L2's); then the rest: PL
# DDR at 0 for the GPU's masters, in HPM1's 4 GiB window for the CPU (one pass: the CPU's address
# first would leave the 32-bit masters none); gpu_0's PS DDR masters without the OCM and QSPI. IP
# integrator cannot see through ctrl_xbar and ddr_xbar: the masters get their slave ports' own
# windows, the slaves their master ports'.
set data [get_bd_addr_spaces $ps/Data]
assign_bd_address -target_address_space $data -offset 0xA0000000 -range 8K \
    [get_bd_addr_segs ctrl_xbar/s00_axi/*]
assign_bd_address
set pl_ddr [get_bd_addr_segs $ps/Data/SEG_ddr_xbar_reg0]
set_property range 4G $pl_ddr
set_property offset 0x500000000 $pl_ddr
foreach {master hp} {m_axi_vb HP0 m_axi_tile HP1} {
  foreach seg {LPS_OCM QSPI} {
    exclude_bd_addr_seg [get_bd_addr_segs gpu_0/$master/SEG_zynq_ultra_ps_e_0_${hp}_$seg]
  }
}

validate_bd_design
save_bd_design
