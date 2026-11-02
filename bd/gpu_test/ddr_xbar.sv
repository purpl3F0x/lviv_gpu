// PL DDR4 interconnect: taxi's AXI crossbar (rtl/third_party/taxi), lean; ddr_xbar_bd.v puts it in
// the block design.
//
// s00 the triangle DMA, s01 the L2, s02 the CPU (HPM1: 128-bit, 40-bit addresses), m00 the DDR4
// controller, on one clock. The L2 is crossbar port 0, which wins ties (round robin). The CPU goes
// through taxi's width adapter, every burst re-packed to 512 bits (the controller takes no narrow
// bursts); it keeps the low 32 bits of its address. One R skid buffer at the controller, none per
// port unless S_R_SKID; no W one (the controller registers W).

`timescale 1ns / 1ps

module ddr_xbar #(
    parameter bit S_R_SKID = 1'b0
) (
    input logic aclk,
    input logic aresetn,

    // s00: the triangle DMA (read only)
    input  logic [ 31:0] s00_axi_araddr,
    input  logic [  3:0] s00_axi_arid,
    input  logic [  7:0] s00_axi_arlen,
    input  logic [  2:0] s00_axi_arsize,
    input  logic [  1:0] s00_axi_arburst,
    input  logic [  2:0] s00_axi_arprot,
    input  logic [  3:0] s00_axi_arcache,
    input  logic [  3:0] s00_axi_aruser,
    input  logic         s00_axi_arvalid,
    output logic         s00_axi_arready,
    output logic [  3:0] s00_axi_rid,
    output logic [511:0] s00_axi_rdata,
    output logic [  1:0] s00_axi_rresp,
    output logic         s00_axi_rlast,
    output logic         s00_axi_rvalid,
    input  logic         s00_axi_rready,

    // s01: the L2 (read only)
    input  logic [ 31:0] s01_axi_araddr,
    input  logic [  2:0] s01_axi_arid,
    input  logic [  7:0] s01_axi_arlen,
    input  logic [  2:0] s01_axi_arsize,
    input  logic [  1:0] s01_axi_arburst,
    input  logic         s01_axi_arvalid,
    output logic         s01_axi_arready,
    output logic [  2:0] s01_axi_rid,
    output logic [511:0] s01_axi_rdata,
    output logic [  1:0] s01_axi_rresp,
    output logic         s01_axi_rlast,
    output logic         s01_axi_rvalid,
    input  logic         s01_axi_rready,

    // s02: the CPU (HPM1)
    input  logic [ 15:0] s02_axi_awid,
    input  logic [ 39:0] s02_axi_awaddr,
    input  logic [  7:0] s02_axi_awlen,
    input  logic [  2:0] s02_axi_awsize,
    input  logic [  1:0] s02_axi_awburst,
    input  logic         s02_axi_awlock,
    input  logic [  3:0] s02_axi_awcache,
    input  logic [  2:0] s02_axi_awprot,
    input  logic [  3:0] s02_axi_awqos,
    input  logic [ 15:0] s02_axi_awuser,
    input  logic         s02_axi_awvalid,
    output logic         s02_axi_awready,
    input  logic [127:0] s02_axi_wdata,
    input  logic [ 15:0] s02_axi_wstrb,
    input  logic         s02_axi_wlast,
    input  logic         s02_axi_wvalid,
    output logic         s02_axi_wready,
    output logic [ 15:0] s02_axi_bid,
    output logic [  1:0] s02_axi_bresp,
    output logic         s02_axi_bvalid,
    input  logic         s02_axi_bready,
    input  logic [ 15:0] s02_axi_arid,
    input  logic [ 39:0] s02_axi_araddr,
    input  logic [  7:0] s02_axi_arlen,
    input  logic [  2:0] s02_axi_arsize,
    input  logic [  1:0] s02_axi_arburst,
    input  logic         s02_axi_arlock,
    input  logic [  3:0] s02_axi_arcache,
    input  logic [  2:0] s02_axi_arprot,
    input  logic [  3:0] s02_axi_arqos,
    input  logic [ 15:0] s02_axi_aruser,
    input  logic         s02_axi_arvalid,
    output logic         s02_axi_arready,
    output logic [ 15:0] s02_axi_rid,
    output logic [127:0] s02_axi_rdata,
    output logic [  1:0] s02_axi_rresp,
    output logic         s02_axi_rlast,
    output logic         s02_axi_rvalid,
    input  logic         s02_axi_rready,

    // m00: the DDR4 controller
    output logic [  5:0] m00_axi_awid,
    output logic [ 31:0] m00_axi_awaddr,
    output logic [  7:0] m00_axi_awlen,
    output logic [  2:0] m00_axi_awsize,
    output logic [  1:0] m00_axi_awburst,
    output logic         m00_axi_awlock,
    output logic [  3:0] m00_axi_awcache,
    output logic [  2:0] m00_axi_awprot,
    output logic [  3:0] m00_axi_awqos,
    output logic         m00_axi_awvalid,
    input  logic         m00_axi_awready,
    output logic [511:0] m00_axi_wdata,
    output logic [ 63:0] m00_axi_wstrb,
    output logic         m00_axi_wlast,
    output logic         m00_axi_wvalid,
    input  logic         m00_axi_wready,
    input  logic [  5:0] m00_axi_bid,
    input  logic [  1:0] m00_axi_bresp,
    input  logic         m00_axi_bvalid,
    output logic         m00_axi_bready,
    output logic [  5:0] m00_axi_arid,
    output logic [ 31:0] m00_axi_araddr,
    output logic [  7:0] m00_axi_arlen,
    output logic [  2:0] m00_axi_arsize,
    output logic [  1:0] m00_axi_arburst,
    output logic         m00_axi_arlock,
    output logic [  3:0] m00_axi_arcache,
    output logic [  2:0] m00_axi_arprot,
    output logic [  3:0] m00_axi_arqos,
    output logic         m00_axi_arvalid,
    input  logic         m00_axi_arready,
    input  logic [  5:0] m00_axi_rid,
    input  logic [511:0] m00_axi_rdata,
    input  logic [  1:0] m00_axi_rresp,
    input  logic         m00_axi_rlast,
    input  logic         m00_axi_rvalid,
    output logic         m00_axi_rready
);

  localparam int DataW = 512;
  localparam int AddrW = 32;
  localparam int SIdW = 4;
  localparam int MIdW = SIdW + 2;

  logic rst;
  assign rst = !aresetn;

  // Crossbar ports: 0 the L2, 1 the triangle DMA, 2 the CPU
  taxi_axi_if #(.DATA_W(DataW), .ADDR_W(AddrW), .ID_W(SIdW)) xbar_s[3] ();
  taxi_axi_if #(.DATA_W(DataW), .ADDR_W(AddrW), .ID_W(MIdW)) xbar_m[1] ();
  taxi_axi_if #(.DATA_W(128), .ADDR_W(AddrW), .ID_W(16)) cpu ();

  // The L2 and the triangle DMA only read
  for (genvar n = 0; n < 2; n++) begin : g_read_only
    assign xbar_s[n].awid     = '0;
    assign xbar_s[n].awaddr   = '0;
    assign xbar_s[n].awlen    = '0;
    assign xbar_s[n].awsize   = '0;
    assign xbar_s[n].awburst  = '0;
    assign xbar_s[n].awlock   = 1'b0;
    assign xbar_s[n].awcache  = '0;
    assign xbar_s[n].awprot   = '0;
    assign xbar_s[n].awqos    = '0;
    assign xbar_s[n].awregion = '0;
    assign xbar_s[n].awuser   = '0;
    assign xbar_s[n].awvalid  = 1'b0;
    assign xbar_s[n].wdata    = '0;
    assign xbar_s[n].wstrb    = '0;
    assign xbar_s[n].wlast    = 1'b0;
    assign xbar_s[n].wuser    = '0;
    assign xbar_s[n].wvalid   = 1'b0;
    assign xbar_s[n].bready   = 1'b1;
    assign xbar_s[n].arlock   = 1'b0;
    assign xbar_s[n].arqos    = '0;
    assign xbar_s[n].arregion = '0;
    assign xbar_s[n].aruser   = '0;
  end

  // L2
  assign xbar_s[0].arid    = SIdW'(s01_axi_arid);
  assign xbar_s[0].araddr  = s01_axi_araddr;
  assign xbar_s[0].arlen   = s01_axi_arlen;
  assign xbar_s[0].arsize  = s01_axi_arsize;
  assign xbar_s[0].arburst = s01_axi_arburst;
  assign xbar_s[0].arcache = 4'b0011;
  assign xbar_s[0].arprot  = 3'b000;
  assign xbar_s[0].arvalid = s01_axi_arvalid;
  assign s01_axi_arready   = xbar_s[0].arready;
  assign s01_axi_rid       = xbar_s[0].rid[2:0];
  assign s01_axi_rdata     = xbar_s[0].rdata;
  assign s01_axi_rresp     = xbar_s[0].rresp;
  assign s01_axi_rlast     = xbar_s[0].rlast;
  assign s01_axi_rvalid    = xbar_s[0].rvalid;
  assign xbar_s[0].rready  = s01_axi_rready;

  // Triangle DMA
  assign xbar_s[1].arid    = s00_axi_arid;
  assign xbar_s[1].araddr  = s00_axi_araddr;
  assign xbar_s[1].arlen   = s00_axi_arlen;
  assign xbar_s[1].arsize  = s00_axi_arsize;
  assign xbar_s[1].arburst = s00_axi_arburst;
  assign xbar_s[1].arcache = s00_axi_arcache;
  assign xbar_s[1].arprot  = s00_axi_arprot;
  assign xbar_s[1].arvalid = s00_axi_arvalid;
  assign s00_axi_arready   = xbar_s[1].arready;
  assign s00_axi_rid       = xbar_s[1].rid;
  assign s00_axi_rdata     = xbar_s[1].rdata;
  assign s00_axi_rresp     = xbar_s[1].rresp;
  assign s00_axi_rlast     = xbar_s[1].rlast;
  assign s00_axi_rvalid    = xbar_s[1].rvalid;
  assign xbar_s[1].rready  = s00_axi_rready;

  // CPU, 128 to 512 bits
  assign cpu.awid        = s02_axi_awid;
  assign cpu.awaddr      = s02_axi_awaddr[AddrW-1:0];
  assign cpu.awlen       = s02_axi_awlen;
  assign cpu.awsize      = s02_axi_awsize;
  assign cpu.awburst     = s02_axi_awburst;
  assign cpu.awlock      = s02_axi_awlock;
  assign cpu.awcache     = s02_axi_awcache;
  assign cpu.awprot      = s02_axi_awprot;
  assign cpu.awqos       = s02_axi_awqos;
  assign cpu.awregion    = '0;
  assign cpu.awuser      = '0;
  assign cpu.awvalid     = s02_axi_awvalid;
  assign s02_axi_awready = cpu.awready;
  assign cpu.wdata       = s02_axi_wdata;
  assign cpu.wstrb       = s02_axi_wstrb;
  assign cpu.wlast       = s02_axi_wlast;
  assign cpu.wuser       = '0;
  assign cpu.wvalid      = s02_axi_wvalid;
  assign s02_axi_wready  = cpu.wready;
  assign s02_axi_bid     = cpu.bid;
  assign s02_axi_bresp   = cpu.bresp;
  assign s02_axi_bvalid  = cpu.bvalid;
  assign cpu.bready      = s02_axi_bready;
  assign cpu.arid        = s02_axi_arid;
  assign cpu.araddr      = s02_axi_araddr[AddrW-1:0];
  assign cpu.arlen       = s02_axi_arlen;
  assign cpu.arsize      = s02_axi_arsize;
  assign cpu.arburst     = s02_axi_arburst;
  assign cpu.arlock      = s02_axi_arlock;
  assign cpu.arcache     = s02_axi_arcache;
  assign cpu.arprot      = s02_axi_arprot;
  assign cpu.arqos       = s02_axi_arqos;
  assign cpu.arregion    = '0;
  assign cpu.aruser      = '0;
  assign cpu.arvalid     = s02_axi_arvalid;
  assign s02_axi_arready = cpu.arready;
  assign s02_axi_rid     = cpu.rid;
  assign s02_axi_rdata   = cpu.rdata;
  assign s02_axi_rresp   = cpu.rresp;
  assign s02_axi_rlast   = cpu.rlast;
  assign s02_axi_rvalid  = cpu.rvalid;
  assign cpu.rready      = s02_axi_rready;

  taxi_axi_adapter #(
      .CONVERT_NARROW_BURST(1'b1)
  ) cpu_adapter (
      .clk     (aclk),
      .rst     (rst),
      .s_axi_wr(cpu),
      .s_axi_rd(cpu),
      .m_axi_wr(xbar_s[2]),
      .m_axi_rd(xbar_s[2])
  );

  // The L2: 8 threads, one per line in flight; the DMA and the adapter: one each
  taxi_axi_crossbar #(
      .S_COUNT     (3),
      .M_COUNT     (1),
      .ADDR_W      (AddrW),
      .S_THREADS   ({32'd1, 32'd1, 32'd8}),
      .S_ACCEPT    ({32'd2, 32'd2, 32'd8}),
      .M_ADDR_W    (32'd32),
      .M_ISSUE     (32'd16),
      .S_R_REG_TYPE(S_R_SKID ? {3{2'd2}} : {3{2'd0}}),
      .M_W_REG_TYPE(2'd0),
      .M_R_REG_TYPE(2'd2)
  ) xbar (
      .clk     (aclk),
      .rst     (rst),
      .s_axi_wr(xbar_s),
      .s_axi_rd(xbar_s),
      .m_axi_wr(xbar_m),
      .m_axi_rd(xbar_m)
  );

  // DDR4 controller
  assign m00_axi_awid      = xbar_m[0].awid;
  assign m00_axi_awaddr    = xbar_m[0].awaddr;
  assign m00_axi_awlen     = xbar_m[0].awlen;
  assign m00_axi_awsize    = xbar_m[0].awsize;
  assign m00_axi_awburst   = xbar_m[0].awburst;
  assign m00_axi_awlock    = xbar_m[0].awlock;
  assign m00_axi_awcache   = xbar_m[0].awcache;
  assign m00_axi_awprot    = xbar_m[0].awprot;
  assign m00_axi_awqos     = xbar_m[0].awqos;
  assign m00_axi_awvalid   = xbar_m[0].awvalid;
  assign xbar_m[0].awready = m00_axi_awready;
  assign m00_axi_wdata     = xbar_m[0].wdata;
  assign m00_axi_wstrb     = xbar_m[0].wstrb;
  assign m00_axi_wlast     = xbar_m[0].wlast;
  assign m00_axi_wvalid    = xbar_m[0].wvalid;
  assign xbar_m[0].wready  = m00_axi_wready;
  assign xbar_m[0].bid     = m00_axi_bid;
  assign xbar_m[0].bresp   = m00_axi_bresp;
  assign xbar_m[0].buser   = '0;
  assign xbar_m[0].bvalid  = m00_axi_bvalid;
  assign m00_axi_bready    = xbar_m[0].bready;
  assign m00_axi_arid      = xbar_m[0].arid;
  assign m00_axi_araddr    = xbar_m[0].araddr;
  assign m00_axi_arlen     = xbar_m[0].arlen;
  assign m00_axi_arsize    = xbar_m[0].arsize;
  assign m00_axi_arburst   = xbar_m[0].arburst;
  assign m00_axi_arlock    = xbar_m[0].arlock;
  assign m00_axi_arcache   = xbar_m[0].arcache;
  assign m00_axi_arprot    = xbar_m[0].arprot;
  assign m00_axi_arqos     = xbar_m[0].arqos;
  assign m00_axi_arvalid   = xbar_m[0].arvalid;
  assign xbar_m[0].arready = m00_axi_arready;
  assign xbar_m[0].rid     = m00_axi_rid;
  assign xbar_m[0].rdata   = m00_axi_rdata;
  assign xbar_m[0].rresp   = m00_axi_rresp;
  assign xbar_m[0].rlast   = m00_axi_rlast;
  assign xbar_m[0].ruser   = '0;
  assign xbar_m[0].rvalid  = m00_axi_rvalid;
  assign m00_axi_rready    = xbar_m[0].rready;

endmodule
