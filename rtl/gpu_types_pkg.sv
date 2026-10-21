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
  parameter int SCREEN_RES_X_WIDTH = $clog2(MAX_RES_X);
  parameter int SCREEN_RES_Y_WIDTH = $clog2(MAX_RES_Y);
  parameter int TILE_ID_W_X = $clog2(MAX_RES_X / TILE_SIZE_X);
  parameter int TILE_ID_W_Y = $clog2(MAX_RES_Y / TILE_SIZE_Y);
  parameter int PIXEL_ADDR_W = $clog2(TILE_SIZE_X * TILE_SIZE_Y);
  parameter int PIXEL_ADDR_W_THREAD = $clog2(TILE_SIZE_X * TILE_SIZE_Y / NUM_OF_THREADS);

  parameter int TILE_ADDR_X = $clog2(TILE_SIZE_X / X_THREADS);
  parameter int TILE_ADDR_Y = $clog2(TILE_SIZE_Y / Y_THREADS);

  typedef logic [TILE_ADDR_X-1:0] tile_addr_x_t;
  typedef logic [TILE_ADDR_Y-1:0] tile_addr_y_t;

  typedef logic [SCREEN_RES_X_WIDTH-1:0] screen_addr_x_t;
  typedef logic [SCREEN_RES_Y_WIDTH-1:0] screen_addr_y_t;

  // typedef declarations
  typedef logic [31:0] float_t;

  typedef logic signed [23:0] fx_14_10_t;
  typedef logic signed [47:0] fx_28_20_t;
  typedef logic signed [30:0] fx_14_17_t;
  typedef logic signed [42:0] fx_27_16_t;
  typedef logic signed [17:0] fx_5_13_t;
  typedef logic signed [15:0] int16_t;

  typedef logic [2:0] uint3_t;
  typedef logic [3:0] uint4_t;
  typedef logic [5:0] uint6_t;
  typedef logic [7:0] uint8_t;
  typedef logic [11:0] uint12_t;
  typedef logic [13:0] uint14_t;
  typedef logic [31:0] uint32_t;

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

  // Depth test function, in OpenGL order (the low 3 bits of GL_NEVER..GL_ALWAYS). Each value is a
  // mask of the compare results {gt, eq, lt} that pass, for the fragment's z against the stored z.
  typedef enum logic [2:0] {
    DEPTH_NEVER    = 3'b000,
    DEPTH_LESS     = 3'b001,
    DEPTH_EQUAL    = 3'b010,
    DEPTH_LEQUAL   = 3'b011,
    DEPTH_GREATER  = 3'b100,
    DEPTH_NOTEQUAL = 3'b101,
    DEPTH_GEQUAL   = 3'b110,
    DEPTH_ALWAYS   = 3'b111
  } depth_func_t;

  typedef struct packed {
    logic [7:0] a;  // Alpha
    logic [7:0] r;  // Red
    logic [7:0] g;  // Green
    logic [7:0] b;  // Blue
  } color_argb_t;


  typedef struct packed {
    float_t x;
    float_t y;
    float_t z;
  } vec3_t;

  typedef struct packed {
    float_t x;
    float_t y;
    float_t z;
    float_t w;
  } vec4_t;

  typedef struct packed {
    // Position
    vec4_t position;

    // // Normals
    // vec3_t normals;

    // Color
    color_argb_t color;

    // Textures
    float_t u;
    float_t v;
  } vertex_t;

  typedef struct packed {
    vertex_t v0;
    vertex_t v1;
    vertex_t v2;
    logic [7:0] tex_id;
    texture_address_mode_t texture_mode_u;
    texture_address_mode_t texture_mode_v;
    fragment_op_t texture_function;
    blend_op_t sfactor_op;
    blend_op_t dfactor_op;
    depth_func_t depth_func;
  } frontend_data_in_t;

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
    depth_func_t depth_func;
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
    color_argb_t v0_color;
    color_argb_t v1_color;
    color_argb_t v2_color;
  } thread_data_in_t;

  typedef struct packed {
    fx_28_20_t init_e0;
    fx_28_20_t init_e1;
    fx_28_20_t init_e2;
    fx_14_10_t e0_dx;
    fx_14_10_t e0_dy;
    fx_14_10_t e1_dx;
    fx_14_10_t e1_dy;
    fx_14_10_t e2_dx;
    fx_14_10_t e2_dy;

    // Corner 2x2 group of the box; with the group coordinates this forms the shared thread address.
    tile_addr_x_t minX_local;
    tile_addr_y_t minY_local;
    // Last 2x2 group offset (group count - 1); zero represents one group.
    tile_addr_x_t width;
    tile_addr_y_t height;
    // width == 0 && height == 0: the first group is also the last. Precomputed by the frontend so
    // the orchestrator's pop decision needs no compare on the FIFO output.
    logic single_group;

    // Fixed Point UVs
    fx_5_13_t v0_v;
    fx_5_13_t v0_u;
    fx_5_13_t v1_v;
    fx_5_13_t v1_u;
    fx_5_13_t v2_v;
    fx_5_13_t v2_u;

    // Passthough data

    logic [7:0] tex_id;
    texture_address_mode_t texture_mode_u;
    texture_address_mode_t texture_mode_v;
    fragment_op_t texture_function;
    blend_op_t sfactor_op;
    blend_op_t dfactor_op;
    depth_func_t depth_func;
    float_t inv_area;

    float_t v0_w;
    float_t v0_z;
    float_t v1_w;
    float_t v1_z;
    float_t v2_w;
    float_t v2_z;

    color_argb_t v0_color;
    color_argb_t v1_color;
    color_argb_t v2_color;
  } orchestrator_data_in_t;
endpackage
