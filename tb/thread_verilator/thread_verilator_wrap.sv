`timescale 1ns / 1ps

import gpu_types_pkg::*;

module thread_verilator_wrap (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     valid_in,
    output logic                     ready_out,

    input  logic [PIXEL_ADDR_W_THREAD-1:0]  in_addr,
    input  logic [7:0]               in_tex_id,
    input  logic                     in_texture_mode_u,
    input  logic                     in_texture_mode_v,
    input  logic [2:0]               in_texture_function,
    input  logic [3:0]               in_sfactor_op,
    input  logic [3:0]               in_dfactor_op,
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
    output logic                     out_fb_valid,
    output logic                     out_fb_we,
    output logic                     out_fb_rd_en,
    output logic [PIXEL_ADDR_W_THREAD-1:0] out_fb_rd_addr,
    input  logic [31:0]              in_fb_rd_color,
    output logic                     uv_sample_fire,
    output logic [11:0]              uv_sample_u,
    output logic [11:0]              uv_sample_v,
    output logic                     z_buf_ready,
    output logic                     empty,

    output logic                     z_rd_en,
    output logic [PIXEL_ADDR_W_THREAD-1:0]  z_rd_addr,
    input  logic [31:0]              z_rd_data,
    output logic                     z_wr_en,
    output logic [PIXEL_ADDR_W_THREAD-1:0]  z_wr_addr,
    output logic [31:0]              z_wr_data,

    input  logic                     lut_addr_wr_en,
    input  logic                     lut_size_wr_en,
    input  logic [6:0]               lut_wr_addr,
    input  logic [31:0]              lut_wr_data,

    input  logic                     tex_mem_wr_en,
    input  logic [31:0]              tex_mem_wr_addr,
    input  logic [31:0]              tex_mem_wr_data
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

  localparam int TEX_AXI_ADDR_W = 24;

  logic tex_ram0_arready;
  logic tex_ram1_arready;
  logic tex_ram2_arready;
  logic tex_ram3_arready;
  logic [31:0] tex_ram0_rdata;
  logic [31:0] tex_ram1_rdata;
  logic [31:0] tex_ram2_rdata;
  logic [31:0] tex_ram3_rdata;
  logic [1:0] tex_ram0_rresp;
  logic tex_ram0_rlast;
  logic tex_ram0_rvalid;
  logic [TEX_AXI_ADDR_W-3:0] tex_prog_word_index;

  assign in_data.addr = in_addr;
  assign in_data.tex_id = in_tex_id;
  assign in_data.texture_mode_u = gpu_types_pkg::texture_address_mode_t'(in_texture_mode_u);
  assign in_data.texture_mode_v = gpu_types_pkg::texture_address_mode_t'(in_texture_mode_v);
  assign in_data.texture_function = gpu_types_pkg::fragment_op_t'(in_texture_function);
  assign in_data.sfactor_op = gpu_types_pkg::blend_op_t'(in_sfactor_op);
  assign in_data.dfactor_op = gpu_types_pkg::blend_op_t'(in_dfactor_op);
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

  assign tex_m_axi_arready =
      tex_ram0_arready & tex_ram1_arready & tex_ram2_arready & tex_ram3_arready;
  assign tex_m_axi_rdata = {tex_ram3_rdata, tex_ram2_rdata, tex_ram1_rdata, tex_ram0_rdata};
  assign tex_m_axi_rresp = tex_ram0_rresp;
  assign tex_m_axi_rvalid = tex_ram0_rvalid;
  assign tex_m_axi_rlast = tex_ram0_rlast;
  assign tex_prog_word_index = {2'b00, tex_mem_wr_addr[TEX_AXI_ADDR_W-1:4]};

  // Backdoor texture RAM programming from C++ driver.
  always_ff @(posedge clk) begin
    if (tex_mem_wr_en) begin
      unique case (tex_mem_wr_addr[3:2])
        2'd0: u_tex_axi_ram0.mem[tex_prog_word_index] <= tex_mem_wr_data;
        2'd1: u_tex_axi_ram1.mem[tex_prog_word_index] <= tex_mem_wr_data;
        2'd2: u_tex_axi_ram2.mem[tex_prog_word_index] <= tex_mem_wr_data;
        2'd3: u_tex_axi_ram3.mem[tex_prog_word_index] <= tex_mem_wr_data;
        default: begin
        end
      endcase
    end
  end

  axi_ram #(
      .DATA_WIDTH(32),
      .ADDR_WIDTH(TEX_AXI_ADDR_W),
      .ID_WIDTH(1),
      .PIPELINE_OUTPUT(0)
  ) u_tex_axi_ram0 (
      .clk(clk),
      .rst(~rst_n),
      .s_axi_awid('0),
      .s_axi_awaddr('0),
      .s_axi_awlen('0),
      .s_axi_awsize('0),
      .s_axi_awburst('0),
      .s_axi_awlock(1'b0),
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
      .s_axi_araddr(tex_m_axi_araddr[TEX_AXI_ADDR_W+1:2]),
      .s_axi_arlen(tex_m_axi_arlen),
      .s_axi_arsize(tex_m_axi_arsize),
      .s_axi_arburst(tex_m_axi_arburst),
      .s_axi_arlock(1'b0),
      .s_axi_arcache('0),
      .s_axi_arprot('0),
      .s_axi_arvalid(tex_m_axi_arvalid),
      .s_axi_arready(tex_ram0_arready),
      .s_axi_rid(),
      .s_axi_rdata(tex_ram0_rdata),
      .s_axi_rresp(tex_ram0_rresp),
      .s_axi_rlast(tex_ram0_rlast),
      .s_axi_rvalid(tex_ram0_rvalid),
      .s_axi_rready(tex_m_axi_rready)
  );

  axi_ram #(
      .DATA_WIDTH(32),
      .ADDR_WIDTH(TEX_AXI_ADDR_W),
      .ID_WIDTH(1),
      .PIPELINE_OUTPUT(0)
  ) u_tex_axi_ram1 (
      .clk(clk),
      .rst(~rst_n),
      .s_axi_awid('0),
      .s_axi_awaddr('0),
      .s_axi_awlen('0),
      .s_axi_awsize('0),
      .s_axi_awburst('0),
      .s_axi_awlock(1'b0),
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
      .s_axi_araddr(tex_m_axi_araddr[TEX_AXI_ADDR_W+1:2]),
      .s_axi_arlen(tex_m_axi_arlen),
      .s_axi_arsize(tex_m_axi_arsize),
      .s_axi_arburst(tex_m_axi_arburst),
      .s_axi_arlock(1'b0),
      .s_axi_arcache('0),
      .s_axi_arprot('0),
      .s_axi_arvalid(tex_m_axi_arvalid),
      .s_axi_arready(tex_ram1_arready),
      .s_axi_rid(),
      .s_axi_rdata(tex_ram1_rdata),
      .s_axi_rresp(),
      .s_axi_rlast(),
      .s_axi_rvalid(),
      .s_axi_rready(tex_m_axi_rready)
  );

  axi_ram #(
      .DATA_WIDTH(32),
      .ADDR_WIDTH(TEX_AXI_ADDR_W),
      .ID_WIDTH(1),
      .PIPELINE_OUTPUT(0)
  ) u_tex_axi_ram2 (
      .clk(clk),
      .rst(~rst_n),
      .s_axi_awid('0),
      .s_axi_awaddr('0),
      .s_axi_awlen('0),
      .s_axi_awsize('0),
      .s_axi_awburst('0),
      .s_axi_awlock(1'b0),
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
      .s_axi_araddr(tex_m_axi_araddr[TEX_AXI_ADDR_W+1:2]),
      .s_axi_arlen(tex_m_axi_arlen),
      .s_axi_arsize(tex_m_axi_arsize),
      .s_axi_arburst(tex_m_axi_arburst),
      .s_axi_arlock(1'b0),
      .s_axi_arcache('0),
      .s_axi_arprot('0),
      .s_axi_arvalid(tex_m_axi_arvalid),
      .s_axi_arready(tex_ram2_arready),
      .s_axi_rid(),
      .s_axi_rdata(tex_ram2_rdata),
      .s_axi_rresp(),
      .s_axi_rlast(),
      .s_axi_rvalid(),
      .s_axi_rready(tex_m_axi_rready)
  );

  axi_ram #(
      .DATA_WIDTH(32),
      .ADDR_WIDTH(TEX_AXI_ADDR_W),
      .ID_WIDTH(1),
      .PIPELINE_OUTPUT(0)
  ) u_tex_axi_ram3 (
      .clk(clk),
      .rst(~rst_n),
      .s_axi_awid('0),
      .s_axi_awaddr('0),
      .s_axi_awlen('0),
      .s_axi_awsize('0),
      .s_axi_awburst('0),
      .s_axi_awlock(1'b0),
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
      .s_axi_araddr(tex_m_axi_araddr[TEX_AXI_ADDR_W+1:2]),
      .s_axi_arlen(tex_m_axi_arlen),
      .s_axi_arsize(tex_m_axi_arsize),
      .s_axi_arburst(tex_m_axi_arburst),
      .s_axi_arlock(1'b0),
      .s_axi_arcache('0),
      .s_axi_arprot('0),
      .s_axi_arvalid(tex_m_axi_arvalid),
      .s_axi_arready(tex_ram3_arready),
      .s_axi_rid(),
      .s_axi_rdata(tex_ram3_rdata),
      .s_axi_rresp(),
      .s_axi_rlast(),
      .s_axi_rvalid(),
      .s_axi_rready(tex_m_axi_rready)
  );

    assign z_rd_en = z_rd_en_int;
    assign z_rd_addr = z_rd_addr_int;
    assign z_wr_en = z_wr_en_int;
    assign z_wr_addr = z_wr_addr_int;
    assign z_wr_data = z_wr_data_int;
      // Thread-local z-buffer in wrapper.
    z_buffer_ram #(
        .ADDR_WIDTH(PIXEL_ADDR_W_THREAD)
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
      .empty(empty),
      .out_fb_color(out_fb_color),
      .out_fb_addr(out_fb_addr),
      .out_fb_valid(out_fb_valid),
      .out_fb_we(out_fb_we),
      .out_fb_rd_en(out_fb_rd_en),
      .out_fb_rd_addr(out_fb_rd_addr),
      .in_fb_rd_color(color_argb_t'(in_fb_rd_color)),
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
        .tex_m_axi_rlast(tex_m_axi_rlast),
        .lut_addr_wr_en(lut_addr_wr_en),
        .lut_size_wr_en(lut_size_wr_en),
        .lut_wr_addr(lut_wr_addr),
        .lut_wr_data(lut_wr_data)
  );

  logic uv_sample_event_now;
  assign uv_sample_event_now =
      u_thread.address_step && u_thread.address_control_input.valid;

  // Register the address-stage token-accept event at the clock edge so the
  // checker sees a stable pulse aligned with the updated stage-1 UV regs.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      uv_sample_fire <= 1'b0;
    end else begin
      uv_sample_fire <= uv_sample_event_now;
    end
  end

  assign uv_sample_u = u_thread.u_texture_address_generator.u_norm_s1;
  assign uv_sample_v = u_thread.u_texture_address_generator.v_norm_s1;

endmodule
