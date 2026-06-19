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
    output logic    [6:0]  out_minX_local,
    output logic    [6:0]  out_minY_local,
    output logic    [7:0]  out_width,
    output logic    [7:0]  out_height,
    output logic    [31:0] out_invArea,
    output vertex_t        out_v0,
    output vertex_t        out_v1,
    output vertex_t        out_v2
);

  // Frontend to Orchestrator connections
  logic f_valid_out;
  logic f_ready_in;
  logic [31:0] f_e0_row, f_e1_row, f_e2_row;
  logic [31:0] f_e0_10, f_e1_10, f_e2_10;
  logic [31:0] f_e0_01, f_e1_01, f_e2_01;
  logic [31:0] f_e0_11, f_e1_11, f_e2_11;
  logic [31:0] f_e0_dx, f_e0_dy, f_e1_dx, f_e1_dy, f_e2_dx, f_e2_dy;
  logic [31:0] f_invArea;
  vertex_t f_v0, f_v1, f_v2;
  logic [6:0] f_minX_local, f_minY_local;
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
      .out_e0_row     (f_e0_row),
      .out_e1_row     (f_e1_row),
      .out_e2_row     (f_e2_row),
      .out_e0_10      (f_e0_10),
      .out_e1_10      (f_e1_10),
      .out_e2_10      (f_e2_10),
      .out_e0_01      (f_e0_01),
      .out_e1_01      (f_e1_01),
      .out_e2_01      (f_e2_01),
      .out_e0_11      (f_e0_11),
      .out_e1_11      (f_e1_11),
      .out_e2_11      (f_e2_11),
      .out_e0_dx      (f_e0_dx),
      .out_e0_dy      (f_e0_dy),
      .out_e1_dx      (f_e1_dx),
      .out_e1_dy      (f_e1_dy),
      .out_e2_dx      (f_e2_dx),
      .out_e2_dy      (f_e2_dy),
      .out_invArea    (f_invArea),
      .out_v0         (f_v0),
      .out_v1         (f_v1),
      .out_v2         (f_v2),
      .out_minX_local (f_minX_local),
      .out_minY_local (f_minY_local),
      .out_width      (f_width),
      .out_height     (f_height)
  );

  assign out_e0[0] = f_e0_row;
  assign out_e0[1] = f_e0_10;
  assign out_e0[2] = f_e0_01;
  assign out_e0[3] = f_e0_11;

  assign out_e1[0] = f_e1_row;
  assign out_e1[1] = f_e1_10;
  assign out_e1[2] = f_e1_01;
  assign out_e1[3] = f_e1_11;

  assign out_e2[0] = f_e2_row;
  assign out_e2[1] = f_e2_10;
  assign out_e2[2] = f_e2_01;
  assign out_e2[3] = f_e2_11;

  assign out_minX_local = f_minX_local;
  assign out_minY_local = f_minY_local;
  assign out_width      = f_width;
  assign out_height     = f_height;

  assign out_invArea = f_invArea;
  assign out_v0 = f_v0;
  assign out_v1 = f_v1;
  assign out_v2 = f_v2;
  assign valid_out = f_valid_out;
  assign f_ready_in = ready_in[0];

endmodule

