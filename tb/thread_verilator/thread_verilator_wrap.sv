`timescale 1ns / 1ps

import gpu_types_pkg::*;

module thread_verilator_wrap (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     valid_in,
    output logic                     ready_out,

    input  logic [PIXEL_ADDR_W_THREAD-1:0]  in_addr,
    input  logic [6:0]               in_tex_id,
    input  logic                     in_texture_mode_u,
    input  logic                     in_texture_mode_v,
    input  logic [2:0]               in_texture_function,
    input  logic [31:0]              in_inv_area,
    input  logic [31:0]              in_e2,
    input  logic [31:0]              in_e1,
    input  logic [31:0]              in_e0,
    input  logic [17:0]              in_v2_v,
    input  logic [17:0]              in_v2_u,
    input  logic [31:0]              in_v2_w,
    input  logic [31:0]              in_v2_z,
    input  logic [17:0]              in_v1_v,
    input  logic [17:0]              in_v1_u,
    input  logic [31:0]              in_v1_w,
    input  logic [31:0]              in_v1_z,
    input  logic [17:0]              in_v0_v,
    input  logic [17:0]              in_v0_u,
    input  logic [31:0]              in_v0_w,
    input  logic [31:0]              in_v0_z,
    input  logic [7:0]               in_v0_color_a,
    input  logic [7:0]               in_v0_color_r,
    input  logic [7:0]               in_v0_color_g,
    input  logic [7:0]               in_v0_color_b,
    input  logic [7:0]               in_v1_color_a,
    input  logic [7:0]               in_v1_color_r,
    input  logic [7:0]               in_v1_color_g,
    input  logic [7:0]               in_v1_color_b,
    input  logic [7:0]               in_v2_color_a,
    input  logic [7:0]               in_v2_color_r,
    input  logic [7:0]               in_v2_color_g,
    input  logic [7:0]               in_v2_color_b,

    output logic [31:0]              out_fb_color,
    output logic [PIXEL_ADDR_W_THREAD-1:0]  out_fb_addr,
    output logic                     out_fb_we,
    output logic                     z_buf_ready,

    output logic                     z_rd_en,
    output logic [PIXEL_ADDR_W_THREAD-1:0]  z_rd_addr,
    input  logic [31:0]              z_rd_data,
    output logic                     z_wr_en,
    output logic [PIXEL_ADDR_W_THREAD-1:0]  z_wr_addr,
    output logic [31:0]              z_wr_data
);

  gpu_types_pkg::thread_data_in_t in_data;

  logic [31:0]  tex_m_axi_araddr;
  logic [7:0]   tex_m_axi_arlen;
  logic [2:0]   tex_m_axi_arsize;
  logic [1:0]   tex_m_axi_arburst;
  logic         tex_m_axi_arvalid;
  logic         tex_m_axi_arready;
  logic [127:0] tex_m_axi_rdata;
  logic [1:0]   tex_m_axi_rresp;
  logic         tex_m_axi_rvalid;
  logic         tex_m_axi_rready;
  logic         tex_m_axi_rlast;

  logic                           z_rd_en_int;
  logic [PIXEL_ADDR_W_THREAD-1:0] z_rd_addr_int;
  logic [31:0]                    z_rd_data_int;
  logic                           z_wr_en_int;
  logic [PIXEL_ADDR_W_THREAD-1:0] z_wr_addr_int;
  logic [31:0]                    z_wr_data_int;

  assign in_data.addr = in_addr;
  assign in_data.tex_id = in_tex_id;
  assign in_data.texture_mode_u = gpu_types_pkg::texture_address_mode_t'(in_texture_mode_u);
  assign in_data.texture_mode_v = gpu_types_pkg::texture_address_mode_t'(in_texture_mode_v);
  assign in_data.texture_function = gpu_types_pkg::fragment_op_t'(in_texture_function);
  assign in_data.inv_area = in_inv_area;
  assign in_data.e2 = in_e2;
  assign in_data.e1 = in_e1;
  assign in_data.e0 = in_e0;
  assign in_data.v2_v = in_v2_v;
  assign in_data.v2_u = in_v2_u;
  assign in_data.v2_w = in_v2_w;
  assign in_data.v2_z = in_v2_z;
  assign in_data.v1_v = in_v1_v;
  assign in_data.v1_u = in_v1_u;
  assign in_data.v1_w = in_v1_w;
  assign in_data.v1_z = in_v1_z;
  assign in_data.v0_v = in_v0_v;
  assign in_data.v0_u = in_v0_u;
  assign in_data.v0_w = in_v0_w;
  assign in_data.v0_z = in_v0_z;
  assign in_data.v0_color_a = in_v0_color_a;
  assign in_data.v0_color_r = in_v0_color_r;
  assign in_data.v0_color_g = in_v0_color_g;
  assign in_data.v0_color_b = in_v0_color_b;
  assign in_data.v1_color_a = in_v1_color_a;
  assign in_data.v1_color_r = in_v1_color_r;
  assign in_data.v1_color_g = in_v1_color_g;
  assign in_data.v1_color_b = in_v1_color_b;
  assign in_data.v2_color_a = in_v2_color_a;
  assign in_data.v2_color_r = in_v2_color_r;
  assign in_data.v2_color_g = in_v2_color_g;
  assign in_data.v2_color_b = in_v2_color_b;

  // Texture backend is tied off for now; tex_id=0 should keep this path idle.
  assign tex_m_axi_arready = 1'b1;
  assign tex_m_axi_rdata = '0;
  assign tex_m_axi_rresp = '0;
  assign tex_m_axi_rvalid = 1'b0;
  assign tex_m_axi_rlast = 1'b0;

    assign z_rd_en = z_rd_en_int;
    assign z_rd_addr = z_rd_addr_int;
    assign z_wr_en = z_wr_en_int;
    assign z_wr_addr = z_wr_addr_int;
    assign z_wr_data = z_wr_data_int;
      // Thread-local z-buffer in wrapper.
    z_buffer_ram #(
        .ADDR_WIDTH(PIXEL_ADDR_W_THREAD),
      .USE_XPM(1'b0)
    ) u_z_buffer_ram (
      .clk(clk),
      .rst_n(rst_n),
      .ready(z_buf_ready),
      .wr_en(z_wr_en_int),
        .wr_addr(z_wr_addr_int),
      .din(z_wr_data_int),
      .rd_en(z_rd_en_int),
        .rd_addr(z_rd_addr_int),
      .dout(z_rd_data_int)
    );

  thread u_thread (
      .clk(clk),
      .rst_n(rst_n),
      .valid_in(valid_in),
      .ready_out(ready_out),
      .in_data(in_data),
      .out_fb_color(out_fb_color),
      .out_fb_addr(out_fb_addr),
      .out_fb_we(out_fb_we),
      .z_rd_en(z_rd_en_int),
      .z_rd_addr(z_rd_addr_int),
      .z_rd_data(z_rd_data_int),
      .z_wr_en(z_wr_en_int),
      .z_wr_addr(z_wr_addr_int),
      .z_wr_data(z_wr_data_int),
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

endmodule
