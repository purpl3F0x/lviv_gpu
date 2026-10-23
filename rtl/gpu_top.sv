// GPU Top
// Copyright (c) 2026 Stavros Avramidis
//
// The GPU as the CPU sees it: one AXI control port and the memory masters, around the raster core
// (or dummy_core, to bring up everything else on hardware first).
//
//   CPU ── s_axi_ctrl ──► Axi4ToApbXbar ──► APB: frontend, threads 0..3, texture LUT,
//                                              tile DMA, visibility DMA
//   visibility DMA ◄── m_axi_vb (PS DDR): one 64-bit tile mask per triangle
//        │ DataMover commands
//        ▼
//   triangle DMA (DataMover) ◄── m_axi_tri (PL DDR, 512-bit)
//        │ 512-bit stream, TKEEP marking the halves that are data
//        ▼
//   triangle_stream_adapter ──► async FIFO (aclk → frontend_clk) ──► core
//   core frame buffers ──► tile DMA ── m_axi_tile (PS DDR): the finished tile; the tile DMA writes
//                          CLEAR_VALUE back over what it read, and fills them with it on CLEAR
//
// Control map (4 KiB, from Axi4ToApbXbar): 0x000 texture LUT, 0x800 frontend, 0x820 + 0x20 * n
// thread n, 0xF00 tile DMA, 0xF80 visibility DMA.
//
// Clocks: aclk runs the crossbar, every APB slave, both DMAs and the DataMover; the core runs on
// frontend_clk and thread_clk, and the tile DMA reads the frame buffers on thread_clk.
//
// Not connected yet: the Control Unit's crossbar port (tied off) and the texture masters (no L2
// cache; their reads are never answered, so only untextured triangles complete on the real core).

