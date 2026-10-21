`timescale 1ns / 1ps

import gpu_types_pkg::*;

// Renders raster_sw's raster core CSV (--raster-core-csv) through the whole raster core and writes
// the frame as a TGA. Runs on Verilator and Icarus (behavioural FP models, Makefile) and on xsim
// (Xilinx FP IP, Makefile.vivado).
//
// The CSV rows are grouped by bin. For each bin:
//   1. set the frontend's tile registers over APB
//   2. stream the bin's triangles into the frontend
//   3. wait until the frontend, the orchestrator and all four threads report empty
//   4. read the four frame buffer slices back through the host ports into the frame
//   5. fill the frame buffers with the clear colour and clear the z-buffers for the next bin
// Bins without triangles keep the clear colour, as in raster_sw.
//
// Texture 0 comes from +TEXTURE, an uncompressed 24- or 32-bit TGA, square and a power of two. It
// is stored Morton-ordered at word address 0 (as texture_address_generator addresses it), in one
// AXI RAM per thread read master, and the texture table is programmed over APB. Without +TEXTURE,
// textured triangles are drawn untextured (COLOR) and the texture ports stay idle.
//
// Plusargs: +INPUTS=<csv> (default raster_core_inputs.csv), +TEXTURE=<tga> (default none),
//           +OUT=<tga> (default raster_core.tga)
module tb_raster_core #(
    parameter int WIDTH  = 1280,
    parameter int HEIGHT = 720
);
  localparam int Lanes = NUM_OF_THREADS;
  localparam int HostWords = 1 << (PIXEL_ADDR_W_THREAD - 1);
  localparam int HostReadLatency = 4;  // frame_buffer_ram: data 4 cycles after r1_en
  localparam logic [31:0] ClearColor = 32'hFF636363;  // raster_sw's clear colour (ARGB)
  localparam int WaitLimit = 200000;  // cycles before a wait is declared hung

  // APB slaves: 0..3 thread register blocks, 4 frontend, 5 texture table.
  localparam int ApbFrontend = 4, ApbLut = 5;
  localparam logic [ApbLut:0] SelThreads = {{(ApbLut + 1 - Lanes) {1'b0}}, {Lanes{1'b1}}};
  localparam logic [9:0] RegFrontendStatus = 10'h00, RegTileX = 10'h04, RegTileY = 10'h08;
  localparam logic [9:0] RegThreadBusy = 10'h00, RegZbufClear = 10'h04, RegCacheFlush = 10'h10;
  localparam logic [9:0] RegLutBase = 10'h000, RegLutSize = 10'h200;  // + 4 * texture id

  // Texture memory: byte addresses, 128-bit beats of four texels.
  localparam int TexId = 0;
  localparam int MaxTexLog2 = 8;  // up to 256 x 256 texels
  localparam int TexAxiAddrW = 2 * MaxTexLog2 + 2;
  localparam int TexBeats = 1 << (TexAxiAddrW - 4);

  // -------------------------------------------------------------------------
  // Clocks and DUT
  // -------------------------------------------------------------------------

  // The frontend and the threads share one clock; the CDC FIFOs work with related clocks too.
  logic clk = 1'b0, apb_clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;
  always #10 apb_clk = ~apb_clk;

  logic valid_in = 1'b0, ready_out;
  frontend_data_in_t in_data = '0;

  logic [9:0] apb_addr = '0;
  logic [31:0] apb_wdata = '0;
  logic apb_write = 1'b0, apb_enable = 1'b0;
  logic [ApbLut:0] apb_sel = '0;

  logic s_apb_frontend_PREADY, s_apb_frontend_PSLVERROR;
  logic [31:0] s_apb_frontend_PRDATA;
  logic [Lanes-1:0] s_apb_thread_PREADY, s_apb_thread_PSLVERROR;
  logic [Lanes-1:0][31:0] s_apb_thread_PRDATA;
  logic [Lanes-1:0][7:0] s_apb_thread_PADDR;
  logic [Lanes-1:0][31:0] s_apb_thread_PWDATA;
  logic s_apb_lut_PREADY, s_apb_lut_PSLVERROR;
  logic [31:0] s_apb_lut_PRDATA;

  logic [Lanes-1:0] fb_wr_en = '0, fb_rd_en = '0;
  logic [PIXEL_ADDR_W_THREAD-2:0] fb_addr = '0;  // one host address for all four slices
  logic [63:0] fb_wr_data = '0;
  logic [Lanes-1:0][63:0] fb_rd_data;

  logic [Lanes-1:0][31:0] tex_m_axi_araddr;
  logic [Lanes-1:0][7:0] tex_m_axi_arlen;
  logic [Lanes-1:0][2:0] tex_m_axi_arsize;
  logic [Lanes-1:0][1:0] tex_m_axi_arburst;
  logic [Lanes-1:0] tex_m_axi_arvalid, tex_m_axi_rready;
  logic [Lanes-1:0] tex_m_axi_arready, tex_m_axi_rvalid, tex_m_axi_rlast;
  logic [Lanes-1:0][127:0] tex_m_axi_rdata;
  logic [Lanes-1:0][1:0] tex_m_axi_rresp;

  for (genvar lane = 0; lane < Lanes; lane++) begin : g_apb_fanout
    assign s_apb_thread_PADDR[lane]  = apb_addr[7:0];
    assign s_apb_thread_PWDATA[lane] = apb_wdata;
  end

  raster_core dut (
      .frontend_clk(clk),
      .frontend_rst_n(rst_n),
      .thread_clk(clk),
      .thread_rst_n(rst_n),
      .apb_clk(apb_clk),
      .apb_rst_n(rst_n),
      .valid_in(valid_in),
      .ready_out(ready_out),
      .in_data(in_data),
      .s_apb_frontend_PADDR(apb_addr[4:0]),
      .s_apb_frontend_PSEL(apb_sel[ApbFrontend]),
      .s_apb_frontend_PENABLE(apb_enable),
      .s_apb_frontend_PREADY(s_apb_frontend_PREADY),
      .s_apb_frontend_PWRITE(apb_write),
      .s_apb_frontend_PWDATA(apb_wdata),
      .s_apb_frontend_PRDATA(s_apb_frontend_PRDATA),
      .s_apb_frontend_PSLVERROR(s_apb_frontend_PSLVERROR),
      .s_apb_thread_PADDR(s_apb_thread_PADDR),
      .s_apb_thread_PSEL(apb_sel[Lanes-1:0]),
      .s_apb_thread_PENABLE({Lanes{apb_enable}}),
      .s_apb_thread_PREADY(s_apb_thread_PREADY),
      .s_apb_thread_PWRITE({Lanes{apb_write}}),
      .s_apb_thread_PWDATA(s_apb_thread_PWDATA),
      .s_apb_thread_PRDATA(s_apb_thread_PRDATA),
      .s_apb_thread_PSLVERROR(s_apb_thread_PSLVERROR),
      .s_apb_lut_PADDR(apb_addr),
      .s_apb_lut_PSEL(apb_sel[ApbLut]),
      .s_apb_lut_PENABLE(apb_enable),
      .s_apb_lut_PREADY(s_apb_lut_PREADY),
      .s_apb_lut_PWRITE(apb_write),
      .s_apb_lut_PWDATA(apb_wdata),
      .s_apb_lut_PRDATA(s_apb_lut_PRDATA),
      .s_apb_lut_PSLVERROR(s_apb_lut_PSLVERROR),
      .fb_wr_en(fb_wr_en),
      .fb_wr_addr({Lanes{fb_addr}}),
      .fb_wr_data({Lanes{fb_wr_data}}),
      .fb_rd_en(fb_rd_en),
      .fb_rd_addr({Lanes{fb_addr}}),
      .fb_rd_data(fb_rd_data),
      .tex_m_axi_araddr(tex_m_axi_araddr),
      .tex_m_axi_arlen(tex_m_axi_arlen),
      .tex_m_axi_arsize(tex_m_axi_arsize),
      .tex_m_axi_arburst(tex_m_axi_arburst),
      .tex_m_axi_arvalid(tex_m_axi_arvalid),
      .tex_m_axi_arready(tex_m_axi_arready),
      .tex_m_axi_rdata(tex_m_axi_rdata),
      .tex_m_axi_rresp(tex_m_axi_rresp),
      .tex_m_axi_rvalid(tex_m_axi_rvalid),
      .tex_m_axi_rready(tex_m_axi_rready),
      .tex_m_axi_rlast(tex_m_axi_rlast)
  );

  // -------------------------------------------------------------------------
  // Texture memory
  // -------------------------------------------------------------------------

  int tex_log2 = -1;  // -1: no texture loaded
  bit tex_loaded = 0;
  logic [127:0] tex_beats[TexBeats];

  for (genvar lane = 0; lane < Lanes; lane++) begin : g_tex_ram
    axi_ram #(
        .DATA_WIDTH(128),
        .ADDR_WIDTH(TexAxiAddrW),
        .ID_WIDTH(1),
        .PIPELINE_OUTPUT(0)
    ) u_ram (
        .clk(clk),
        .rst(~rst_n),
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
        .s_axi_arid('0),
        .s_axi_araddr(tex_m_axi_araddr[lane][TexAxiAddrW-1:0]),
        .s_axi_arlen(tex_m_axi_arlen[lane]),
        .s_axi_arsize(tex_m_axi_arsize[lane]),
        .s_axi_arburst(tex_m_axi_arburst[lane]),
        .s_axi_arlock('0),
        .s_axi_arcache('0),
        .s_axi_arprot('0),
        .s_axi_arvalid(tex_m_axi_arvalid[lane]),
        .s_axi_arready(tex_m_axi_arready[lane]),
        .s_axi_rid(),
        .s_axi_rdata(tex_m_axi_rdata[lane]),
        .s_axi_rresp(tex_m_axi_rresp[lane]),
        .s_axi_rlast(tex_m_axi_rlast[lane]),
        .s_axi_rvalid(tex_m_axi_rvalid[lane]),
        .s_axi_rready(tex_m_axi_rready[lane])
    );

    // Copied in once the image is loaded, after axi_ram's own initial block has zeroed it.
    initial begin
      wait (tex_loaded);
      for (int beat = 0; beat < TexBeats; beat++) u_ram.mem[beat] = tex_beats[beat];
    end
  end

  // Reads must stay inside the loaded texture; with no texture there must be none.
  always @(posedge clk) begin
    for (int lane = 0; lane < Lanes; lane++)
      if (rst_n && tex_m_axi_arvalid[lane] &&
          (tex_log2 < 0 || tex_m_axi_araddr[lane] >= (32'd4 << (2 * tex_log2))))
        $fatal(1, "thread %0d texture read at 0x%08h outside the texture", lane,
               tex_m_axi_araddr[lane]);
  end

  function automatic int morton(input int x, input int y);
    int m;
    m = 0;
    for (int b = 0; b < MaxTexLog2; b++) begin
      m |= ((x >> b) & 1) << (2 * b);
      m |= ((y >> b) & 1) << (2 * b + 1);
    end
    return m;
  endfunction

  // Texel (x, y) of the image, y = 0 the top row, goes to word morton(x, y): texture_address_generator
  // interleaves x (from u) into the even address bits and y (from v) into the odd ones.
  logic [31:0] texels[1 << (2 * MaxTexLog2)];

  task automatic load_texture(input string path);
    int fd, w, h, bpp, desc, y;
    int header[18];
    int c[4];
    fd = $fopen(path, "rb");
    if (fd == 0) $fatal(1, "cannot open texture %s", path);
    for (int i = 0; i < 18; i++) header[i] = $fgetc(fd);
    w = header[12] | (header[13] << 8);
    h = header[14] | (header[15] << 8);
    bpp = header[16];
    desc = header[17];
    if (header[1] != 0 || header[2] != 2 || (bpp != 24 && bpp != 32))
      $fatal(1, "%s: need an uncompressed 24- or 32-bit true-colour TGA", path);
    if (w != h || (w & (w - 1)) != 0 || w > (1 << MaxTexLog2))
      $fatal(1, "%s is %0dx%0d: need a square power of two up to %0d", path, w, h,
             1 << MaxTexLog2);
    for (int i = 0; i < header[0]; i++) void'($fgetc(fd));  // image id
    for (int row = 0; row < h; row++) begin
      y = ((desc >> 5) & 1) ? row : h - 1 - row;  // descriptor bit 5: top-left origin
      for (int x = 0; x < w; x++) begin
        c[0] = $fgetc(fd);  // B, G, R, (A)
        c[1] = $fgetc(fd);
        c[2] = $fgetc(fd);
        c[3] = (bpp == 32) ? $fgetc(fd) : 255;
        if (c[0] < 0 || c[1] < 0 || c[2] < 0 || c[3] < 0) $fatal(1, "%s is truncated", path);
        texels[morton(x, y)] = {8'(c[3]), 8'(c[2]), 8'(c[1]), 8'(c[0])};
      end
    end
    $fclose(fd);
    for (int beat = 0; beat < TexBeats; beat++)
      tex_beats[beat] = {texels[4*beat+3], texels[4*beat+2], texels[4*beat+1], texels[4*beat]};
    tex_log2 = $clog2(w);
    tex_loaded = 1;
    $display("texture %s: %0dx%0d, %0d bpp", path, w, h, bpp);
  endtask

  // -------------------------------------------------------------------------
  // APB
  // -------------------------------------------------------------------------

  function automatic logic [31:0] apb_rdata(input int slave);
    if (slave == ApbFrontend) return s_apb_frontend_PRDATA;
    if (slave == ApbLut) return s_apb_lut_PRDATA;
    return s_apb_thread_PRDATA[slave];
  endfunction

  function automatic logic apb_error(input int slave);
    if (slave == ApbFrontend) return s_apb_frontend_PSLVERROR;
    if (slave == ApbLut) return s_apb_lut_PSLVERROR;
    return s_apb_thread_PSLVERROR[slave];
  endfunction

  // sel is a mask of slaves, so one write can reach all four threads.
  task automatic apb_write_sel(input logic [ApbLut:0] sel, input logic [9:0] addr,
                               input logic [31:0] data);
    @(posedge apb_clk);
    apb_addr <= addr;
    apb_wdata <= data;
    apb_write <= 1'b1;
    apb_sel <= sel;
    apb_enable <= 1'b0;
    @(posedge apb_clk);
    apb_enable <= 1'b1;
    @(posedge apb_clk);
    apb_sel <= '0;
    apb_enable <= 1'b0;
    apb_write <= 1'b0;
  endtask

  task automatic apb_read(input int slave, input logic [9:0] addr, output logic [31:0] data);
    @(posedge apb_clk);
    apb_addr <= addr;
    apb_write <= 1'b0;
    apb_sel <= 1 << slave;
    apb_enable <= 1'b0;
    @(posedge apb_clk);
    apb_enable <= 1'b1;
    @(negedge apb_clk);
    data = apb_rdata(slave);
    if (apb_error(slave)) $fatal(1, "APB read of slave %0d, 0x%02h returned an error", slave, addr);
    @(posedge apb_clk);
    apb_sel <= '0;
    apb_enable <= 1'b0;
  endtask

  task automatic clear_zbuffers();
    logic [31:0] data;
    int polls;
    apb_write_sel(SelThreads, RegZbufClear, 32'h1);
    repeat (5) @(posedge apb_clk);
    for (int lane = 0; lane < Lanes; lane++) begin
      polls = 0;
      do begin
        apb_read(lane, RegZbufClear, data);
        if (++polls > WaitLimit / 10) $fatal(1, "thread %0d z-buffer clear never finished", lane);
      end while (data[0] !== 1'b0);
    end
  endtask

  task automatic set_tile(input int tile_x, input int tile_y);
    logic [31:0] data;
    apb_write_sel(1 << ApbFrontend, RegTileX, tile_x);
    apb_write_sel(1 << ApbFrontend, RegTileY, tile_y);
    apb_read(ApbFrontend, RegTileX, data);
    if (data[4:0] !== tile_x[4:0]) $fatal(1, "tile X readback %0d, expected %0d", data[4:0], tile_x);
    apb_read(ApbFrontend, RegTileY, data);
    if (data[4:0] !== tile_y[4:0]) $fatal(1, "tile Y readback %0d, expected %0d", data[4:0], tile_y);
    repeat (16) @(posedge clk);  // the tile index crosses into the frontend clock
  endtask

  // Valid lines in each thread's texture cache, peeked from the tag store.
  int cache_valid_lines[Lanes];

  for (genvar lane = 0; lane < Lanes; lane++) begin : g_cache_probe
    always @(posedge clk) begin
      int n;
      n = 0;
      for (int way = 0;
           way < $size(dut.g_thread[lane].u_thread.u_l1_texture_cache.u_cache_tags.valid_mem);
           way++)
        n += int'(dut.g_thread[lane].u_thread.u_l1_texture_cache.u_cache_tags.valid_mem[way]);
      cache_valid_lines[lane] <= n;
    end
  end

  // Only while the core is idle: a flush drops in-flight cache requests and refills. Returns the
  // number of lines that were valid, and checks that none is left.
  task automatic flush_texture_caches(output int flushed);
    flushed = 0;
    for (int lane = 0; lane < Lanes; lane++) flushed += cache_valid_lines[lane];
    apb_write_sel(SelThreads, RegCacheFlush, 32'h1);
    repeat (20) @(posedge clk);  // the pulse crosses from the APB clock
    for (int lane = 0; lane < Lanes; lane++)
      if (cache_valid_lines[lane] != 0)
        $fatal(1, "thread %0d: %0d texture cache lines still valid after a flush", lane,
               cache_valid_lines[lane]);
  endtask

  // Texture TexId: base word address 0, log2 of its size; checked by reading both back.
  task automatic program_texture_table();
    logic [31:0] data;
    apb_write_sel(1 << ApbLut, RegLutBase + 10'(4 * TexId), 32'd0);
    apb_write_sel(1 << ApbLut, RegLutSize + 10'(4 * TexId), tex_log2);
    apb_read(ApbLut, RegLutBase + 10'(4 * TexId), data);
    if (data !== 32'd0) $fatal(1, "texture table base readback %h", data);
    apb_read(ApbLut, RegLutSize + 10'(4 * TexId), data);
    if (data[3:0] !== 4'(tex_log2)) $fatal(1, "texture table size readback %h", data);
  endtask

  // True when the frontend (bit 0), the orchestrator (bit 1) and every thread are empty.
  task automatic core_idle(output bit idle);
    logic [31:0] data;
    apb_read(ApbFrontend, RegFrontendStatus, data);
    idle = data[0] === 1'b1 && data[1] === 1'b1;
    for (int lane = 0; lane < Lanes; lane++) begin
      apb_read(lane, RegThreadBusy, data);
      if (data[0] !== 1'b0) idle = 0;
    end
  endtask

  // Two idle polls in a row: a group still crossing a CDC FIFO can look empty for a few cycles.
  task automatic wait_idle();
    bit idle;
    int polls, streak;
    polls = 0;
    streak = 0;
    while (streak < 2) begin
      core_idle(idle);
      streak = idle ? streak + 1 : 0;
      if (++polls > WaitLimit / 20) $fatal(1, "core never went idle");
    end
  endtask

  // -------------------------------------------------------------------------
  // Frame buffer host port and the frame
  // -------------------------------------------------------------------------

  bit [31:0] frame[WIDTH*HEIGHT];
  logic [63:0] host_words[Lanes][HostWords];

  task automatic fill_frame_buffers(input logic [31:0] color);
    for (int a = 0; a < HostWords; a++) begin
      @(negedge clk);
      fb_addr = a;
      fb_wr_data = {color, color};
      fb_wr_en = '1;
    end
    @(negedge clk);
    fb_wr_en = '0;
    repeat (4) @(negedge clk);  // writes land 2 cycles after fb_wr_en
  endtask

  // Pipelined: one read per cycle, the data of read a is on fb_rd_data HostReadLatency cycles later.
  task automatic read_frame_buffers();
    for (int i = 0; i < HostWords + HostReadLatency; i++) begin
      @(negedge clk);
      if (i >= HostReadLatency)
        for (int lane = 0; lane < Lanes; lane++) host_words[lane][i-HostReadLatency] = fb_rd_data[lane];
      fb_addr = (i < HostWords) ? i : 0;
      fb_rd_en = (i < HostWords) ? '1 : '0;
    end
  endtask

  // Checks the read latency once: every word holds its own address before the first bin.
  task automatic check_host_port();
    for (int a = 0; a < HostWords; a++) begin
      @(negedge clk);
      fb_addr = a;
      fb_wr_data = {32'(a), ~32'(a)};
      fb_wr_en = '1;
    end
    @(negedge clk);
    fb_wr_en = '0;
    repeat (4) @(negedge clk);
    read_frame_buffers();
    for (int lane = 0; lane < Lanes; lane++)
      for (int a = 0; a < HostWords; a++)
        if (host_words[lane][a] !== {32'(a), ~32'(a)})
          $fatal(1, "host port check: slice %0d word %0d read %h", lane, a, host_words[lane][a]);
  endtask

  // Thread lane = {y[0], x[0]} of the pixel; its slice address is {quad_y, quad_x}, and host word
  // a holds slice addresses {a, 0} (low half) and {a, 1} (high half).
  task automatic store_tile(input int tile_x, input int tile_y);
    logic [PIXEL_ADDR_W_THREAD-1:0] slice_addr;
    int x, y;
    for (int lane = 0; lane < Lanes; lane++)
      for (int a = 0; a < HostWords; a++)
        for (int half = 0; half < 2; half++) begin
          slice_addr = {a[PIXEL_ADDR_W_THREAD-2:0], half[0]};
          x = tile_x * TILE_SIZE_X + 2 * slice_addr[TILE_ADDR_X-1:0] + lane % 2;
          y = tile_y * TILE_SIZE_Y + 2 * slice_addr[PIXEL_ADDR_W_THREAD-1:TILE_ADDR_X] + lane / 2;
          if (x < WIDTH && y < HEIGHT) frame[y*WIDTH+x] = host_words[lane][a][32*half+:32];
        end
  endtask

  // Uncompressed 32-bit true-colour TGA, top-left origin. An ARGB word is B, G, R, A in memory order.
  task automatic write_tga(input string path);
    int fd;
    fd = $fopen(path, "wb");
    if (fd == 0) $fatal(1, "cannot open %s", path);
    $fwrite(fd, "%c%c%c", 8'd0, 8'd0, 8'd2);  // no image id, no colour map, true colour
    $fwrite(fd, "%c%c%c%c%c", 8'd0, 8'd0, 8'd0, 8'd0, 8'd0);  // colour map spec
    $fwrite(fd, "%c%c%c%c", 8'd0, 8'd0, 8'd0, 8'd0);  // x, y origin
    $fwrite(fd, "%c%c%c%c", WIDTH[7:0], WIDTH[15:8], HEIGHT[7:0], HEIGHT[15:8]);
    $fwrite(fd, "%c%c", 8'd32, 8'h28);  // 32 bpp; 8 alpha bits, top-left origin
    for (int i = 0; i < WIDTH * HEIGHT; i++)
      $fwrite(fd, "%c%c%c%c", frame[i][7:0], frame[i][15:8], frame[i][23:16], frame[i][31:24]);
    $fclose(fd);
  endtask

  // -------------------------------------------------------------------------
  // Triangles
  // -------------------------------------------------------------------------

  function automatic logic [31:0] fp32(input real value);
`ifdef VERILATOR
    return dpi_float_to_bits(value);  // no $shortrealtobits in Verilator; imported by fp_wrappers
