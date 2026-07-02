import gpu_types_pkg::*;

module raster_frontend (
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
    input  logic           ready_in,
    output logic           valid_out,
    output logic    [31:0] out_e0_00,
    output logic    [31:0] out_e1_00,
    output logic    [31:0] out_e2_00,
    output logic    [31:0] out_e0_10,
    output logic    [31:0] out_e1_10,
    output logic    [31:0] out_e2_10,
    output logic    [31:0] out_e0_01,
    output logic    [31:0] out_e1_01,
    output logic    [31:0] out_e2_01,
    output logic    [31:0] out_e0_11,
    output logic    [31:0] out_e1_11,
    output logic    [31:0] out_e2_11,
    output logic    [31:0] out_e0_dx_2x,
    output logic    [31:0] out_e0_dy_2x,
    output logic    [31:0] out_e1_dx_2x,
    output logic    [31:0] out_e1_dy_2x,
    output logic    [31:0] out_e2_dx_2x,
    output logic    [31:0] out_e2_dy_2x,
    output logic    [31:0] out_invArea,
    output vertex_t        out_v0,
    output vertex_t        out_v1,
    output vertex_t        out_v2,
    output logic    [ 7:0] out_minX_local,
    output logic    [ 7:0] out_minY_local,
    output logic    [ 7:0] out_width,
    output logic    [ 7:0] out_height
);
  // --------------------------------------------------------------------------
  // Tile ID Float ROMs
  // --------------------------------------------------------------------------
  localparam int MAX_RES = (MAX_RES_X > MAX_RES_Y) ? MAX_RES_X : MAX_RES_Y;
  localparam int VAL_W = (MAX_RES) + 1;
  localparam int NUM_TILES_X = MAX_RES_X / TILE_SIZE_X;
  // localparam int NUM_TILES_Y = MAX_RES_Y / TILE_SIZE_Y;

  function automatic logic [31:0] calc_tile_min_float(input int tile_id, input int tile_size);
    int val;
    logic [31:0] f;
    val = tile_id * tile_size;
    if (val == 0) begin
      return 32'h0;  // 0.0f
    end else begin
      f = 32'b0;
      for (int i = VAL_W - 1; i >= 0; i--) begin
        if ((val & (1 << i)) != 0) begin
          f[30:23] = 8'(127 + i);
          f[22:0]  = (32'(val) << (23 - i)) & 23'h7fffff;
          break;
        end
      end
      return f;
    end
  endfunction

  function automatic logic [31:0] calc_tile_max_float(input int tile_id, input int tile_size);
    int val;
    logic [31:0] f;
    val = tile_id * tile_size + (tile_size - 1);
    f   = 32'b0;
    for (int i = VAL_W - 1; i >= 0; i--) begin
      if ((val & (1 << i)) != 0) begin
        f[30:23] = 8'(127 + i);
        f[22:0]  = (32'(val) << (23 - i)) & 23'h7fffff;
        break;
      end
    end
    return f;
  endfunction

  typedef logic [31:0] float_rom_x_t[NUM_TILES_X];
  // typedef logic [31:0] float_rom_y_t[NUM_TILES_Y];

  function automatic float_rom_x_t init_rom_x_min();
    float_rom_x_t rom;
    for (int i = 0; i < NUM_TILES_X; i++) begin
      rom[i] = calc_tile_min_float(i, TILE_SIZE_X);
    end
    return rom;
  endfunction

  function automatic float_rom_x_t init_rom_x_max();
    float_rom_x_t rom;
    for (int i = 0; i < NUM_TILES_X; i++) begin
      rom[i] = calc_tile_max_float(i, TILE_SIZE_X);
    end
    return rom;
  endfunction

  // function automatic float_rom_y_t init_rom_y_min();
  //   float_rom_y_t rom;
  //   for (int i = 0; i < NUM_TILES_Y; i++) begin
  //     rom[i] = calc_tile_min_float(i, TILE_SIZE_Y);
  //   end
  //   return rom;
  // endfunction

  // function automatic float_rom_y_t init_rom_y_max();
  //   float_rom_y_t rom;
  //   for (int i = 0; i < NUM_TILES_Y; i++) begin
  //     rom[i] = calc_tile_max_float(i, TILE_SIZE_Y);
  //   end
  //   return rom;
  // endfunction


  // !: ONLY WORKS IF TILES ARE SQUARE
  localparam logic [31:0] TILE_X_MIN_ROM[NUM_TILES_X] = init_rom_x_min();
  localparam logic [31:0] TILE_X_MAX_ROM[NUM_TILES_X] = init_rom_x_max();
  // localparam logic [31:0] TILE_Y_MIN_ROM[NUM_TILES_Y] = init_rom_y_min();
  // localparam logic [31:0] TILE_Y_MAX_ROM[NUM_TILES_Y] = init_rom_y_max();



  // --------------------------------------------------------------------------
  // States and Registers
  // --------------------------------------------------------------------------
  typedef enum logic [2:0] {
    ST_READ_V0,
    ST_READ_V1,
    ST_READ_V2,
    ST_CALC,
    ST_STALL
  } state_t;

  state_t state, next_state;
  logic [TILE_ID_W_X-1:0] tile_x_id_reg;
  logic [TILE_ID_W_Y-1:0] tile_y_id_reg;
  vertex_t v0_reg, v1_reg, v2_reg;
  logic [31:0] binMinX, binMaxX;
  logic [31:0] binMinY, binMaxY;


  localparam int CYC_W = 8;
  logic [CYC_W-1:0] cycle_cnt;
  logic             out_data_valid;

  // --------------------------------------------------------------------------
  // Internal Signal Declarations
  // --------------------------------------------------------------------------
  logic [     31:0] fp32_to_int16_1_in_reg;
  logic [      0:0] fp32_to_int16_1_valid_in_reg;
  logic [     31:0] fp_add_half_fast_1_in_reg;
  logic [      0:0] fp_add_half_fast_1_valid_in_reg;
  logic [     31:0] fp_add_sub_1_a_reg;
  logic [     31:0] fp_add_sub_1_b_reg;
  logic [      0:0] fp_add_sub_1_op_reg;
  logic [      0:0] fp_add_sub_1_valid_in_reg;
  logic [     31:0] fp_add_sub_2_a_reg;
  logic [     31:0] fp_add_sub_2_b_reg;
  logic [      0:0] fp_add_sub_2_op_reg;
  logic [      0:0] fp_add_sub_2_valid_in_reg;
  logic [     31:0] fp_max_2_1_a_reg;
  logic [     31:0] fp_max_2_1_b_reg;
  logic [      0:0] fp_max_2_1_valid_in_reg;
  logic [     31:0] fp_min_2_1_a_reg;
  logic [     31:0] fp_min_2_1_b_reg;
  logic [      0:0] fp_min_2_1_valid_in_reg;
  logic [     31:0] fp_mul_1_a_reg;
  logic [     31:0] fp_mul_1_b_reg;
  logic [      0:0] fp_mul_1_valid_in_reg;
  logic [     31:0] fp_mul_2_a_reg;
  logic [     31:0] fp_mul_2_b_reg;
  logic [      0:0] fp_mul_2_valid_in_reg;
  logic [     31:0] fp_recip_1_in_reg;
  logic [      0:0] fp_recip_1_valid_in_reg;
  logic [     15:0] int16_sub_1_a_reg;
  logic [     15:0] int16_sub_1_b_reg;
  logic [     31:0] tri_bb_min_max_1_a_reg;
  logic [     31:0] tri_bb_min_max_1_b_reg;
  logic [     31:0] tri_bb_min_max_1_c_reg;
  logic [      0:0] tri_bb_min_max_1_valid_in_reg;

  // ---- Pipeline output/intermediate registers ----
  logic [     15:0] bb_height_reg;
  logic [     15:0] bb_start_x_reg;
  logic [     15:0] bb_start_y_reg;
  logic [     15:0] bb_width_reg;
  logic [     31:0] e0_00_reg;
  logic [     31:0] e0_01_reg;
  logic [     31:0] e0_10_reg;
  logic [     31:0] e0_11_reg;
  logic [     31:0] e0_dx_2x_reg;
  logic [     31:0] e0_dy_2x_reg;
  logic [     31:0] e1_00_reg;
  logic [     31:0] e1_01_reg;
  logic [     31:0] e1_10_reg;
  logic [     31:0] e1_11_reg;
  logic [     31:0] e1_dx_2x_reg;
  logic [     31:0] e1_dy_2x_reg;
  logic [     31:0] e2_00_reg;
  logic [     31:0] e2_01_reg;
  logic [     31:0] e2_10_reg;
  logic [     31:0] e2_11_reg;
  logic [     31:0] e2_dx_2x_reg;
  logic [     31:0] e2_dy_2x_reg;
  logic [     31:0] fp32_to_int16_1_in_src_reg;
  logic [     31:0] fp_add_sub_1_a_src_reg;
  logic [     31:0] fp_add_sub_1_b_src_reg;
  logic [     31:0] fp_add_sub_2_a_src_reg;
  logic [     31:0] fp_add_sub_2_b_src_reg;
  logic [     31:0] fp_mul_1_b_src_reg;
  logic [     31:0] fp_mul_2_a_src_reg;
  logic [     31:0] fp_mul_2_b_src_reg;
  logic [     31:0] fp_recip_1_in_src_reg;
  logic [     31:0] int16_add_sub_1_a_src_reg;
  logic [     31:0] invArea_reg;
  logic [     31:0] tmp0;
  logic [     31:0] tmp1;
  logic [     31:0] tmp2;
  logic [     31:0] tmp3;
  logic [     31:0] tmp4;
  logic [     31:0] tmp5;
  logic [     31:0] tmp6;
  logic [     31:0] tmp7;
  logic [     31:0] tmp8;
  logic [     31:0] tmp9;

  // ---------------- Unit Instantiations (ports tied to input regs) ----------------
  logic [     15:0] fp32_to_int16_1_out;
  fp32_to_int16 #(
      .LATENCY(2)
  ) u_fp32_to_int16_1 (
      .aclk    (clk),
      .aresetn (rst_n),
      .aclken  (1'b1),
      .valid_in(fp32_to_int16_1_valid_in_reg),
      .a       (fp32_to_int16_1_in_reg),
      .result  (fp32_to_int16_1_out)
  );

  logic [31:0] fp_add_half_fast_1_out;
  logic fp_add_half_fast_1_valid_out;
  fp_add_half_fast u_fp_add_half_fast_1 (
      .clk      (clk),
      .rst_n    (rst_n),
      .valid_in (fp_add_half_fast_1_valid_in_reg),
      .f_in     (fp_add_half_fast_1_in_reg),
      .valid_out(fp_add_half_fast_1_valid_out),
      .f_out    (fp_add_half_fast_1_out)
  );

  logic [31:0] fp_add_sub_1_res;
  fp_add_sub #(
      .LATENCY(8)
  ) u_fp_add_sub_1 (
      .aclk    (clk),
      .aresetn (rst_n),
      .aclken  (1'b1),
      .op_sub  (fp_add_sub_1_op_reg),
      .valid_in(fp_add_sub_1_valid_in_reg),
      .a       (fp_add_sub_1_a_reg),
      .b       (fp_add_sub_1_b_reg),
      .result  (fp_add_sub_1_res)
  );

  logic [31:0] fp_add_sub_2_res;
  fp_add_sub #(
      .LATENCY(8)
  ) u_fp_add_sub_2 (
      .aclk    (clk),
      .aresetn (rst_n),
      .aclken  (1'b1),
      .op_sub  (fp_add_sub_2_op_reg),
      .valid_in(fp_add_sub_2_valid_in_reg),
      .a       (fp_add_sub_2_a_reg),
      .b       (fp_add_sub_2_b_reg),
      .result  (fp_add_sub_2_res)
  );

  logic [31:0] fp_max_2_1_res;
  logic fp_max_2_1_valid_out;
  fp_max_2 u_fp_max_2_1 (
      .clk      (clk),
      .rst_n    (rst_n),
      .valid_in (fp_max_2_1_valid_in_reg),
      .f_a      (fp_max_2_1_a_reg),
      .f_b      (fp_max_2_1_b_reg),
      .valid_out(fp_max_2_1_valid_out),
      .f_max    (fp_max_2_1_res)
  );

  logic [31:0] fp_min_2_1_res;
  logic fp_min_2_1_valid_out;
  fp_min_2 u_fp_min_2_1 (
      .clk      (clk),
      .rst_n    (rst_n),
      .valid_in (fp_min_2_1_valid_in_reg),
      .f_a      (fp_min_2_1_a_reg),
      .f_b      (fp_min_2_1_b_reg),
      .valid_out(fp_min_2_1_valid_out),
      .f_min    (fp_min_2_1_res)
  );

  logic [31:0] fp_mul_1_res;
  fp_mul #(
      .LATENCY(5)
  ) u_fp_mul_1 (
      .aclk    (clk),
      .aresetn (rst_n),
      .aclken  (1'b1),
      .valid_in(fp_mul_1_valid_in_reg),
      .a       (fp_mul_1_a_reg),
      .b       (fp_mul_1_b_reg),
      .result  (fp_mul_1_res)
  );

  logic [31:0] fp_mul_2_res;
  fp_mul #(
      .LATENCY(5)
  ) u_fp_mul_2 (
      .aclk    (clk),
      .aresetn (rst_n),
      .aclken  (1'b1),
      .valid_in(fp_mul_2_valid_in_reg),
      .a       (fp_mul_2_a_reg),
      .b       (fp_mul_2_b_reg),
      .result  (fp_mul_2_res)
  );

  logic [31:0] fp_recip_1_out;
  fp_recip #(
      .LATENCY(22)
  ) u_fp_recip_1 (
      .aclk    (clk),
      .aresetn (rst_n),
      .aclken  (1'b1),
      .valid_in(fp_recip_1_valid_in_reg),
      .a       (fp_recip_1_in_reg),
      .result  (fp_recip_1_out)
  );

  logic [15:0] int16_sub_1_res;
  int16_sub u_int16_sub_1 (
      .clken(1'b1),
      .a    (int16_sub_1_a_reg),
      .b    (int16_sub_1_b_reg),
      .s    (int16_sub_1_res)
  );

  logic [31:0] tri_bb_min_max_1_min, tri_bb_min_max_1_max;
  logic tri_bb_min_max_1_valid_out;
  tri_bb_min_max u_tri_bb_min_max_1 (
      .clk        (clk),
      .rst_n      (rst_n),
      .valid_in   (tri_bb_min_max_1_valid_in_reg),
      .f_a        (tri_bb_min_max_1_a_reg),
      .f_b        (tri_bb_min_max_1_b_reg),
      .f_c        (tri_bb_min_max_1_c_reg),
      .valid_out  (tri_bb_min_max_1_valid_out),
      .f_min_floor(tri_bb_min_max_1_min),
      .f_max_ceil (tri_bb_min_max_1_max)
  );
  // ---------------- Sequential Latch FSM ----------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      fp32_to_int16_1_in_reg <= 32'b0;
      fp32_to_int16_1_valid_in_reg <= 1'b0;
      fp_add_half_fast_1_in_reg <= 32'b0;
      fp_add_half_fast_1_valid_in_reg <= 1'b0;
      fp_add_sub_1_a_reg <= 32'b0;
      fp_add_sub_1_b_reg <= 32'b0;
      fp_add_sub_1_op_reg <= 1'b0;
      fp_add_sub_1_valid_in_reg <= 1'b0;
      fp_add_sub_2_a_reg <= 32'b0;
      fp_add_sub_2_b_reg <= 32'b0;
      fp_add_sub_2_op_reg <= 1'b0;
      fp_add_sub_2_valid_in_reg <= 1'b0;
      fp_max_2_1_a_reg <= 32'b0;
      fp_max_2_1_b_reg <= 32'b0;
      fp_max_2_1_valid_in_reg <= 1'b0;
      fp_min_2_1_a_reg <= 32'b0;
      fp_min_2_1_b_reg <= 32'b0;
      fp_min_2_1_valid_in_reg <= 1'b0;
      fp_mul_1_a_reg <= 32'b0;
      fp_mul_1_b_reg <= 32'b0;
      fp_mul_1_valid_in_reg <= 1'b0;
      fp_mul_2_a_reg <= 32'b0;
      fp_mul_2_b_reg <= 32'b0;
      fp_mul_2_valid_in_reg <= 1'b0;
      fp_recip_1_in_reg <= 32'b0;
      fp_recip_1_valid_in_reg <= 1'b0;
      int16_sub_1_a_reg <= 16'b0;
      int16_sub_1_b_reg <= 16'b0;
      tri_bb_min_max_1_a_reg <= 32'b0;
      tri_bb_min_max_1_b_reg <= 32'b0;
      tri_bb_min_max_1_c_reg <= 32'b0;
      tri_bb_min_max_1_valid_in_reg <= 1'b0;
      bb_height_reg <= 16'b0;
      bb_start_x_reg <= 16'b0;
      bb_start_y_reg <= 16'b0;
      bb_width_reg <= 16'b0;
      e0_00_reg <= 32'b0;
      e0_01_reg <= 32'b0;
      e0_10_reg <= 32'b0;
      e0_11_reg <= 32'b0;
      e0_dx_2x_reg <= 32'b0;
      e0_dy_2x_reg <= 32'b0;
      e1_00_reg <= 32'b0;
      e1_01_reg <= 32'b0;
      e1_10_reg <= 32'b0;
      e1_11_reg <= 32'b0;
      e1_dx_2x_reg <= 32'b0;
      e1_dy_2x_reg <= 32'b0;
      e2_00_reg <= 32'b0;
      e2_01_reg <= 32'b0;
      e2_10_reg <= 32'b0;
      e2_11_reg <= 32'b0;
      e2_dx_2x_reg <= 32'b0;
      e2_dy_2x_reg <= 32'b0;
      fp32_to_int16_1_in_src_reg <= 32'b0;
      fp_add_sub_1_a_src_reg <= 32'b0;
      fp_add_sub_1_b_src_reg <= 32'b0;
      fp_add_sub_2_a_src_reg <= 32'b0;
      fp_add_sub_2_b_src_reg <= 32'b0;
      fp_mul_1_b_src_reg <= 32'b0;
      fp_mul_2_a_src_reg <= 32'b0;
      fp_mul_2_b_src_reg <= 32'b0;
      fp_recip_1_in_src_reg <= 32'b0;
      int16_add_sub_1_a_src_reg <= 32'b0;
      invArea_reg <= 32'b0;
      tmp0 <= 32'b0;
      tmp1 <= 32'b0;
      tmp2 <= 32'b0;
      tmp3 <= 32'b0;
      tmp4 <= 32'b0;
      tmp5 <= 32'b0;
      tmp6 <= 32'b0;
      tmp7 <= 32'b0;
      tmp8 <= 32'b0;
      tmp9 <= 32'b0;
    end else if (next_state == ST_CALC) begin
      // PRE-CALC: load input regs for operations firing at cycle 0
      fp_add_sub_1_a_reg <= v2_reg.y;
      fp_add_sub_1_b_reg <= v1_reg.y;
      fp_add_sub_1_op_reg <= 1'b1;
      fp_add_sub_1_valid_in_reg <= 1'b1;
      tri_bb_min_max_1_a_reg <= v0_reg.x;
      tri_bb_min_max_1_b_reg <= v1_reg.x;
      tri_bb_min_max_1_c_reg <= v2_reg.x;
      tri_bb_min_max_1_valid_in_reg <= 1'b1;
    end else if (state == ST_CALC) begin
      case (cycle_cnt)
        8'd0: begin
          fp_add_sub_2_a_reg <= v2_reg.x;
          fp_add_sub_2_b_reg <= v0_reg.x;
          fp_add_sub_2_op_reg <= 1'b1;
          fp_add_sub_2_valid_in_reg <= 1'b1;
          fp_add_sub_1_a_reg <= v1_reg.y;
          fp_add_sub_1_b_reg <= v0_reg.y;
          fp_add_sub_1_op_reg <= 1'b1;
          fp_add_sub_1_valid_in_reg <= 1'b1;
          tri_bb_min_max_1_a_reg <= v0_reg.y;
          tri_bb_min_max_1_b_reg <= v1_reg.y;
          tri_bb_min_max_1_c_reg <= v2_reg.y;
          tri_bb_min_max_1_valid_in_reg <= 1'b1;
        end
        8'd1: begin
          fp_add_sub_1_a_reg <= v2_reg.y;
          fp_add_sub_1_b_reg <= v0_reg.y;
          fp_add_sub_1_op_reg <= 1'b1;
          fp_add_sub_1_valid_in_reg <= 1'b1;
          fp_add_sub_2_a_reg <= v1_reg.x;
          fp_add_sub_2_b_reg <= v0_reg.x;
          fp_add_sub_2_op_reg <= 1'b1;
          fp_add_sub_2_valid_in_reg <= 1'b1;
          tri_bb_min_max_1_valid_in_reg <= 1'b0;
        end
        8'd2: begin
          fp_add_sub_1_a_reg <= v1_reg.x;
          fp_add_sub_1_b_reg <= v2_reg.x;
          fp_add_sub_1_op_reg <= 1'b1;
          fp_add_sub_1_valid_in_reg <= 1'b1;
          fp_add_sub_2_a_reg <= v0_reg.y;
          fp_add_sub_2_b_reg <= v2_reg.y;
          fp_add_sub_2_op_reg <= 1'b1;
          fp_add_sub_2_valid_in_reg <= 1'b1;
        end
        8'd3: begin
          fp_add_sub_1_a_reg <= v0_reg.x;
          fp_add_sub_1_b_reg <= v1_reg.x;
          fp_add_sub_1_op_reg <= 1'b1;
          fp_add_sub_1_valid_in_reg <= 1'b1;
          fp_add_sub_2_valid_in_reg <= 1'b0;
        end
        8'd4: begin
          fp_add_sub_1_valid_in_reg <= 1'b0;
        end
        8'd5: begin
          fp_max_2_1_a_reg <= tmp0;
          fp_max_2_1_b_reg <= binMinX;
          fp_max_2_1_valid_in_reg <= 1'b1;
          fp_min_2_1_a_reg <= tmp1;
          fp_min_2_1_b_reg <= binMaxX;
          fp_min_2_1_valid_in_reg <= 1'b1;
          tmp0 <= tri_bb_min_max_1_min;
          tmp1 <= tri_bb_min_max_1_max;
        end
        8'd6: begin
          fp_max_2_1_a_reg <= tmp3;
          fp_max_2_1_b_reg <= binMinY;
          fp_max_2_1_valid_in_reg <= 1'b1;
          fp_min_2_1_a_reg <= tmp4;
          fp_min_2_1_b_reg <= binMaxY;
          fp_min_2_1_valid_in_reg <= 1'b1;
          tmp3 <= tri_bb_min_max_1_min;
          tmp4 <= tri_bb_min_max_1_max;
        end
        8'd7: begin
          fp_add_half_fast_1_in_reg <= tmp0;
          fp_add_half_fast_1_valid_in_reg <= 1'b1;
          fp32_to_int16_1_in_reg <= fp32_to_int16_1_in_src_reg;
          fp32_to_int16_1_valid_in_reg <= 1'b1;
          fp_max_2_1_valid_in_reg <= 1'b0;
          fp_min_2_1_valid_in_reg <= 1'b0;
          tmp0 <= fp_max_2_1_res;
          fp32_to_int16_1_in_src_reg <= fp_min_2_1_res;
        end
        8'd8: begin
          fp_add_half_fast_1_in_reg <= tmp1;
          fp_add_half_fast_1_valid_in_reg <= 1'b1;
          fp32_to_int16_1_in_reg <= tmp0;
          fp32_to_int16_1_valid_in_reg <= 1'b1;
          tmp2 <= fp_add_sub_1_res;
          tmp1 <= fp_max_2_1_res;
          fp32_to_int16_1_in_src_reg <= fp_min_2_1_res;
        end
        8'd9: begin
          fp_add_sub_2_a_reg <= tmp5;
          fp_add_sub_2_b_reg <= tmp5;
          fp_add_sub_2_op_reg <= 1'b0;
          fp_add_sub_2_valid_in_reg <= 1'b1;
          fp32_to_int16_1_in_reg <= tmp1;
          fp32_to_int16_1_valid_in_reg <= 1'b1;
          fp_add_half_fast_1_valid_in_reg <= 1'b0;
          tmp6 <= fp_add_sub_2_res;
          tmp5 <= fp_add_sub_1_res;
        end
        8'd10: begin
          fp_mul_1_a_reg <= tmp6;
          fp_mul_1_b_reg <= tmp5;
          fp_mul_1_valid_in_reg <= 1'b1;
          fp_mul_2_a_reg <= fp_mul_2_a_src_reg;
          fp_mul_2_b_reg <= fp_mul_2_b_src_reg;
          fp_mul_2_valid_in_reg <= 1'b1;
          fp_add_sub_1_a_reg <= tmp3;
          fp_add_sub_1_b_reg <= v1_reg.x;
          fp_add_sub_1_op_reg <= 1'b1;
          fp_add_sub_1_valid_in_reg <= 1'b1;
          fp_add_sub_2_a_reg <= tmp3;
          fp_add_sub_2_b_reg <= v2_reg.x;
          fp_add_sub_2_op_reg <= 1'b1;
          fp_add_sub_2_valid_in_reg <= 1'b1;
          fp32_to_int16_1_in_reg <= fp32_to_int16_1_in_src_reg;
          fp32_to_int16_1_valid_in_reg <= 1'b1;
          fp_mul_2_a_src_reg <= fp_add_sub_1_res;
          fp_mul_2_b_src_reg <= fp_add_sub_2_res;
          tmp3 <= fp_add_half_fast_1_out;
          int16_add_sub_1_a_src_reg <= fp32_to_int16_1_out;
        end
        8'd11: begin
          fp_add_sub_1_a_reg <= tmp3;
          fp_add_sub_1_b_reg <= v0_reg.x;
          fp_add_sub_1_op_reg <= 1'b1;
          fp_add_sub_1_valid_in_reg <= 1'b1;
          fp_add_sub_2_a_reg <= tmp0;
          fp_add_sub_2_b_reg <= v0_reg.y;
          fp_add_sub_2_op_reg <= 1'b1;
          fp_add_sub_2_valid_in_reg <= 1'b1;
          fp_mul_1_valid_in_reg <= 1'b0;
          fp_mul_2_valid_in_reg <= 1'b0;
          fp32_to_int16_1_valid_in_reg <= 1'b0;
          tmp8 <= fp_add_sub_1_res;
          tmp7 <= fp_add_sub_2_res;
          tmp0 <= fp_add_half_fast_1_out;
          bb_start_x_reg <= fp32_to_int16_1_out;
        end
        8'd12: begin
          fp_add_sub_1_a_reg <= tmp0;
          fp_add_sub_1_b_reg <= v1_reg.y;
          fp_add_sub_1_op_reg <= 1'b1;
          fp_add_sub_1_valid_in_reg <= 1'b1;
          fp_add_sub_2_a_reg <= tmp0;
          fp_add_sub_2_b_reg <= v2_reg.y;
          fp_add_sub_2_op_reg <= 1'b1;
          fp_add_sub_2_valid_in_reg <= 1'b1;
          int16_sub_1_a_reg <= int16_add_sub_1_a_src_reg[15:0];
          int16_sub_1_b_reg <= bb_start_x_reg[15:0];
          tmp9 <= fp_add_sub_1_res;
          bb_start_y_reg <= fp32_to_int16_1_out;
        end
        8'd13: begin
          int16_sub_1_a_reg <= int16_add_sub_1_a_src_reg[15:0];
          int16_sub_1_b_reg <= bb_start_y_reg[15:0];
          fp_add_sub_1_valid_in_reg <= 1'b0;
          fp_add_sub_2_valid_in_reg <= 1'b0;
          int16_add_sub_1_a_src_reg <= fp32_to_int16_1_out;
          bb_width_reg <= int16_sub_1_res;
        end
        8'd14: begin
          bb_height_reg <= int16_sub_1_res;
        end
        8'd15: begin
          fp_add_sub_1_a_reg <= tmp7;
          fp_add_sub_1_b_reg <= tmp7;
          fp_add_sub_1_op_reg <= 1'b0;
          fp_add_sub_1_valid_in_reg <= 1'b1;
        end
        8'd16: begin
          fp_add_sub_2_a_reg <= fp_add_sub_2_a_src_reg;
          fp_add_sub_2_b_reg <= fp_add_sub_2_b_src_reg;
          fp_add_sub_2_op_reg <= 1'b1;
          fp_add_sub_2_valid_in_reg <= 1'b1;
          fp_add_sub_1_valid_in_reg <= 1'b0;
          fp_add_sub_2_a_src_reg <= fp_mul_1_res;
          fp_add_sub_2_b_src_reg <= fp_mul_2_res;
        end
        8'd17: begin
          fp_add_sub_2_valid_in_reg <= 1'b0;
        end
        8'd18: begin
          e2_dx_2x_reg <= fp_add_sub_2_res;
        end
        8'd19: begin
          fp_mul_1_a_reg <= tmp2;
          fp_mul_1_b_reg <= fp_mul_1_b_src_reg;
          fp_mul_1_valid_in_reg <= 1'b1;
          fp_mul_2_a_reg <= tmp7;
          fp_mul_2_b_reg <= fp_mul_2_b_src_reg;
          fp_mul_2_valid_in_reg <= 1'b1;
          fp_mul_1_b_src_reg <= fp_add_sub_1_res;
          fp_mul_2_b_src_reg <= fp_add_sub_2_res;
        end
        8'd20: begin
          fp_mul_1_a_reg <= tmp5;
          fp_mul_1_b_reg <= fp_mul_1_b_src_reg;
          fp_mul_1_valid_in_reg <= 1'b1;
          fp_mul_2_a_reg <= tmp9;
          fp_mul_2_b_reg <= fp_mul_2_b_src_reg;
          fp_mul_2_valid_in_reg <= 1'b1;
          fp_mul_1_b_src_reg <= fp_add_sub_1_res;
          fp_mul_2_b_src_reg <= fp_add_sub_2_res;
        end
        8'd21: begin
          fp_mul_1_a_reg <= tmp8;
          fp_mul_1_b_reg <= fp_mul_1_b_src_reg;
          fp_mul_1_valid_in_reg <= 1'b1;
          fp_mul_2_a_reg <= tmp6;
          fp_mul_2_b_reg <= fp_mul_2_b_src_reg;
          fp_mul_2_valid_in_reg <= 1'b1;
          fp_mul_1_b_src_reg <= fp_add_sub_1_res;
          fp_mul_2_b_src_reg <= fp_add_sub_2_res;
        end
        8'd22: begin
          fp_mul_1_valid_in_reg <= 1'b0;
          fp_mul_2_valid_in_reg <= 1'b0;
        end
        8'd23: begin
          fp_add_sub_1_a_reg <= tmp8;
          fp_add_sub_1_b_reg <= tmp8;
          fp_add_sub_1_op_reg <= 1'b0;
          fp_add_sub_1_valid_in_reg <= 1'b1;
        end
        8'd24: begin
          fp_add_sub_2_a_reg <= tmp2;
          fp_add_sub_2_b_reg <= tmp2;
          fp_add_sub_2_op_reg <= 1'b0;
          fp_add_sub_2_valid_in_reg <= 1'b1;
          fp_add_sub_1_valid_in_reg <= 1'b0;
          e1_dx_2x_reg <= fp_add_sub_1_res;
        end
        8'd25: begin
          fp_add_sub_2_valid_in_reg <= 1'b0;
          fp_recip_1_in_src_reg <= fp_add_sub_2_res;
          fp_add_sub_2_a_src_reg <= fp_mul_1_res;
          fp_add_sub_1_a_src_reg <= fp_mul_2_res;
        end
        8'd26: begin
          fp_add_sub_1_a_reg <= fp_add_sub_1_a_src_reg;
          fp_add_sub_1_b_reg <= fp_add_sub_1_b_src_reg;
          fp_add_sub_1_op_reg <= 1'b0;
          fp_add_sub_1_valid_in_reg <= 1'b1;
          fp_add_sub_1_a_src_reg <= fp_mul_1_res;
          fp_add_sub_1_b_src_reg <= fp_mul_2_res;
        end
        8'd27: begin
          fp_add_sub_2_a_reg <= fp_add_sub_2_a_src_reg;
          fp_add_sub_2_b_reg <= fp_add_sub_2_b_src_reg;
          fp_add_sub_2_op_reg <= 1'b0;
          fp_add_sub_2_valid_in_reg <= 1'b1;
          fp_add_sub_1_a_reg <= fp_add_sub_1_a_src_reg;
          fp_add_sub_1_b_reg <= fp_add_sub_1_b_src_reg;
          fp_add_sub_1_op_reg <= 1'b0;
          fp_add_sub_1_valid_in_reg <= 1'b1;
          fp_add_sub_2_b_src_reg <= fp_mul_1_res;
          fp_add_sub_1_b_src_reg <= fp_mul_2_res;
        end
        8'd28: begin
          fp_add_sub_2_valid_in_reg <= 1'b0;
          fp_add_sub_1_valid_in_reg <= 1'b0;
        end
        8'd30: begin
          fp_recip_1_in_reg <= fp_recip_1_in_src_reg;
          fp_recip_1_valid_in_reg <= 1'b1;
          fp_add_sub_1_a_reg <= tmp6;
          fp_add_sub_1_b_reg <= tmp6;
          fp_add_sub_1_op_reg <= 1'b0;
          fp_add_sub_1_valid_in_reg <= 1'b1;
        end
        8'd31: begin
          fp_recip_1_valid_in_reg   <= 1'b0;
          fp_add_sub_1_valid_in_reg <= 1'b0;
        end
        8'd32: begin
          fp_add_sub_2_a_reg <= tmp9;
          fp_add_sub_2_b_reg <= tmp9;
          fp_add_sub_2_op_reg <= 1'b0;
          fp_add_sub_2_valid_in_reg <= 1'b1;
          e0_dy_2x_reg <= fp_add_sub_1_res;
        end
        8'd33: begin
          fp_add_sub_2_valid_in_reg <= 1'b0;
          e0_dx_2x_reg <= fp_add_sub_2_res;
        end
        8'd35: begin
          fp_add_sub_1_a_reg <= e2_00_reg;
          fp_add_sub_1_b_reg <= tmp5;
          fp_add_sub_1_op_reg <= 1'b0;
          fp_add_sub_1_valid_in_reg <= 1'b1;
          e2_00_reg <= fp_add_sub_1_res;
        end
        8'd36: begin
          fp_add_sub_2_a_reg <= e0_00_reg;
          fp_add_sub_2_b_reg <= tmp2;
          fp_add_sub_2_op_reg <= 1'b0;
          fp_add_sub_2_valid_in_reg <= 1'b1;
          fp_add_sub_1_a_reg <= e1_00_reg;
          fp_add_sub_1_b_reg <= tmp7;
          fp_add_sub_1_op_reg <= 1'b0;
          fp_add_sub_1_valid_in_reg <= 1'b1;
          e0_00_reg <= fp_add_sub_2_res;
          e1_00_reg <= fp_add_sub_1_res;
        end
        8'd37: begin
          fp_add_sub_2_valid_in_reg <= 1'b0;
          fp_add_sub_1_valid_in_reg <= 1'b0;
        end
        8'd38: begin
          fp_add_sub_1_a_reg <= e1_00_reg;
          fp_add_sub_1_b_reg <= tmp6;
          fp_add_sub_1_op_reg <= 1'b0;
          fp_add_sub_1_valid_in_reg <= 1'b1;
        end
        8'd39: begin
          fp_add_sub_2_a_reg <= e0_00_reg;
          fp_add_sub_2_b_reg <= tmp8;
          fp_add_sub_2_op_reg <= 1'b0;
          fp_add_sub_2_valid_in_reg <= 1'b1;
          fp_add_sub_1_valid_in_reg <= 1'b0;
          e1_dy_2x_reg <= fp_add_sub_1_res;
        end
        8'd40: begin
          fp_add_sub_1_a_reg <= e2_00_reg;
          fp_add_sub_1_b_reg <= tmp9;
          fp_add_sub_1_op_reg <= 1'b0;
          fp_add_sub_1_valid_in_reg <= 1'b1;
          fp_add_sub_2_valid_in_reg <= 1'b0;
        end
        8'd41: begin
          fp_add_sub_1_valid_in_reg <= 1'b0;
          e2_dy_2x_reg <= fp_add_sub_2_res;
        end
        8'd44: begin
          fp_add_sub_2_a_reg <= e2_10_reg;
          fp_add_sub_2_b_reg <= tmp9;
          fp_add_sub_2_op_reg <= 1'b0;
          fp_add_sub_2_valid_in_reg <= 1'b1;
          e2_10_reg <= fp_add_sub_1_res;
        end
        8'd45: begin
          fp_add_sub_1_a_reg <= e0_10_reg;
          fp_add_sub_1_b_reg <= tmp8;
          fp_add_sub_1_op_reg <= 1'b0;
          fp_add_sub_1_valid_in_reg <= 1'b1;
          fp_add_sub_2_a_reg <= e1_10_reg;
          fp_add_sub_2_b_reg <= tmp6;
          fp_add_sub_2_op_reg <= 1'b0;
          fp_add_sub_2_valid_in_reg <= 1'b1;
          e0_10_reg <= fp_add_sub_2_res;
          e1_10_reg <= fp_add_sub_1_res;
        end
        8'd46: begin
          fp_add_sub_1_valid_in_reg <= 1'b0;
          fp_add_sub_2_valid_in_reg <= 1'b0;
        end
        8'd47: begin
          e1_01_reg <= fp_add_sub_1_res;
        end
        8'd48: begin
          e0_01_reg <= fp_add_sub_2_res;
        end
        8'd49: begin
          e2_01_reg <= fp_add_sub_1_res;
        end
        8'd53: begin
          invArea_reg <= fp_recip_1_out;
          e2_11_reg   <= fp_add_sub_2_res;
        end
        8'd54: begin
          e0_11_reg <= fp_add_sub_1_res;
          e1_11_reg <= fp_add_sub_2_res;
        end
        default: ;
      endcase
    end
  end

  assign ready_out = (state == ST_READ_V0 || state == ST_READ_V1 || state == ST_READ_V2);

  // --------------------------------------------------------------------------
  // FSM State and Cycle Counter Logic
  // --------------------------------------------------------------------------
  localparam int NUM_OF_PIPELINE_STAGES = 55;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= ST_READ_V0;
      cycle_cnt <= '0;
    end else begin
      state <= next_state;
      if (state == ST_CALC) begin
        if (cycle_cnt == CYC_W'(NUM_OF_PIPELINE_STAGES)) begin
          cycle_cnt <= '0;
        end else begin
          cycle_cnt <= cycle_cnt + 1;
        end
      end else if (next_state == ST_CALC) begin
        cycle_cnt <= CYC_W'(0);
      end else begin
        cycle_cnt <= '0;
      end
    end
  end

  always_comb begin
    next_state = state;
    case (state)
      ST_READ_V0: if (valid_in) next_state = ST_READ_V1;
      ST_READ_V1: if (valid_in) next_state = ST_READ_V2;
      ST_READ_V2: if (valid_in) next_state = ST_CALC;
      ST_CALC:    if (cycle_cnt == CYC_W'(NUM_OF_PIPELINE_STAGES)) begin
                    next_state = ST_STALL;
                  end else begin
                    next_state = ST_CALC;
                  end
      ST_STALL:   if (ready_in) begin
                    next_state = ST_READ_V0;
                  end else begin
                    next_state = ST_STALL;
                  end
      default:    next_state = ST_READ_V0;
    endcase
  end

  always_ff @(posedge clk) begin
    if (valid_in) begin
      case (state)
        ST_READ_V0: begin
          v0_reg <= vertex_in;
          tile_x_id_reg <= tile_x_id;
          tile_y_id_reg <= tile_y_id;
          binMinX <= TILE_X_MIN_ROM[tile_x_id];
          binMaxX <= TILE_X_MAX_ROM[tile_x_id];
          binMinY <= TILE_X_MIN_ROM[tile_y_id];
          binMaxY <= TILE_X_MAX_ROM[tile_y_id];
        end
        ST_READ_V1: v1_reg <= vertex_in;
        ST_READ_V2: v2_reg <= vertex_in;
        default: ;
      endcase
    end
  end



  // --------------------------------------------------------------------------
  // Output Ports Buffering
  // --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      out_data_valid <= 1'b0;
      out_e0_00      <= 32'b0;
      out_e1_00      <= 32'b0;
      out_e2_00      <= 32'b0;
      out_e0_10      <= 32'b0;
      out_e1_10      <= 32'b0;
      out_e2_10      <= 32'b0;
      out_e0_01      <= 32'b0;
      out_e1_01      <= 32'b0;
      out_e2_01      <= 32'b0;
      out_e0_11      <= 32'b0;
      out_e1_11      <= 32'b0;
      out_e2_11      <= 32'b0;
      out_e0_dx_2x   <= 32'b0;
      out_e0_dy_2x   <= 32'b0;
      out_e1_dx_2x   <= 32'b0;
      out_e1_dy_2x   <= 32'b0;
      out_e2_dx_2x   <= 32'b0;
      out_e2_dy_2x   <= 32'b0;
      out_invArea    <= 32'b0;
      out_v0         <= '0;
      out_v1         <= '0;
      out_v2         <= '0;
      out_minX_local <= 8'b0;
      out_minY_local <= 8'b0;
      out_width      <= 8'b0;
      out_height     <= 8'b0;
    end else begin
      if (state == ST_CALC && cycle_cnt == CYC_W'(NUM_OF_PIPELINE_STAGES)) begin
        out_data_valid <= 1'b1;
        out_e0_00      <= e0_00_reg;
        out_e1_00      <= e1_00_reg;
        out_e2_00      <= e2_00_reg;
        out_e0_10      <= e0_10_reg;
        out_e1_10      <= e1_10_reg;
        out_e2_10      <= e2_10_reg;
        out_e0_01      <= e0_01_reg;
        out_e1_01      <= e1_01_reg;
        out_e2_01      <= e2_01_reg;
        out_e0_11      <= e0_11_reg;
        out_e1_11      <= e1_11_reg;
        out_e2_11      <= e2_11_reg;
        out_e0_dx_2x   <= e0_dx_2x_reg;
        out_e0_dy_2x   <= e0_dy_2x_reg;
        out_e1_dx_2x   <= e1_dx_2x_reg;
        out_e1_dy_2x   <= e1_dy_2x_reg;
        out_e2_dx_2x   <= e2_dx_2x_reg;
        out_e2_dy_2x   <= e2_dy_2x_reg;
        out_invArea    <= invArea_reg;
        out_v0         <= v0_reg;
        out_v1         <= v1_reg;
        out_v2         <= v2_reg;
        out_minX_local <= bb_start_x_reg[7:0] % TILE_SIZE_X;
        out_minY_local <= bb_start_y_reg[7:0] % TILE_SIZE_Y;
        out_width      <= bb_width_reg;
        out_height     <= bb_height_reg;
      end else if (state == ST_STALL && ready_in) begin
        out_data_valid <= 1'b0;
      end
    end
  end

  assign valid_out = out_data_valid;

endmodule
