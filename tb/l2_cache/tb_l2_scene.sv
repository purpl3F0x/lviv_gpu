`timescale 1ns / 1ps

import gpu_types_pkg::*;

// gpu_top rendering a scene with L2Cache between the threads' texture caches and DDR, for comparing
// L2 configurations on a real scene's texture traffic (on Verilator, run in WSL): the command
// processor's frame, as tb/gpu_top renders it but without its checks, twice: cold (the caches
// empty) and warm (what the first left in them, as frame after frame on the board).
//   +SCENE=        lviv_gl_test's OUT.hex (triangles); its textures from OUT_textures.hex next to it
//   +OUT=          the image (TGA, default scene.tga)
//   +TRACE_READS=  a file of the threads' texture reads (frame, thread, address)
// DDR (the L2's master, 512-bit on mem_clk): bursts served in their order, each one's first beat
// +LAT_MIN..+LAT_MAX mem clocks (30..50) after its address, then a beat every 1 + BEAT_GAP mem
// clocks (0). With NO_L2 defined, the texture caches go to it straight, 4 beats a block.
// Reported per frame: its time, the threads' texture reads (how many, the time to their first and
// last beat, the blocks and lines they cover), DDR's traffic and the L2's counters; last, a RESULT
// line of them.
module tb_l2_scene;
  localparam int TriangleStride = 96;
  localparam int TilesX = 10, TilesY = 6;
  localparam int Width = TilesX * TILE_SIZE_X;
  localparam int Height = 720;
  localparam int RowBytes = Width * 4;
  localparam logic [31:0] ClearColor = 32'hFF636363;
  localparam int N = NUM_OF_THREADS;

  // The behavioural memories (byte addresses, inside each RAM), texture words from the window's 0
  localparam logic [31:0] VbBase = 32'h0000_1000;
  localparam logic [31:0] TriBase = 32'h0000_8000;
  localparam logic [31:0] ImgBase = 32'h0002_0000;
  localparam int VbAddrW = 21, TriAddrW = 24, ImgAddrW = 22, TexWordsW = 23;
  localparam int MaxTriangles = ((1 << TriAddrW) - int'(TriBase)) / TriangleStride;

  // Control map (tb_gpu_top's)
  localparam logic [11:0] LutBase = 12'h000, LutSize = 12'h200;
  localparam logic [11:0] FrontendBbMinX = 12'h804, FrontendBbMinY = 12'h808;
  localparam logic [11:0] FrontendBbMaxX = 12'h80C, FrontendBbMaxY = 12'h810;
  localparam logic [11:0] VisVbBase = 12'hF88, VisTriBase = 12'hF90, VisTriCount = 12'hF98;
  localparam logic [11:0] VisTileIndex = 12'hF9C, VisIrqRaw = 12'hFC0, VisTileCount = 12'hFB8;
  localparam logic [11:0] TileCtrl = 12'hF00, TileStatus = 12'hF04, TileBase = 12'hF08;
  localparam logic [11:0] TileStride = 12'hF10, TileTilesX = 12'hF14, TileTilesY = 12'hF18;
  localparam logic [11:0] TileIrqClear = 12'hF40, TileClearValue = 12'hF28;
  localparam logic [11:0] CpCtrl = 12'h400, CpStatus = 12'h404, CpMode = 12'h408;
  localparam logic [11:0] CpSize = 12'h40C, CpCycles = 12'h410;

  // The L2's registers (l2_cache_regmap.h) and counters (L2Cache.counters): cycles (40 bits) at
  // L2Counter0 and + 4, counter i > 0 (32 bits) at L2Counter0 + 4 + 4 * i
  localparam logic [7:0] L2Ctrl = 8'h00, L2Info = 8'h04, L2CntCtrl = 8'h08, L2Counter0 = 8'h40;
  localparam int L2Global = 12, L2PerPort = 5, L2Counters = L2Global + L2PerPort * N;
  localparam string L2Names[L2Global] = '{
      "cycles", "lookups", "hits", "misses", "merges", "replays", "set_full", "multicast",
      "evictions", "ddr_reads", "ddr_errors", "mshr_full"
  };
  localparam string L2PortNames[L2PerPort] = '{"requests", "hits", "misses", "merges", "replays"};

  function automatic logic [11:0] thread_reg(input int lane, input int offset);
    return 12'(12'h820 + 32 * lane + offset);
  endfunction

  // -------------------------------------------------------------------------
  // Clocks, resets, DUT
  // -------------------------------------------------------------------------

  // The board's: lpd_clk 100 MHz (also the L2's register port), mem_clk 300 MHz, core_clk 500 MHz
  logic lpd_clk = 0, mem_clk = 0, core_clk = 0;
  logic lpd_rst_n = 0, mem_rst_n = 0, core_rst_n = 0;
  real lpd_ns = 10, mem_ns = 3.333, core_ns = 2.0;
  int lat_min = 30, lat_max = 50, beat_gap = 0;
  initial begin
    void'($value$plusargs("LPD_NS=%f", lpd_ns));
    void'($value$plusargs("MEM_NS=%f", mem_ns));
    void'($value$plusargs("CORE_NS=%f", core_ns));
    void'($value$plusargs("LAT_MIN=%d", lat_min));
    void'($value$plusargs("LAT_MAX=%d", lat_max));
    void'($value$plusargs("BEAT_GAP=%d", beat_gap));
    $display("clocks (ns): lpd %0.3f, mem %0.3f, core %0.3f; DDR latency %0d..%0d, beat gap %0d",
             lpd_ns, mem_ns, core_ns, lat_min, lat_max, beat_gap);
    /* verilator lint_off ZERODLY */  // set at run time, never 0
    fork
      forever #(lpd_ns / 2) lpd_clk = ~lpd_clk;
      forever #(mem_ns / 2) mem_clk = ~mem_clk;
      forever #(core_ns / 2) core_clk = ~core_clk;
    join_none
    /* verilator lint_on ZERODLY */
  end

  longint mcycle = 0, ccycle = 0;
  always @(posedge mem_clk) mcycle++;
  always @(posedge core_clk) ccycle++;

  logic [11:0] awaddr = '0, araddr = '0;
  logic awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
  logic [31:0] wdata = '0;
  logic awready, wready, bvalid, arready, rvalid, rlast;
  logic [1:0] bresp, rresp;
  logic [31:0] rdata;

  logic [31:0] vb_araddr, tri_araddr, tile_awaddr;
  logic [3:0] vb_arid, vb_rid, tri_arid, tile_awid, tile_bid;
  logic [7:0] vb_arlen, tri_arlen, tile_awlen;
  logic [2:0] vb_arsize, tri_arsize, tile_awsize;
  logic [1:0] vb_arburst, tri_arburst, tile_awburst;
  logic vb_arvalid, vb_arready, vb_rvalid, vb_rready, vb_rlast;
  logic tri_arvalid, tri_arready, tri_rvalid, tri_rready, tri_rlast;
  logic tile_awvalid, tile_awready, tile_wvalid, tile_wready, tile_wlast, tile_bvalid, tile_bready;
  logic [1:0] vb_rresp, tri_rresp, tile_bresp;
  logic [127:0] vb_rdata, tile_wdata;
  logic [15:0] tile_wstrb;
  logic [511:0] tri_rdata;
  logic vis_irq, tile_irq, tri_err;
  logic [N-1:0][31:0] tex_araddr;
  logic [N-1:0][7:0] tex_arlen;
  logic [N-1:0][2:0] tex_arsize;
  logic [N-1:0][1:0] tex_arburst, tex_rresp;
  logic [N-1:0] tex_arvalid, tex_arready, tex_rlast, tex_rvalid, tex_rready;
  logic [N-1:0][127:0] tex_rdata;

  gpu_top #(
      .TRIANGLE_STRIDE(TriangleStride),
      .TEXTURE_WINDOW(32'h0)
  ) dut (
      .lpd_clk(lpd_clk),
      .lpd_rst_n(lpd_rst_n),
      .mem_clk(mem_clk),
      .mem_rst_n(mem_rst_n),
      .core_clk(core_clk),
      .core_rst_n(core_rst_n),
      .s_axi_ctrl_awaddr(awaddr),
      .s_axi_ctrl_awid('0),
      .s_axi_ctrl_awlen('0),
      .s_axi_ctrl_awsize(3'd2),
      .s_axi_ctrl_awburst(2'b01),
      .s_axi_ctrl_awvalid(awvalid),
      .s_axi_ctrl_awready(awready),
      .s_axi_ctrl_wdata(wdata),
      .s_axi_ctrl_wstrb(4'hF),
      .s_axi_ctrl_wlast(1'b1),
      .s_axi_ctrl_wvalid(wvalid),
      .s_axi_ctrl_wready(wready),
      .s_axi_ctrl_bid(),
      .s_axi_ctrl_bresp(bresp),
      .s_axi_ctrl_bvalid(bvalid),
      .s_axi_ctrl_bready(bready),
      .s_axi_ctrl_araddr(araddr),
      .s_axi_ctrl_arid('0),
      .s_axi_ctrl_arlen('0),
      .s_axi_ctrl_arsize(3'd2),
      .s_axi_ctrl_arburst(2'b01),
      .s_axi_ctrl_arvalid(arvalid),
      .s_axi_ctrl_arready(arready),
      .s_axi_ctrl_rdata(rdata),
      .s_axi_ctrl_rid(),
      .s_axi_ctrl_rresp(rresp),
      .s_axi_ctrl_rlast(rlast),
      .s_axi_ctrl_rvalid(rvalid),
      .s_axi_ctrl_rready(rready),
      .m_axi_vb_araddr(vb_araddr),
      .m_axi_vb_arid(vb_arid),
      .m_axi_vb_arregion(),
      .m_axi_vb_arlen(vb_arlen),
      .m_axi_vb_arsize(vb_arsize),
      .m_axi_vb_arburst(vb_arburst),
      .m_axi_vb_arlock(),
      .m_axi_vb_arcache(),
      .m_axi_vb_arqos(),
      .m_axi_vb_arprot(),
      .m_axi_vb_arvalid(vb_arvalid),
      .m_axi_vb_arready(vb_arready),
      .m_axi_vb_rdata(vb_rdata),
      .m_axi_vb_rid(vb_rid),
      .m_axi_vb_rresp(vb_rresp),
      .m_axi_vb_rlast(vb_rlast),
      .m_axi_vb_rvalid(vb_rvalid),
      .m_axi_vb_rready(vb_rready),
      .m_axi_tri_araddr(tri_araddr),
      .m_axi_tri_arid(tri_arid),
      .m_axi_tri_arlen(tri_arlen),
      .m_axi_tri_arsize(tri_arsize),
      .m_axi_tri_arburst(tri_arburst),
      .m_axi_tri_arprot(),
      .m_axi_tri_arcache(),
      .m_axi_tri_aruser(),
      .m_axi_tri_arvalid(tri_arvalid),
      .m_axi_tri_arready(tri_arready),
      .m_axi_tri_rdata(tri_rdata),
      .m_axi_tri_rresp(tri_rresp),
      .m_axi_tri_rlast(tri_rlast),
      .m_axi_tri_rvalid(tri_rvalid),
      .m_axi_tri_rready(tri_rready),
      .m_axi_tile_awaddr(tile_awaddr),
      .m_axi_tile_awid(tile_awid),
      .m_axi_tile_awregion(),
      .m_axi_tile_awlen(tile_awlen),
      .m_axi_tile_awsize(tile_awsize),
      .m_axi_tile_awburst(tile_awburst),
      .m_axi_tile_awlock(),
      .m_axi_tile_awcache(),
      .m_axi_tile_awqos(),
      .m_axi_tile_awprot(),
      .m_axi_tile_awvalid(tile_awvalid),
      .m_axi_tile_awready(tile_awready),
      .m_axi_tile_wdata(tile_wdata),
      .m_axi_tile_wstrb(tile_wstrb),
      .m_axi_tile_wlast(tile_wlast),
      .m_axi_tile_wvalid(tile_wvalid),
      .m_axi_tile_wready(tile_wready),
      .m_axi_tile_bid(tile_bid),
      .m_axi_tile_bresp(tile_bresp),
      .m_axi_tile_bvalid(tile_bvalid),
      .m_axi_tile_bready(tile_bready),
      .m_axi_tex_araddr(tex_araddr),
      .m_axi_tex_arlen(tex_arlen),
      .m_axi_tex_arsize(tex_arsize),
      .m_axi_tex_arburst(tex_arburst),
      .m_axi_tex_arvalid(tex_arvalid),
      .m_axi_tex_arready(tex_arready),
      .m_axi_tex_rdata(tex_rdata),
      .m_axi_tex_rresp(tex_rresp),
      .m_axi_tex_rlast(tex_rlast),
      .m_axi_tex_rvalid(tex_rvalid),
      .m_axi_tex_rready(tex_rready),
      .vis_dma_irq(vis_irq),
      .tile_dma_irq(tile_irq),
      .tri_dma_err(tri_err)
  );

  // -------------------------------------------------------------------------
  // Memories: visibility words, triangles, image (as tb_gpu_top's), textures
  // -------------------------------------------------------------------------

  axi_ram #(
      .DATA_WIDTH(128),
      .ADDR_WIDTH(VbAddrW),
      .ID_WIDTH(4)
  ) u_vb_ram (
      .clk(mem_clk),
      .rst(!mem_rst_n),
      .s_axi_awid('0),
      .s_axi_awaddr('0),
      .s_axi_awlen('0),
      .s_axi_awsize('0),
      .s_axi_awburst('0),
      .s_axi_awlock('0),
      .s_axi_awcache('0),
      .s_axi_awprot('0),
      .s_axi_awvalid(1'b0),
      .s_axi_awready(),
      .s_axi_wdata('0),
      .s_axi_wstrb('0),
      .s_axi_wlast(1'b0),
      .s_axi_wvalid(1'b0),
      .s_axi_wready(),
      .s_axi_bid(),
      .s_axi_bresp(),
      .s_axi_bvalid(),
      .s_axi_bready(1'b1),
      .s_axi_arid(vb_arid),
      .s_axi_araddr(vb_araddr[VbAddrW-1:0]),
      .s_axi_arlen(vb_arlen),
      .s_axi_arsize(vb_arsize),
      .s_axi_arburst(vb_arburst),
      .s_axi_arlock('0),
      .s_axi_arcache('0),
      .s_axi_arprot('0),
      .s_axi_arvalid(vb_arvalid),
      .s_axi_arready(vb_arready),
      .s_axi_rid(vb_rid),
      .s_axi_rdata(vb_rdata),
      .s_axi_rresp(vb_rresp),
      .s_axi_rlast(vb_rlast),
      .s_axi_rvalid(vb_rvalid),
      .s_axi_rready(vb_rready)
  );

  axi_ram #(
      .DATA_WIDTH(512),
      .ADDR_WIDTH(TriAddrW),
      .ID_WIDTH(4)
  ) u_tri_ram (
      .clk(mem_clk),
      .rst(!mem_rst_n),
      .s_axi_awid('0),
      .s_axi_awaddr('0),
      .s_axi_awlen('0),
      .s_axi_awsize('0),
      .s_axi_awburst('0),
      .s_axi_awlock('0),
      .s_axi_awcache('0),
      .s_axi_awprot('0),
      .s_axi_awvalid(1'b0),
      .s_axi_awready(),
      .s_axi_wdata('0),
      .s_axi_wstrb('0),
      .s_axi_wlast(1'b0),
      .s_axi_wvalid(1'b0),
      .s_axi_wready(),
      .s_axi_bid(),
      .s_axi_bresp(),
      .s_axi_bvalid(),
      .s_axi_bready(1'b1),
      .s_axi_arid(tri_arid),
      .s_axi_araddr(tri_araddr[TriAddrW-1:0]),
      .s_axi_arlen(tri_arlen),
      .s_axi_arsize(tri_arsize),
      .s_axi_arburst(tri_arburst),
      .s_axi_arlock('0),
      .s_axi_arcache('0),
      .s_axi_arprot('0),
      .s_axi_arvalid(tri_arvalid),
      .s_axi_arready(tri_arready),
      .s_axi_rid(),
      .s_axi_rdata(tri_rdata),
      .s_axi_rresp(tri_rresp),
      .s_axi_rlast(tri_rlast),
      .s_axi_rvalid(tri_rvalid),
      .s_axi_rready(tri_rready)
  );

  axi_ram #(
      .DATA_WIDTH(128),
      .ADDR_WIDTH(ImgAddrW),
      .ID_WIDTH(4)
  ) u_img_ram (
      .clk(mem_clk),
      .rst(!mem_rst_n),
      .s_axi_awid(tile_awid),
      .s_axi_awaddr(tile_awaddr[ImgAddrW-1:0]),
      .s_axi_awlen(tile_awlen),
      .s_axi_awsize(tile_awsize),
      .s_axi_awburst(tile_awburst),
      .s_axi_awlock('0),
      .s_axi_awcache('0),
      .s_axi_awprot('0),
      .s_axi_awvalid(tile_awvalid),
      .s_axi_awready(tile_awready),
      .s_axi_wdata(tile_wdata),
      .s_axi_wstrb(tile_wstrb),
      .s_axi_wlast(tile_wlast),
      .s_axi_wvalid(tile_wvalid),
      .s_axi_wready(tile_wready),
      .s_axi_bid(tile_bid),
      .s_axi_bresp(tile_bresp),
      .s_axi_bvalid(tile_bvalid),
      .s_axi_bready(tile_bready),
      .s_axi_arid('0),
      .s_axi_araddr('0),
      .s_axi_arlen('0),
      .s_axi_arsize('0),
      .s_axi_arburst('0),
      .s_axi_arlock('0),
      .s_axi_arcache('0),
      .s_axi_arprot('0),
      .s_axi_arvalid(1'b0),
      .s_axi_arready(),
      .s_axi_rid(),
      .s_axi_rdata(),
      .s_axi_rresp(),
      .s_axi_rlast(),
      .s_axi_rvalid(),
      .s_axi_rready(1'b1)
  );

  logic [31:0] tex_mem[1 << TexWordsW];

  function automatic logic [511:0] ddr_beat(input logic [31:0] addr);
    logic [511:0] d;
    for (int i = 0; i < 16; i++) begin
      logic [31:0] a = addr + 32'(4 * i);
      d[32*i+:32] = a[31:2] < (1 << TexWordsW) ? tex_mem[a[TexWordsW+1:2]] : 32'h0;
    end
    return d;
  endfunction

  // -------------------------------------------------------------------------
  // DDR: bursts in their order, the first beat of each at its time (and not before the one ahead
  // is done), then a beat every 1 + beat_gap clocks
  // -------------------------------------------------------------------------

  logic [31:0] q_addr[$];
  int q_id[$], q_beats[$], q_port[$];
  longint q_ready[$];
  longint ddr_bursts = 0, ddr_beats = 0;
  int gap = 0;

  function automatic void ddr_push(input logic [31:0] addr, input int id, input int beats,
                                   input int port);
    q_addr.push_back(addr);
    q_id.push_back(id);
    q_beats.push_back(beats);
    q_port.push_back(port);
    q_ready.push_back(mcycle + longint'($urandom_range(lat_max, lat_min)));
    ddr_bursts++;
  endfunction

  // The burst ahead a beat on, gone after its last
  function automatic void ddr_advance();
    ddr_beats++;
    q_addr[0] = q_addr[0] + 32'd64;
    q_beats[0] = q_beats[0] - 1;
    if (q_beats[0] == 0) begin
      void'(q_addr.pop_front());
      void'(q_id.pop_front());
      void'(q_beats.pop_front());
      void'(q_port.pop_front());
      void'(q_ready.pop_front());
    end
    gap = beat_gap;
  endfunction

  function automatic bit ddr_due();
    return q_addr.size() > 0 && q_ready[0] <= mcycle;
  endfunction

  // A thread's texture port to L2 port n
  `define L2_PORT(n) \
      .s_axi_``n``_arvalid(tex_arvalid[n]), \
      .s_axi_``n``_arready(tex_arready[n]), \
      .s_axi_``n``_araddr(tex_araddr[n]), \
      .s_axi_``n``_arlen(tex_arlen[n]), \
      .s_axi_``n``_arsize(tex_arsize[n]), \
      .s_axi_``n``_arburst(tex_arburst[n]), \
      .s_axi_``n``_rvalid(tex_rvalid[n]), \
      .s_axi_``n``_rready(tex_rready[n]), \
      .s_axi_``n``_rdata(tex_rdata[n]), \
      .s_axi_``n``_rresp(tex_rresp[n]), \
      .s_axi_``n``_rlast(tex_rlast[n]),