`timescale 1ns / 1ps

import gpu_types_pkg::*;

module gpu_top #(
    // dummy_core instead of raster_core
    parameter bit DUMMY_CORE = 1'b1,
    // Bytes between triangles in memory: the packed 96-byte gpu_triangle_t, as AxiVisibilityDma
    // addresses them
    parameter int TRIANGLE_STRIDE = 96
) (
    // * Clocks and resets * //
    input logic aclk,
    input logic aresetn,
    input logic frontend_clk,
    input logic frontend_rst_n,
    input logic thread_clk,
    input logic thread_rst_n,

    // * CPU control port: AXI4, 32-bit, 4 KiB * //
    input  logic [11:0] s_axi_ctrl_awaddr,
    input  logic [ 3:0] s_axi_ctrl_awid,
    input  logic [ 7:0] s_axi_ctrl_awlen,
    input  logic [ 2:0] s_axi_ctrl_awsize,
    input  logic [ 1:0] s_axi_ctrl_awburst,
    input  logic        s_axi_ctrl_awvalid,
    output logic        s_axi_ctrl_awready,
    input  logic [31:0] s_axi_ctrl_wdata,
    input  logic [ 3:0] s_axi_ctrl_wstrb,
    input  logic        s_axi_ctrl_wlast,
    input  logic        s_axi_ctrl_wvalid,
    output logic        s_axi_ctrl_wready,
    output logic [ 3:0] s_axi_ctrl_bid,
    output logic [ 1:0] s_axi_ctrl_bresp,
    output logic        s_axi_ctrl_bvalid,
    input  logic        s_axi_ctrl_bready,
    input  logic [11:0] s_axi_ctrl_araddr,
    input  logic [ 3:0] s_axi_ctrl_arid,
    input  logic [ 7:0] s_axi_ctrl_arlen,
    input  logic [ 2:0] s_axi_ctrl_arsize,
    input  logic [ 1:0] s_axi_ctrl_arburst,
    input  logic        s_axi_ctrl_arvalid,
    output logic        s_axi_ctrl_arready,
    output logic [31:0] s_axi_ctrl_rdata,
    output logic [ 3:0] s_axi_ctrl_rid,
    output logic [ 1:0] s_axi_ctrl_rresp,
    output logic        s_axi_ctrl_rlast,
    output logic        s_axi_ctrl_rvalid,
    input  logic        s_axi_ctrl_rready,

    // * Visibility buffer reads (PS DDR), 128-bit * //
    output logic [ 31:0] m_axi_vb_araddr,
    output logic [  3:0] m_axi_vb_arid,
    output logic [  3:0] m_axi_vb_arregion,
    output logic [  7:0] m_axi_vb_arlen,
    output logic [  2:0] m_axi_vb_arsize,
    output logic [  1:0] m_axi_vb_arburst,
    output logic [  0:0] m_axi_vb_arlock,
    output logic [  3:0] m_axi_vb_arcache,
    output logic [  3:0] m_axi_vb_arqos,
    output logic [  2:0] m_axi_vb_arprot,
    output logic         m_axi_vb_arvalid,
    input  logic         m_axi_vb_arready,
    input  logic [127:0] m_axi_vb_rdata,
    input  logic [  3:0] m_axi_vb_rid,
    input  logic [  1:0] m_axi_vb_rresp,
    input  logic         m_axi_vb_rlast,
    input  logic         m_axi_vb_rvalid,
    output logic         m_axi_vb_rready,

    // * Triangle reads (PL DDR), 512-bit * //
    output logic [ 31:0] m_axi_tri_araddr,
    output logic [  3:0] m_axi_tri_arid,
    output logic [  7:0] m_axi_tri_arlen,
    output logic [  2:0] m_axi_tri_arsize,
    output logic [  1:0] m_axi_tri_arburst,
    output logic [  2:0] m_axi_tri_arprot,
    output logic [  3:0] m_axi_tri_arcache,
    output logic [  3:0] m_axi_tri_aruser,
    output logic         m_axi_tri_arvalid,
    input  logic         m_axi_tri_arready,
    input  logic [511:0] m_axi_tri_rdata,
    input  logic [  1:0] m_axi_tri_rresp,
    input  logic         m_axi_tri_rlast,
    input  logic         m_axi_tri_rvalid,
    output logic         m_axi_tri_rready,

    // * Tile write-back (PS DDR), 128-bit * //
    output logic [ 31:0] m_axi_tile_awaddr,
    output logic [  3:0] m_axi_tile_awid,
    output logic [  3:0] m_axi_tile_awregion,
    output logic [  7:0] m_axi_tile_awlen,
    output logic [  2:0] m_axi_tile_awsize,
    output logic [  1:0] m_axi_tile_awburst,
    output logic [  0:0] m_axi_tile_awlock,
    output logic [  3:0] m_axi_tile_awcache,
    output logic [  3:0] m_axi_tile_awqos,
    output logic [  2:0] m_axi_tile_awprot,
    output logic         m_axi_tile_awvalid,
    input  logic         m_axi_tile_awready,
    output logic [127:0] m_axi_tile_wdata,
    output logic [ 15:0] m_axi_tile_wstrb,
    output logic         m_axi_tile_wlast,
    output logic         m_axi_tile_wvalid,
    input  logic         m_axi_tile_wready,
    input  logic [  3:0] m_axi_tile_bid,
    input  logic [  1:0] m_axi_tile_bresp,
    input  logic         m_axi_tile_bvalid,
    output logic         m_axi_tile_bready,

    // * Interrupts (aclk) * //
    output logic vis_dma_irq,
    output logic tile_dma_irq,
    output logic tri_dma_err
);

  //
  // Control crossbar
  //

  logic [9:0] lut_PADDR;
  logic [4:0] frontend_PADDR;
  logic [NUM_OF_THREADS-1:0][4:0] thread_PADDR;
  logic [6:0] tile_dma_PADDR, vis_dma_PADDR;
  logic lut_PSEL, lut_PENABLE, lut_PREADY, lut_PWRITE, lut_PSLVERROR;
  logic frontend_PSEL, frontend_PENABLE, frontend_PREADY, frontend_PWRITE, frontend_PSLVERROR;
  logic tile_dma_PSEL, tile_dma_PENABLE, tile_dma_PREADY, tile_dma_PWRITE, tile_dma_PSLVERROR;
  logic vis_dma_PSEL, vis_dma_PENABLE, vis_dma_PREADY, vis_dma_PWRITE, vis_dma_PSLVERROR;
  logic [31:0] lut_PWDATA, lut_PRDATA, frontend_PWDATA, frontend_PRDATA;
  logic [31:0] tile_dma_PWDATA, tile_dma_PRDATA, vis_dma_PWDATA, vis_dma_PRDATA;
  logic [NUM_OF_THREADS-1:0] thread_PSEL, thread_PENABLE, thread_PREADY, thread_PWRITE;
  logic [NUM_OF_THREADS-1:0] thread_PSLVERROR;
  logic [NUM_OF_THREADS-1:0][31:0] thread_PWDATA, thread_PRDATA;

  Axi4ToApbXbar u_xbar (
      .clk(aclk),
      .resetn(aresetn),
      // CPU
      .m_axi_0_awvalid(s_axi_ctrl_awvalid),
      .m_axi_0_awready(s_axi_ctrl_awready),
      .m_axi_0_awaddr(s_axi_ctrl_awaddr),
      .m_axi_0_awid(s_axi_ctrl_awid),
      .m_axi_0_awlen(s_axi_ctrl_awlen),
      .m_axi_0_awsize(s_axi_ctrl_awsize),
      .m_axi_0_awburst(s_axi_ctrl_awburst),
      .m_axi_0_wvalid(s_axi_ctrl_wvalid),
      .m_axi_0_wready(s_axi_ctrl_wready),
      .m_axi_0_wdata(s_axi_ctrl_wdata),
      .m_axi_0_wstrb(s_axi_ctrl_wstrb),
      .m_axi_0_wlast(s_axi_ctrl_wlast),
      .m_axi_0_bvalid(s_axi_ctrl_bvalid),
      .m_axi_0_bready(s_axi_ctrl_bready),
      .m_axi_0_bid(s_axi_ctrl_bid),
      .m_axi_0_bresp(s_axi_ctrl_bresp),
      .m_axi_0_arvalid(s_axi_ctrl_arvalid),
      .m_axi_0_arready(s_axi_ctrl_arready),
      .m_axi_0_araddr(s_axi_ctrl_araddr),
      .m_axi_0_arid(s_axi_ctrl_arid),
      .m_axi_0_arlen(s_axi_ctrl_arlen),
      .m_axi_0_arsize(s_axi_ctrl_arsize),
      .m_axi_0_arburst(s_axi_ctrl_arburst),
      .m_axi_0_rvalid(s_axi_ctrl_rvalid),
      .m_axi_0_rready(s_axi_ctrl_rready),
      .m_axi_0_rdata(s_axi_ctrl_rdata),
      .m_axi_0_rid(s_axi_ctrl_rid),
      .m_axi_0_rresp(s_axi_ctrl_rresp),
      .m_axi_0_rlast(s_axi_ctrl_rlast),
      // Control Unit: not there yet
      .m_axi_1_awvalid(1'b0),
      .m_axi_1_awready(),
      .m_axi_1_awaddr('0),
      .m_axi_1_awid('0),
      .m_axi_1_awlen('0),
      .m_axi_1_awsize('0),
      .m_axi_1_awburst('0),
      .m_axi_1_wvalid(1'b0),
      .m_axi_1_wready(),
      .m_axi_1_wdata('0),
      .m_axi_1_wstrb('0),
      .m_axi_1_wlast(1'b0),
      .m_axi_1_bvalid(),
      .m_axi_1_bready(1'b1),
      .m_axi_1_bid(),
      .m_axi_1_bresp(),
      .m_axi_1_arvalid(1'b0),
      .m_axi_1_arready(),
      .m_axi_1_araddr('0),
      .m_axi_1_arid('0),
      .m_axi_1_arlen('0),
      .m_axi_1_arsize('0),
      .m_axi_1_arburst('0),
      .m_axi_1_rvalid(),
      .m_axi_1_rready(1'b1),
      .m_axi_1_rdata(),
      .m_axi_1_rid(),
      .m_axi_1_rresp(),
      .m_axi_1_rlast(),
      // APB slaves
      .lut_PADDR(lut_PADDR),
      .lut_PSEL(lut_PSEL),
      .lut_PENABLE(lut_PENABLE),
      .lut_PREADY(lut_PREADY),
      .lut_PWRITE(lut_PWRITE),
      .lut_PWDATA(lut_PWDATA),
      .lut_PRDATA(lut_PRDATA),
      .lut_PSLVERROR(lut_PSLVERROR),
      .frontend_PADDR(frontend_PADDR),
      .frontend_PSEL(frontend_PSEL),
      .frontend_PENABLE(frontend_PENABLE),
      .frontend_PREADY(frontend_PREADY),
      .frontend_PWRITE(frontend_PWRITE),
      .frontend_PWDATA(frontend_PWDATA),
      .frontend_PRDATA(frontend_PRDATA),
      .frontend_PSLVERROR(frontend_PSLVERROR),
      .threadRegs_0_PADDR(thread_PADDR[0]),
      .threadRegs_0_PSEL(thread_PSEL[0]),
      .threadRegs_0_PENABLE(thread_PENABLE[0]),
      .threadRegs_0_PREADY(thread_PREADY[0]),
      .threadRegs_0_PWRITE(thread_PWRITE[0]),
      .threadRegs_0_PWDATA(thread_PWDATA[0]),
      .threadRegs_0_PRDATA(thread_PRDATA[0]),
      .threadRegs_0_PSLVERROR(thread_PSLVERROR[0]),
      .threadRegs_1_PADDR(thread_PADDR[1]),
      .threadRegs_1_PSEL(thread_PSEL[1]),
      .threadRegs_1_PENABLE(thread_PENABLE[1]),
      .threadRegs_1_PREADY(thread_PREADY[1]),
      .threadRegs_1_PWRITE(thread_PWRITE[1]),
      .threadRegs_1_PWDATA(thread_PWDATA[1]),
      .threadRegs_1_PRDATA(thread_PRDATA[1]),
      .threadRegs_1_PSLVERROR(thread_PSLVERROR[1]),
      .threadRegs_2_PADDR(thread_PADDR[2]),
      .threadRegs_2_PSEL(thread_PSEL[2]),
      .threadRegs_2_PENABLE(thread_PENABLE[2]),
      .threadRegs_2_PREADY(thread_PREADY[2]),
      .threadRegs_2_PWRITE(thread_PWRITE[2]),
      .threadRegs_2_PWDATA(thread_PWDATA[2]),
      .threadRegs_2_PRDATA(thread_PRDATA[2]),
      .threadRegs_2_PSLVERROR(thread_PSLVERROR[2]),
      .threadRegs_3_PADDR(thread_PADDR[3]),
      .threadRegs_3_PSEL(thread_PSEL[3]),
      .threadRegs_3_PENABLE(thread_PENABLE[3]),
      .threadRegs_3_PREADY(thread_PREADY[3]),
      .threadRegs_3_PWRITE(thread_PWRITE[3]),
      .threadRegs_3_PWDATA(thread_PWDATA[3]),
      .threadRegs_3_PRDATA(thread_PRDATA[3]),
      .threadRegs_3_PSLVERROR(thread_PSLVERROR[3]),
      .tileDma_PADDR(tile_dma_PADDR),
      .tileDma_PSEL(tile_dma_PSEL),
      .tileDma_PENABLE(tile_dma_PENABLE),
      .tileDma_PREADY(tile_dma_PREADY),
      .tileDma_PWRITE(tile_dma_PWRITE),
      .tileDma_PWDATA(tile_dma_PWDATA),
      .tileDma_PRDATA(tile_dma_PRDATA),
      .tileDma_PSLVERROR(tile_dma_PSLVERROR),
      .visDma_PADDR(vis_dma_PADDR),
      .visDma_PSEL(vis_dma_PSEL),
      .visDma_PENABLE(vis_dma_PENABLE),
      .visDma_PREADY(vis_dma_PREADY),
      .visDma_PWRITE(vis_dma_PWRITE),
      .visDma_PWDATA(vis_dma_PWDATA),
      .visDma_PRDATA(vis_dma_PRDATA),
      .visDma_PSLVERROR(vis_dma_PSLVERROR)
  );

  //
  // Visibility DMA, triangle DMA and the triangle stream
  //

  logic        vis_cmd_tvalid, vis_cmd_tready;
  logic [71:0] vis_cmd_tdata;
  logic dm_sts_tvalid, dm_sts_tready;
  logic [7:0] dm_sts_tdata;
  logic [511:0] tri_stream_tdata;
  logic [63:0] tri_stream_tkeep;
  logic tri_stream_tvalid, tri_stream_tready;

  AxiVisibilityDma u_vis_dma (
      .aclk(aclk),
      .aresetn(aresetn),
      .s_apb_PADDR(vis_dma_PADDR),
      .s_apb_PSEL(vis_dma_PSEL),
      .s_apb_PENABLE(vis_dma_PENABLE),
      .s_apb_PREADY(vis_dma_PREADY),
      .s_apb_PWRITE(vis_dma_PWRITE),
      .s_apb_PWDATA(vis_dma_PWDATA),
      .s_apb_PRDATA(vis_dma_PRDATA),
      .s_apb_PSLVERROR(vis_dma_PSLVERROR),
      .m_axi_vb_arvalid(m_axi_vb_arvalid),
      .m_axi_vb_arready(m_axi_vb_arready),
      .m_axi_vb_araddr(m_axi_vb_araddr),
      .m_axi_vb_arid(m_axi_vb_arid),
      .m_axi_vb_arregion(m_axi_vb_arregion),
      .m_axi_vb_arlen(m_axi_vb_arlen),
      .m_axi_vb_arsize(m_axi_vb_arsize),
      .m_axi_vb_arburst(m_axi_vb_arburst),
      .m_axi_vb_arlock(m_axi_vb_arlock),
      .m_axi_vb_arcache(m_axi_vb_arcache),
      .m_axi_vb_arqos(m_axi_vb_arqos),
      .m_axi_vb_arprot(m_axi_vb_arprot),
      .m_axi_vb_rvalid(m_axi_vb_rvalid),
      .m_axi_vb_rready(m_axi_vb_rready),
      .m_axi_vb_rdata(m_axi_vb_rdata),
      .m_axi_vb_rid(m_axi_vb_rid),
      .m_axi_vb_rresp(m_axi_vb_rresp),
      .m_axi_vb_rlast(m_axi_vb_rlast),
      .m_axis_datamover_cmd_tvalid(vis_cmd_tvalid),
      .m_axis_datamover_cmd_tready(vis_cmd_tready),
      .m_axis_datamover_cmd_tdata(vis_cmd_tdata),
      .s_axis_datamover_sts_tvalid(dm_sts_tvalid),
      .s_axis_datamover_sts_tready(dm_sts_tready),
      .s_axis_datamover_sts_tdata(dm_sts_tdata),
      .ready(),
      .irq(vis_dma_irq),
      .irq_done(),
      .irq_error(),
      .irq_frame_done()
  );

  frontend_data_in_t adapted_tri, core_tri;
  logic adapted_tri_valid, tri_cdc_full, tri_cdc_empty, core_tri_ready;

  triangle_stream_adapter #(
      .TRIANGLE_STRIDE(TRIANGLE_STRIDE)
  ) u_tri_adapter (
      .aclk(aclk),
      .aresetn(aresetn),
      .s_axis_tdata(tri_stream_tdata),
      .s_axis_tkeep(tri_stream_tkeep),
      .s_axis_tvalid(tri_stream_tvalid),
      .s_axis_tready(tri_stream_tready),
      .m_tri_valid(adapted_tri_valid),
      .m_tri_ready(!tri_cdc_full),
      .m_tri_data(adapted_tri)
  );

  triangle_datamover u_tri_dma (
      .aclk(aclk),
      .aresetn(aresetn),
      .s_cmd_tvalid(vis_cmd_tvalid),
      .s_cmd_tready(vis_cmd_tready),
      .s_cmd_tdata(vis_cmd_tdata),
      .m_sts_tvalid(dm_sts_tvalid),
      .m_sts_tready(dm_sts_tready),
      .m_sts_tdata(dm_sts_tdata),
      .m_axi_arid(m_axi_tri_arid),
      .m_axi_araddr(m_axi_tri_araddr),
      .m_axi_arlen(m_axi_tri_arlen),
      .m_axi_arsize(m_axi_tri_arsize),
      .m_axi_arburst(m_axi_tri_arburst),
      .m_axi_arprot(m_axi_tri_arprot),
      .m_axi_arcache(m_axi_tri_arcache),
      .m_axi_aruser(m_axi_tri_aruser),
      .m_axi_arvalid(m_axi_tri_arvalid),
      .m_axi_arready(m_axi_tri_arready),
      .m_axi_rdata(m_axi_tri_rdata),
      .m_axi_rresp(m_axi_tri_rresp),
      .m_axi_rlast(m_axi_tri_rlast),
      .m_axi_rvalid(m_axi_tri_rvalid),
      .m_axi_rready(m_axi_tri_rready),
      .m_axis_tdata(tri_stream_tdata),
      .m_axis_tkeep(tri_stream_tkeep),
      .m_axis_tlast(),
      .m_axis_tvalid(tri_stream_tvalid),
      .m_axis_tready(tri_stream_tready),
      .mm2s_err(tri_dma_err)
  );

  // Into the core's clock. The core's own input FIFO holds the depth; 32 entries fill the LUTRAM.
  logic [$bits(frontend_data_in_t)-1:0] core_tri_bits;

  async_fifo #(
      .DATA_WIDTH($bits(frontend_data_in_t)),
      .FIFO_DEPTH(32)
  ) u_tri_cdc (
      .clk(aclk),
      .rst_n(aresetn),
      .wr_en(adapted_tri_valid && !tri_cdc_full),
      .data_i(adapted_tri),
      .fifo_full(tri_cdc_full),
      .fifo_almost_full(),
      .fill_cnt(),
      .rd_clk(frontend_clk),
      .rd_rst_n(frontend_rst_n),
      .rd_en(core_tri_ready),
      .data_o(core_tri_bits),
      .rd_fill_cnt(),
      .fifo_empty(tri_cdc_empty)
  );

  assign core_tri = frontend_data_in_t'(core_tri_bits);

  //
  // Core
  //

  // The frame buffers' host ports, the tile DMA's: it reads a tile out and writes CLEAR_VALUE back.
  logic [NUM_OF_THREADS-1:0] fb_rd_en, fb_wr_en;
  logic [NUM_OF_THREADS-1:0][PIXEL_ADDR_W_THREAD-2:0] fb_rd_addr, fb_wr_addr;
  logic [NUM_OF_THREADS-1:0][63:0] fb_rd_data, fb_wr_data;
  logic [NUM_OF_THREADS-1:0][7:0] core_thread_PADDR;

  for (genvar lane = 0; lane < NUM_OF_THREADS; lane++) begin : g_thread_paddr
    assign core_thread_PADDR[lane] = 8'(thread_PADDR[lane]);
  end

  // The core's port list, shared by both cores.
`define GPU_TOP_CORE_PORTS \
      .frontend_clk(frontend_clk), \
      .frontend_rst_n(frontend_rst_n), \
      .thread_clk(thread_clk), \
      .thread_rst_n(thread_rst_n), \
      .apb_clk(aclk), \
      .apb_rst_n(aresetn), \
      .valid_in(!tri_cdc_empty), \
      .ready_out(core_tri_ready), \
      .in_data(core_tri), \
      .s_apb_frontend_PADDR(5'(frontend_PADDR)), \
      .s_apb_frontend_PSEL(frontend_PSEL), \
      .s_apb_frontend_PENABLE(frontend_PENABLE), \
      .s_apb_frontend_PREADY(frontend_PREADY), \
      .s_apb_frontend_PWRITE(frontend_PWRITE), \
      .s_apb_frontend_PWDATA(frontend_PWDATA), \
      .s_apb_frontend_PRDATA(frontend_PRDATA), \
      .s_apb_frontend_PSLVERROR(frontend_PSLVERROR), \
      .s_apb_thread_PADDR(core_thread_PADDR), \
      .s_apb_thread_PSEL(thread_PSEL), \
      .s_apb_thread_PENABLE(thread_PENABLE), \
      .s_apb_thread_PREADY(thread_PREADY), \
      .s_apb_thread_PWRITE(thread_PWRITE), \
      .s_apb_thread_PWDATA(thread_PWDATA), \
      .s_apb_thread_PRDATA(thread_PRDATA), \
      .s_apb_thread_PSLVERROR(thread_PSLVERROR), \
      .s_apb_lut_PADDR(10'(lut_PADDR)), \
      .s_apb_lut_PSEL(lut_PSEL), \
      .s_apb_lut_PENABLE(lut_PENABLE), \
      .s_apb_lut_PREADY(lut_PREADY), \
      .s_apb_lut_PWRITE(lut_PWRITE), \
      .s_apb_lut_PWDATA(lut_PWDATA), \
      .s_apb_lut_PRDATA(lut_PRDATA), \
      .s_apb_lut_PSLVERROR(lut_PSLVERROR), \
      .fb_wr_en(fb_wr_en), \
      .fb_wr_addr(fb_wr_addr), \
      .fb_wr_data(fb_wr_data), \
      .fb_rd_en(fb_rd_en), \
      .fb_rd_addr(fb_rd_addr), \
      .fb_rd_data(fb_rd_data), \
      .tex_m_axi_araddr(), \
      .tex_m_axi_arlen(), \
      .tex_m_axi_arsize(), \
      .tex_m_axi_arburst(), \
      .tex_m_axi_arvalid(), \
      .tex_m_axi_arready('0), \
      .tex_m_axi_rdata('0), \
      .tex_m_axi_rresp('0), \
      .tex_m_axi_rvalid('0), \
      .tex_m_axi_rready(), \
      .tex_m_axi_rlast('0)

  if (DUMMY_CORE) begin : g_core
    dummy_core u_core (`GPU_TOP_CORE_PORTS);
  end else begin : g_core
    raster_core u_core (`GPU_TOP_CORE_PORTS);
  end

`undef GPU_TOP_CORE_PORTS

  //
  // Tile DMA: frame buffers (thread_clk) to PS DDR, and CLEAR_VALUE back into them
  //

  // Byte addresses of 64-bit host words
  logic [NUM_OF_THREADS-1:0][13:0] tile_ram_addr, tile_ram_wr_addr;

  AxiTileDma u_tile_dma (
      .aclk(aclk),
      .aresetn(aresetn),
      .ram_clk(thread_clk),
      .ram_resetn(thread_rst_n),
      .s_apb_PADDR(tile_dma_PADDR),
      .s_apb_PSEL(tile_dma_PSEL),
      .s_apb_PENABLE(tile_dma_PENABLE),
      .s_apb_PREADY(tile_dma_PREADY),
      .s_apb_PWRITE(tile_dma_PWRITE),
      .s_apb_PWDATA(tile_dma_PWDATA),
      .s_apb_PRDATA(tile_dma_PRDATA),
      .s_apb_PSLVERROR(tile_dma_PSLVERROR),
      .m_axi_awvalid(m_axi_tile_awvalid),
      .m_axi_awready(m_axi_tile_awready),
      .m_axi_awaddr(m_axi_tile_awaddr),
      .m_axi_awid(m_axi_tile_awid),
      .m_axi_awregion(m_axi_tile_awregion),
      .m_axi_awlen(m_axi_tile_awlen),
      .m_axi_awsize(m_axi_tile_awsize),
      .m_axi_awburst(m_axi_tile_awburst),
      .m_axi_awlock(m_axi_tile_awlock),
      .m_axi_awcache(m_axi_tile_awcache),
      .m_axi_awqos(m_axi_tile_awqos),
      .m_axi_awprot(m_axi_tile_awprot),
      .m_axi_wvalid(m_axi_tile_wvalid),
      .m_axi_wready(m_axi_tile_wready),
      .m_axi_wdata(m_axi_tile_wdata),
      .m_axi_wstrb(m_axi_tile_wstrb),
      .m_axi_wlast(m_axi_tile_wlast),
      .m_axi_bvalid(m_axi_tile_bvalid),
      .m_axi_bready(m_axi_tile_bready),
      .m_axi_bid(m_axi_tile_bid),
      .m_axi_bresp(m_axi_tile_bresp),
      .tile_ram_0_clk(),
      .tile_ram_0_rst(),
      .tile_ram_0_en(fb_rd_en[0]),
      .tile_ram_0_addr(tile_ram_addr[0]),
      .tile_ram_0_dout(fb_rd_data[0]),
      .tile_ram_0_wr_en(fb_wr_en[0]),
      .tile_ram_0_wr_addr(tile_ram_wr_addr[0]),
      .tile_ram_0_wr_data(fb_wr_data[0]),
      .tile_ram_1_clk(),
      .tile_ram_1_rst(),
      .tile_ram_1_en(fb_rd_en[1]),
      .tile_ram_1_addr(tile_ram_addr[1]),
      .tile_ram_1_dout(fb_rd_data[1]),
      .tile_ram_1_wr_en(fb_wr_en[1]),
      .tile_ram_1_wr_addr(tile_ram_wr_addr[1]),
      .tile_ram_1_wr_data(fb_wr_data[1]),
      .tile_ram_2_clk(),
      .tile_ram_2_rst(),
      .tile_ram_2_en(fb_rd_en[2]),
      .tile_ram_2_addr(tile_ram_addr[2]),
      .tile_ram_2_dout(fb_rd_data[2]),
      .tile_ram_2_wr_en(fb_wr_en[2]),
      .tile_ram_2_wr_addr(tile_ram_wr_addr[2]),
      .tile_ram_2_wr_data(fb_wr_data[2]),
      .tile_ram_3_clk(),
      .tile_ram_3_rst(),
      .tile_ram_3_en(fb_rd_en[3]),
      .tile_ram_3_addr(tile_ram_addr[3]),
      .tile_ram_3_dout(fb_rd_data[3]),
      .tile_ram_3_wr_en(fb_wr_en[3]),
      .tile_ram_3_wr_addr(tile_ram_wr_addr[3]),
      .tile_ram_3_wr_data(fb_wr_data[3]),
      .irq(tile_dma_irq),
      .irq_done(),
      .irq_error(),
      .irq_frame_done()
  );

  for (genvar lane = 0; lane < NUM_OF_THREADS; lane++) begin : g_tile_ram_addr
    assign fb_rd_addr[lane] = tile_ram_addr[lane][13:3];
    assign fb_wr_addr[lane] = tile_ram_wr_addr[lane][13:3];
  end

endmodule
