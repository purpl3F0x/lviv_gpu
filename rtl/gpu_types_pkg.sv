// GPU Types Package
// Copyright (c) 2026 Stavros Avramidis

`timescale 1ns / 1ns

package gpu_types_pkg;

  // Global Config
  parameter int TILE_SIZE_X = 128;
  parameter int TILE_SIZE_Y = 128;
  parameter int MAX_RES_X = 4096;
  parameter int MAX_RES_Y = 4096;

  parameter int X_THREADS = 2;
  parameter int Y_THREADS = 2;
  parameter int NUM_OF_THREADS = X_THREADS * Y_THREADS;


  // Calculated Widths
  parameter int TILE_ID_W_X = $clog2(MAX_RES_X / TILE_SIZE_X);
  parameter int TILE_ID_W_Y = $clog2(MAX_RES_Y / TILE_SIZE_Y);
  parameter int PIXEL_ADDR_W = $clog2(TILE_SIZE_X * TILE_SIZE_Y);
  parameter int PIXEL_ADDR_W_THREAD = $clog2(TILE_SIZE_X * TILE_SIZE_Y / NUM_OF_THREADS);

  parameter int TILE_ADDR_X = $clog2(TILE_SIZE_X / X_THREADS);
  parameter int TILE_ADDR_Y = $clog2(TILE_SIZE_Y / Y_THREADS);

  typedef enum logic [2:0] {
    REPLACE = 0,
    MODULATE = 1,
    DECAL = 2,
    BLEND = 3,
    ADD = 4,
    COLOR = 5
  } fragment_op_t;

  typedef enum logic [3:0] {
    ZERO = 0,
    ONE = 1,
    SRC_COLOR = 2,
    ONE_MINUS_SRC_COLOR = 3,
    DST_COLOR = 4,
    ONE_MINUS_DST_COLOR = 5,
    SRC_ALPHA = 6,
    ONE_MINUS_SRC_ALPHA = 7,
    DST_ALPHA = 8,
    ONE_MINUS_DST_ALPHA = 9
  } blend_op_t;

  typedef enum logic {
    TEXTURE_CLAMP = 1'b0,
    TEXTURE_TILE  = 1'b1
  } texture_address_mode_t;

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

  // Thread ingress token after frontend preprocessing.
  // Texture u/v arrive in the narrower fixed-point format used by the thread path.
  typedef struct packed {
    logic [PIXEL_ADDR_W_THREAD-1:0] addr;
    logic [7:0] tex_id;
    texture_address_mode_t texture_mode_u;
    texture_address_mode_t texture_mode_v;
    fragment_op_t texture_function;
    blend_op_t sfactor_op;
    blend_op_t dfactor_op;
    logic [31:0] inv_area;
    logic [31:0] e2;
    logic [31:0] e1;
    logic [31:0] e0;
    logic [17:0] v2_v;
    logic [17:0] v2_u;
    logic [31:0] v2_w;
    logic [31:0] v2_z;
    logic [17:0] v1_v;
    logic [17:0] v1_u;
    logic [31:0] v1_w;
    logic [31:0] v1_z;
    logic [17:0] v0_v;
    logic [17:0] v0_u;
    logic [31:0] v0_w;
    logic [31:0] v0_z;
    logic [7:0] v0_color_a;
    logic [7:0] v0_color_r;
    logic [7:0] v0_color_g;
    logic [7:0] v0_color_b;
    logic [7:0] v1_color_a;
    logic [7:0] v1_color_r;
    logic [7:0] v1_color_g;
    logic [7:0] v1_color_b;
    logic [7:0] v2_color_a;
    logic [7:0] v2_color_r;
    logic [7:0] v2_color_g;
    logic [7:0] v2_color_b;
  } thread_data_in_t;

  typedef logic signed [47:0] edge_fixed_t;

  typedef struct packed {
    edge_fixed_t init_e0;
    edge_fixed_t init_e1;
    edge_fixed_t init_e2;
    edge_fixed_t e0_dx;
    edge_fixed_t e0_dy;
    edge_fixed_t e1_dx;
    edge_fixed_t e1_dy;
    edge_fixed_t e2_dx;
    edge_fixed_t e2_dy;
    // Corner 2x2 group of the box; with the group coordinates this forms the shared thread address.
    logic [TILE_ADDR_X-1:0] minX_local;
    logic [TILE_ADDR_Y-1:0] minY_local;
    // Box size in 2x2 groups (pixels / 2), traversed size-1 down to 0; extra bit holds a full tile.
    logic [TILE_ADDR_X:0] width;
    logic [TILE_ADDR_Y:0] height;
    thread_data_in_t thread_data;
  } orchestrator_data_in_t;
endpackage