`ifndef NO_L2
  logic m_arvalid, m_arready, m_rvalid = 1'b0, m_rready, m_rlast = 1'b0;
  logic [31:0] m_araddr;
  logic [2:0] m_arid, m_rid = '0;
  logic [7:0] m_arlen;
  logic [2:0] m_arsize;
  logic [1:0] m_arburst, m_rresp = '0;
  logic [511:0] m_rdata = '0;
  assign m_arready = mem_rst_n;

  always @(posedge mem_clk) begin
    if (m_arvalid && m_arready) ddr_push(m_araddr, int'(m_arid), int'(m_arlen) + 1, -1);
    if (m_rvalid && m_rready) ddr_advance();
    if (!m_rvalid || m_rready) begin
      if (gap > 0) begin
        gap--;
        m_rvalid <= 1'b0;
      end else if (ddr_due()) begin
        m_rvalid <= 1'b1;
        m_rid <= 3'(q_id[0]);
        m_rdata <= ddr_beat(q_addr[0]);
        m_rlast <= q_beats[0] == 1;
      end else m_rvalid <= 1'b0;
    end
  end

  logic awvalid_l = 1'b0, awready_l, wvalid_l = 1'b0, wready_l, bvalid_l, bready_l = 1'b0;
  logic arvalid_l = 1'b0, arready_l, rvalid_l, rready_l = 1'b0;
  logic [7:0] awaddr_l = '0, araddr_l = '0;
  logic [31:0] wdata_l = '0, rdata_l;
  logic [1:0] bresp_l, rresp_l;

  L2Cache u_l2 (
      .s_axil_awvalid(awvalid_l),
      .s_axil_awready(awready_l),
      .s_axil_awaddr(awaddr_l),
      .s_axil_awprot(3'b000),
      .s_axil_wvalid(wvalid_l),
      .s_axil_wready(wready_l),
      .s_axil_wdata(wdata_l),
      .s_axil_wstrb(4'hF),
      .s_axil_bvalid(bvalid_l),
      .s_axil_bready(bready_l),
      .s_axil_bresp(bresp_l),
      .s_axil_arvalid(arvalid_l),
      .s_axil_arready(arready_l),
      .s_axil_araddr(araddr_l),
      .s_axil_arprot(3'b000),
      .s_axil_rvalid(rvalid_l),
      .s_axil_rready(rready_l),
      .s_axil_rdata(rdata_l),
      .s_axil_rresp(rresp_l),
      `L2_PORT(0)
      `L2_PORT(1)
      `L2_PORT(2)
      `L2_PORT(3)
      .m_axi_arvalid(m_arvalid),
      .m_axi_arready(m_arready),
      .m_axi_araddr(m_araddr),
      .m_axi_arid(m_arid),
      .m_axi_arlen(m_arlen),
      .m_axi_arsize(m_arsize),
      .m_axi_arburst(m_arburst),
      .m_axi_rvalid(m_rvalid),
      .m_axi_rready(m_rready),
      .m_axi_rdata(m_rdata),
      .m_axi_rid(m_rid),
      .m_axi_rresp(m_rresp),
      .m_axi_rlast(m_rlast),
      .core_clk(core_clk),
      .core_resetn(core_rst_n),
      .mem_clk(mem_clk),
      .mem_resetn(mem_rst_n),
      .axil_clk(lpd_clk),
      .axil_resetn(lpd_rst_n)
  );

  task automatic l2_write(input logic [7:0] addr, input logic [31:0] data);
    @(posedge lpd_clk);
    awvalid_l <= 1'b1;
    awaddr_l  <= addr;
    wvalid_l  <= 1'b1;
    wdata_l   <= data;
    fork
      begin
        do @(posedge lpd_clk); while (!awready_l);
        awvalid_l <= 1'b0;
      end
      begin
        do @(posedge lpd_clk); while (!wready_l);
        wvalid_l <= 1'b0;
      end
    join
    bready_l <= 1'b1;
    do @(posedge lpd_clk); while (!bvalid_l);
    bready_l <= 1'b0;
  endtask

  task automatic l2_read(input logic [7:0] addr, output logic [31:0] data);
    @(posedge lpd_clk);
    arvalid_l <= 1'b1;
    araddr_l  <= addr;
    do @(posedge lpd_clk); while (!arready_l);
    arvalid_l <= 1'b0;
    rready_l  <= 1'b1;
    do @(posedge lpd_clk); while (!rvalid_l);
    data = rdata_l;
    rready_l <= 1'b0;
  endtask

  task automatic l2_wait_clear(input logic [7:0] addr, input logic [31:0] mask, input string what);
    logic [31:0] data;
    for (int i = 0; i < 100000; i++) begin
      l2_read(addr, data);
      if ((data & mask) == 0) return;
    end
    $fatal(1, "%s never done", what);
  endtask

  // Every counter, the GPU idle, once their carries are in
  longint l2_cnt[L2Counters];
  task automatic read_l2_counters();
    logic [31:0] lo, hi;
    l2_wait_clear(L2CntCtrl, 32'h4, "L2 CNT_PENDING");
    l2_read(L2Counter0, lo);
    l2_read(L2Counter0 + 8'd4, hi);
    l2_cnt[0] = {24'h0, hi[7:0], lo};
    for (int i = 1; i < L2Counters; i++) begin
      l2_read(L2Counter0 + 8'(4 + 4 * i), lo);
      l2_cnt[i] = {32'h0, lo};
    end
  endtask
`else
  // The texture caches straight to DDR: an AR a burst of 4 beats, each beat's 4 words to the port
  logic [31:0] req_addr[$];
  int req_port[$];
  logic [127:0] port_words[N][$];

  for (genvar p = 0; p < N; p++) begin : g_direct
    logic busy = 1'b0, valid = 1'b0, last = 1'b0;
    logic [127:0] data = '0;
    int sent = 0;
    assign tex_arready[p] = core_rst_n && !busy;
    assign tex_rvalid[p] = valid;
    assign tex_rdata[p] = data;
    assign tex_rlast[p] = last;
    assign tex_rresp[p] = 2'b00;
    always @(posedge core_clk) begin
      if (tex_arvalid[p] && tex_arready[p]) begin
        busy <= 1'b1;
        req_addr.push_back(tex_araddr[p]);
        req_port.push_back(p);
      end
      if (valid && tex_rready[p] && last) busy <= 1'b0;
      if (!valid || tex_rready[p]) begin
        if (port_words[p].size() > 0) begin
          valid <= 1'b1;
          data  <= port_words[p].pop_front();
          last  <= sent % 16 == 15;
          sent++;
        end else valid <= 1'b0;
      end
    end
  end

  always @(posedge mem_clk) begin
    while (req_addr.size() > 0) ddr_push(req_addr.pop_front(), 0, 4, req_port.pop_front());
    if (gap > 0) gap--;
    else if (ddr_due()) begin
      automatic logic [511:0] d = ddr_beat(q_addr[0]);
      for (int i = 0; i < 4; i++) port_words[q_port[0]].push_back(d[128*i+:128]);
      ddr_advance();
    end
  end