`else
    shortreal single_value;
    single_value = value;
    return $shortrealtobits(single_value);
`endif
  endfunction

  // The current CSV row. Module scope: Icarus does not support unpacked arrays as task ports.
  real px[3], py[3], pz[3], pw[3], tu[3], tv[3];
  logic [31:0] vcolor[3];
  int tex_id, mode_u, mode_v, tex_function, sfactor, dfactor, depth_func;
  int textured_skipped = 0;

  function automatic vertex_t vertex(input int i);
    vertex_t v;
    v.position = {fp32(px[i]), fp32(py[i]), fp32(pz[i]), fp32(pw[i])};
    v.color = vcolor[i];
    v.u = fp32(tu[i]);
    v.v = fp32(tv[i]);
    return v;
  endfunction

  task automatic send_triangle();
    int cycles;
    @(negedge clk);
    in_data = '0;
    in_data.v0 = vertex(0);
    in_data.v1 = vertex(1);
    in_data.v2 = vertex(2);
    in_data.texture_mode_u = texture_address_mode_t'(mode_u);
    in_data.texture_mode_v = texture_address_mode_t'(mode_v);
    in_data.sfactor_op = blend_op_t'(sfactor);
    in_data.dfactor_op = blend_op_t'(dfactor);
    in_data.depth_func = depth_func_t'(depth_func);
    if (tex_id[7] || (tex_log2 >= 0 && tex_id == TexId)) begin
      in_data.tex_id = 8'(tex_id);
      in_data.texture_function = fragment_op_t'(tex_function);
    end else begin
      in_data.tex_id = 8'h80;  // its texture is not loaded
      in_data.texture_function = COLOR;
      textured_skipped++;
    end
    valid_in = 1'b1;
    cycles = 0;
    do begin
      @(posedge clk);
      if (++cycles > WaitLimit) $fatal(1, "frontend input stalled");
    end while (!ready_out);
    @(negedge clk);
    valid_in = 1'b0;
  endtask

  // -------------------------------------------------------------------------
  // Test
  // -------------------------------------------------------------------------

  task automatic skip_line(input int fd);
    int c;
    do c = $fgetc(fd); while (c != -1 && c != 10);
  endtask

  bit caches_flushed = 0;

  // The caches are flushed once, after the first bin: they hold lines by then, and the later bins
  // check that refills after a flush return the right texels.
  task automatic finish_bin(input int tile_x, input int tile_y, input int triangles);
    int flushed;
    wait_idle();
    if (!caches_flushed) begin
      flush_texture_caches(flushed);
      caches_flushed = 1;
      $display("[%0t] flushed %0d valid texture cache lines", $time, flushed);
    end
    read_frame_buffers();
    store_tile(tile_x, tile_y);
    fill_frame_buffers(ClearColor);
    clear_zbuffers();
    $display("[%0t] bin (%0d, %0d): %0d triangles", $time, tile_x, tile_y, triangles);
  endtask

  initial begin : run
    string input_path, texture_path, out_path;
    int fd, scanned, id, bin_min_x, bin_min_y;
    int tile_x, tile_y, bin_triangles, bin_count, triangles;

    input_path = "raster_core_inputs.csv";
    texture_path = "";
    out_path = "raster_core.tga";
    void'($value$plusargs("INPUTS=%s", input_path));
    void'($value$plusargs("TEXTURE=%s", texture_path));
    void'($value$plusargs("OUT=%s", out_path));
    fd = $fopen(input_path, "r");
    if (fd == 0) $fatal(1, "cannot open input CSV: %s", input_path);
    skip_line(fd);

    for (int i = 0; i < WIDTH * HEIGHT; i++) frame[i] = ClearColor;

    repeat (10) @(posedge apb_clk);
    if (texture_path != "") load_texture(texture_path);  // after axi_ram zeroes its memory
    rst_n = 1'b1;
    repeat (10) @(posedge apb_clk);

    check_host_port();
    fill_frame_buffers(ClearColor);
    clear_zbuffers();
    if (tex_log2 >= 0) program_texture_table();

    tile_x = -1;
    tile_y = -1;
    bin_triangles = 0;
    bin_count = 0;
    triangles = 0;
    forever begin
      // id, bin_min_x, bin_min_y, then x, y, z, w, u, v, color per vertex, then the render state.
      scanned = $fscanf(fd, "%d,%d,%d,%f,%f,%f,%f,%f,%f,%h,%f,%f,%f,%f,%f,%f,%h,%f,%f,%f,%f,%f,%f,%h,%d,%d,%d,%d,%d,%d,%d\n",
                        id, bin_min_x, bin_min_y,
                        px[0], py[0], pz[0], pw[0], tu[0], tv[0], vcolor[0],
                        px[1], py[1], pz[1], pw[1], tu[1], tv[1], vcolor[1],
                        px[2], py[2], pz[2], pw[2], tu[2], tv[2], vcolor[2],
                        tex_id, mode_u, mode_v, tex_function, sfactor, dfactor, depth_func);
      if (scanned == -1 || (scanned == 0 && $feof(fd))) break;
      if (scanned != 31) $fatal(1, "malformed CSV row after transaction %0d", id);

      if (bin_min_x / TILE_SIZE_X != tile_x || bin_min_y / TILE_SIZE_Y != tile_y) begin
        if (tile_x >= 0) finish_bin(tile_x, tile_y, bin_triangles);
        tile_x = bin_min_x / TILE_SIZE_X;
        tile_y = bin_min_y / TILE_SIZE_Y;
        set_tile(tile_x, tile_y);
        bin_triangles = 0;
        bin_count++;
      end
      send_triangle();
      bin_triangles++;
      triangles++;
    end
    if (tile_x >= 0) finish_bin(tile_x, tile_y, bin_triangles);
    $fclose(fd);

    write_tga(out_path);
    if (textured_skipped)
      $display("NOTE: %0d textured triangles drawn untextured (texture not loaded)",
               textured_skipped);
    $display("PASS: %0d triangles in %0d bins, wrote %s", triangles, bin_count, out_path);
    $finish;
  end
endmodule
