// Control interconnect: taxi's AXI to AXI-Lite adapter and AXI-Lite crossbar (rtl/third_party/taxi);
// ctrl_xbar_bd.v puts it in the block design.
// Copyright (c) 2026 Stavros Avramidis
//
// s00 the CPU (HPM0: AXI4, 32-bit data, 16-bit IDs), m00 gpu_0's control port (AXI4, driven as
// AXI-Lite: single beats, ID 0), m01 the L2's registers; 4 KiB each, from the low 13 address bits.
// taxi's default register slices.

`timescale 1ns / 1ps

module ctrl_xbar (
    input logic aclk,
    input logic aresetn,

    input  logic [15:0] s00_axi_awid,
    input  logic [39:0] s00_axi_awaddr,
    input  logic [ 7:0] s00_axi_awlen,
    input  logic [ 2:0] s00_axi_awsize,
    input  logic [ 1:0] s00_axi_awburst,
    input  logic        s00_axi_awlock,
    input  logic [ 3:0] s00_axi_awcache,
    input  logic [ 2:0] s00_axi_awprot,
    input  logic [ 3:0] s00_axi_awqos,
    input  logic [15:0] s00_axi_awuser,
    input  logic        s00_axi_awvalid,
    output logic        s00_axi_awready,
    input  logic [31:0] s00_axi_wdata,
    input  logic [ 3:0] s00_axi_wstrb,
    input  logic        s00_axi_wlast,
    input  logic        s00_axi_wvalid,
    output logic        s00_axi_wready,
    output logic [15:0] s00_axi_bid,
    output logic [ 1:0] s00_axi_bresp,
    output logic        s00_axi_bvalid,
    input  logic        s00_axi_bready,
    input  logic [15:0] s00_axi_arid,
    input  logic [39:0] s00_axi_araddr,
    input  logic [ 7:0] s00_axi_arlen,
    input  logic [ 2:0] s00_axi_arsize,
    input  logic [ 1:0] s00_axi_arburst,
    input  logic        s00_axi_arlock,
    input  logic [ 3:0] s00_axi_arcache,
    input  logic [ 2:0] s00_axi_arprot,
    input  logic [ 3:0] s00_axi_arqos,
    input  logic [15:0] s00_axi_aruser,
    input  logic        s00_axi_arvalid,
    output logic        s00_axi_arready,
    output logic [15:0] s00_axi_rid,
    output logic [31:0] s00_axi_rdata,
    output logic [ 1:0] s00_axi_rresp,
    output logic        s00_axi_rlast,
    output logic        s00_axi_rvalid,
    input  logic        s00_axi_rready,

    // gpu_0 s_axi_ctrl
    output logic [11:0] m00_axi_awaddr,
    output logic [ 3:0] m00_axi_awid,
    output logic [ 7:0] m00_axi_awlen,
    output logic [ 2:0] m00_axi_awsize,
    output logic [ 1:0] m00_axi_awburst,
    output logic        m00_axi_awvalid,
    input  logic        m00_axi_awready,
    output logic [31:0] m00_axi_wdata,
    output logic [ 3:0] m00_axi_wstrb,
    output logic        m00_axi_wlast,
    output logic        m00_axi_wvalid,
    input  logic        m00_axi_wready,
    input  logic [ 3:0] m00_axi_bid,
    input  logic [ 1:0] m00_axi_bresp,
    input  logic        m00_axi_bvalid,
    output logic        m00_axi_bready,
    output logic [11:0] m00_axi_araddr,
    output logic [ 3:0] m00_axi_arid,
    output logic [ 7:0] m00_axi_arlen,
    output logic [ 2:0] m00_axi_arsize,
    output logic [ 1:0] m00_axi_arburst,
    output logic        m00_axi_arvalid,
    input  logic        m00_axi_arready,
    input  logic [31:0] m00_axi_rdata,
    input  logic [ 3:0] m00_axi_rid,
    input  logic [ 1:0] m00_axi_rresp,
    input  logic        m00_axi_rlast,
    input  logic        m00_axi_rvalid,
    output logic        m00_axi_rready,

    // L2Cache_0 s_axil
    output logic [ 7:0] m01_axil_awaddr,
    output logic [ 2:0] m01_axil_awprot,
    output logic        m01_axil_awvalid,
    input  logic        m01_axil_awready,
    output logic [31:0] m01_axil_wdata,
    output logic [ 3:0] m01_axil_wstrb,
    output logic        m01_axil_wvalid,
    input  logic        m01_axil_wready,
    input  logic [ 1:0] m01_axil_bresp,
    input  logic        m01_axil_bvalid,
    output logic        m01_axil_bready,
    output logic [ 7:0] m01_axil_araddr,
    output logic [ 2:0] m01_axil_arprot,
    output logic        m01_axil_arvalid,
    input  logic        m01_axil_arready,
    input  logic [31:0] m01_axil_rdata,
    input  logic [ 1:0] m01_axil_rresp,
    input  logic        m01_axil_rvalid,
    output logic        m01_axil_rready
);

  localparam int AddrW = 13;

  logic rst;
  assign rst = !aresetn;

  taxi_axi_if #(.DATA_W(32), .ADDR_W(AddrW), .ID_W(16)) s ();
  taxi_axil_if #(.DATA_W(32), .ADDR_W(AddrW)) sl ();
  taxi_axil_if #(.DATA_W(32), .ADDR_W(AddrW)) ml[2] ();

  assign s.awid = s00_axi_awid;
  assign s.awaddr = s00_axi_awaddr[AddrW-1:0];
  assign s.awlen = s00_axi_awlen;
  assign s.awsize = s00_axi_awsize;
  assign s.awburst = s00_axi_awburst;
  assign s.awlock = s00_axi_awlock;
  assign s.awcache = s00_axi_awcache;
  assign s.awprot = s00_axi_awprot;
  assign s.awqos = s00_axi_awqos;
  assign s.awregion = '0;
  assign s.awuser = '0;
  assign s.awvalid = s00_axi_awvalid;
  assign s00_axi_awready = s.awready;
  assign s.wdata = s00_axi_wdata;
  assign s.wstrb = s00_axi_wstrb;
  assign s.wlast = s00_axi_wlast;
  assign s.wuser = '0;
  assign s.wvalid = s00_axi_wvalid;
  assign s00_axi_wready = s.wready;
  assign s00_axi_bid = s.bid;
  assign s00_axi_bresp = s.bresp;
  assign s00_axi_bvalid = s.bvalid;
  assign s.bready = s00_axi_bready;
  assign s.arid = s00_axi_arid;
  assign s.araddr = s00_axi_araddr[AddrW-1:0];
  assign s.arlen = s00_axi_arlen;
  assign s.arsize = s00_axi_arsize;
  assign s.arburst = s00_axi_arburst;
  assign s.arlock = s00_axi_arlock;
  assign s.arcache = s00_axi_arcache;
  assign s.arprot = s00_axi_arprot;
  assign s.arqos = s00_axi_arqos;
  assign s.arregion = '0;
  assign s.aruser = '0;
  assign s.arvalid = s00_axi_arvalid;
  assign s00_axi_arready = s.arready;
  assign s00_axi_rid = s.rid;
  assign s00_axi_rdata = s.rdata;
  assign s00_axi_rresp = s.rresp;
  assign s00_axi_rlast = s.rlast;
  assign s00_axi_rvalid = s.rvalid;
  assign s.rready = s00_axi_rready;

  taxi_axi_axil_adapter adapter (
      .clk(aclk),
      .rst(rst),
      .s_axi_wr(s),
      .s_axi_rd(s),
      .m_axil_wr(sl),
      .m_axil_rd(sl)
  );

  taxi_axil_crossbar_1s #(
      .M_COUNT (2),
      .ADDR_W  (AddrW),
      .S_ACCEPT(32'd4),
      .M_ADDR_W({32'd12, 32'd12}),
      .M_ISSUE ({32'd4, 32'd4})
  ) xbar (
      .clk(aclk),
      .rst(rst),
      .s_axil_wr(sl),
      .s_axil_rd(sl),
      .m_axil_wr(ml),
      .m_axil_rd(ml)
  );

  // gpu_0: AXI-Lite on its AXI4 port (single beats, ID 0)
  assign m00_axi_awaddr = ml[0].awaddr[11:0];
  assign m00_axi_awid = '0;
  assign m00_axi_awlen = '0;
  assign m00_axi_awsize = 3'd2;
  assign m00_axi_awburst = 2'b01;
  assign m00_axi_awvalid = ml[0].awvalid;
  assign ml[0].awready = m00_axi_awready;
  assign m00_axi_wdata = ml[0].wdata;
  assign m00_axi_wstrb = ml[0].wstrb;
  assign m00_axi_wlast = 1'b1;
  assign m00_axi_wvalid = ml[0].wvalid;
  assign ml[0].wready = m00_axi_wready;
  assign ml[0].bresp = m00_axi_bresp;
  assign ml[0].buser = '0;
  assign ml[0].bvalid = m00_axi_bvalid;
  assign m00_axi_bready = ml[0].bready;
  assign m00_axi_araddr = ml[0].araddr[11:0];
  assign m00_axi_arid = '0;
  assign m00_axi_arlen = '0;
  assign m00_axi_arsize = 3'd2;
  assign m00_axi_arburst = 2'b01;
  assign m00_axi_arvalid = ml[0].arvalid;
  assign ml[0].arready = m00_axi_arready;
  assign ml[0].rdata = m00_axi_rdata;
  assign ml[0].rresp = m00_axi_rresp;
  assign ml[0].ruser = '0;
  assign ml[0].rvalid = m00_axi_rvalid;
  assign m00_axi_rready = ml[0].rready;

  // L2
  assign m01_axil_awaddr = ml[1].awaddr[7:0];
  assign m01_axil_awprot = ml[1].awprot;
  assign m01_axil_awvalid = ml[1].awvalid;
  assign ml[1].awready = m01_axil_awready;
  assign m01_axil_wdata = ml[1].wdata;
  assign m01_axil_wstrb = ml[1].wstrb;
  assign m01_axil_wvalid = ml[1].wvalid;
  assign ml[1].wready = m01_axil_wready;
  assign ml[1].bresp = m01_axil_bresp;
  assign ml[1].buser = '0;
  assign ml[1].bvalid = m01_axil_bvalid;
  assign m01_axil_bready = ml[1].bready;
  assign m01_axil_araddr = ml[1].araddr[7:0];
  assign m01_axil_arprot = ml[1].arprot;
  assign m01_axil_arvalid = ml[1].arvalid;
  assign ml[1].arready = m01_axil_arready;
  assign ml[1].rdata = m01_axil_rdata;
  assign ml[1].rresp = m01_axil_rresp;
  assign ml[1].ruser = '0;
  assign ml[1].rvalid = m01_axil_rvalid;
  assign m01_axil_rready = ml[1].rready;

endmodule
