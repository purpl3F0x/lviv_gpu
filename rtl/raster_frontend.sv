`timescale 1ns / 1ns

import gpu_types_pkg::*;

`include "generated/raster_frontend_fixed_autogen.svh"


/*
 *                       FrontEnd Core Block Diagram
 *   ┌──────────────────────────────────────────────────────────────────┐
 *   │ ┌────────┐ ┌─tile-info───►┌────────────┐                       ──┼►
 *  ─┼─►APB Crtl├─┘        ┌─────►Compute Core├────┐                    │
 *   │ └────────┘          │     └────────────┘    │                    │
 *   │┌─────────────────┐  │                       │┌──────────────────┐│
 * ──┼►Input Skid buffer├──┤                       ├┼Output Skid buffer├┼►
 *   │└─────────────────┘  │                       │└──────────────────┘│
 *   │                     │   ┌─────────────────┐ │                    │
 *   │                     └───►Delay unused data├─┘                    │
 *   │                         └─────────────────┘                      │
 *   └──────────────────────────────────────────────────────────────────┘
 */

module raster_frontend (
    input logic clk,
    input logic rst_n,

    // * APB Interface * //
    input logic apb_clk,
    input logic apb_rst_n,
    input logic [4:0] s_apb_PADDR,
    input logic [0:0] s_apb_PSEL,
    input logic s_apb_PENABLE,
    output logic s_apb_PREADY,
    input logic s_apb_PWRITE,
    input logic [31:0] s_apb_PWDATA,
    output logic [31:0] s_apb_PRDATA,
    output logic s_apb_PSLVERROR,

    // * Input Interface * //
    input logic valid_in,
    output logic ready_out,
    input frontend_data_in_t in_data,

    // * Output Interface * //
    input logic ready_in,
    output logic valid_out,
    output orchestrator_data_in_t out_data,

    // * Status Signal * //
    input logic orchestrator_empty,   // We use the APB of the frontend since it's just 1 signal
    output logic core_empty
);
  typedef struct packed {
    logic [7:0] tex_id;
    texture_address_mode_t texture_mode_u;
    texture_address_mode_t texture_mode_v;
    fragment_op_t texture_function;
    blend_op_t sfactor_op;
    blend_op_t dfactor_op;
    float_t v0_z;
    float_t v0_w;
    color_argb_t v0_color;
    float_t v1_z;
    float_t v1_w;
    color_argb_t v1_color;
    float_t v2_z;
    float_t v2_w;
    color_argb_t v2_color;
  } frontend_passthrough_t;

  localparam int FrontendLatency = RASTER_FRONTEND_FIXED_LATENCY;
  localparam int InputWidth = $bits(frontend_data_in_t);
  localparam int OutputWidth = $bits(orchestrator_data_in_t);
  localparam int TileOffsetWidthX = SCREEN_RES_X_WIDTH - TILE_ID_W_X;
  localparam int TileOffsetWidthY = SCREEN_RES_Y_WIDTH - TILE_ID_W_Y;

  frontend_data_in_t input_skid_source;
  frontend_data_in_t input_skid_data;
  logic [InputWidth-1:0] input_skid_data_bits;
  logic input_skid_valid;
  logic input_skid_ready;
  logic input_skid_m_ready;
  logic output_skid_s_ready;
  logic [OutputWidth-1:0] output_skid_data_bits;
  logic pipe_advance;
  logic delayed_valid;

  frontend_passthrough_t passthrough_in;
  frontend_passthrough_t passthrough_out;
  wire orchestrator_data_in_t output_data_internal;
  logic [TILE_ID_W_X-1:0] tile_x_index;
  logic [TILE_ID_W_Y-1:0] tile_y_index;
  logic frontend_sw_reset;

  screen_addr_x_t bb_min_x;
  screen_addr_y_t bb_min_y;
  screen_addr_x_t bb_max_x;
  screen_addr_y_t bb_max_y;

  // Buffer reset and combine it with the software reset.
  (*dont_touch = "true" *) logic local_reset_n;
  always_ff @(posedge clk) begin
    local_reset_n <= rst_n & ~frontend_sw_reset;
  end

  APBFrontendRegs u_apb_frontend_regs (
      .apb_clock(apb_clk),
      .apb_resetn(apb_rst_n),
      .thread_clk(clk),
      .thread_resetn(rst_n),
      .s_apb_PADDR(s_apb_PADDR),
      .s_apb_PSEL(s_apb_PSEL),
      .s_apb_PENABLE(s_apb_PENABLE),
      .s_apb_PREADY(s_apb_PREADY),
      .s_apb_PWRITE(s_apb_PWRITE),
      .s_apb_PWDATA(s_apb_PWDATA),
      .s_apb_PRDATA(s_apb_PRDATA),
      .s_apb_PSLVERROR(s_apb_PSLVERROR),
      .thread_empty(core_empty),
      .orchestrator_empty(orchestrator_empty),
      .thread_sw_reset(frontend_sw_reset),
      .tile_x_index(tile_x_index),
      .tile_y_index(tile_y_index)
  );

  assign bb_min_x = {tile_x_index, {TileOffsetWidthX{1'b0}}};
  assign bb_min_y = {tile_y_index, {TileOffsetWidthY{1'b0}}};
  assign bb_max_x = {tile_x_index, {TileOffsetWidthX{1'b1}}};
  assign bb_max_y = {tile_y_index, {TileOffsetWidthY{1'b1}}};

  assign input_skid_source = in_data;
  assign pipe_advance = output_skid_s_ready;
  assign ready_out = input_skid_ready;
  assign input_skid_m_ready = pipe_advance;
  assign input_skid_data = frontend_data_in_t'(input_skid_data_bits);

  axis_skid_buffer #(
      .WIDTH(InputWidth)
  ) u_input_skid (
      .aclk(clk),
      .aresetn(local_reset_n),
      .s_axis_tdata(input_skid_source),
      .s_axis_tvalid(valid_in),
      .s_axis_tready(input_skid_ready),
      .m_axis_tdata(input_skid_data_bits),
      .m_axis_tvalid(input_skid_valid),
      .m_axis_tready(input_skid_m_ready)
  );

  raster_frontend_fixed_core u_generated_core (
      .clk(clk),
      .clken(pipe_advance),
      .in_v0_x(input_skid_data.v0.position.x),
      .in_v0_y(input_skid_data.v0.position.y),
      .in_v1_x(input_skid_data.v1.position.x),
      .in_v1_y(input_skid_data.v1.position.y),
      .in_v2_x(input_skid_data.v2.position.x),
      .in_v2_y(input_skid_data.v2.position.y),
      .in_bin_min_x(bb_min_x),
      .in_bin_min_y(bb_min_y),
      .in_bin_max_x(bb_max_x),
      .in_bin_max_y(bb_max_y),
      .in_v0_u(input_skid_data.v0.u),
      .in_v0_v(input_skid_data.v0.v),
      .in_v1_u(input_skid_data.v1.u),
      .in_v1_v(input_skid_data.v1.v),
      .in_v2_u(input_skid_data.v2.u),
      .in_v2_v(input_skid_data.v2.v),
      .out_invArea(output_data_internal.inv_area),
      .out_w0(output_data_internal.init_e0),
      .out_w1(output_data_internal.init_e1),
      .out_w2(output_data_internal.init_e2),
      .out_dx_0(output_data_internal.e0_dx),
      .out_dx_1(output_data_internal.e1_dx),
      .out_dx_2(output_data_internal.e2_dx),
      .out_dy_0(output_data_internal.e0_dy),
      .out_dy_1(output_data_internal.e1_dy),
      .out_dy_2(output_data_internal.e2_dy),
      .out_bb_width(output_data_internal.width),
      .out_bb_height(output_data_internal.height),
      .out_minX_local(output_data_internal.minX_local),
      .out_minY_local(output_data_internal.minY_local),
      .out_v0_u_fixed(output_data_internal.v0_u),
      .out_v0_v_fixed(output_data_internal.v0_v),
      .out_v1_u_fixed(output_data_internal.v1_u),
      .out_v1_v_fixed(output_data_internal.v1_v),
      .out_v2_u_fixed(output_data_internal.v2_u),
      .out_v2_v_fixed(output_data_internal.v2_v)
  );

  always_comb begin
    passthrough_in.tex_id = input_skid_data.tex_id;
    passthrough_in.texture_mode_u = input_skid_data.texture_mode_u;
    passthrough_in.texture_mode_v = input_skid_data.texture_mode_v;
    passthrough_in.texture_function = input_skid_data.texture_function;
    passthrough_in.sfactor_op = input_skid_data.sfactor_op;
    passthrough_in.dfactor_op = input_skid_data.dfactor_op;
    passthrough_in.v0_z = input_skid_data.v0.position.z;
    passthrough_in.v0_w = input_skid_data.v0.position.w;
    passthrough_in.v0_color = input_skid_data.v0.color;
    passthrough_in.v1_z = input_skid_data.v1.position.z;
    passthrough_in.v1_w = input_skid_data.v1.position.w;
    passthrough_in.v1_color = input_skid_data.v1.color;
    passthrough_in.v2_z = input_skid_data.v2.position.z;
    passthrough_in.v2_w = input_skid_data.v2.position.w;
    passthrough_in.v2_color = input_skid_data.v2.color;
  end

  // delay_pipe #(
  //     .WIDTH ($bits(frontend_passthrough_t)),
  //     .STAGES(FrontendLatency)
  // ) u_passthrough_delay (
  //     .clk(clk),
  //     .rst_n(1'b1),
  //     .clken(pipe_advance),
  //     .data_in(passthrough_in),
  //     .data_out(passthrough_out)
  // );

  delay_pipe_fifo #(
      .WIDTH ($bits(frontend_passthrough_t)),
      .STAGES(FrontendLatency),
      .IN_REG(0)
  ) u_passthrough_delay (
      .clk(clk),
      .rst_n(rst_n),
      .clken(pipe_advance),
      .data_in(passthrough_in),
      .data_out(passthrough_out)
  );

  delay_pipe #(
      .WIDTH (1),
      .STAGES(FrontendLatency)
  ) u_valid_delay (
      .clk(clk),
      .rst_n(local_reset_n),
      .clken(pipe_advance),
      .data_in(input_skid_valid),
      .data_out(delayed_valid)
  );

  assign output_data_internal.tex_id = passthrough_out.tex_id;
  assign output_data_internal.texture_mode_u = passthrough_out.texture_mode_u;
  assign output_data_internal.texture_mode_v = passthrough_out.texture_mode_v;
  assign output_data_internal.texture_function = passthrough_out.texture_function;
  assign output_data_internal.sfactor_op = passthrough_out.sfactor_op;
  assign output_data_internal.dfactor_op = passthrough_out.dfactor_op;
  assign output_data_internal.v0_w = passthrough_out.v0_w;
  assign output_data_internal.v0_z = passthrough_out.v0_z;
  assign output_data_internal.v0_color = passthrough_out.v0_color;
  assign output_data_internal.v1_w = passthrough_out.v1_w;
  assign output_data_internal.v1_z = passthrough_out.v1_z;
  assign output_data_internal.v1_color = passthrough_out.v1_color;
  assign output_data_internal.v2_w = passthrough_out.v2_w;
  assign output_data_internal.v2_z = passthrough_out.v2_z;
  assign output_data_internal.v2_color = passthrough_out.v2_color;

  axis_skid_buffer #(
      .WIDTH(OutputWidth)
  ) u_output_skid (
      .aclk(clk),
      .aresetn(local_reset_n),
      .s_axis_tdata(output_data_internal),
      .s_axis_tvalid(delayed_valid),
      .s_axis_tready(output_skid_s_ready),
      .m_axis_tdata(output_skid_data_bits),
      .m_axis_tvalid(valid_out),
      .m_axis_tready(ready_in)
  );

  assign out_data = orchestrator_data_in_t'(output_skid_data_bits);

  // ********************** //
  // * Emptiness Tracker * //
  // ********************* //

  localparam int MaxOutstandingTransactions = FrontendLatency + 2 * 2;  // 2 * SkidBufferCapacity
  localparam int CoreCountWidth = $clog2(MaxOutstandingTransactions + 1);

  logic [CoreCountWidth-1:0] core_inflight_count;
  logic frontend_input_fire;
  logic frontend_output_fire;

  assign frontend_input_fire = valid_in && ready_out;
  assign frontend_output_fire = valid_out && ready_in;
  assign core_empty = core_inflight_count == '0;

  always_ff @(posedge clk) begin
    if (!local_reset_n) core_inflight_count <= '0;
    else begin
      case ({
        frontend_input_fire, frontend_output_fire
      })
        2'b10:   core_inflight_count <= core_inflight_count + 1'b1;
        2'b01:   core_inflight_count <= core_inflight_count - 1'b1;
        default: ;
      endcase
    end
  end
endmodule
