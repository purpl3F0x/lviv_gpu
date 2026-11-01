# Block design: gpu_top with its raster core on the ZCU104, the CPU driving it.
#
#   PS M_AXI_HPM0_FPD ──► sc_ctrl ──► gpu_0 s_axi_ctrl     (4 KiB at 0xA000_0000)
#                                 ──► L2Cache_0 s_axil     (4 KiB at 0xA000_1000)
#   gpu_0 m_axi_vb, m_axi_tile ──► sc_mem ──► PS S_AXI_HP0_FPD (PS DDR)
#   gpu_0 m_axi_tex0..3 (the threads' texture caches) ──► L2Cache_0 s_axi_0..3
#   gpu_0 m_axi_tri (512-bit, the triangle stream) ──► sc_ddr S00 ──► ddr4_0 (PL DDR4, 4 GiB at 0)
#   L2Cache_0 m_axi (512-bit)                      ──► sc_ddr S01 (first)
#   PS M_AXI_HPM1_FPD (the CPU's DMA)              ──► sc_ddr S02 (PL DDR4 at 0x5_0000_0000)
#   clk_300mhz (the board's differential 300 MHz) ──► ddr4_0 (its MMCM):
#     clk_100 100 MHz: gpu_0's lpd_clk (the control port, its APB registers, the command
#                      processor); the L2's axil_clk; HPM0, sc_ctrl
#     clk_300 300 MHz (the DDR's UI clock): gpu_0's mem_clk (the DMAs, the frontend); the L2's
#                      mem_clk (its DDR master); HP0, HPM1, sc_mem, sc_ddr
#     clk_500 500 MHz: gpu_0's core_clk (the orchestrator, the threads, their texture masters);
#                      the L2's core_clk (the cache)
#   gpu_0 vis_dma_irq, tile_dma_irq ──► pl_ps_irq0[1:0]
#
# No PS clock reaches the PL; the PS's pl_resetn0 (inverted) resets the DDR controller, and every
# clock's reset block waits for its calibration. ddr4_0 takes the board interfaces, which place
# the clock and memory pins, with the SODIMM's own part (ddr4_2400_samy.csv). The texture caches
# reach the first 128 MiB of PL DDR (gpu_0's TEXTURE_WINDOW, 0); the L2 and SmartConnect pass
# addresses on as they are. sc_ddr serves the L2 first (its misses stall the threads), then the
# rest round robin, with AXI IDs on to the DDR controller, which may answer them out of order.
# Every crossing between the clocks in gpu_top and the L2 has its own synchroniser.
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
    CONFIG.PSU__USE__M_AXI_GP1 {1} \
    CONFIG.PSU__MAXIGP1__DATA_WIDTH {128} \
    CONFIG.PSU__USE__M_AXI_GP2 {0} \
    CONFIG.PSU__USE__S_AXI_GP2 {1} \
    CONFIG.PSU__SAXIGP2__DATA_WIDTH {128} \
    CONFIG.PSU__USE__S_AXI_GP3 {0} \
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
# speed and input clock but no part); the extra clocks last, their choices following from those
set ddr4 [create_bd_cell -type ip -vlnv [ip_vlnv ddr4] ddr4_0]
set sodimm [file join [file dirname [file normalize [info script]]] ddr4_2400_samy.csv]
set_property -dict [list \
    CONFIG.C0.DDR4_TimePeriod {833} \
    CONFIG.C0.DDR4_InputClockPeriod {3331} \
    CONFIG.C0.DDR4_MemoryType {SODIMMs} \
    CONFIG.C0.DDR4_isCustom {true} \
    CONFIG.C0.DDR4_CustomParts $sodimm \
    CONFIG.C0.DDR4_MemoryPart {SAMY2400}] $ddr4
set_property -dict [list \
    CONFIG.C0_CLOCK_BOARD_INTERFACE {clk_300mhz} \
    CONFIG.C0_DDR4_BOARD_INTERFACE {ddr4_sdram} \
    CONFIG.RESET_BOARD_INTERFACE {Custom}] $ddr4
set_property -dict [list CONFIG.ADDN_UI_CLKOUT1_FREQ_HZ {100} CONFIG.ADDN_UI_CLKOUT2_FREQ_HZ {500}] $ddr4
# Its AXI port's narrow bursts as sc_ddr has them; its ID width that of sc_ddr's 8 threads (when
# propagated, it is taken before sc_ddr widens its port)
set_property -dict [list \
    CONFIG.C0.DDR4_AxiNarrowBurst.VALUE_SRC PROPAGATED \
    CONFIG.C0.DDR4_AxiIDWidth {3}] $ddr4
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

#
# Resets, one per clock, held until the DDR is calibrated
#

foreach clk {100 300 500} {
  create_bd_cell -type ip -vlnv [ip_vlnv proc_sys_reset] rst_clk_$clk
  connect_bd_net [get_bd_pins ddr4_0/c0_ddr4_ui_clk_sync_rst] [get_bd_pins rst_clk_$clk/ext_reset_in]
}

#
# Interconnect
#

set sc_ctrl [create_bd_cell -type ip -vlnv [ip_vlnv smartconnect] sc_ctrl]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] $sc_ctrl
connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_HPM0_FPD] [get_bd_intf_pins sc_ctrl/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_ctrl/M00_AXI] [get_bd_intf_pins gpu_0/s_axi_ctrl]
connect_bd_intf_net [get_bd_intf_pins sc_ctrl/M01_AXI] [get_bd_intf_pins L2Cache_0/s_axil]