`endif

  // -------------------------------------------------------------------------
  // The threads' texture reads, during the frame
  // -------------------------------------------------------------------------

  // and the blocks and lines they read, each counted once; with +TRACE_READS=<file>, a line a read
  // there: frame (0, 1), thread, address
  bit measuring = 1'b0;
  longint reads[N], first_sum[N], last_sum[N], last_max[N], t_ar[N];
  bit want_first[N];
  bit seen_block[int unsigned], seen_line[int unsigned];
  int frame_no = -1, trace_fd = 0;
  initial begin
    string path;
    if ($value$plusargs("TRACE_READS=%s", path)) trace_fd = $fopen(path, "w");
  end

  function automatic void measure_from_0();
    for (int p = 0; p < N; p++) begin
      reads[p] = 0;
      first_sum[p] = 0;
      last_sum[p] = 0;
      last_max[p] = 0;
      want_first[p] = 0;
    end
    seen_block.delete();
    seen_line.delete();
    ddr_bursts = 0;
    ddr_beats = 0;
  endfunction

  always @(posedge core_clk)
    if (measuring)
      for (int p = 0; p < N; p++) begin
        if (tex_arvalid[p] && tex_arready[p]) begin
          t_ar[p] = ccycle;
          want_first[p] = 1'b1;
          reads[p]++;
          seen_block[tex_araddr[p][31:8]] = 1'b1;
          seen_line[tex_araddr[p][31:9]] = 1'b1;
          if (trace_fd != 0) $fwrite(trace_fd, "%0d %0d %08h\n", frame_no, p, tex_araddr[p]);
        end
        if (tex_rvalid[p] && tex_rready[p]) begin
          if (want_first[p]) begin
            first_sum[p] += ccycle - t_ar[p];
            want_first[p] = 1'b0;
          end
          if (tex_rlast[p]) begin
            last_sum[p] += ccycle - t_ar[p];
            if (ccycle - t_ar[p] > last_max[p]) last_max[p] = ccycle - t_ar[p];
          end
        end
      end

  // -------------------------------------------------------------------------
  // Scene and textures
  // -------------------------------------------------------------------------

  int triangles;

  // Per line, the visibility word, then the record as 24 words in memory order; straight into the
  // memories
  task automatic load_scene(input string path);
    int fd;
    logic [63:0] mask;
    logic [31:0] word, a;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "cannot open scene %s", path);
    triangles = 0;
    while ($fscanf(fd, "%h", mask) == 1) begin
      if (triangles == MaxTriangles)
        $fatal(1, "scene %s: more than %0d triangles", path, MaxTriangles);
      a = VbBase + 32'(8 * triangles);
      u_vb_ram.mem[a[VbAddrW-1:4]][64*a[3]+:64] = mask;
      for (int w = 0; w < 24; w++) begin
        if ($fscanf(fd, "%h", word) != 1)
          $fatal(1, "scene %s: triangle %0d is short", path, triangles);
        a = TriBase + 32'(TriangleStride * triangles + 4 * w);
        u_tri_ram.mem[a[TriAddrW-1:6]][8*a[5:0]+:32] = word;
      end
      triangles++;
    end
    $fclose(fd);
    $display("scene %s: %0d triangles", path, triangles);
  endtask

  // The texture table from the file's "// texture ID ADDRESS SIZE" lines, the texels by $readmemh
  int tex_ids[$], tex_sizes[$];
  logic [31:0] tex_bases[$];
  task automatic load_textures(input string path);
    int fd, id, size;
    logic [31:0] base;
    string line;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "cannot open textures %s", path);
    while ($fgets(line, fd) > 0)
      if ($sscanf(line, "// texture %d %h %d", id, base, size) == 3) begin
        if (base + (32'd1 << (2 * size)) > (32'd1 << TexWordsW))
          $fatal(1, "texture %0d: beyond the %0d-word texture memory", id, 1 << TexWordsW);
        tex_ids.push_back(id);
        tex_bases.push_back(base);
        tex_sizes.push_back(size);
      end
    $fclose(fd);
    $readmemh(path, tex_mem);
    $display("textures %s: %0d", path, tex_ids.size());
  endtask

  // -------------------------------------------------------------------------
  // CPU port (tb_gpu_top's)
  // -------------------------------------------------------------------------

  task automatic axi_write(input logic [11:0] addr, input logic [31:0] data);
    bit aw_done, w_done;
    @(posedge lpd_clk);
    awaddr <= addr;
    awvalid <= 1'b1;
    wdata <= data;
    wvalid <= 1'b1;
    aw_done = 0;
    w_done = 0;
    while (!(aw_done && w_done)) begin
      @(posedge lpd_clk);
      if (awvalid && awready) begin
        aw_done = 1;
        awvalid <= 1'b0;
      end
      if (wvalid && wready) begin
        w_done = 1;
        wvalid <= 1'b0;
      end
    end
    bready <= 1'b1;
    do @(posedge lpd_clk); while (!bvalid);
    bready <= 1'b0;
    if (bresp != 2'b00) $fatal(1, "write 0x%03h: BRESP %0d", addr, bresp);
  endtask

  task automatic axi_read(input logic [11:0] addr, output logic [31:0] data);
    @(posedge lpd_clk);
    araddr  <= addr;
    arvalid <= 1'b1;
    do @(posedge lpd_clk); while (!arready);
    arvalid <= 1'b0;
    rready  <= 1'b1;
    do @(posedge lpd_clk); while (!rvalid);
    data = rdata;
    rready <= 1'b0;
    if (rresp != 2'b00) $fatal(1, "read 0x%03h: RRESP %0d", addr, rresp);
  endtask

  task automatic wait_bits(input logic [11:0] addr, input logic [31:0] mask,
                           input logic [31:0] value, input string what);
    logic [31:0] data;
    int polls;
    polls = 0;
    do begin
      axi_read(addr, data);
      if (++polls > 20000) $fatal(1, "%s: 0x%03h stuck at %08h", what, addr, data);
    end while ((data & mask) !== value);
  endtask

  function automatic logic [31:0] box_end(input int t, input int tile_size, input int size);
    return 32'((t + 1) * tile_size - 1 < size ? (t + 1) * tile_size - 1 : size - 1);
  endfunction

  task automatic clear_frame_buffers(input logic [31:0] color);
    axi_write(TileClearValue, color);
    axi_write(TileCtrl, 32'h8);  // CLEAR
    wait_bits(TileStatus, 32'h10, 32'h0, "tile DMA CLEAR_BUSY");
  endtask

  task automatic clear_zbuffers();
    for (int lane = 0; lane < N; lane++) axi_write(thread_reg(lane, 4), 32'h1);
    repeat (8) @(posedge lpd_clk);
    for (int lane = 0; lane < N; lane++)
      wait_bits(thread_reg(lane, 4), 32'h1, 32'h0, $sformatf("thread %0d z-buffer clear", lane));
  endtask

  // The command processor's frame, set up as the CPU does it (tb_gpu_top's cp_program)
  task automatic cp_program();
    axi_write(VisIrqRaw, 32'h7);
    axi_write(TileIrqClear, 32'h7);
    axi_write(VisVbBase, VbBase);
    axi_write(VisTriBase, TriBase);
    axi_write(VisTriCount, triangles);
    axi_write(VisTileIndex, 32'h0);
    axi_write(VisTileCount, TilesX * TilesY);
    axi_write(TileBase, ImgBase);
    axi_write(TileStride, RowBytes);
    axi_write(TileTilesX, TilesX);
    axi_write(TileTilesY, TilesY);
    axi_write(TileCtrl, 32'h2);  // RESET_POS
    clear_frame_buffers(ClearColor);
    clear_zbuffers();
    axi_write(FrontendBbMinX, 32'h0);
    axi_write(FrontendBbMinY, 32'h0);
    axi_write(FrontendBbMaxX, box_end(0, TILE_SIZE_X, Width));
    axi_write(FrontendBbMaxY, box_end(0, TILE_SIZE_Y, Height));
    axi_write(CpSize, {16'(Height), 16'(Width)});
  endtask

  function automatic logic [31:0] image_pixel(input int x, input int y);
    logic [31:0] addr;
    addr = ImgBase + 32'(y * RowBytes + x * 4);
    return u_img_ram.mem[addr[ImgAddrW-1:4]][32*addr[3:2]+:32];
  endfunction

  task automatic write_tga(input string path);
    int fd;
    logic [31:0] p;
    fd = $fopen(path, "wb");
    if (fd == 0) $fatal(1, "cannot open %s", path);
    $fwrite(fd, "%c%c%c%c%c%c%c%c%c%c%c%c", 8'd0, 8'd0, 8'd2, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0,
            8'd0, 8'd0, 8'd0, 8'd0);
    $fwrite(fd, "%c%c%c%c%c%c", Width[7:0], Width[15:8], Height[7:0], Height[15:8], 8'd32,
            8'h28);
    for (int y = 0; y < Height; y++)
      for (int x = 0; x < Width; x++) begin
        p = image_pixel(x, y);
        $fwrite(fd, "%c%c%c%c", p[7:0], p[15:8], p[23:16], p[31:24]);
      end
    $fclose(fd);
  endtask

  // -------------------------------------------------------------------------
  // The frames: the first with the caches empty (cold), the second with what the first left in
  // them (warm, as the board draws frame after frame)
  // -------------------------------------------------------------------------

  // A frame from the command processor, the L2's counters from 0; its numbers, tagged
  task automatic render(input string tag);
    logic [31:0] status, cycles;
    longint all_reads, all_first, all_last, worst;
    measure_from_0();
    frame_no++;
`ifndef NO_L2
    l2_write(L2CntCtrl, 32'h2);  // CLEAR
    l2_wait_clear(L2CntCtrl, 32'h2, "L2 CNT_CLEAR");
`endif
    cp_program();
    axi_write(CpMode, 32'h1);
    $display("[%0t] %s frame", $time, tag);
    measuring = 1'b1;
    axi_write(CpCtrl, 32'h1);  // START
    for (int polls = 0;; polls++) begin
      repeat (100) @(posedge lpd_clk);
      axi_read(CpStatus, status);
      if (!status[0]) break;
      if (polls > 1000000) $fatal(1, "command processor: still busy, STATUS %08h", status);
    end
    measuring = 1'b0;
    axi_read(CpCycles, cycles);
    if (status[2] || !status[1])
      $fatal(1, "command processor: STATUS %08h after the frame", status);
    $display("[%0t] %s frame: %0d command processor cycles (%0.1f us)", $time, tag, cycles,
             cycles * lpd_ns / 1000.0);

    all_reads = 0;
    all_first = 0;
    all_last = 0;
    worst = 0;
    for (int p = 0; p < N; p++) begin
      $display("thread %0d: %0d texture reads, %0.1f ns to the first beat, %0.1f to the last %s",
               p, reads[p], reads[p] ? first_sum[p] * core_ns / reads[p] : 0.0,
               reads[p] ? last_sum[p] * core_ns / reads[p] : 0.0,
               $sformatf("(worst %0.1f)", last_max[p] * core_ns));
      all_reads += reads[p];
      all_first += first_sum[p];
      all_last += last_sum[p];
      if (last_max[p] > worst) worst = last_max[p];
    end
    $display("texture blocks read: %0d (%0.2f MiB), in %0d lines of 512 B (%0.2f MiB)",
             seen_block.num(), seen_block.num() / 4096.0, seen_line.num(),
             seen_line.num() / 2048.0);
    $display("DDR: %0d bursts, %0d beats (%0.2f MiB)", ddr_bursts, ddr_beats,
             ddr_beats * 64.0 / (1 << 20));
`ifndef NO_L2
    read_l2_counters();
    for (int i = 0; i < L2Global; i++) $display("L2 %s %0d", L2Names[i], l2_cnt[i]);
    for (int p = 0; p < N; p++)
      for (int i = 0; i < L2PerPort; i++)
        $display("L2 %s port%0d_%s %0d", tag, p, L2PortNames[i], l2_cnt[L2Global+L2PerPort*p+i]);
`endif
    $write("RESULT %s frame_cycles %0d frame_us %0.1f reads %0d", tag, cycles,
           cycles * lpd_ns / 1000.0, all_reads);
    $write(" first_ns %0.2f last_ns %0.2f worst_ns %0.1f",
           all_reads ? all_first * core_ns / all_reads : 0.0,
           all_reads ? all_last * core_ns / all_reads : 0.0, worst * core_ns);
    $write(" blocks %0d lines %0d ddr_bursts %0d ddr_mib %0.3f", seen_block.num(), seen_line.num(),
           ddr_bursts, ddr_beats * 64.0 / (1 << 20));
`ifndef NO_L2
    for (int i = 0; i < L2Global; i++) $write(" %s %0d", L2Names[i], l2_cnt[i]);
    for (int i = 0; i < L2PerPort; i++) begin
      longint sum = 0;
      for (int p = 0; p < N; p++) sum += l2_cnt[L2Global+L2PerPort*p+i];
      $write(" port_%s %0d", L2PortNames[i], sum);
    end
`endif
    $display("");
  endtask

  initial begin : run
    string out_path, scene_path, tex_path;
    logic [31:0] data;
    out_path = "scene.tga";
    if (!$value$plusargs("SCENE=%s", scene_path)) $fatal(1, "no +SCENE=");
    void'($value$plusargs("OUT=%s", out_path));
    tex_path = scene_path;
    if (tex_path.len() > 4 && tex_path.substr(tex_path.len() - 4, tex_path.len() - 1) == ".hex")
      tex_path = tex_path.substr(0, tex_path.len() - 5);
    tex_path = {tex_path, "_textures.hex"};

    #20;  // after axi_ram's own initial blocks
    load_scene(scene_path);
    load_textures(tex_path);
    repeat (10) @(posedge lpd_clk);
    lpd_rst_n = 1;
    mem_rst_n = 1;
    core_rst_n = 1;
    repeat (10) @(posedge lpd_clk);

    foreach (tex_ids[i]) begin
      axi_write(LutBase + 12'(4 * tex_ids[i]), tex_bases[i]);
      axi_write(LutSize + 12'(4 * tex_ids[i]), 32'(tex_sizes[i]));
    end
`ifndef NO_L2
    l2_wait_clear(L2Ctrl, 32'h1, "L2 sweep after reset");
    l2_read(L2Info, data);
    $display("L2: %0d KiB, %0d ways, %0d-byte lines, %0d ports", data[31:16], data[3:0],
             1 << data[7:4], data[11:8]);
`else
    $display("no L2: the texture caches straight to DDR");
`endif

    render("cold");
    render("warm");
    if (trace_fd != 0) $fclose(trace_fd);
    write_tga(out_path);
    $display("wrote %s", out_path);
    $finish;
  end

  initial begin
    #2s;
    $fatal(1, "testbench timeout");
  end
endmodule
