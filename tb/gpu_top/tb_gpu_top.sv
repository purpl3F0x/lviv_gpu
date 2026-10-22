`timescale 1ns / 1ps

import gpu_types_pkg::*;

// gpu_top with dummy_core, driven through its CPU port as software would:
//
//   1. register access through the crossbar to every slave
//   2. per tile of a 2 x 2 tile image: set the frontend tile, run the visibility DMA over the
//      visibility buffer, wait for the core to go idle, run the tile DMA
//   3. check every pixel the tile DMA wrote (dummy_core's pattern, B = the triangles the tile got)
//
// Every triangle that reaches the core is checked against the next one the tile should get, so the
// visibility DMA, the DataMover (its simulation model), triangle_stream_adapter and the clock
// crossing are checked end to end. The image is also written to +OUT (default gpu_top.tga).
module tb_gpu_top;
  localparam int TriangleStride = 96;  // as AxiVisibilityDma addresses them
  localparam int Triangles = 40;
  localparam int TilesX = 2, TilesY = 2;
  localparam int Width = TilesX * TILE_SIZE_X, Height = TilesY * TILE_SIZE_Y;
  localparam int RowBytes = Width * 4;

  // Memory map of the three behavioural memories (byte addresses, inside each RAM).
  localparam logic [31:0] VbBase = 32'h0000_1000;
  localparam logic [31:0] TriBase = 32'h0000_8000;
  localparam logic [31:0] ImgBase = 32'h0001_0000;
  localparam int VbAddrW = 16, TriAddrW = 18, ImgAddrW = 20;

  // Control map
  localparam logic [11:0] FrontendStatus = 12'h800, FrontendTileX = 12'h804;
  localparam logic [11:0] FrontendTileY = 12'h808, LutBase = 12'h000;
  localparam logic [11:0] VisCtrl = 12'hF80, VisStatus = 12'hF84, VisVbBase = 12'hF88;
  localparam logic [11:0] VisTriBase = 12'hF90, VisTriCount = 12'hF98, VisTileIndex = 12'hF9C;
  localparam logic [11:0] TileCtrl = 12'hF00, TileStatus = 12'hF04, TileBase = 12'hF08;
  localparam logic [11:0] TileStride = 12'hF10, TileTilesX = 12'hF14, TileTilesY = 12'hF18;
  localparam logic [11:0] TileCur = 12'hF1C, TileIrqRaw = 12'hF44, TileIrqClear = 12'hF40;

  function automatic logic [11:0] thread_reg(input int lane, input int offset);
    return 12'(12'h820 + 32 * lane + offset);
  endfunction

  // -------------------------------------------------------------------------
  // Clocks, resets, DUT
  // -------------------------------------------------------------------------

  logic aclk = 0, frontend_clk = 0, thread_clk = 0;
  logic aresetn = 0, frontend_rst_n = 0, thread_rst_n = 0;
  always #5 aclk = ~aclk;
  always #3 frontend_clk = ~frontend_clk;
  always #2 thread_clk = ~thread_clk;

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

  gpu_top #(
      .DUMMY_CORE(1'b1),
      .TRIANGLE_STRIDE(TriangleStride)
  ) dut (
      .aclk(aclk),
      .aresetn(aresetn),
      .frontend_clk(frontend_clk),
      .frontend_rst_n(frontend_rst_n),
      .thread_clk(thread_clk),
      .thread_rst_n(thread_rst_n),
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
      .vis_dma_irq(vis_irq),
      .tile_dma_irq(tile_irq),
      .tri_dma_err(tri_err)
  );

  // -------------------------------------------------------------------------
  // Memories
  // -------------------------------------------------------------------------

  // Visibility buffer (PS DDR): read only.
  axi_ram #(
      .DATA_WIDTH(128),
      .ADDR_WIDTH(VbAddrW),
      .ID_WIDTH(4)
  ) u_vb_ram (
      .clk(aclk),
      .rst(!aresetn),
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

  // Triangles (PL DDR): read only.
  axi_ram #(
      .DATA_WIDTH(512),
      .ADDR_WIDTH(TriAddrW),
      .ID_WIDTH(4)
  ) u_tri_ram (
      .clk(aclk),
      .rst(!aresetn),
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

  // Image (PS DDR): written by the tile DMA.
  axi_ram #(
      .DATA_WIDTH(128),
      .ADDR_WIDTH(ImgAddrW),
      .ID_WIDTH(4)
  ) u_img_ram (
      .clk(aclk),
      .rst(!aresetn),
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

  // -------------------------------------------------------------------------
  // Scene: triangles, their tile masks, and what each tile must receive
  // -------------------------------------------------------------------------

  logic [767:0] records[Triangles];
  logic [63:0] tile_mask[Triangles];
  frontend_data_in_t expected[Triangles];

  // Runs and gaps that differ per tile: some tiles get every triangle, some none in a stretch.
  function automatic bit visible(input int tri_idx, input int tile);
    case (tile)
      0: return 1'b1;
      1: return (tri_idx % 5) != 2 && (tri_idx % 7) != 0;
      2: return tri_idx >= 10 && tri_idx < 23;
      default: return (tri_idx % 3) == 1;
    endcase
  endfunction

  function automatic int tile_triangles(input int tile);
    int n;
    n = 0;
    for (int t = 0; t < Triangles; t++) if (visible(t, tile)) n++;
    return n;
  endfunction

  // The record as the core must receive it, through the RTL's own unpack.
  logic [767:0] unpack_in;
  frontend_data_in_t unpack_out;
  triangle_unpack u_expected_unpack (
      .packed_triangle(unpack_in),
      .triangle(unpack_out)
  );

  task automatic build_scene();
    logic [31:0] addr;
    logic [7:0] value;
    for (int t = 0; t < Triangles; t++) begin
      for (int w = 0; w < 24; w++) records[t][32*w+:32] = $urandom();
      tile_mask[t] = '0;
      for (int k = 0; k < TilesX * TilesY; k++) tile_mask[t][k] = visible(t, k);
      unpack_in = records[t];
      #1;
      expected[t] = unpack_out;
    end
    // Triangles every TriangleStride bytes; the gap after each record is filled with noise.
    for (int t = 0; t < Triangles; t++) begin
      for (int b = 0; b < TriangleStride; b++) begin
        addr = TriBase + 32'(t * TriangleStride + b);
        value = b < 96 ? records[t][8*b+:8] : 8'($urandom());
        u_tri_ram.mem[addr[TriAddrW-1:6]][8*addr[5:0]+:8] = value;
      end
    end
    // One 64-bit tile mask per triangle, two per 128-bit word.
    for (int t = 0; t < Triangles; t += 2) begin
      addr = VbBase + 32'(8 * t);
      u_vb_ram.mem[addr[VbAddrW-1:4]] = {t + 1 < Triangles ? tile_mask[t+1] : 64'd0, tile_mask[t]};
    end
  endtask

  // -------------------------------------------------------------------------
  // Triangle monitor at the core's input
  // -------------------------------------------------------------------------

  int current_tile = -1;
  int received, errors;
  int tile_order[$];

  always @(posedge frontend_clk) begin
    if (frontend_rst_n && !dut.tri_cdc_empty && dut.core_tri_ready) begin
      if (received >= tile_order.size()) begin
        error($sformatf("tile %0d: unexpected extra triangle", current_tile));
      end else if (dut.core_tri !== expected[tile_order[received]]) begin
        error($sformatf("tile %0d: triangle %0d of the tile (index %0d) arrived corrupted",
                        current_tile, received, tile_order[received]));
      end
      received++;
    end
  end

  function automatic void error(input string msg);
    errors++;
    if (errors <= 20) $display("[%0t] ERROR: %s", $time, msg);
  endfunction

  // +TRACE: every DataMover command (as the visibility DMA issued it) and status.
  bit trace;
  initial trace = $test$plusargs("TRACE");

  always @(posedge aclk) begin
    if (trace && dut.vis_cmd_tvalid && dut.vis_cmd_tready)
      $display("[%0t] command: address %08h, %0d bytes (%0d triangles), EOF %0d, DRR %0d", $time,
               dut.vis_cmd_tdata[63:32], dut.vis_cmd_tdata[22:0],
               dut.vis_cmd_tdata[22:0] / TriangleStride, dut.vis_cmd_tdata[30],
               dut.vis_cmd_tdata[31]);
    if (trace && dut.dm_sts_tvalid && dut.dm_sts_tready)
      $display("[%0t] status: %02h", $time, dut.dm_sts_tdata);
  end

  // -------------------------------------------------------------------------
  // CPU port
  // -------------------------------------------------------------------------

  task automatic axi_write(input logic [11:0] addr, input logic [31:0] data);
    bit aw_done, w_done;
    @(posedge aclk);
    awaddr <= addr;
    awvalid <= 1'b1;
    wdata <= data;
    wvalid <= 1'b1;
    aw_done = 0;
    w_done = 0;
    while (!(aw_done && w_done)) begin
      @(posedge aclk);
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
    do @(posedge aclk); while (!bvalid);
    bready <= 1'b0;
    if (bresp != 2'b00) error($sformatf("write 0x%03h: BRESP %0d", addr, bresp));
  endtask

  task automatic axi_read(input logic [11:0] addr, output logic [31:0] data);
    @(posedge aclk);
    araddr  <= addr;
    arvalid <= 1'b1;
    do @(posedge aclk); while (!arready);
    arvalid <= 1'b0;
    rready  <= 1'b1;
    do @(posedge aclk); while (!rvalid);
    data = rdata;
    rready <= 1'b0;
    if (rresp != 2'b00) error($sformatf("read 0x%03h: RRESP %0d", addr, rresp));
  endtask

  task automatic expect_read(input logic [11:0] addr, input logic [31:0] mask,
                             input logic [31:0] value, input string what);
    logic [31:0] data;
    axi_read(addr, data);
    if ((data & mask) !== value)
      error($sformatf("%s: 0x%03h read %08h, expected %08h under mask %08h", what, addr, data,
                      value, mask));
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

  // -------------------------------------------------------------------------
  // Test
  // -------------------------------------------------------------------------

  task automatic register_access();
    axi_write(FrontendTileX, 32'd3);
    expect_read(FrontendTileX, 32'h1F, 32'd3, "frontend tile X");
    axi_write(FrontendTileX, 32'd0);
    expect_read(FrontendStatus, 32'h7, 32'h7, "frontend status, idle");
    for (int lane = 0; lane < NUM_OF_THREADS; lane++)
      expect_read(thread_reg(lane, 0), 32'h1, 32'h0, $sformatf("thread %0d busy", lane));
    axi_write(LutBase + 12'h8, 32'hCAFE_0000);
    expect_read(LutBase + 12'h8, 32'hFFFF_FFFF, 32'hCAFE_0000, "texture LUT base 2");
    axi_write(VisTriCount, 32'd1234);
    expect_read(VisTriCount, 32'hFFFF_FFFF, 32'd1234, "visibility DMA TRI_COUNT");
    axi_write(TileStride, 32'h0000_0400);
    expect_read(TileStride, 32'hFFFF_FFFF, 32'h0000_0400, "tile DMA STRIDE");
    $display("[%0t] register access through the crossbar: %0d errors", $time, errors);
  endtask

  // The frontend (bits 0..2) and every thread idle, twice in a row (a CDC can hide work briefly).
  task automatic wait_core_idle();
    logic [31:0] data;
    int streak, polls;
    bit idle;
    streak = 0;
    polls = 0;
    while (streak < 2) begin
      axi_read(FrontendStatus, data);
      idle = (data & 32'h7) == 32'h7;
      for (int lane = 0; lane < NUM_OF_THREADS; lane++) begin
        axi_read(thread_reg(lane, 0), data);
        if (data[0]) idle = 0;
      end
      streak = idle ? streak + 1 : 0;
      if (++polls > 20000) $fatal(1, "core never went idle");
    end
  endtask

  task automatic render_tile(input int tx, input int ty);
    int tile;
    tile = ty * TilesX + tx;
    tile_order.delete();
    for (int t = 0; t < Triangles; t++) if (visible(t, tile)) tile_order.push_back(t);
    received = 0;
    current_tile = tile;

    axi_write(FrontendTileX, tx);
    axi_write(FrontendTileY, ty);

    axi_write(VisVbBase, VbBase);
    axi_write(VisTriBase, TriBase);
    axi_write(VisTriCount, Triangles);
    axi_write(VisTileIndex, tile);
    axi_write(VisCtrl, 32'h1);  // START
    wait_bits(VisStatus, 32'h2, 32'h2, "visibility DMA DONE");
    expect_read(VisStatus, 32'h64, 32'h0, "visibility DMA error flags");
    axi_write(VisStatus, 32'h2);  // clear DONE

    wait_core_idle();
    if (received != tile_order.size())
      error($sformatf("tile %0d: the core received %0d triangles, expected %0d", tile, received,
                      tile_order.size()));

    axi_write(TileBase, ImgBase);
    axi_write(TileStride, RowBytes);
    axi_write(TileTilesX, TilesX);
    axi_write(TileTilesY, TilesY);
    axi_write(TileCur, {16'(ty), 16'(tx)});
    axi_write(TileCtrl, 32'h1);  // START
    wait_bits(TileIrqRaw, 32'h1, 32'h1, "tile DMA done");
    axi_write(TileIrqClear, 32'h1);
    expect_read(TileStatus, 32'h1, 32'h0, "tile DMA BUSY after done");

    $display("[%0t] tile (%0d, %0d): %0d triangles", $time, tx, ty, received);
  endtask

  function automatic logic [31:0] image_pixel(input int x, input int y);
    logic [31:0] addr;
    addr = ImgBase + 32'(y * RowBytes + x * 4);
    return u_img_ram.mem[addr[ImgAddrW-1:4]][32*addr[3:2]+:32];
  endfunction

  task automatic check_image();
    logic [31:0] got, want;
    int tile, bad;
    bad = 0;
    for (int y = 0; y < Height; y++) begin
      for (int x = 0; x < Width; x++) begin
        tile = (y / TILE_SIZE_Y) * TilesX + x / TILE_SIZE_X;
        want = {8'hFF, 8'(2 * (x % TILE_SIZE_X)), 8'(2 * (y % TILE_SIZE_Y)),
                8'(tile_triangles(tile) > 255 ? 255 : tile_triangles(tile))};
        got = image_pixel(x, y);
        if (got !== want) begin
          if (bad < 8) error($sformatf("pixel (%0d, %0d): %08h, expected %08h", x, y, got, want));
          bad++;
        end
      end
    end
    $display("[%0t] image: %0d of %0d pixels wrong", $time, bad, Width * Height);
  endtask

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

  initial begin : run
    string out_path;
    out_path = "gpu_top.tga";
    void'($value$plusargs("OUT=%s", out_path));
    errors = 0;

    #20;  // after axi_ram's own initial blocks
    build_scene();
    repeat (10) @(posedge aclk);
    aresetn = 1;
    frontend_rst_n = 1;
    thread_rst_n = 1;
    repeat (10) @(posedge aclk);

    register_access();
    for (int ty = 0; ty < TilesY; ty++)
      for (int tx = 0; tx < TilesX; tx++) render_tile(tx, ty);
    check_image();
    write_tga(out_path);
    if (tri_err) error("triangle DMA reported an error");

    if (errors == 0) $display("PASS: %0d tiles, %0d triangles, wrote %s", TilesX * TilesY,
                              Triangles, out_path);
    else $display("FAIL: %0d errors", errors);
    $finish;
  end

  initial begin
    #50ms;
    $fatal(1, "testbench timeout");
  end
endmodule
