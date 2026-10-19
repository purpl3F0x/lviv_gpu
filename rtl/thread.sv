`timescale 1ns / 1ps

import gpu_types_pkg::*;

module thread (
    input logic clk,
    input logic rst_n,

    // Orchestrator-style input bundle (single lane)
    input logic valid_in,
    output logic ready_out,
    input thread_data_in_t in_data,

    output logic empty,

    output logic        [                   31:0] out_fb_color,
    output logic        [PIXEL_ADDR_W_THREAD-1:0] out_fb_addr,
    output logic                                  out_fb_valid,
    output logic                                  out_fb_we,
    output logic                                  out_fb_rd_en,
    output logic        [PIXEL_ADDR_W_THREAD-1:0] out_fb_rd_addr,
    input  color_argb_t                           in_fb_rd_color,

    // APB Slave Interface
    input  logic        apb_clk,
    input  logic        apb_rst_n,
    input  logic [ 7:0] s_apb_PADDR,
    input  logic [ 0:0] s_apb_PSEL,
    input  logic        s_apb_PENABLE,
    output logic        s_apb_PREADY,
    input  logic        s_apb_PWRITE,
    input  logic [31:0] s_apb_PWDATA,
    output logic [31:0] s_apb_PRDATA,
    output logic        s_apb_PSLVERROR,

    output logic zbuf_ready,

    // L1 texture cache AXI read channel
    output logic [ 31:0] tex_m_axi_araddr,
    output logic [  7:0] tex_m_axi_arlen,
    output logic [  2:0] tex_m_axi_arsize,
    output logic [  1:0] tex_m_axi_arburst,
    output logic         tex_m_axi_arvalid,
    input  logic         tex_m_axi_arready,
    input  logic [127:0] tex_m_axi_rdata,
    input  logic [  1:0] tex_m_axi_rresp,
    input  logic         tex_m_axi_rvalid,
    output logic         tex_m_axi_rready,
    input  logic         tex_m_axi_rlast,

    // Texture LUT interface
    output logic [ 6:0] lut_addr,
    input  logic [31:0] lut_base,
    input  logic [ 3:0] lut_size

);

  localparam int THREAD_ADDR_W = PIXEL_ADDR_W_THREAD;

  logic [THREAD_ADDR_W-1:0] s_axis_addr_tdata;
  logic z_rd_en;
  logic [THREAD_ADDR_W-1:0] z_rd_addr;
  logic [31:0] z_rd_data;
  logic z_wr_en;
  logic [THREAD_ADDR_W-1:0] z_wr_addr;
  logic [31:0] z_wr_data;
  logic zbuf_clear;
  logic zbuf_clear_busy;
  logic thread_soft_reset;
  logic cache_flush;

  // Reset register (HW && SW reset)
  (* dont_touch = "true" *) reg rst_reg;
  always_ff @(posedge clk) begin
    rst_reg <= !(!rst_n | thread_soft_reset);  // keep active low behavior
  end

  ApbThreadRegs u_apb_thread_regs (
      .s_apb_PADDR(s_apb_PADDR),
      .s_apb_PSEL(s_apb_PSEL),
      .s_apb_PENABLE(s_apb_PENABLE),
      .s_apb_PREADY(s_apb_PREADY),
      .s_apb_PWRITE(s_apb_PWRITE),
      .s_apb_PWDATA(s_apb_PWDATA),
      .s_apb_PRDATA(s_apb_PRDATA),
      .s_apb_PSLVERROR(s_apb_PSLVERROR),
      .thread_busy(!empty),
      .zbuf_clear_busy(zbuf_clear_busy),
      .zbuf_clear(zbuf_clear),
      .thread_soft_reset(thread_soft_reset),
      .cache_flush(cache_flush),
      .clk(apb_clk),
      .resetn(apb_rst_n),
      .thread_clk(clk)
  );

  z_buffer_ram #(
      .ADDR_WIDTH(THREAD_ADDR_W)
  ) u_z_buffer_ram (
      .clk(clk),
      .rst_n(!zbuf_clear),
      .ready(zbuf_ready),
      .wr_en(z_wr_en),
      .wr_addr(z_wr_addr),
      .din(z_wr_data),
      .rd_en(z_rd_en),
      .rd_addr(z_rd_addr),
      .dout(z_rd_data)
  );

  assign zbuf_clear_busy = !zbuf_ready;

  // Single ingress skid buffer for the whole orchestrator token.
  localparam int INBUNDLEWIDTH = $bits(thread_data_in_t);

  logic input_bundle_s_axis_tready;
  logic [INBUNDLEWIDTH-1:0] input_bundle_buf_tdata;
  logic input_bundle_buf_tvalid;
  logic input_bundle_m_axis_tready;
  logic pipe_en_internal;
  thread_data_in_t thread_data_buf;

  // Reject triangles with e0 < 0 or e1 < 0 or e2 < 0
  logic skid_valid_in;
  assign skid_valid_in = valid_in & (
    (in_data.e0[31] == 0) & (in_data.e1[31] == 0) & (in_data.e2[31] == 0)
    );

  axis_skid_buffer #(
      .WIDTH(INBUNDLEWIDTH)
  ) u_input_bundle_skid (
      .aclk(clk),
      .aresetn(rst_reg),
      .s_axis_tdata(in_data),
      .s_axis_tvalid(skid_valid_in),
      .s_axis_tready(input_bundle_s_axis_tready),
      .m_axis_tdata(input_bundle_buf_tdata),
      .m_axis_tvalid(input_bundle_buf_tvalid),
      .m_axis_tready(input_bundle_m_axis_tready)
  );

  assign thread_data_buf   = input_bundle_buf_tdata;
  assign s_axis_addr_tdata = thread_data_buf.addr[THREAD_ADDR_W-1:0];

  // -------------------------------
  // ---- Master valid pipeline ----
  // -------------------------------
  localparam unsigned ValidPipeDepth = 98;
  logic [ValidPipeDepth:0] valid_pipe;
  assign valid_pipe[0] = input_bundle_buf_tvalid;
  always_ff @(posedge clk) begin
    if (~rst_reg) valid_pipe[ValidPipeDepth:1] <= '0;
    else if (pipe_en_internal) valid_pipe[ValidPipeDepth:1] <= valid_pipe[ValidPipeDepth-1:0];
  end

  /** START OF AUTO-GENERATED PIPELINE LOGIC **/

  `include "thread_pipeline_autogen.svh"

  /** END OF AUTO-GENERATED PIPELINE LOGIC **/

  localparam int FRAGMENT_SHADER_LATENCY_STAGES = 7;
  localparam int FRAME_BUFFER_READ_LATECNY = 3;
  localparam int BLEND_UNIT_LATENCY_STAGES = 7;
  localparam int FRAGMENT_OUTPUT_LATENCY_STAGES = FRAGMENT_SHADER_LATENCY_STAGES + BLEND_UNIT_LATENCY_STAGES;
  localparam int DST_READ_REQUEST_DELAY_STAGES = FRAGMENT_SHADER_LATENCY_STAGES - FRAME_BUFFER_READ_LATECNY;
  localparam int L1_TEXTURE_HIT_LATENCY_STAGES = 4;
  localparam int L1RespQueueDepth = 1 << $clog2(L1_TEXTURE_HIT_LATENCY_STAGES + 1);
  localparam int L1RespPtrWidth = $clog2(L1RespQueueDepth);
  localparam int L1RespCountWidth = $clog2(L1RespQueueDepth + 1);

  typedef struct packed {
    logic [47:0] texcoord_u;
    logic [47:0] texcoord_v;
    logic [THREAD_ADDR_W-1:0] addr;
    logic [7:0] tex_id;
    texture_address_mode_t texture_mode_u;
    texture_address_mode_t texture_mode_v;
    fragment_op_t texture_function;
    blend_op_t sfactor_op;
    blend_op_t dfactor_op;
    color_argb_t color;
  } fragment_token_t;

  typedef struct packed {
    logic valid;
    logic comp_z;
  } fragment_control_t;

  typedef struct packed {
    fragment_token_t token;
    logic [31:0] texture_addr;
    logic no_texture;
  } address_token_t;

  typedef struct packed {
    logic [47:0] texcoord_u;
    logic [47:0] texcoord_v;
    logic [THREAD_ADDR_W-1:0] addr;
    logic [7:0] tex_id;
    texture_address_mode_t texture_mode_u;
    texture_address_mode_t texture_mode_v;
    fragment_op_t texture_function;
    blend_op_t sfactor_op;
    blend_op_t dfactor_op;
    color_argb_t color;
    logic comp_z;
  } fragment_bundle_t;

  typedef struct packed {
    logic [31:0] texture_addr;
    color_argb_t pixel_color;
    fragment_op_t op;
    blend_op_t sfactor_op;
    blend_op_t dfactor_op;
    logic [THREAD_ADDR_W-1:0] addr;
    logic comp_z;
    logic use_texture;
  } fragment_request_token_t;

  typedef struct packed {
    logic [31:0] texture_addr;
    color_argb_t pixel_color;
    fragment_op_t op;
    blend_op_t sfactor_op;
    blend_op_t dfactor_op;
    logic [THREAD_ADDR_W-1:0] addr;
    logic use_texture;
  } fragment_request_payload_t;

  fragment_token_t post_skid_token;
  fragment_bundle_t post_skid_bundle;
  address_token_t address_token_s3;
  fragment_control_t address_control_input;
  fragment_control_t address_control_s3;
  fragment_request_token_t fragment_request_input;
  fragment_request_token_t fragment_request_output;
  fragment_request_payload_t fragment_request_delay_input;
  fragment_request_payload_t fragment_request_delay_output;
  fragment_control_t fragment_request_control_input;
  fragment_control_t fragment_request_control_output;
  logic address_step;
  logic address_use_texture;
  logic texture_response_ready;
  logic texture_response_available;
  logic [31:0] texture_response_data;
  logic texture_response_consume;
  logic texture_response_queue_push;
  logic texture_response_queue_pop;
  (* ram_style = "distributed" *) logic [31:0] texture_response_queue[L1RespQueueDepth];
  logic [L1RespPtrWidth-1:0] texture_response_queue_wr_ptr;
  logic [L1RespPtrWidth-1:0] texture_response_queue_rd_ptr;
  logic [L1RespCountWidth-1:0] texture_response_queue_count;
  logic fragment_request_input_valid;
  logic fragment_request_input_ready;
  logic fragment_request_output_valid;
  logic fragment_request_output_ready;
  logic fragment_request_fire;
  logic delayed_texture_wait;
  logic address_pipe_valid;
  logic texture_wait_valid;
  logic fragment_join_output_valid;
  logic fragment_join_input_ready;

  logic [31:0] texture_addr;
  logic texture_no_texture;
  logic l1_req_valid;
  logic l1_cache_req_ready;
  logic l1_resp_valid;
  logic [31:0] l1_resp_data;
  logic [31:0] l1_perf_total_req;
  logic [31:0] l1_perf_hit_req;
  logic [31:0] l1_perf_miss_req;
  color_argb_t fragment_color_tdata;
  color_argb_t blend_color_tdata;
  logic [2*$bits(blend_op_t)-1:0] blend_factor_tdata;
  logic fragment_valid_tdata;
  logic [THREAD_ADDR_W-1:0] fb_addr_tdata;
  logic cmp_pass_fragment_out_tdata;

  assign address_pipe_valid = address_control_s3.valid;
  assign texture_wait_valid = delayed_texture_wait || !l1_cache_req_ready;
  assign fragment_join_output_valid = fragment_request_output_valid;
  assign fragment_join_input_ready = fragment_request_input_ready;

  assign post_skid_bundle = fragment_bundle_t'(output_bundle_buf_tdata);

  always_comb begin
    post_skid_token = '0;
    post_skid_token.texcoord_u = post_skid_bundle.texcoord_u;
    post_skid_token.texcoord_v = post_skid_bundle.texcoord_v;
    post_skid_token.addr = post_skid_bundle.addr;
    post_skid_token.tex_id = post_skid_bundle.tex_id;
    post_skid_token.texture_mode_u = post_skid_bundle.texture_mode_u;
    post_skid_token.texture_mode_v = post_skid_bundle.texture_mode_v;
    post_skid_token.texture_function = post_skid_bundle.texture_function;
    post_skid_token.sfactor_op = post_skid_bundle.sfactor_op;
    post_skid_token.dfactor_op = post_skid_bundle.dfactor_op;
    post_skid_token.color = post_skid_bundle.color;
  end

  assign address_control_input.valid = output_bundle_buf_tvalid;
  assign address_control_input.comp_z = post_skid_bundle.comp_z;

  assign texture_response_available = (texture_response_queue_count != 0) || l1_resp_valid;
  assign texture_response_data = (texture_response_queue_count != 0)
      ? texture_response_queue[texture_response_queue_rd_ptr]
      : l1_resp_data;
  assign texture_response_consume =
      fragment_request_control_output.valid
      && fragment_request_delay_output.use_texture
      && texture_response_available;
  assign texture_response_ready = texture_response_consume;
  assign texture_response_queue_pop =
      texture_response_consume && (texture_response_queue_count != 0);
  assign texture_response_queue_push =
      l1_resp_valid && !((texture_response_queue_count == 0) && texture_response_consume);
  // Backpressure from the fragment request skid is the holding point for the
  // address stage; delayed accepted requests continue toward cache responses.
  assign address_step = fragment_request_input_ready;
  assign output_bundle_buf_tready = address_step;

  localparam int TextureAddressLatencyStages = 5;

  delay_pipe #(
      .WIDTH ($bits(fragment_token_t)),
      .STAGES(TextureAddressLatencyStages)
  ) u_fragment_token_to_address_stage (
      .clk(clk),
      .rst_n(rst_reg),
      .clken(address_step),
      .data_in(post_skid_token),
      .data_out(address_token_s3.token)
  );

  delay_pipe #(
      .WIDTH ($bits(fragment_control_t)),
      .STAGES(TextureAddressLatencyStages)
  ) u_fragment_control_to_address_stage (
      .clk(clk),
      .rst_n(rst_reg),
      .clken(address_step),
      .data_in(address_control_input),
      .data_out(address_control_s3)
  );

  texture_address_generator u_texture_address_generator (
      .clk(clk),
      .clken(address_step),
      .tex_idx(post_skid_token.tex_id),
      .u_in(post_skid_token.texcoord_u),
      .v_in(post_skid_token.texcoord_v),
      .texture_mode_u(post_skid_token.texture_mode_u),
      .texture_mode_v(post_skid_token.texture_mode_v),
      .addr_out(texture_addr),
      .no_texture(texture_no_texture),
      .lut_addr(lut_addr),
      .lut_base(lut_base),
      .lut_size(lut_size)
  );

  // The address generator is itself a five-stage registered pipeline. Its
  // outputs are therefore already aligned with the delayed fragment token.
  assign address_token_s3.texture_addr = texture_addr;
  assign address_token_s3.no_texture = texture_no_texture;

  assign address_use_texture =
      address_control_s3.valid
      && address_control_s3.comp_z
      && address_token_s3.token.texture_function != COLOR
      && !address_token_s3.no_texture;

  texture_cache #(
      .ADDR_WIDTH(27),
      .PIXEL_BITS(32),
      .CACHE_LINES(32),
      .LINE_PIXELS_X(8),
      .LINE_PIXELS_Y(8),
      .AXI_DATA_WIDTH(128),
      .ENABLE_PERF_COUNTERS(1'b0)
  ) u_l1_texture_cache (
      .clk(clk),
      .rst_n(rst_n),
      .flush(cache_flush),
      .req_valid(l1_req_valid),
      .req_ready(l1_cache_req_ready),
      .req_addr(fragment_request_output.texture_addr[26:0]),
      .resp_valid(l1_resp_valid),
      .resp_data(l1_resp_data),
      .m_axi_araddr(tex_m_axi_araddr),
      .m_axi_arlen(tex_m_axi_arlen),
      .m_axi_arsize(tex_m_axi_arsize),
      .m_axi_arburst(tex_m_axi_arburst),
      .m_axi_arvalid(tex_m_axi_arvalid),
      .m_axi_arready(tex_m_axi_arready),
      .m_axi_rdata(tex_m_axi_rdata),
      .m_axi_rresp(tex_m_axi_rresp),
      .m_axi_rvalid(tex_m_axi_rvalid),
      .m_axi_rready(tex_m_axi_rready),
      .m_axi_rlast(tex_m_axi_rlast),
      .perf_total_req(l1_perf_total_req),
      .perf_hit_req(l1_perf_hit_req),
      .perf_miss_req(l1_perf_miss_req),
      .perf_re(1'b0),
      .perf_we(1'b0),
      .perf_addr('0),
      .perf_wdata('0),
      .perf_rdata(),
      .perf_rvalid()
  );

  assign fragment_request_input_valid = address_control_s3.valid;

  always_comb begin
    fragment_request_input = '0;
    fragment_request_input.texture_addr = address_token_s3.texture_addr;
    fragment_request_input.pixel_color = address_token_s3.token.color;
    fragment_request_input.op = fragment_op_t'(address_use_texture
                ? address_token_s3.token.texture_function
                : COLOR);
    fragment_request_input.addr = address_token_s3.token.addr;
    fragment_request_input.sfactor_op = address_token_s3.token.sfactor_op;
    fragment_request_input.dfactor_op = address_token_s3.token.dfactor_op;
    fragment_request_input.comp_z = address_control_s3.comp_z;
    fragment_request_input.use_texture = address_use_texture;
  end

  // Skid buffer sits right at the address/delay merge point. Cache backpressure
  // releases the held token only when a textured request is accepted, while the
  // delayed metadata pipe aligns accepted tokens to in-order cache responses.
  axis_skid_buffer #(
      .WIDTH($bits(fragment_request_token_t))
  ) u_fragment_request_skid_buffer (
      .aclk(clk),
      .aresetn(rst_reg),
      .s_axis_tdata(fragment_request_input),
      .s_axis_tvalid(fragment_request_input_valid),
      .s_axis_tready(fragment_request_input_ready),
      .m_axis_tdata(fragment_request_output),
      .m_axis_tvalid(fragment_request_output_valid),
      .m_axis_tready(fragment_request_output_ready)
  );

  assign delayed_texture_wait =
      fragment_request_control_output.valid
      && fragment_request_delay_output.use_texture
      && !texture_response_available;

  assign fragment_request_output_ready = !delayed_texture_wait && l1_cache_req_ready;

  assign fragment_request_fire = fragment_request_output_valid && fragment_request_output_ready;

  always_comb begin
    fragment_request_delay_input = '0;
    fragment_request_delay_input.texture_addr = fragment_request_output.texture_addr;
    fragment_request_delay_input.pixel_color = fragment_request_output.pixel_color;
    fragment_request_delay_input.op = fragment_request_output.op;
    fragment_request_delay_input.sfactor_op = fragment_request_output.sfactor_op;
    fragment_request_delay_input.dfactor_op = fragment_request_output.dfactor_op;
    fragment_request_delay_input.addr = fragment_request_output.addr;
    fragment_request_delay_input.use_texture = fragment_request_output.use_texture;
    fragment_request_control_input.valid = fragment_request_fire;
    fragment_request_control_input.comp_z = fragment_request_output.comp_z;
  end

  delay_pipe #(
      .WIDTH ($bits(fragment_request_payload_t)),
      .STAGES(L1_TEXTURE_HIT_LATENCY_STAGES)
  ) u_fragment_request_to_l1_response_stage (
      .clk(clk),
      .rst_n(1'b1),
      .clken(!delayed_texture_wait),
      .data_in(fragment_request_delay_input),
      .data_out(fragment_request_delay_output)
  );

  delay_pipe #(
      .WIDTH ($bits(fragment_control_t)),
      .STAGES(L1_TEXTURE_HIT_LATENCY_STAGES)
  ) u_fragment_control_to_l1_response_stage (
      .clk(clk),
      .rst_n(rst_reg),
      .clken(!delayed_texture_wait),
      .data_in(fragment_request_control_input),
      .data_out(fragment_request_control_output)
  );

  // L1 requests fire from the skid's held output. Hit streams can issue one
  // request per cycle; misses deassert cache ready and stall new issues.
  assign l1_req_valid =
      fragment_request_output_valid
      && fragment_request_output.use_texture
      && !delayed_texture_wait;

  logic fragment_shader_input_valid;
  assign fragment_shader_input_valid = fragment_request_control_output.valid && !delayed_texture_wait;

  always_ff @(posedge clk) begin
    if (texture_response_queue_push) begin
      texture_response_queue[texture_response_queue_wr_ptr] <= l1_resp_data;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_reg) begin
      texture_response_queue_wr_ptr <= '0;
      texture_response_queue_rd_ptr <= '0;
      texture_response_queue_count  <= '0;
    end else begin
      if (texture_response_queue_push) begin
        texture_response_queue_wr_ptr <= texture_response_queue_wr_ptr + 1'b1;
      end

      if (texture_response_queue_pop) begin
        texture_response_queue_rd_ptr <= texture_response_queue_rd_ptr + 1'b1;
      end

      if (texture_response_queue_push != texture_response_queue_pop) begin
        texture_response_queue_count <= texture_response_queue_push
                        ? texture_response_queue_count + 1'b1
                        : texture_response_queue_count - 1'b1;
      end

      if (texture_response_queue_push && !texture_response_queue_pop
                      && (texture_response_queue_count == L1RespCountWidth'(L1RespQueueDepth))) begin
        $fatal(1, "thread texture response queue overflow");
      end
    end
  end

  fragment_shader u_fragment_shader (
      .clk(clk),
      .rst_n(1'b1),
      .pixel_color(fragment_request_delay_output.pixel_color),
      .texture_color(color_argb_t'(texture_response_data)),
      .env_color('0),
      .op(fragment_request_delay_output.op),
      .valid_in(),  // Leave unused
      .fragment_color(fragment_color_tdata),
      .valid_out()
  );

  delay_pipe #(
      .WIDTH (1),
      .STAGES(FRAGMENT_OUTPUT_LATENCY_STAGES)
  ) u_fragment_valid_to_output (
      .clk(clk),
      .rst_n(rst_reg),
      .clken(1'b1),
      .data_in(fragment_shader_input_valid),
      .data_out(fragment_valid_tdata)
  );

  delay_pipe #(
      .WIDTH (THREAD_ADDR_W),
      .STAGES(FRAGMENT_OUTPUT_LATENCY_STAGES)
  ) u_align_fb_addr_to_fragment_output (
      .clk(clk),
      .rst_n(1'b1),
      .clken(1'b1),
      .data_in(fragment_request_delay_output.addr),
      .data_out(fb_addr_tdata)
  );

  delay_pipe #(
      .WIDTH (1),
      .STAGES(FRAGMENT_OUTPUT_LATENCY_STAGES)
  ) u_align_compare_to_fragment_output (
      .clk(clk),
      .rst_n(rst_reg),
      .clken(1'b1),
      .data_in(fragment_request_control_output.comp_z),
      .data_out(cmp_pass_fragment_out_tdata)
  );

  delay_pipe #(
      .WIDTH (1),
      .STAGES(DST_READ_REQUEST_DELAY_STAGES)
  ) u_align_dst_read_valid (
      .clk(clk),
      .rst_n(rst_reg),
      .clken(1'b1),
      .data_in(fragment_shader_input_valid),
      .data_out(out_fb_rd_en)
  );

  delay_pipe #(
      .WIDTH (THREAD_ADDR_W),
      .STAGES(DST_READ_REQUEST_DELAY_STAGES)
  ) u_align_dst_read_addr (
      .clk(clk),
      .rst_n(1'b1),
      .clken(1'b1),
      .data_in(fragment_request_delay_output.addr),
      .data_out(out_fb_rd_addr)
  );

  delay_pipe #(
      .WIDTH (2 * $bits(blend_op_t)),
      .STAGES(FRAGMENT_SHADER_LATENCY_STAGES)
  ) u_align_blend_factors (
      .clk(clk),
      .rst_n(1'b1),
      .clken(1'b1),
      .data_in({
        fragment_request_delay_output.sfactor_op, fragment_request_delay_output.dfactor_op
      }),
      .data_out(blend_factor_tdata)
  );

  blend_unit u_blend_unit (
      .clk(clk),
      .sfactor_op(blend_op_t'(blend_factor_tdata[2*$bits(blend_op_t)-1:$bits(blend_op_t)])),
      .dfactor_op(blend_op_t'(blend_factor_tdata[$bits(blend_op_t)-1:0])),
      .src_color(fragment_color_tdata),
      .dst_color(in_fb_rd_color),
      .blend_color(blend_color_tdata)
  );

  assign out_fb_color = blend_color_tdata;
  assign out_fb_addr = fb_addr_tdata;
  assign out_fb_valid = fragment_valid_tdata;
  assign out_fb_we = out_fb_valid && cmp_pass_fragment_out_tdata;


  // Thread emptiness counter: incremented once per token actually accepted
  // into the main pipeline (not merely presented-but-stalled at the ingress
  // skid), decremented once per fragment completing the blend pipeline.
  reg [7:0] emptiness_counter;
  logic input_bundle_fire;
  assign input_bundle_fire = skid_valid_in && ready_out;
  always_ff @(posedge clk) begin
    if (!rst_reg) begin
      emptiness_counter <= 0;
    end else begin

      unique case ({
        input_bundle_fire, fragment_valid_tdata
      })
        2'b00: emptiness_counter <= emptiness_counter;
        2'b01: emptiness_counter <= emptiness_counter - 1;
        2'b10: emptiness_counter <= emptiness_counter + 1;
        2'b11: emptiness_counter <= emptiness_counter;
      endcase
    end

    empty <= (emptiness_counter == 0) && !input_bundle_fire;
  end

endmodule
