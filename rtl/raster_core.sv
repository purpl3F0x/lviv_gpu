// Raster Core
// Copyright (c) 2026 Stavros Avramidis

`timescale 1ns / 1ns

import gpu_types_pkg::*;

// ============================================================================
// Top-Level Wrapper Instantiating Frontend and Thread Orchestrator
// ============================================================================
module raster_core (
    input logic clk,
    input logic rst_n,

    // Input Vertex Data (Sequential)
    input vertex_t vertex_in,

    // Tile Identification (Valid with v0)
    input logic [TILE_ID_W_X-1:0] tile_x_id,
    input logic [TILE_ID_W_Y-1:0] tile_y_id,

    // Handshake
    input  logic valid_in,
    output logic ready_out,

    // Output Handshake & Data
    input  logic           ready_in [4],
    output logic           valid_out,
    output logic    [31:0] out_e0 [4],
    output logic    [31:0] out_e1 [4],
    output logic    [31:0] out_e2 [4],
    output logic    [PIXEL_ADDR_W-1:0] out_pixel_id [4],
    output logic    [6:0]  out_minX_local,
    output logic    [6:0]  out_minY_local,
    output logic    [7:0]  out_width,
    output logic    [7:0]  out_height,
    output logic    [31:0] out_invArea,
    output logic    [31:0] out_e0_dx_2x,
    output logic    [31:0] out_e0_dy_2x,
    output logic    [31:0] out_e1_dx_2x,
    output logic    [31:0] out_e1_dy_2x,
    output logic    [31:0] out_e2_dx_2x,
    output logic    [31:0] out_e2_dy_2x,
    output vertex_t        out_v0,
    output vertex_t        out_v1,
    output vertex_t        out_v2
);

  // Frontend to Orchestrator connections
  logic f_valid_out;
  logic f_ready_in;
  logic [31:0] f_e0_00, f_e1_00, f_e2_00;
  logic [31:0] f_e0_10, f_e1_10, f_e2_10;
  logic [31:0] f_e0_01, f_e1_01, f_e2_01;
  logic [31:0] f_e0_11, f_e1_11, f_e2_11;
  logic [31:0] f_e0_dx, f_e0_dy, f_e1_dx, f_e1_dy, f_e2_dx, f_e2_dy;
  logic [31:0] f_invArea;
  vertex_t f_v0, f_v1, f_v2;
  logic [7:0] f_minX_local, f_minY_local;
  logic [7:0] f_width, f_height;

  raster_frontend u_frontend (
      .clk            (clk),
      .rst_n          (rst_n),
      .vertex_in      (vertex_in),
      .tile_x_id      (tile_x_id),
      .tile_y_id      (tile_y_id),
      .valid_in       (valid_in),
      .ready_out      (ready_out),
      .ready_in       (f_ready_in),
      .valid_out      (f_valid_out),
      .out_e0_00      (f_e0_00),
      .out_e1_00      (f_e1_00),
      .out_e2_00      (f_e2_00),
      .out_e0_10      (f_e0_10),
      .out_e1_10      (f_e1_10),
      .out_e2_10      (f_e2_10),
      .out_e0_01      (f_e0_01),
      .out_e1_01      (f_e1_01),
      .out_e2_01      (f_e2_01),
      .out_e0_11      (f_e0_11),
      .out_e1_11      (f_e1_11),
      .out_e2_11      (f_e2_11),
      .out_e0_dx_2x   (f_e0_dx),
      .out_e0_dy_2x   (f_e0_dy),
      .out_e1_dx_2x   (f_e1_dx),
      .out_e1_dy_2x   (f_e1_dy),
      .out_e2_dx_2x   (f_e2_dx),
      .out_e2_dy_2x   (f_e2_dy),
      .out_invArea    (f_invArea),
      .out_v0         (f_v0),
      .out_v1         (f_v1),
      .out_v2         (f_v2),
      .out_minX_local (f_minX_local),
      .out_minY_local (f_minY_local),
      .out_width      (f_width),
      .out_height     (f_height)
  );

  logic [31:0] f_e0_arr [4];
  logic [31:0] f_e1_arr [4];
  logic [31:0] f_e2_arr [4];

  assign f_e0_arr[0] = f_e0_00;
  assign f_e0_arr[1] = f_e0_10;
  assign f_e0_arr[2] = f_e0_01;
  assign f_e0_arr[3] = f_e0_11;

  assign f_e1_arr[0] = f_e1_00;
  assign f_e1_arr[1] = f_e1_10;
  assign f_e1_arr[2] = f_e1_01;
  assign f_e1_arr[3] = f_e1_11;

  assign f_e2_arr[0] = f_e2_00;
  assign f_e2_arr[1] = f_e2_10;
  assign f_e2_arr[2] = f_e2_01;
  assign f_e2_arr[3] = f_e2_11;

  logic o_valid_out [4];
  logic [31:0] o_e0 [4];
  logic [31:0] o_e1 [4];
  logic [31:0] o_e2 [4];
  logic [PIXEL_ADDR_W-1:0] o_pixel_id [4];
  logic [31:0] o_invArea;
  vertex_t o_v0, o_v1, o_v2;

  thread_orchestrator u_orchestrator (
      .clk           (clk),
      .rst_n         (rst_n),
      .valid_in      (f_valid_out),
      .ready_out     (f_ready_in),
      .ready_in      (ready_in),
      .valid_out     (o_valid_out),
      .init_e0       (f_e0_arr),
      .init_e1       (f_e1_arr),
      .init_e2       (f_e2_arr),
      .e0_dx_2x      (f_e0_dx),
      .e0_dy_2x      (f_e0_dy),
      .e1_dx_2x      (f_e1_dx),
      .e1_dy_2x      (f_e1_dy),
      .e2_dx_2x      (f_e2_dx),
      .e2_dy_2x      (f_e2_dy),
      .minX_local    (f_minX_local),
      .minY_local    (f_minY_local),
      .width         (f_width),
      .height        (f_height),
      .invArea       (f_invArea),
      .v0            (f_v0),
      .v1            (f_v1),
      .v2            (f_v2),
      .out_e0        (o_e0),
      .out_e1        (o_e1),
      .out_e2        (o_e2),
      .out_pixel_id  (o_pixel_id),
      .out_invArea   (o_invArea),
      .out_v0        (o_v0),
      .out_v1        (o_v1),
      .out_v2        (o_v2)
  );

  assign out_e0 = o_e0;
  assign out_e1 = o_e1;
  assign out_e2 = o_e2;
  assign out_pixel_id = o_pixel_id;

  assign out_minX_local = f_minX_local[6:0];
  assign out_minY_local = f_minY_local[6:0];
  assign out_width      = f_width;
  assign out_height     = f_height;

  assign out_invArea = o_invArea;
  assign out_e0_dx_2x = f_e0_dx;
  assign out_e0_dy_2x = f_e0_dy;
  assign out_e1_dx_2x = f_e1_dx;
  assign out_e1_dy_2x = f_e1_dy;
  assign out_e2_dx_2x = f_e2_dx;
  assign out_e2_dy_2x = f_e2_dy;
  assign out_v0 = o_v0;
  assign out_v1 = o_v1;
  assign out_v2 = o_v2;
  assign valid_out = o_valid_out[0] || o_valid_out[1] || o_valid_out[2] || o_valid_out[3];

endmodule

