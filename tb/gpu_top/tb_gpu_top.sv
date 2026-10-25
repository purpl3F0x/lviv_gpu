`timescale 1ns / 1ps

import gpu_types_pkg::*;

// gpu_top driven through its CPU port as software would, rendering a scene (+SCENE, made by
// `make gpu_top_scene` in dv/raster_sw: its visibility words and gpu_triangle_t records) at
// 1280 x 720 in 10 x 6 tiles:
//
//   1. register access through the crossbar to every slave
//   2. the tile DMA's CLEAR fills the frame buffers with raster_sw's clear color; each write-back
//      leaves it behind
//   3. per tile: clear the z-buffers, set the frontend's tile box (BB_MIN, BB_MAX: the tile's
//      first pixel to its last, or the screen's), run the visibility DMA over the visibility
//      buffer, wait for the core to go idle, run the tile DMA
//   4. the same frame from the command processor (MODE 1, one START): its checks first (START
//      ignored in MODE 0, a size of 0, MODE kept while busy, SOFT_RESET mid-frame), then the frame,
//      which must end with the tile DMA's frame_done and give the per-tile frame's image (rows
//      past the screen: the clear color, as BB_MAX clips them)
//   5. a second write-back of the first tile must read the clear color everywhere
//
// Every triangle that reaches the core is checked against the next one the tile should get, so the
// visibility DMA, the DataMover (its simulation model), triangle_stream_adapter and the clock
// crossing are checked end to end; in the command processor's frame the tile comes from the
// frontend's box (BB_MIN), which it sets before the tile's triangles. The image (the command
// processor's) is written to +OUT (default gpu_top.tga), and make compares it with raster_sw's.
//
// +TEXTURE: a texture for LUT entry 0, in the texture memory that every thread's texture cache
// reads through its own port. gpu_top's TEXTURE_WINDOW is not 0 here, and every texture read must
// carry it. The memory answers like PS DDR behind an interconnect: +TEX_LATENCY thread clocks
// (default 64) from a read's address to its first beat, then beats with random gaps.
module tb_gpu_top;
  localparam int TriangleStride = 96;  // as AxiVisibilityDma addresses them
  localparam int TilesX = 10, TilesY = 6;
  localparam int Width = TilesX * TILE_SIZE_X;
  localparam int Height = 720;  // the rows written out
  localparam int RowBytes = Width * 4;
  localparam logic [31:0] ClearColor = 32'hFF636363;  // raster_sw's clear color (ARGB)

  // Memory map of the three behavioural memories (byte addresses, inside each RAM).
  localparam logic [31:0] VbBase = 32'h0000_1000;
  localparam logic [31:0] TriBase = 32'h0000_8000;
  localparam logic [31:0] ImgBase = 32'h0001_0000;
  localparam int VbAddrW = 16, TriAddrW = 18, ImgAddrW = 22, TexAddrW = 16;
  localparam logic [31:0] TextureWindow = 32'h3800_0000;  // gpu_top's TEXTURE_WINDOW
  localparam int MaxTriangles = ((1 << TriAddrW) - int'(TriBase)) / TriangleStride;

  // Control map
  localparam logic [11:0] FrontendStatus = 12'h800, FrontendBbMinX = 12'h804;
  localparam logic [11:0] FrontendBbMinY = 12'h808, LutBase = 12'h000, LutSize = 12'h200;
  localparam logic [11:0] VisCtrl = 12'hF80, VisStatus = 12'hF84, VisVbBase = 12'hF88;
  localparam logic [11:0] VisTriBase = 12'hF90, VisTriCount = 12'hF98, VisTileIndex = 12'hF9C;
  localparam logic [11:0] TileCtrl = 12'hF00, TileStatus = 12'hF04, TileBase = 12'hF08;
  localparam logic [11:0] TileStride = 12'hF10, TileTilesX = 12'hF14, TileTilesY = 12'hF18;
  localparam logic [11:0] TileCur = 12'hF1C, TileIrqRaw = 12'hF44, TileIrqClear = 12'hF40;
  localparam logic [11:0] TileClearValue = 12'hF28, VisIrqRaw = 12'hFC0, VisTileCount = 12'hFB8;
  localparam logic [11:0] FrontendBbMaxX = 12'h80C, FrontendBbMaxY = 12'h810;
  localparam logic [11:0] CpCtrl = 12'h400, CpStatus = 12'h404, CpMode = 12'h408;
  localparam logic [11:0] CpSize = 12'h40C, CpCycles = 12'h410;
  // CP CTRL: START 1, SOFT_RESET 2; STATUS: BUSY 1, DONE 2, ERROR 4, CAUSE [6:4], TILE [13:8]

  function automatic logic [11:0] thread_reg(input int lane, input int offset);
    return 12'(12'h820 + 32 * lane + offset);
  endfunction

  // -------------------------------------------------------------------------
  // Clocks, resets, DUT
  // -------------------------------------------------------------------------

  // Clock periods (ns), the design's: the control port and the command processor at 150 MHz, the
  // AXI clock and the frontend at 300 MHz, the orchestrator and the threads at 500 MHz; or
  // +CTRL_NS=, +ACLK_NS=, +FRONTEND_NS=, +THREAD_NS= (the board's today: all 10)
  logic ctrl_clk = 0, aclk = 0, frontend_clk = 0, thread_clk = 0;
  logic ctrl_rst_n = 0, aresetn = 0, frontend_rst_n = 0, thread_rst_n = 0;
  real ctrl_ns = 6.667, aclk_ns = 3.334, frontend_ns = 3.334, thread_ns = 2;
  initial begin
    void'($value$plusargs("CTRL_NS=%f", ctrl_ns));
    void'($value$plusargs("ACLK_NS=%f", aclk_ns));
    void'($value$plusargs("FRONTEND_NS=%f", frontend_ns));
    void'($value$plusargs("THREAD_NS=%f", thread_ns));
    $display("clocks (ns): ctrl %0.3f, aclk %0.3f, frontend %0.3f, thread %0.3f", ctrl_ns, aclk_ns,
             frontend_ns, thread_ns);
    /* verilator lint_off ZERODLY */  // set at run time, never 0
    fork
      forever #(ctrl_ns / 2) ctrl_clk = ~ctrl_clk;
      forever #(aclk_ns / 2) aclk = ~aclk;
      forever #(frontend_ns / 2) frontend_clk = ~frontend_clk;
      forever #(thread_ns / 2) thread_clk = ~thread_clk;
    join_none
    /* verilator lint_on ZERODLY */
  end

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
  logic [NUM_OF_THREADS-1:0][31:0] tex_araddr;
  logic [NUM_OF_THREADS-1:0][7:0] tex_arlen;
  logic [NUM_OF_THREADS-1:0][2:0] tex_arsize;
  logic [NUM_OF_THREADS-1:0][1:0] tex_arburst, tex_rresp;
  logic [NUM_OF_THREADS-1:0] tex_arvalid, tex_arready, tex_rlast, tex_rvalid, tex_rready;
  logic [NUM_OF_THREADS-1:0][127:0] tex_rdata;

  gpu_top #(
      .TRIANGLE_STRIDE(TriangleStride),
      .TEXTURE_WINDOW(TextureWindow)
  ) dut (
      .ctrl_clk(ctrl_clk),
      .ctrl_rst_n(ctrl_rst_n),
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

  // Textures (PS DDR): one memory, read through a port per thread's texture cache, one INCR burst
  // of 128-bit beats at a time per port. The low TexAddrW bits of the address select the byte.
  logic [31:0] tex_mem[1 << (TexAddrW - 2)];
  logic [31:0] tex_base;  // +TEXTURE's LUT entry: word address and size code
  logic [3:0] tex_size;
  bit tex_loaded = 1'b0;
  int tex_latency = 64;
  initial void'($value$plusargs("TEX_LATENCY=%d", tex_latency));

  for (genvar lane = 0; lane < NUM_OF_THREADS; lane++) begin : g_tex_port
    logic busy = 1'b0;
    logic [TexAddrW-1:0] addr;
    logic [7:0] beats_left;
    int wait_cycles = 0;  // before the next beat
    logic beat;

    assign beat = busy && wait_cycles == 0;
    assign tex_arready[lane] = !busy;
    assign tex_rvalid[lane] = beat;
    assign tex_rlast[lane] = beat && beats_left == 0;
    assign tex_rresp[lane] = 2'b00;
    for (genvar w = 0; w < 4; w++) begin : g_word
      assign tex_rdata[lane][32*w+:32] = tex_mem[{addr[TexAddrW-1:4], 2'(w)}];
    end

    always @(posedge thread_clk) begin
      if (tex_arvalid[lane] && tex_arready[lane]) begin
        if (tex_araddr[lane][31:27] != TextureWindow[31:27])
          error($sformatf("thread %0d texture read at %08h, outside TEXTURE_WINDOW %08h", lane,
                          tex_araddr[lane], TextureWindow));
        if (tex_arsize[lane] != 3'd4 || tex_arburst[lane] != 2'b01)
          error($sformatf("thread %0d texture read: size %0d, burst %0d, expected 16-byte INCR",
                          lane, tex_arsize[lane], tex_arburst[lane]));
        busy <= 1'b1;
        addr <= tex_araddr[lane][TexAddrW-1:0];
        beats_left <= tex_arlen[lane];
        wait_cycles <= tex_latency;
      end else if (busy && wait_cycles != 0) begin
        wait_cycles <= wait_cycles - 1;
      end else if (beat && tex_rready[lane]) begin
        addr <= addr + TexAddrW'(16);
        beats_left <= beats_left - 8'd1;
        busy <= beats_left != 0;
        wait_cycles <= $urandom_range(3) == 0 ? int'($urandom_range(4, 1)) : 0;
      end
    end
  end

  // The texture: its word address and size code (log2 of its width) in hex on the first line, then
  // its words, in memory order.
  task automatic load_texture(input string path);
    int fd, n;
    logic [31:0] word;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "cannot open texture %s", path);
    if ($fscanf(fd, "%h %h", tex_base, tex_size) != 2)
      $fatal(1, "texture %s: no word address and size code", path);
    n = 0;
    while ($fscanf(fd, "%h", word) == 1) begin
      if (tex_base + 32'(n) >= 32'(1 << (TexAddrW - 2)))
        $fatal(1, "texture %s: beyond the %0d-byte texture memory", path, 1 << TexAddrW);
      tex_mem[tex_base+32'(n)] = word;
      n++;
    end
    $fclose(fd);
    tex_loaded = 1'b1;
    $display("texture %s: %0d words at word %08h, size code %0d", path, n, tex_base, tex_size);
  endtask

  // -------------------------------------------------------------------------
  // Scene: triangles, their tile masks, and what each tile must receive
  // -------------------------------------------------------------------------

  int triangles;
  logic [767:0] records[];
  logic [63:0] tile_mask[];  // the triangle's visibility word: bit t set if tile t gets it
  frontend_data_in_t expected[];

  // The scene: per line, the visibility word, then the record as 24 words in memory order.
  task automatic load_scene(input string path);
    int fd;
    logic [63:0] mask;
    logic [31:0] word;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "cannot open scene %s (make gpu_top_scene in dv/raster_sw)", path);
    records = new[MaxTriangles];
    tile_mask = new[MaxTriangles];
    triangles = 0;
    while ($fscanf(fd, "%h", mask) == 1) begin
      if (triangles == MaxTriangles)
        $fatal(1, "scene %s: more than %0d triangles", path, MaxTriangles);
      tile_mask[triangles] = mask;
      for (int w = 0; w < 24; w++) begin
        if ($fscanf(fd, "%h", word) != 1)
          $fatal(1, "scene %s: triangle %0d is short", path, triangles);
        records[triangles][32*w+:32] = word;
      end
      triangles++;
    end
    $fclose(fd);
    records = new[triangles] (records);
    tile_mask = new[triangles] (tile_mask);
    $display("scene %s: %0d triangles", path, triangles);
  endtask

  // The record as the core must receive it, through the RTL's own unpack.
  logic [767:0] unpack_in;
  frontend_data_in_t unpack_out;
  triangle_unpack u_expected_unpack (
      .packed_triangle(unpack_in),
      .triangle(unpack_out)
  );

  task automatic build_scene(input string scene_path);
    logic [31:0] addr;
    logic [7:0] value;
    load_scene(scene_path);
    expected = new[triangles];
    for (int t = 0; t < triangles; t++) begin
      unpack_in = records[t];
      #1;
      expected[t] = unpack_out;
    end
    // Triangles every TriangleStride bytes; the gap after each record is filled with noise.
    for (int t = 0; t < triangles; t++) begin
      for (int b = 0; b < TriangleStride; b++) begin
        addr = TriBase + 32'(t * TriangleStride + b);
        value = b < 96 ? records[t][8*b+:8] : 8'($urandom());
        u_tri_ram.mem[addr[TriAddrW-1:6]][8*addr[5:0]+:8] = value;
      end
    end
    // One 64-bit tile mask per triangle, two per 128-bit word.
    for (int t = 0; t < triangles; t += 2) begin
      addr = VbBase + 32'(8 * t);
      u_vb_ram.mem[addr[VbAddrW-1:4]] = {t + 1 < triangles ? tile_mask[t+1] : 64'd0, tile_mask[t]};
    end
  endtask

  // -------------------------------------------------------------------------
  // Frame buffers and z-buffers
  // -------------------------------------------------------------------------

  // The tile DMA's CLEAR: color into every frame buffer word, STATUS.CLEAR_BUSY until done. The
  // write-backs then leave CLEAR_VALUE behind them.
  task automatic clear_frame_buffers(input logic [31:0] color);
    axi_write(TileClearValue, color);
    axi_write(TileCtrl, 32'h8);  // CLEAR
    expect_read(TileStatus, 32'h10, 32'h10, "tile DMA CLEAR_BUSY after CLEAR");
    wait_bits(TileStatus, 32'h10, 32'h0, "tile DMA CLEAR_BUSY");
  endtask

  // Through the thread registers: ZBUF_CLEAR reads 1 until the clear is done.
  task automatic clear_zbuffers();
    for (int lane = 0; lane < NUM_OF_THREADS; lane++) axi_write(thread_reg(lane, 4), 32'h1);
    repeat (8) @(posedge ctrl_clk);  // the clear pulse crosses into the thread clock
    for (int lane = 0; lane < NUM_OF_THREADS; lane++)
      wait_bits(thread_reg(lane, 4), 32'h1, 32'h0, $sformatf("thread %0d z-buffer clear", lane));
  endtask

  // -------------------------------------------------------------------------
  // Triangle monitor at the core's input
  // -------------------------------------------------------------------------

  int current_tile = -1;
  int received, errors;
  int tile_order[$];
  bit monitor_on = 1'b1;
  bit cp_mode = 1'b0;  // the tile from the frontend, not from render_tile
  int cp_received, cp_expected;  // the command processor's frame, all tiles

  function automatic void open_tile(input int tile);
    tile_order.delete();
    for (int t = 0; t < triangles; t++) if (tile_mask[t][tile]) tile_order.push_back(t);
    received = 0;
    current_tile = tile;
  endfunction

  function automatic void close_tile();
    if (current_tile >= 0 && received != tile_order.size())
      error($sformatf("tile %0d: the core received %0d triangles, expected %0d", current_tile,
                      received, tile_order.size()));
  endfunction

  always @(posedge frontend_clk) begin
    if (monitor_on && frontend_rst_n && !dut.tri_cdc_empty && dut.core_tri_ready) begin
      if (cp_mode) begin
        int tile;
        tile = int'(dut.u_core.u_frontend.bb_min_y) / TILE_SIZE_Y * TilesX +
            int'(dut.u_core.u_frontend.bb_min_x) / TILE_SIZE_X;
        if (tile != current_tile) begin
          close_tile();
          open_tile(tile);
        end
        cp_received++;
      end
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

  // The command processor's idle flags after the visibility DMA's done (from its acknowledge to
  // the next tile's start): every unit empty for some cycles, then one busy again is a triangle
  // between two units that no flag showed. The longest such run, against the CP's idle window.
  int cp_idle_run, cp_false_idle_max;
  always @(posedge ctrl_clk) begin
    if (dut.u_cp.frame_sequencer_stateReg < 4'd4) cp_idle_run <= 0;  // up to visWait
    else if (dut.u_cp.frame_unitsIdle) cp_idle_run <= cp_idle_run + 1;
    else begin
      if (cp_idle_run > cp_false_idle_max) cp_false_idle_max <= cp_idle_run;
      cp_idle_run <= 0;
    end
  end

  // -------------------------------------------------------------------------
  // CPU port
  // -------------------------------------------------------------------------

  task automatic axi_write(input logic [11:0] addr, input logic [31:0] data);
    bit aw_done, w_done;
    @(posedge ctrl_clk);
    awaddr <= addr;
    awvalid <= 1'b1;
    wdata <= data;
    wvalid <= 1'b1;
    aw_done = 0;
    w_done = 0;
    while (!(aw_done && w_done)) begin
      @(posedge ctrl_clk);
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
    do @(posedge ctrl_clk); while (!bvalid);
    bready <= 1'b0;
    if (bresp != 2'b00) error($sformatf("write 0x%03h: BRESP %0d", addr, bresp));
  endtask

  task automatic axi_read(input logic [11:0] addr, output logic [31:0] data);
    @(posedge ctrl_clk);
    araddr  <= addr;
    arvalid <= 1'b1;
    do @(posedge ctrl_clk); while (!arready);
    arvalid <= 1'b0;
    rready  <= 1'b1;
    do @(posedge ctrl_clk); while (!rvalid);
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
    axi_write(FrontendBbMinX, 32'h183);
    expect_read(FrontendBbMinX, 32'hFFF, 32'h183, "frontend BB_MIN_X");
    axi_write(FrontendBbMinX, 32'd0);
    expect_read(FrontendStatus, 32'h7, 32'h7, "frontend status, idle");
    for (int lane = 0; lane < NUM_OF_THREADS; lane++)
      expect_read(thread_reg(lane, 0), 32'h1, 32'h0, $sformatf("thread %0d busy", lane));
    axi_write(LutBase + 12'h8, 32'hCAFE_0000);
    expect_read(LutBase + 12'h8, 32'hFFFF_FFFF, 32'hCAFE_0000, "texture LUT base 2");
    axi_write(VisTriCount, 32'd1234);
    expect_read(VisTriCount, 32'hFFFF_FFFF, 32'd1234, "visibility DMA TRI_COUNT");
    axi_write(TileStride, 32'h0000_0400);
    expect_read(TileStride, 32'hFFFF_FFFF, 32'h0000_0400, "tile DMA STRIDE");
    expect_read(TileClearValue, 32'hFFFF_FFFF, 32'h0, "tile DMA CLEAR_VALUE after reset");
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

  // The last pixel of tile t's box: the tile's own, or the screen's when the tile runs past it
  function automatic logic [31:0] box_end(input int t, input int tile_size, input int size);
    return 32'((t + 1) * tile_size - 1 < size ? (t + 1) * tile_size - 1 : size - 1);
  endfunction

  task automatic render_tile(input int tx, input int ty);
    int tile;
    tile = ty * TilesX + tx;
    open_tile(tile);

    clear_zbuffers();

    axi_write(FrontendBbMinX, tx * TILE_SIZE_X);
    axi_write(FrontendBbMinY, ty * TILE_SIZE_Y);
    axi_write(FrontendBbMaxX, box_end(tx, TILE_SIZE_X, Width));
    axi_write(FrontendBbMaxY, box_end(ty, TILE_SIZE_Y, Height));

    axi_write(VisVbBase, VbBase);
    axi_write(VisTriBase, TriBase);
    axi_write(VisTriCount, triangles);
    axi_write(VisTileIndex, tile);
    axi_write(VisStatus, 32'h2);  // DONE left by an earlier tile or frame cleared
    axi_write(VisCtrl, 32'h1);  // START
    wait_bits(VisStatus, 32'h2, 32'h2, "visibility DMA DONE");
    expect_read(VisStatus, 32'h64, 32'h0, "visibility DMA error flags");
    axi_write(VisStatus, 32'h2);  // clear DONE

    wait_core_idle();
    if (received != tile_order.size())
      error($sformatf("tile %0d: the core received %0d triangles, expected %0d", tile, received,
                      tile_order.size()));

    write_back_tile(tx, ty);
    $display("[%0t] tile (%0d, %0d): %0d triangles", $time, tx, ty, received);
  endtask

  // The tile DMA: the frame buffers to tile (tx, ty) of the image.
  task automatic write_back_tile(input int tx, input int ty);
    axi_write(TileBase, ImgBase);
    axi_write(TileStride, RowBytes);
    axi_write(TileTilesX, TilesX);
    axi_write(TileTilesY, TilesY);
    axi_write(TileCur, {16'(ty), 16'(tx)});
    axi_write(TileIrqClear, 32'h1);  // done left by an earlier tile (the command processor's)
    axi_write(TileCtrl, 32'h1);  // START
    wait_bits(TileIrqRaw, 32'h1, 32'h1, "tile DMA done");
    axi_write(TileIrqClear, 32'h1);
    expect_read(TileStatus, 32'h1, 32'h0, "tile DMA BUSY after done");
  endtask

  // Each write-back left CLEAR_VALUE behind it: a second write-back of the first tile, with nothing
  // rendered in between, reads only that.
  task automatic check_cleared();
    int bad;
    write_back_tile(0, 0);
    bad = 0;
    for (int y = 0; y < TILE_SIZE_Y; y++)
      for (int x = 0; x < TILE_SIZE_X; x++)
        if (image_pixel(x, y) !== ClearColor) begin
          if (bad < 8)
            error($sformatf("after the write-back, pixel (%0d, %0d): %08h, expected %08h", x, y,
                            image_pixel(x, y), ClearColor));
          bad++;
        end
    $display("[%0t] frame buffers after a write-back: %0d of %0d pixels not the clear value",
             $time, bad, TILE_SIZE_X * TILE_SIZE_Y);
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
  // Command processor
  // -------------------------------------------------------------------------

  logic [31:0] cpu_image[Height][Width];  // the per-tile frame, to compare with

  task automatic cp_wait_stopped(output logic [31:0] status);
    int polls;
    polls = 0;
    do begin
      axi_read(CpStatus, status);
      if (++polls > 200000) $fatal(1, "command processor: still busy, STATUS %08h", status);
    end while (status[0]);
  endtask

  task automatic expect_cp(input logic [31:0] mask, input logic [31:0] value, input string what);
    expect_read(CpStatus, mask, value, $sformatf("command processor STATUS: %s", what));
  endtask

  // The frame, set up as the CPU does it for the command processor: the DMAs' events cleared and
  // their frame registers at tile 0 (the visibility DMA's tile count too: it moves on by itself),
  // the frame buffers and z-buffers cleared, tile 0's box
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
    axi_write(TileCtrl, 32'h2);  // RESET_POS: tile (0, 0)
    clear_frame_buffers(ClearColor);
    clear_zbuffers();
    axi_write(FrontendBbMinX, 32'h0);
    axi_write(FrontendBbMinY, 32'h0);
    axi_write(FrontendBbMaxX, box_end(0, TILE_SIZE_X, Width));
    axi_write(FrontendBbMaxY, box_end(0, TILE_SIZE_Y, Height));
    axi_write(CpSize, {16'(Height), 16'(Width)});
  endtask

  task automatic cp_checks();
    logic [31:0] status, data;
    int polls;

    // MODE 0: START does nothing
    axi_write(CpMode, 32'h0);
    axi_write(CpCtrl, 32'h1);
    repeat (20) @(posedge ctrl_clk);
    expect_cp(32'h7, 32'h0, "after START in MODE 0");

    // A size of 0: ERROR, CAUSE 4, at once
    axi_write(CpMode, 32'h1);
    axi_write(CpSize, 32'h0);
    axi_write(CpCtrl, 32'h1);
    cp_wait_stopped(status);
    expect_cp(32'h77, 32'h44, "after START with a size of 0");

    // Mid-frame: MODE kept, then SOFT_RESET back to idle
    monitor_on = 1'b0;
    cp_program();
    axi_write(CpCtrl, 32'h1);
    polls = 0;
    do begin
      axi_read(CpStatus, status);
      if (++polls > 200000) $fatal(1, "command processor: never reached tile 2");
    end while (status[13:8] < 2);
    axi_write(CpMode, 32'h0);
    expect_read(CpMode, 32'h1, 32'h1, "command processor MODE written while busy");
    axi_write(CpCtrl, 32'h2);  // SOFT_RESET
    repeat (10) @(posedge ctrl_clk);
    expect_cp(32'h3F07, 32'h0, "after SOFT_RESET");
    // The units finish what they had
    wait_bits(VisStatus, 32'h1, 32'h0, "visibility DMA BUSY after SOFT_RESET");
    wait_bits(TileStatus, 32'h1, 32'h0, "tile DMA BUSY after SOFT_RESET");
    wait_core_idle();
    monitor_on = 1'b1;
    $display("[%0t] command processor: START in MODE 0, size 0, MODE while busy, SOFT_RESET",
             $time);
  endtask

  task automatic cp_frame();
    logic [31:0] status, cycles;
    int wrong, past_screen;

    for (int y = 0; y < Height; y++)
      for (int x = 0; x < Width; x++) cpu_image[y][x] = image_pixel(x, y);
    // Every word of the image overwritten, or it shows
    for (int i = 0; i < (1 << (ImgAddrW - 4)); i++) u_img_ram.mem[i] = {4{32'hDEAD_BEEF}};

    cp_program();
    axi_write(CpMode, 32'h1);
    current_tile = -1;
    cp_received = 0;
    cp_false_idle_max = 0;
    cp_expected = 0;
    for (int tile = 0; tile < TilesX * TilesY; tile++)
      for (int t = 0; t < triangles; t++) if (tile_mask[t][tile]) cp_expected++;
    cp_mode = 1'b1;
    axi_write(CpCtrl, 32'h1);
    cp_wait_stopped(status);
    cp_mode = 1'b0;
    close_tile();
    axi_read(CpCycles, cycles);
    $display("[%0t] command processor: frame in %0d cycles, STATUS %08h", $time, cycles, status);
    $display("[%0t] command processor: longest false idle %0d cycles", $time, cp_false_idle_max);
    expect_cp(32'h76, 32'h2, "after the frame");
    if (cp_received != cp_expected)
      error($sformatf("command processor frame: the core received %0d triangles, expected %0d",
                      cp_received, cp_expected));
    expect_read(TileIrqRaw, 32'h4, 32'h4, "tile DMA frame_done after the frame");
    expect_read(VisIrqRaw, 32'h4, 32'h4, "visibility DMA frame_done after the frame");
    expect_read(VisTileIndex, 32'h3F, 32'h0, "visibility DMA TILE_INDEX after the frame (wrapped)");

    wrong = 0;
    for (int y = 0; y < Height; y++)
      for (int x = 0; x < Width; x++)
        if (image_pixel(x, y) !== cpu_image[y][x]) begin
          if (wrong < 8)
            error($sformatf("command processor frame, pixel (%0d, %0d): %08h, per tile %08h", x,
                            y, image_pixel(x, y), cpu_image[y][x]));
          wrong++;
        end
    past_screen = 0;
    for (int y = Height; y < TilesY * TILE_SIZE_Y; y++)
      for (int x = 0; x < Width; x++)
        if (image_pixel(x, y) !== ClearColor) begin
          if (past_screen < 8)
            error($sformatf("command processor frame, pixel (%0d, %0d) past the screen: %08h", x,
                            y, image_pixel(x, y)));
          past_screen++;
        end
    $display("[%0t] command processor frame: %0d of %0d pixels unlike the per-tile frame",
             $time, wrong, Width * Height);
    $display("[%0t] command processor frame: %0d pixels past the screen not the clear color",
             $time, past_screen);
  endtask

  initial begin : run
    string out_path, scene_path, texture_path;
    out_path = "gpu_top.tga";
    scene_path = "gpu_top_scene.hex";
    void'($value$plusargs("OUT=%s", out_path));
    void'($value$plusargs("SCENE=%s", scene_path));
    errors = 0;

    #20;  // after axi_ram's own initial blocks
    build_scene(scene_path);
    if ($value$plusargs("TEXTURE=%s", texture_path)) load_texture(texture_path);
    repeat (10) @(posedge ctrl_clk);
    ctrl_rst_n = 1;
    aresetn = 1;
    frontend_rst_n = 1;
    thread_rst_n = 1;
    repeat (10) @(posedge ctrl_clk);

    register_access();
    if (tex_loaded) begin
      axi_write(LutBase, tex_base);
      axi_write(LutSize, 32'(tex_size));
    end
    clear_frame_buffers(ClearColor);
    for (int ty = 0; ty < TilesY; ty++)
      for (int tx = 0; tx < TilesX; tx++) render_tile(tx, ty);
    cp_checks();
    cp_frame();
    $display("[%0t] image not checked here (make compares it with raster_sw's)", $time);
    write_tga(out_path);
    check_cleared();
    if (tri_err) error("triangle DMA reported an error");

    if (errors == 0) $display("PASS: %0d tiles, %0d triangles, wrote %s", TilesX * TilesY,
                              triangles, out_path);
    else $display("FAIL: %0d errors", errors);
    $finish;
  end

  initial begin
    #50ms;
    $fatal(1, "testbench timeout");
  end
endmodule
