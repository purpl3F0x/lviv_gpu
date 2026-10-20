// Raster Core
// Copyright (c) 2026 Stavros Avramidis

`timescale 1ns / 1ns

import gpu_types_pkg::*;

/*
 *                          Raster Core Block Diagram
 *   ┌──────────────────────────────────────────────────────────────┐
 *   │                                         ┌──────────┐         │
 *   │                                    ┌───►│ Thread 0 ├─────────┼─► tile buffer 0, texture AXI 0
 *   │ ┌──────────┐   ┌──────────────┐    │    ├──────────┤         │
 * ──┼►│ Frontend ├──►│ Orchestrator ├────┼───►│ Thread 1 ├─────────┼─► tile buffer 1, texture AXI 1
 *   │ └────▲─────┘   └──────┬───────┘    │    ├──────────┤         │
 *   │      │      empty     │            ├───►│ Thread 2 ├─────────┼─► tile buffer 2, texture AXI 2
 *   │      └────────────────┘            │    ├──────────┤         │
 *   │                                    └───►│ Thread 3 ├─────────┼─► tile buffer 3, texture AXI 3
 *   │                                         └────▲─────┘         │
 *   │                                     Texture LUT (shared)     │
 *   └──────────────────────────────────────────────────────────────┘
 *     APB: frontend, thread 0..3, texture LUT
 *
 * Clocks: the frontend runs on frontend_clk; the orchestrator and the threads run on thread_clk.
 * The orchestrator's input FIFO crosses between the two, so they may be the same clock or
 * unrelated ones. Every APB slave runs on apb_clk and synchronises into its core clock internally.
 *
 * Each thread owns one pixel of every 2x2 quad (thread = {y[0], x[0]}) and writes its own slice of
 * the tile buffer, addressed {quad_y, quad_x}. The tile buffer must accept a write every cycle and
 * return a read 3 cycles after the request. Texture reads leave through one AXI4 read master per
 * thread; the texture descriptor table is shared and read by all four threads.
 */
module raster_core (
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

    // * Tile buffer, one slice per thread (thread_clk) * //
    output logic        [NUM_OF_THREADS-1:0][                   31:0] out_fb_color,
    output logic        [NUM_OF_THREADS-1:0][PIXEL_ADDR_W_THREAD-1:0] out_fb_addr,
    output logic        [NUM_OF_THREADS-1:0]                          out_fb_valid,
    output logic        [NUM_OF_THREADS-1:0]                          out_fb_we,
    output logic        [NUM_OF_THREADS-1:0]                          out_fb_rd_en,
    output logic        [NUM_OF_THREADS-1:0][PIXEL_ADDR_W_THREAD-1:0] out_fb_rd_addr,
    input  color_argb_t [NUM_OF_THREADS-1:0]                          in_fb_rd_color,

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

  // The orchestrator and the texture table are built for exactly four threads.
  if (NUM_OF_THREADS != 4) begin : g_thread_count_check
    $error("raster_core requires NUM_OF_THREADS == 4");
  end

  //
  // Frontend
  //

  logic                  frontend_valid;
  logic                  orchestrator_ready;
  orchestrator_data_in_t frontend_data;
  logic                  orchestrator_empty;

  raster_frontend u_frontend (
      .clk(frontend_clk),
      .rst_n(frontend_rst_n),
      .apb_clk(apb_clk),
      .apb_rst_n(apb_rst_n),
      .s_apb_PADDR(s_apb_frontend_PADDR),
      .s_apb_PSEL(s_apb_frontend_PSEL),
      .s_apb_PENABLE(s_apb_frontend_PENABLE),
      .s_apb_PREADY(s_apb_frontend_PREADY),
      .s_apb_PWRITE(s_apb_frontend_PWRITE),
      .s_apb_PWDATA(s_apb_frontend_PWDATA),
      .s_apb_PRDATA(s_apb_frontend_PRDATA),
      .s_apb_PSLVERROR(s_apb_frontend_PSLVERROR),
      .valid_in(valid_in),
      .ready_out(ready_out),
      .in_data(in_data),
      .ready_in(orchestrator_ready),
      .valid_out(frontend_valid),
      .out_data(frontend_data),
      .orchestrator_empty(orchestrator_empty),
      .core_empty()  // also readable through the frontend status register
  );

  //
  // Thread orchestrator
  //

  logic            thread_valid[4];
  logic            thread_ready[4];
  thread_data_in_t thread_data [4];

  thread_orchestrator u_orchestrator (
      .in_clk(frontend_clk),
      .in_rst_n(frontend_rst_n),
      .valid_in(frontend_valid),
      .ready_out(orchestrator_ready),
      .in_data(frontend_data),
      .clk(thread_clk),
      .rst_n(thread_rst_n),
      .ready_in(thread_ready),
      .valid_out(thread_valid),
      .out_data(thread_data),
      .empty(orchestrator_empty)
  );

  //
  // Texture descriptor table, one read port per thread
  //

  logic [ 6:0] lut_addr[4];
  logic [31:0] lut_base[4];
  logic [ 3:0] lut_size[4];

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
      .lut_0_data_addr(lut_addr[0]),
      .lut_0_base(lut_base[0]),
      .lut_0_size(lut_size[0]),
      .lut_1_data_addr(lut_addr[1]),
      .lut_1_base(lut_base[1]),
      .lut_1_size(lut_size[1]),
      .lut_2_data_addr(lut_addr[2]),
      .lut_2_base(lut_base[2]),
      .lut_2_size(lut_size[2]),
      .lut_3_data_addr(lut_addr[3]),
      .lut_3_base(lut_base[3]),
      .lut_3_size(lut_size[3])
  );

  //
  // Threads
  //

  for (genvar lane = 0; lane < 4; lane++) begin : g_thread
    thread u_thread (
        .clk(thread_clk),
        .rst_n(thread_rst_n),
        .valid_in(thread_valid[lane]),
        .ready_out(thread_ready[lane]),
        .in_data(thread_data[lane]),
        .empty(),  // also readable through the thread's busy register
        .out_fb_color(out_fb_color[lane]),
        .out_fb_addr(out_fb_addr[lane]),
        .out_fb_valid(out_fb_valid[lane]),
        .out_fb_we(out_fb_we[lane]),
        .out_fb_rd_en(out_fb_rd_en[lane]),
        .out_fb_rd_addr(out_fb_rd_addr[lane]),
        .in_fb_rd_color(in_fb_rd_color[lane]),
        .apb_clk(apb_clk),
        .apb_rst_n(apb_rst_n),
        .s_apb_PADDR(s_apb_thread_PADDR[lane]),
        .s_apb_PSEL(s_apb_thread_PSEL[lane]),
        .s_apb_PENABLE(s_apb_thread_PENABLE[lane]),
        .s_apb_PREADY(s_apb_thread_PREADY[lane]),
        .s_apb_PWRITE(s_apb_thread_PWRITE[lane]),
        .s_apb_PWDATA(s_apb_thread_PWDATA[lane]),
        .s_apb_PRDATA(s_apb_thread_PRDATA[lane]),
        .s_apb_PSLVERROR(s_apb_thread_PSLVERROR[lane]),
        .zbuf_ready(),  // also readable through the thread's z-buffer clear register
        .tex_m_axi_araddr(tex_m_axi_araddr[lane]),
        .tex_m_axi_arlen(tex_m_axi_arlen[lane]),
        .tex_m_axi_arsize(tex_m_axi_arsize[lane]),
        .tex_m_axi_arburst(tex_m_axi_arburst[lane]),
        .tex_m_axi_arvalid(tex_m_axi_arvalid[lane]),
        .tex_m_axi_arready(tex_m_axi_arready[lane]),
        .tex_m_axi_rdata(tex_m_axi_rdata[lane]),
        .tex_m_axi_rresp(tex_m_axi_rresp[lane]),
        .tex_m_axi_rvalid(tex_m_axi_rvalid[lane]),
        .tex_m_axi_rready(tex_m_axi_rready[lane]),
        .tex_m_axi_rlast(tex_m_axi_rlast[lane]),
        .lut_addr(lut_addr[lane]),
        .lut_base(lut_base[lane]),
        .lut_size(lut_size[lane])
    );
  end

endmodule
