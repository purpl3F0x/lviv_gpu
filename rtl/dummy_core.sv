// Dummy Core
// Copyright (c) 2026 Stavros Avramidis
//
// Stands in for raster_core in gpu_top (same ports) to bring up the DMAs, the register crossbar and
// the CPU flow on hardware without the rasteriser.
//
//  - Registers: the real APBFrontendRegs, ApbThreadRegs and ApbLutRam, so software sees the same
//    map. Writes that would start work (z-buffer clear, cache flush, soft reset) do nothing.
//  - Triangles: not processed. After taking one, ready_out stays low for READY_DELAY cycles, so
//    the stream sees back-pressure. The frontend reports busy until BUSY_CYCLES cycles after the
//    last one, and every thread until BUSY_CYCLES thread cycles after that.
//  - Frame buffer host port: no RAM. A read returns, with the real 4-cycle latency and held until
//    the next read, a pattern for the pixel it addresses: A = 0xFF, R = 2 * x, G = 2 * y (x, y in
//    the tile), B = the number of triangles received since the tile registers last changed
//    (saturating at 255). The image the tile DMA writes then shows the tile addressing, and how many
//    triangles each bin was sent.
//  - Texture masters: idle.

`timescale 1ns / 1ps

import gpu_types_pkg::*;

module dummy_core #(
    parameter int READY_DELAY = 64,
    parameter int BUSY_CYCLES = 128
) (
    // * Clocks and resets * //
    input logic frontend_clk,
    input logic frontend_rst_n,
    input logic thread_clk,
    input logic thread_rst_n,
    input logic apb_clk,
    input logic apb_rst_n,

    // * Triangle input (frontend_clk) * //
    input  logic              valid_in,
    output logic              ready_out,
    input  frontend_data_in_t in_data,

    // * APB: frontend control and status * //
    input  logic [ 4:0] s_apb_frontend_PADDR,
    input  logic        s_apb_frontend_PSEL,
    input  logic        s_apb_frontend_PENABLE,
    output logic        s_apb_frontend_PREADY,
    input  logic        s_apb_frontend_PWRITE,
    input  logic [31:0] s_apb_frontend_PWDATA,
    output logic [31:0] s_apb_frontend_PRDATA,
    output logic        s_apb_frontend_PSLVERROR,

    // * APB: one register block per thread * //
    input  logic [NUM_OF_THREADS-1:0][ 7:0] s_apb_thread_PADDR,
    input  logic [NUM_OF_THREADS-1:0]       s_apb_thread_PSEL,
    input  logic [NUM_OF_THREADS-1:0]       s_apb_thread_PENABLE,
    output logic [NUM_OF_THREADS-1:0]       s_apb_thread_PREADY,
    input  logic [NUM_OF_THREADS-1:0]       s_apb_thread_PWRITE,
    input  logic [NUM_OF_THREADS-1:0][31:0] s_apb_thread_PWDATA,
    output logic [NUM_OF_THREADS-1:0][31:0] s_apb_thread_PRDATA,
    output logic [NUM_OF_THREADS-1:0]       s_apb_thread_PSLVERROR,

    // * APB: texture descriptor table * //
    input  logic [ 9:0] s_apb_lut_PADDR,
    input  logic        s_apb_lut_PSEL,
    input  logic        s_apb_lut_PENABLE,
    output logic        s_apb_lut_PREADY,
    input  logic        s_apb_lut_PWRITE,
    input  logic [31:0] s_apb_lut_PWDATA,
    output logic [31:0] s_apb_lut_PRDATA,
    output logic        s_apb_lut_PSLVERROR,

    // * Frame buffer host port, one slice per thread (thread_clk) * //
    input  logic [NUM_OF_THREADS-1:0]                          fb_wr_en,
    input  logic [NUM_OF_THREADS-1:0][PIXEL_ADDR_W_THREAD-2:0] fb_wr_addr,
    input  logic [NUM_OF_THREADS-1:0][                   63:0] fb_wr_data,
    input  logic [NUM_OF_THREADS-1:0]                          fb_rd_en,
    input  logic [NUM_OF_THREADS-1:0][PIXEL_ADDR_W_THREAD-2:0] fb_rd_addr,
    output logic [NUM_OF_THREADS-1:0][                   63:0] fb_rd_data,

    // * Texture memory, one AXI4 read master per thread (thread_clk) * //
    output logic [NUM_OF_THREADS-1:0][ 31:0] tex_m_axi_araddr,
    output logic [NUM_OF_THREADS-1:0][  7:0] tex_m_axi_arlen,
    output logic [NUM_OF_THREADS-1:0][  2:0] tex_m_axi_arsize,
    output logic [NUM_OF_THREADS-1:0][  1:0] tex_m_axi_arburst,
    output logic [NUM_OF_THREADS-1:0]        tex_m_axi_arvalid,
    input  logic [NUM_OF_THREADS-1:0]        tex_m_axi_arready,
    input  logic [NUM_OF_THREADS-1:0][127:0] tex_m_axi_rdata,
    input  logic [NUM_OF_THREADS-1:0][  1:0] tex_m_axi_rresp,
    input  logic [NUM_OF_THREADS-1:0]        tex_m_axi_rvalid,
    output logic [NUM_OF_THREADS-1:0]        tex_m_axi_rready,
    input  logic [NUM_OF_THREADS-1:0]        tex_m_axi_rlast
);
  localparam int BusyW = $clog2(BUSY_CYCLES + 1);
  localparam int ReadyW = $clog2(READY_DELAY + 1);
  localparam int FbReadLatency = 4;  // as frame_buffer_ram

  //
  // Frontend (frontend_clk)
  //

  logic [TILE_ID_W_X-1:0] tile_x_index, tile_x_q;
  logic [TILE_ID_W_Y-1:0] tile_y_index, tile_y_q;
  logic [BusyW-1:0] frontend_busy_cnt;
  logic [7:0] tile_triangles;  // since the tile registers last changed, saturating
  logic [ReadyW-1:0] ready_wait;
  logic frontend_idle, sw_reset, take;

  assign ready_out = ready_wait == '0;
  assign take = valid_in && ready_out;
  assign frontend_idle = frontend_busy_cnt == '0;

  always_ff @(posedge frontend_clk) begin
    if (!frontend_rst_n || sw_reset) begin
      ready_wait <= '0;
      frontend_busy_cnt <= '0;
      tile_triangles <= '0;
      tile_x_q <= '0;
      tile_y_q <= '0;
    end else begin
      tile_x_q <= tile_x_index;
      tile_y_q <= tile_y_index;
      if (take) ready_wait <= ReadyW'(READY_DELAY);
      else if (ready_wait != '0) ready_wait <= ready_wait - 1'b1;
      if (take) frontend_busy_cnt <= BusyW'(BUSY_CYCLES);
      else if (!frontend_idle) frontend_busy_cnt <= frontend_busy_cnt - 1'b1;
      if (tile_x_index != tile_x_q || tile_y_index != tile_y_q) tile_triangles <= '0;
      else if (take && tile_triangles != 8'hFF) tile_triangles <= tile_triangles + 1'b1;
    end
  end

  APBFrontendRegs u_apb_frontend_regs (
      .apb_clock(apb_clk),
      .apb_resetn(apb_rst_n),
      .thread_clk(frontend_clk),
      .thread_resetn(frontend_rst_n),
      .s_apb_PADDR(s_apb_frontend_PADDR),
      .s_apb_PSEL(s_apb_frontend_PSEL),
      .s_apb_PENABLE(s_apb_frontend_PENABLE),
      .s_apb_PREADY(s_apb_frontend_PREADY),
      .s_apb_PWRITE(s_apb_frontend_PWRITE),
      .s_apb_PWDATA(s_apb_frontend_PWDATA),
      .s_apb_PRDATA(s_apb_frontend_PRDATA),
      .s_apb_PSLVERROR(s_apb_frontend_PSLVERROR),
      .thread_empty(frontend_idle),
      .orchestrator_empty(frontend_idle),
      .input_fifo_idle(1'b1),
      .thread_sw_reset(sw_reset),
      .tile_x_index(tile_x_index),
      .tile_y_index(tile_y_index)
  );

  //
  // Threads (thread_clk)
  //

  // Level signals that only change between bursts of work: two flops into thread_clk are enough.
  logic [1:0] frontend_idle_sync;
  logic [7:0] tile_triangles_sync[2];
  logic [BusyW-1:0] thread_busy_cnt;
  logic thread_busy, frontend_idle_t;

  always_ff @(posedge thread_clk) begin
    frontend_idle_sync <= {frontend_idle_sync[0], frontend_idle};
    tile_triangles_sync[0] <= tile_triangles;
    tile_triangles_sync[1] <= tile_triangles_sync[0];
  end

  assign frontend_idle_t = frontend_idle_sync[1];

  always_ff @(posedge thread_clk) begin
    if (!thread_rst_n) thread_busy_cnt <= '0;
    else if (!frontend_idle_t) thread_busy_cnt <= BusyW'(BUSY_CYCLES);
    else if (thread_busy_cnt != '0) thread_busy_cnt <= thread_busy_cnt - 1'b1;
  end

  assign thread_busy = !frontend_idle_t || thread_busy_cnt != '0;

  // Which frame buffer read pipeline stages hold the data of a read.
  logic [NUM_OF_THREADS-1:0][FbReadLatency-2:0] fb_rd_en_q;

  always_ff @(posedge thread_clk) begin
    for (int lane = 0; lane < NUM_OF_THREADS; lane++)
      fb_rd_en_q[lane] <= {fb_rd_en_q[lane][FbReadLatency-3:0], fb_rd_en[lane]};
  end

  for (genvar lane = 0; lane < NUM_OF_THREADS; lane++) begin : g_thread
    ApbThreadRegs u_apb_thread_regs (
        .s_apb_PADDR(s_apb_thread_PADDR[lane]),
        .s_apb_PSEL(s_apb_thread_PSEL[lane]),
        .s_apb_PENABLE(s_apb_thread_PENABLE[lane]),
        .s_apb_PREADY(s_apb_thread_PREADY[lane]),
        .s_apb_PWRITE(s_apb_thread_PWRITE[lane]),
        .s_apb_PWDATA(s_apb_thread_PWDATA[lane]),
        .s_apb_PRDATA(s_apb_thread_PRDATA[lane]),
        .s_apb_PSLVERROR(s_apb_thread_PSLVERROR[lane]),
        .thread_busy(thread_busy),
        .zbuf_clear_busy(1'b0),
        .zbuf_clear(),
        .thread_soft_reset(),
        .cache_flush(),
        .clk(apb_clk),
        .resetn(apb_rst_n),
        .thread_clk(thread_clk)
    );

    // Host word a holds slice addresses {a, 0} (low half) and {a, 1} (high half); a slice address
    // is {quad_y, quad_x}, and the lane is {y[0], x[0]}.
    function automatic logic [31:0] pixel(input logic [PIXEL_ADDR_W_THREAD-1:0] slice_addr);
      logic [7:0] x, y;
      x = 8'({slice_addr[TILE_ADDR_X-1:0], 1'(lane % 2)});
      y = 8'({slice_addr[PIXEL_ADDR_W_THREAD-1:TILE_ADDR_X], 1'(lane / 2)});
      return {8'hFF, 8'(x << 1), 8'(y << 1), tile_triangles_sync[1]};
    endfunction

    logic [63:0] rd_pipe[FbReadLatency];

    always_ff @(posedge thread_clk) begin
      if (fb_rd_en[lane])
        rd_pipe[0] <= {pixel({fb_rd_addr[lane], 1'b1}), pixel({fb_rd_addr[lane], 1'b0})};
      for (int i = 1; i < FbReadLatency; i++) begin
        // Moves only behind a read, so the data holds until the next one.
        if (fb_rd_en_q[lane][i-1]) rd_pipe[i] <= rd_pipe[i-1];
      end
    end

    assign fb_rd_data[lane] = rd_pipe[FbReadLatency-1];
  end

  //
  // Texture descriptor table and texture masters
  //

  ApbLutRam u_texture_lut (
      .clk(apb_clk),
      .resetn(apb_rst_n),
      .s_apb_PADDR(s_apb_lut_PADDR),
      .s_apb_PSEL(s_apb_lut_PSEL),
      .s_apb_PENABLE(s_apb_lut_PENABLE),
      .s_apb_PREADY(s_apb_lut_PREADY),
      .s_apb_PWRITE(s_apb_lut_PWRITE),
      .s_apb_PWDATA(s_apb_lut_PWDATA),
      .s_apb_PRDATA(s_apb_lut_PRDATA),
      .s_apb_PSLVERROR(s_apb_lut_PSLVERROR),
      .lut_0_data_addr('0),
      .lut_0_base(),
      .lut_0_size(),
      .lut_1_data_addr('0),
      .lut_1_base(),
      .lut_1_size(),
      .lut_2_data_addr('0),
      .lut_2_base(),
      .lut_2_size(),
      .lut_3_data_addr('0),
      .lut_3_base(),
      .lut_3_size()
  );

  assign tex_m_axi_araddr  = '0;
  assign tex_m_axi_arlen   = '0;
  assign tex_m_axi_arsize  = '0;
  assign tex_m_axi_arburst = '0;
  assign tex_m_axi_arvalid = '0;
  assign tex_m_axi_rready  = '1;

endmodule