set sc_mem [create_bd_cell -type ip -vlnv [ip_vlnv smartconnect] sc_mem]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] $sc_mem
connect_bd_intf_net [get_bd_intf_pins gpu_0/m_axi_vb] [get_bd_intf_pins sc_mem/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins gpu_0/m_axi_tile] [get_bd_intf_pins sc_mem/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_mem/M00_AXI] [get_bd_intf_pins $ps/S_AXI_HP0_FPD]

for {set n 0} {$n < 4} {incr n} {
  connect_bd_intf_net [get_bd_intf_pins gpu_0/m_axi_tex$n] [get_bd_intf_pins L2Cache_0/s_axi_$n]
}

# PL DDR4: the L2 (S01) before the others (PG247's non-GUI advanced properties); AXI IDs on M00,
# for the controller to reorder. 8 read threads (left to itself SmartConnect makes 2): the L1s ask
# one block each, but a line (4 blocks) can still be arriving after its block went out and the L1
# missed again, so the L2 has up to 8 lines in flight (4 at most on Lilith), and the triangle DMA
# needs one too; with 4, it would wait behind the L2's lines (the CPU only writes: other threads)
set sc_ddr [create_bd_cell -type ip -vlnv [ip_vlnv smartconnect] sc_ddr]
set_property -dict [list CONFIG.NUM_SI {3} CONFIG.NUM_MI {1}] $sc_ddr
set_property CONFIG.ADVANCED_PROPERTIES [list \
    __experimental_features__ {enable_multithreaded_mi 1} \
    __view__ {functional {S01_Entry {PRIORITY_ARB 1} M00_Exit {NUM_READ_THREADS 8}}}] $sc_ddr
connect_bd_intf_net [get_bd_intf_pins gpu_0/m_axi_tri] [get_bd_intf_pins sc_ddr/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins L2Cache_0/m_axi] [get_bd_intf_pins sc_ddr/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_HPM1_FPD] [get_bd_intf_pins sc_ddr/S02_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_ddr/M00_AXI] [get_bd_intf_pins ddr4_0/C0_DDR4_S_AXI]

#
# Clock and reset nets
#

# The nets keep these names: gpu_test.xdc finds the clocks by them

# clk_100: lpd_clk, the control port; the L2's register port
connect_bd_net -net clk_100 [get_bd_pins ddr4_0/addn_ui_clkout1] [get_bd_pins gpu_0/lpd_clk] \
    [get_bd_pins L2Cache_0/axil_clk] [get_bd_pins $ps/maxihpm0_fpd_aclk] [get_bd_pins sc_ctrl/aclk] \
    [get_bd_pins rst_clk_100/slowest_sync_clk]
connect_bd_net [get_bd_pins rst_clk_100/peripheral_aresetn] [get_bd_pins gpu_0/lpd_rst_n] \
    [get_bd_pins L2Cache_0/axil_resetn] [get_bd_pins sc_ctrl/aresetn]

# clk_300: mem_clk (the DMAs, the frontend), the L2's DDR master, HP0, HPM1, their SmartConnects
# and the DDR controller's AXI port
connect_bd_net -net clk_300 [get_bd_pins ddr4_0/c0_ddr4_ui_clk] [get_bd_pins gpu_0/mem_clk] \
    [get_bd_pins L2Cache_0/mem_clk] [get_bd_pins $ps/saxihp0_fpd_aclk] \
    [get_bd_pins $ps/maxihpm1_fpd_aclk] [get_bd_pins sc_mem/aclk] [get_bd_pins sc_ddr/aclk] \
    [get_bd_pins rst_clk_300/slowest_sync_clk]
connect_bd_net [get_bd_pins rst_clk_300/peripheral_aresetn] [get_bd_pins gpu_0/mem_rst_n] \
    [get_bd_pins L2Cache_0/mem_resetn] [get_bd_pins sc_mem/aresetn] [get_bd_pins sc_ddr/aresetn] \
    [get_bd_pins ddr4_0/c0_ddr4_aresetn]

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

# The two control ports first, at fixed addresses; then the rest: PL DDR at 0 for the GPU's
# masters, in HPM1's 4 GiB window for the CPU (one pass: the CPU's address first would leave the
# 32-bit masters none); gpu_0's PS DDR masters without the OCM and QSPI
set data [get_bd_addr_spaces $ps/Data]
assign_bd_address -target_address_space $data -offset 0xA0000000 -range 4K \
    [get_bd_addr_segs gpu_0/s_axi_ctrl/*]
assign_bd_address -target_address_space $data -offset 0xA0001000 -range 4K \
    [get_bd_addr_segs L2Cache_0/s_axil/*]
assign_bd_address
set_property offset 0x500000000 [get_bd_addr_segs $ps/Data/SEG_ddr4_0_C0_DDR4_ADDRESS_BLOCK]
foreach master {m_axi_vb m_axi_tile} {
  foreach seg {HP0_LPS_OCM HP0_QSPI} {
    exclude_bd_addr_seg [get_bd_addr_segs gpu_0/$master/SEG_zynq_ultra_ps_e_0_$seg]
  }
}

validate_bd_design
save_bd_design
