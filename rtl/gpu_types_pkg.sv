// GPU Types Package
// Copyright (c) 2026 Stavros Avramidis

`timescale 1ns / 1ns

package gpu_types_pkg;

  // Global Config
  parameter int TILE_SIZE_X = 128;
  parameter int TILE_SIZE_Y = 128;
  parameter int MAX_RES_X = 4096;
  parameter int MAX_RES_Y = 4096;

  // Calculated Widths
  parameter int TILE_ID_W_X = $clog2(MAX_RES_X / TILE_SIZE_X);
  parameter int TILE_ID_W_Y = $clog2(MAX_RES_Y / TILE_SIZE_Y);
  parameter int PIXEL_ADDR_W = $clog2(TILE_SIZE_X * TILE_SIZE_Y);

  typedef enum logic [2:0] {
    REPLACE = 0,
    MODULATE = 1,
    DECAL = 2,
    BLEND = 3,
    ADD = 4,
    COLOR = 5
  } fragment_op_t;

  typedef struct packed {
    logic [7:0] a;  // Alpha
    logic [7:0] r;  // Red
    logic [7:0] g;  // Green
    logic [7:0] b;  // Blue
  } color_argb_t;

  typedef struct packed {
    // Position
    logic [31:0] x;
    logic [31:0] y;
    logic [31:0] z;
    logic [31:0] w;

    // Normals
    logic [31:0] nx;
    logic [31:0] ny;
    logic [31:0] nz;

    // Color
    color_argb_t color;

    // Textures
    logic [31:0] u;
    logic [31:0] v;
  } vertex_t;

endpackage
