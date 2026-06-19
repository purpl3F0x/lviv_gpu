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
    output logic    [31:0] out_e0_row,
    output logic    [31:0] out_e1_row,
    output logic    [31:0] out_e2_row,
    output logic    [31:0] out_e0_10,
    output logic    [31:0] out_e1_10,
    output logic    [31:0] out_e2_10,
    output logic    [31:0] out_e0_01,
    output logic    [31:0] out_e1_01,
    output logic    [31:0] out_e2_01,
    output logic    [31:0] out_e0_11,
    output logic    [31:0] out_e1_11,
    output logic    [31:0] out_e2_11,
    output logic    [31:0] out_e0_dx,
    output logic    [31:0] out_e0_dy,
    output logic    [31:0] out_e1_dx,
    output logic    [31:0] out_e1_dy,
    output logic    [31:0] out_e2_dx,
    output logic    [31:0] out_e2_dy,
    output logic    [31:0] out_invArea,
    output vertex_t        out_v0,
    output vertex_t        out_v1,
    output vertex_t        out_v2,
    output logic    [6:0]  out_minX_local,
    output logic    [6:0]  out_minY_local,
    output logic    [7:0]  out_width,
    output logic    [7:0]  out_height
);

  // --------------------------------------------------------------------------
  // Delay & Latency Configuration
  // --------------------------------------------------------------------------
  localparam int SUB_LATENCY = 11;
  localparam int MUL_LATENCY = 8;
  localparam int RECIP_LATENCY = 29;
  localparam int CONV_LATENCY = 6;

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

  localparam int CYC_W = 8;
  logic [CYC_W-1:0] cycle_cnt;
  logic             out_data_valid;

  // --------------------------------------------------------------------------
  // Internal Signal Declarations
  // --------------------------------------------------------------------------
  logic [31:0] mul0_a, mul0_b, mul0_res;
  logic [31:0] recip0_a, recip0_res;
  logic        mul0_valid_in;
  logic        recip0_valid_in;

  logic [36:0] v0_fixed, v1_fixed, v2_fixed;
  logic [31:0] conv_v0_a, conv_v1_a, conv_v2_a;
  logic        conv_v0_v, conv_v1_v, conv_v2_v;

  logic signed [14:0] triMinX_reg, triMaxX_reg;
  logic signed [14:0] triMinY_reg, triMaxY_reg;
  logic signed [13:0] minX_reg, maxX_reg;
  logic signed [13:0] minY_reg, maxY_reg;
  logic [6:0] x_start_reg, y_start_reg;
  logic [7:0] x_size_reg, y_size_reg;

  logic [15:0] conv_x_a;
  logic        conv_x_v;
  logic [31:0] conv_x_res;

  logic [31:0] p00_x_reg, p00_y_reg;

  logic [31:0] add_sub0_a, add_sub0_b, add_sub0_res;
  logic        add_sub0_op;
  logic        add_sub0_v;

  logic [31:0] add_sub1_a, add_sub1_b, add_sub1_res;
  logic        add_sub1_op;
  logic        add_sub1_v;

  logic [31:0] area_A_reg, area_B_reg;
  logic [31:0] area_C_reg, area_D_reg;
  logic [31:0] e0_A_reg, e0_dx_reg;
  logic [31:0] e0_C_reg;
  logic [31:0] e1_A_reg, e1_dx_reg;
  logic [31:0] e1_C_reg;
  logic [31:0] e2_A_reg, e2_dx_reg;
  logic [31:0] e2_C_reg;

  logic [31:0] area_E, area_F;
  logic [31:0] e0_E, e0_F;
  logic [31:0] e1_E, e1_F;
  logic [31:0] e2_E, e2_F;

  logic [31:0] area_G_reg;
  logic [31:0] e0_row_reg;
  logic [31:0] e1_row_reg;
  logic [31:0] e2_row_reg;
  logic [31:0] e0_dy_reg;
  logic [31:0] e1_dy_reg;
  logic [31:0] e2_dy_reg;

  logic [31:0] invArea_reg;

  logic [31:0] e0_dx_plus_dy, e1_dx_plus_dy, e2_dx_plus_dy;
  logic [31:0] e0_10_reg, e0_01_reg, e0_11_reg;
  logic [31:0] e1_10_reg, e1_01_reg, e1_11_reg;
  logic [31:0] e2_10_reg, e2_01_reg;

  fp_mul #(
      .LATENCY(MUL_LATENCY)
  ) u_mul0 (
      .aclk    (clk),
      .aresetn (rst_n),
      .aclken  (1'b1),
      .valid_in(mul0_valid_in),
      .a       (mul0_a),
      .b       (mul0_b),
      .result  (mul0_res)
  );

  fp_recip #(
      .LATENCY(RECIP_LATENCY)
  ) u_recip0 (
      .aclk    (clk),
      .aresetn (rst_n),
      .aclken  (1'b1),
      .valid_in(recip0_valid_in),
      .a       (recip0_a),
      .result  (recip0_res)
  );

  // --------------------------------------------------------------------------
  // Bounding Box Logic & Coordinates Converters
  // --------------------------------------------------------------------------


  fp_to_s14q23 #(
      .LATENCY(CONV_LATENCY)
  ) u_conv_v0 (
      .aclk    (clk),
      .aresetn (rst_n),
      .aclken  (1'b1),
      .valid_in(conv_v0_v),
      .a       (conv_v0_a),
      .result  (v0_fixed)
  );

  fp_to_s14q23 #(
      .LATENCY(CONV_LATENCY)
  ) u_conv_v1 (
      .aclk    (clk),
      .aresetn (rst_n),
      .aclken  (1'b1),
      .valid_in(conv_v1_v),
      .a       (conv_v1_a),
      .result  (v1_fixed)
  );

  fp_to_s14q23 #(
      .LATENCY(CONV_LATENCY)
  ) u_conv_v2 (
      .aclk    (clk),
      .aresetn (rst_n),
      .aclken  (1'b1),
      .valid_in(conv_v2_v),
      .a       (conv_v2_a),
      .result  (v2_fixed)
  );

  always_comb begin
    conv_v0_a = 32'b0;
    conv_v1_a = 32'b0;
    conv_v2_a = 32'b0;
    conv_v0_v = 1'b0;
    conv_v1_v = 1'b0;
    conv_v2_v = 1'b0;

    if (state == ST_CALC) begin
      if (cycle_cnt == 8'd1) begin
        conv_v0_a = v0_reg.x;
        conv_v1_a = v1_reg.x;
        conv_v2_a = v2_reg.x;
        conv_v0_v = 1'b1;
        conv_v1_v = 1'b1;
        conv_v2_v = 1'b1;
      end else if (cycle_cnt == 8'd2) begin
        conv_v0_a = v0_reg.y;
        conv_v1_a = v1_reg.y;
        conv_v2_a = v2_reg.y;
        conv_v0_v = 1'b1;
        conv_v1_v = 1'b1;
        conv_v2_v = 1'b1;
      end
    end
  end



  function automatic logic signed [14:0] min3(logic signed [14:0] a, logic signed [14:0] b, logic signed [14:0] c);
    logic signed [14:0] tmp;
    tmp = (a < b) ? a : b;
    return (tmp < c) ? tmp : c;
  endfunction

  function automatic logic signed [14:0] max3(logic signed [14:0] a, logic signed [14:0] b, logic signed [14:0] c);
    logic signed [14:0] tmp;
    tmp = (a > b) ? a : b;
    return (tmp > c) ? tmp : c;
  endfunction

  // Combinational inputs to the min3/max3 at Cycle 7 & Cycle 8
  logic signed [14:0] v0x_floor, v1x_floor, v2x_floor;
  logic signed [14:0] v0x_ceil, v1x_ceil, v2x_ceil;
  logic signed [14:0] triMinX, triMaxX;

  assign v0x_floor = v0_fixed[36:23];
  assign v1x_floor = v1_fixed[36:23];
  assign v2x_floor = v2_fixed[36:23];
  assign v0x_ceil  = (v0_fixed[22:0] == 23'd0) ? v0_fixed[36:23] : v0_fixed[36:23] + 15'sd1;
  assign v1x_ceil  = (v1_fixed[22:0] == 23'd0) ? v1_fixed[36:23] : v1_fixed[36:23] + 15'sd1;
  assign v2x_ceil  = (v2_fixed[22:0] == 23'd0) ? v2_fixed[36:23] : v2_fixed[36:23] + 15'sd1;

  assign triMinX = min3(v0x_floor, v1x_floor, v2x_floor);
  assign triMaxX = max3(v0x_ceil, v1x_ceil, v2x_ceil);

  logic signed [14:0] v0y_floor, v1y_floor, v2y_floor;
  logic signed [14:0] v0y_ceil, v1y_ceil, v2y_ceil;
  logic signed [14:0] triMinY, triMaxY;

  assign v0y_floor = v0_fixed[36:23];
  assign v1y_floor = v1_fixed[36:23];
  assign v2y_floor = v2_fixed[36:23];
  assign v0y_ceil  = (v0_fixed[22:0] == 23'd0) ? v0_fixed[36:23] : v0_fixed[36:23] + 15'sd1;
  assign v1y_ceil  = (v1_fixed[22:0] == 23'd0) ? v1_fixed[36:23] : v1_fixed[36:23] + 15'sd1;
  assign v2y_ceil  = (v2_fixed[22:0] == 23'd0) ? v2_fixed[36:23] : v2_fixed[36:23] + 15'sd1;

  assign triMinY = min3(v0y_floor, v1y_floor, v2y_floor);
  assign triMaxY = max3(v0y_ceil, v1y_ceil, v2y_ceil);

  // Align/Intersect combinational logic
  logic [13:0] binMinX, binMinY, binMaxX, binMaxY;
  assign binMinX = {tile_x_id_reg, 7'b0};
  assign binMinY = {tile_y_id_reg, 7'b0};
  assign binMaxX = binMinX + 14'd127;
  assign binMaxY = binMinY + 14'd127;

  logic signed [13:0] triMinX_aligned, triMaxX_aligned;
  assign triMinX_aligned = triMinX_reg & 14'h3FFE;
  assign triMaxX_aligned = triMaxX_reg | 14'h0001;

  logic signed [13:0] minX, maxX_temp, maxX;
  assign minX = (signed'(binMinX) > triMinX_aligned) ? signed'(binMinX) : triMinX_aligned;
  assign maxX_temp = (signed'(binMaxX) < triMaxX_aligned) ? signed'(binMaxX) : triMaxX_aligned;
  assign maxX = (maxX_temp <= minX) ? (minX + 14'sd1) : maxX_temp;

  logic signed [13:0] triMinY_aligned, triMaxY_aligned;
  assign triMinY_aligned = triMinY_reg & 14'h3FFE;
  assign triMaxY_aligned = triMaxY_reg | 14'h0001;

  logic signed [13:0] minY, maxY_temp, maxY;
  assign minY = (signed'(binMinY) > triMinY_aligned) ? signed'(binMinY) : triMinY_aligned;
  assign maxY_temp = (signed'(binMaxY) < triMaxY_aligned) ? signed'(binMaxY) : triMaxY_aligned;
  assign maxY = (maxY_temp <= minY) ? (minY + 14'sd1) : maxY_temp;

  logic signed [15:0] x0_q2, y0_q2;
  assign x0_q2 = {minX, 2'b10};
  assign y0_q2 = {minY, 2'b10};



  s14_q2_to_fp #(
      .LATENCY(CONV_LATENCY)
  ) u_conv_x (
      .aclk    (clk),
      .aresetn (rst_n),
      .aclken  (1'b1),
      .valid_in(conv_x_v),
      .a       (conv_x_a),
      .result  (conv_x_res)
  );

  always_comb begin
    conv_x_a = 16'b0;
    conv_x_v = 1'b0;

    if (state == ST_CALC) begin
      case (cycle_cnt)
        8'd8: begin
          conv_x_a = x0_q2;
          conv_x_v = 1'b1;
        end
        8'd9: begin
          conv_x_a = y0_q2;
          conv_x_v = 1'b1;
        end
        default: ;
      endcase
    end
  end



  always_ff @(posedge clk) begin
    if (!rst_n) begin
      p00_x_reg <= 32'b0;
      p00_y_reg <= 32'b0;
    end else if (state == ST_CALC) begin
      if (cycle_cnt == 8'd14) begin
        p00_x_reg <= conv_x_res;
      end else if (cycle_cnt == 8'd15) begin
        p00_y_reg <= conv_x_res;
      end
    end
  end

  // --------------------------------------------------------------------------
  // Quad-Pixel Edge Calculation FP Add/Sub Units: 2 instances
  // --------------------------------------------------------------------------


  fp_add_sub #(
      .LATENCY(11)
  ) u_add_sub0 (
      .aclk    (clk),
      .aresetn (rst_n),
      .aclken  (1'b1),
      .op_sub  (add_sub0_op),
      .valid_in(add_sub0_v),
      .a       (add_sub0_a),
      .b       (add_sub0_b),
      .result  (add_sub0_res)
  );

  fp_add_sub #(
      .LATENCY(11)
  ) u_add_sub1 (
      .aclk    (clk),
      .aresetn (rst_n),
      .aclken  (1'b1),
      .op_sub  (add_sub1_op),
      .valid_in(add_sub1_v),
      .a       (add_sub1_a),
      .b       (add_sub1_b),
      .result  (add_sub1_res)
  );

  always_comb begin
    mul0_a = 32'b0;
    mul0_b = 32'b0;
    mul0_valid_in = 1'b0;

    if (state == ST_CALC) begin
      case (cycle_cnt)
        8'd12: begin
          mul0_a = area_A_reg;
          mul0_b = area_B_reg;
          mul0_valid_in = 1'b1;
        end
        8'd13: begin
          mul0_a = area_C_reg;
          mul0_b = area_D_reg;
          mul0_valid_in = 1'b1;
        end
        8'd25: begin
          mul0_a = add_sub0_res;
          mul0_b = e0_dx_reg;
          mul0_valid_in = 1'b1;
        end
        8'd26: begin
          mul0_a = e1_A_reg;
          mul0_b = e1_dx_reg;
          mul0_valid_in = 1'b1;
        end
        8'd27: begin
          mul0_a = e0_C_reg;
          mul0_b = e0_dy_reg;
          mul0_valid_in = 1'b1;
        end
        8'd28: begin
          mul0_a = e1_C_reg;
          mul0_b = e1_dy_reg;
          mul0_valid_in = 1'b1;
        end
        8'd29: begin
          mul0_a = e2_A_reg;
          mul0_b = e2_dx_reg;
          mul0_valid_in = 1'b1;
        end
        8'd30: begin
          mul0_a = e2_C_reg;
          mul0_b = e2_dy_reg;
          mul0_valid_in = 1'b1;
        end
        default: ;
      endcase
    end
  end

  always_comb begin
    recip0_a = 32'b0;
    recip0_valid_in = 1'b0;

    if (state == ST_CALC) begin
      case (cycle_cnt)
        8'd32: begin
          recip0_a = add_sub1_res;
          recip0_valid_in = 1'b1;
        end
        default: ;
      endcase
    end
  end

  always_comb begin
    add_sub0_a = 32'b0;
    add_sub0_b = 32'b0;
    add_sub0_op = 1'b0;
    add_sub0_v = 1'b0;

    add_sub1_a = 32'b0;
    add_sub1_b = 32'b0;
    add_sub1_op = 1'b0;
    add_sub1_v = 1'b0;

    if (state == ST_READ_V2 && valid_in) begin
      // Transition/Cycle 0 subtraction
      add_sub0_a = vertex_in.x;
      add_sub0_b = v0_reg.x;
      add_sub0_op = 1'b1; // sub
      add_sub0_v = 1'b1;

      add_sub1_a = v1_reg.y;
      add_sub1_b = v0_reg.y;
      add_sub1_op = 1'b1; // sub
      add_sub1_v = 1'b1;
    end else if (state == ST_CALC) begin
      case (cycle_cnt)
        // Cycle 1 subtraction: area_C, area_D
        8'd1: begin
          add_sub0_a = v2_reg.y;
          add_sub0_b = v0_reg.y;
          add_sub0_op = 1'b1;
          add_sub0_v = 1'b1;

          add_sub1_a = v1_reg.x;
          add_sub1_b = v0_reg.x;
          add_sub1_op = 1'b1;
          add_sub1_v = 1'b1;
        end
        // Cycle 2 subtraction: e0_dx
        8'd2: begin
          add_sub1_a = v2_reg.y;
          add_sub1_b = v1_reg.y;
          add_sub1_op = 1'b1;
          add_sub1_v = 1'b1;
        end
        // Cycle 3 subtraction: e0_dy
        8'd3: begin
          add_sub1_a = v1_reg.x;
          add_sub1_b = v2_reg.x;
          add_sub1_op = 1'b1;
          add_sub1_v = 1'b1;
        end
        // Cycle 4 subtraction: e1_dx
        8'd4: begin
          add_sub1_a = v0_reg.y;
          add_sub1_b = v2_reg.y;
          add_sub1_op = 1'b1;
          add_sub1_v = 1'b1;
        end
        // Cycle 5 subtraction: e1_dy
        8'd5: begin
          add_sub1_a = v2_reg.x;
          add_sub1_b = v0_reg.x;
          add_sub1_op = 1'b1;
          add_sub1_v = 1'b1;
        end
        // Cycle 6 subtraction: e2_dx
        8'd6: begin
          add_sub1_a = v1_reg.y;
          add_sub1_b = v0_reg.y;
          add_sub1_op = 1'b1;
          add_sub1_v = 1'b1;
        end
        // Cycle 7 subtraction: e2_dy
        8'd7: begin
          add_sub1_a = v0_reg.x;
          add_sub1_b = v1_reg.x;
          add_sub1_op = 1'b1;
          add_sub1_v = 1'b1;
        end
        // Cycle 14 subtraction: e0_A, e1_A
        8'd14: begin
          add_sub0_a = conv_x_res;
          add_sub0_b = v1_reg.x;
          add_sub0_op = 1'b1;
          add_sub0_v = 1'b1;

          add_sub1_a = conv_x_res;
          add_sub1_b = v2_reg.x;
          add_sub1_op = 1'b1;
          add_sub1_v = 1'b1;
        end
        // Cycle 15 subtraction: e2_A, e0_C
        8'd15: begin
          add_sub0_a = p00_x_reg;
          add_sub0_b = v0_reg.x;
          add_sub0_op = 1'b1;
          add_sub0_v = 1'b1;

          add_sub1_a = conv_x_res;
          add_sub1_b = v1_reg.y;
          add_sub1_op = 1'b1;
          add_sub1_v = 1'b1;
        end
        // Cycle 16 subtraction: e1_C, e2_C
        8'd16: begin
          add_sub0_a = p00_y_reg;
          add_sub0_b = v2_reg.y;
          add_sub0_op = 1'b1;
          add_sub0_v = 1'b1;

          add_sub1_a = p00_y_reg;
          add_sub1_b = v0_reg.y;
          add_sub1_op = 1'b1;
          add_sub1_v = 1'b1;
        end
        // Cycle 20 additions: e0_dx_plus_dy, e1_dx_plus_dy
        8'd20: begin
          add_sub0_a = e0_dx_reg;
          add_sub0_b = e0_dy_reg;
          add_sub0_op = 1'b0; // add
          add_sub0_v = 1'b1;

          add_sub1_a = e1_dx_reg;
          add_sub1_b = e1_dy_reg;
          add_sub1_op = 1'b0; // add
          add_sub1_v = 1'b1;
        end
        // Cycle 21 addition and subtraction: e2_dx_plus_dy, area_G
        8'd21: begin
          add_sub0_a = e2_dx_reg;
          add_sub0_b = e2_dy_reg;
          add_sub0_op = 1'b0; // add
          add_sub0_v = 1'b1;

          add_sub1_a = area_E;
          add_sub1_b = mul0_res;
          add_sub1_op = 1'b1; // sub
          add_sub1_v = 1'b1;
        end
        // Cycle 35 subtraction: e0_row
        8'd35: begin
          add_sub0_a = e0_E;
          add_sub0_b = mul0_res;
          add_sub0_op = 1'b1;
          add_sub0_v = 1'b1;
        end
        // Cycle 36 subtraction: e1_row
        8'd36: begin
          add_sub0_a = e1_E;
          add_sub0_b = mul0_res;
          add_sub0_op = 1'b1;
          add_sub0_v = 1'b1;
        end
        // Cycle 38 subtraction: e2_row
        8'd38: begin
          add_sub0_a = e2_E;
          add_sub0_b = mul0_res;
          add_sub0_op = 1'b1;
          add_sub0_v = 1'b1;
        end
        // Cycle 45 additions: e0_10, e0_01
        8'd45: begin
          add_sub0_a = e0_row_reg;
          add_sub0_b = e0_dx_reg;
          add_sub0_op = 1'b0; // add
          add_sub0_v = 1'b1;

          add_sub1_a = e0_row_reg;
          add_sub1_b = e0_dy_reg;
          add_sub1_op = 1'b0; // add
          add_sub1_v = 1'b1;
        end
        // Cycle 46 addition: e0_11
        8'd46: begin
          add_sub0_a = e0_row_reg;
          add_sub0_b = e0_dx_plus_dy;
          add_sub0_op = 1'b0;
          add_sub0_v = 1'b1;
        end
        // Cycle 47 additions: e1_10, e1_01
        8'd47: begin
          add_sub0_a = e1_row_reg;
          add_sub0_b = e1_dx_reg;
          add_sub0_op = 1'b0;
          add_sub0_v = 1'b1;

          add_sub1_a = e1_row_reg;
          add_sub1_b = e1_dy_reg;
          add_sub1_op = 1'b0;
          add_sub1_v = 1'b1;
        end
        // Cycle 48 addition: e1_11
        8'd48: begin
          add_sub0_a = e1_row_reg;
          add_sub0_b = e1_dx_plus_dy;
          add_sub0_op = 1'b0;
          add_sub0_v = 1'b1;
        end
        // Cycle 49 additions: e2_10, e2_01
        8'd49: begin
          add_sub0_a = e2_row_reg;
          add_sub0_b = e2_dx_reg;
          add_sub0_op = 1'b0;
          add_sub0_v = 1'b1;

          add_sub1_a = e2_row_reg;
          add_sub1_b = e2_dy_reg;
          add_sub1_op = 1'b0;
          add_sub1_v = 1'b1;
        end
        // Cycle 50 addition: e2_11
        8'd50: begin
          add_sub0_a = e2_row_reg;
          add_sub0_b = e2_dx_plus_dy;
          add_sub0_op = 1'b0;
          add_sub0_v = 1'b1;
        end
        default: ;
      endcase
    end
  end



  // --------------------------------------------------------------------------
  // FSM Cycle and Latency Calculations
  // --------------------------------------------------------------------------
  localparam int CYC_LATCH_INVAREA = 61;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      area_A_reg  <= '0;
      area_B_reg  <= '0;
      area_C_reg  <= '0;
      area_D_reg  <= '0;
      e0_A_reg    <= '0;
      e0_dx_reg   <= '0;
      e0_C_reg    <= '0;
      e1_A_reg    <= '0;
      e1_dx_reg   <= '0;
      e1_C_reg    <= '0;
      e2_A_reg    <= '0;
      e2_dx_reg   <= '0;
      e2_C_reg    <= '0;
      area_E      <= '0;
      area_F      <= '0;
      e0_E        <= '0;
      e0_F        <= '0;
      e1_E        <= '0;
      e1_F        <= '0;
      e2_E        <= '0;
      e2_F        <= '0;
      area_G_reg  <= '0;
      e0_row_reg  <= '0;
      e1_row_reg  <= '0;
      e2_row_reg  <= '0;
      e0_dy_reg   <= '0;
      e1_dy_reg   <= '0;
      e2_dy_reg   <= '0;
      invArea_reg <= '0;
      minX_reg    <= '0;
      minY_reg    <= '0;
      maxX_reg    <= '0;
      maxY_reg    <= '0;
      triMinX_reg <= '0;
      triMaxX_reg <= '0;
      triMinY_reg <= '0;
      triMaxY_reg <= '0;
      e0_dx_plus_dy <= '0;
      e1_dx_plus_dy <= '0;
      e2_dx_plus_dy <= '0;
      e0_10_reg   <= '0;
      e0_01_reg   <= '0;
      e0_11_reg   <= '0;
      e1_10_reg   <= '0;
      e1_01_reg   <= '0;
      e1_11_reg   <= '0;
      e2_10_reg   <= '0;
      e2_01_reg   <= '0;
      x_start_reg <= '0;
      y_start_reg <= '0;
      x_size_reg  <= '0;
      y_size_reg  <= '0;
    end else if (state == ST_CALC) begin
      case (cycle_cnt)
        8'd7: begin
          triMinX_reg <= triMinX;
          triMaxX_reg <= triMaxX;
        end
        8'd8: begin
          triMinY_reg <= triMinY;
          triMaxY_reg <= triMaxY;
          minX_reg    <= minX;
          maxX_reg    <= maxX;
          y_start_reg <= minX[6:0];
          x_size_reg  <= 8'(maxX - minX);
        end
        8'd9: begin
          minY_reg    <= minY;
          maxY_reg    <= maxY;
          x_start_reg <= minY[6:0];
          y_size_reg  <= 8'(maxY - minY);
        end
        8'd11: begin
          area_A_reg <= add_sub0_res;
          area_B_reg <= add_sub1_res;
        end
        8'd12: begin
          area_C_reg <= add_sub0_res;
          area_D_reg <= add_sub1_res;
        end
        8'd13: begin
          e0_dx_reg  <= add_sub1_res;
        end
        8'd14: begin
          e0_dy_reg  <= add_sub1_res;
        end
        8'd15: begin
          e1_dx_reg  <= add_sub1_res;
        end
        8'd16: begin
          e1_dy_reg  <= add_sub1_res;
        end
        8'd17: begin
          e2_dx_reg  <= add_sub1_res;
        end
        8'd18: begin
          e2_dy_reg  <= add_sub1_res;
        end
        8'd20: begin
          area_E     <= mul0_res;
        end
        8'd21: begin
          area_F     <= mul0_res;
        end
        8'd25: begin
          e0_A_reg   <= add_sub0_res;
          e1_A_reg   <= add_sub1_res;
        end
        8'd26: begin
          e2_A_reg   <= add_sub0_res;
          e0_C_reg   <= add_sub1_res;
        end
        8'd27: begin
          e1_C_reg   <= add_sub0_res;
          e2_C_reg   <= add_sub1_res;
        end
        8'd31: begin
          e0_dx_plus_dy <= add_sub0_res;
          e1_dx_plus_dy <= add_sub1_res;
        end
        8'd32: begin
          e2_dx_plus_dy <= add_sub0_res;
          area_G_reg    <= add_sub1_res;
        end
        8'd33: begin
          e0_E       <= mul0_res;
        end
        8'd34: begin
          e1_E       <= mul0_res;
        end
        8'd35: begin
          e0_F       <= mul0_res;
        end
        8'd36: begin
          e1_F       <= mul0_res;
        end
        8'd37: begin
          e2_E       <= mul0_res;
        end
        8'd38: begin
          e2_F       <= mul0_res;
        end
        8'd46: begin
          e0_row_reg <= add_sub0_res;
        end
        8'd47: begin
          e1_row_reg <= add_sub0_res;
        end
        8'd49: begin
          e2_row_reg <= add_sub0_res;
        end
        8'd56: begin
          e0_10_reg  <= add_sub0_res;
          e0_01_reg  <= add_sub1_res;
        end
        8'd57: begin
          e0_11_reg  <= add_sub0_res;
        end
        8'd58: begin
          e1_10_reg  <= add_sub0_res;
          e1_01_reg  <= add_sub1_res;
        end
        8'd59: begin
          e1_11_reg  <= add_sub0_res;
        end
        8'd60: begin
          e2_10_reg  <= add_sub0_res;
          e2_01_reg  <= add_sub1_res;
        end
        8'd61: begin
          invArea_reg <= recip0_res;
        end
        default: ;
      endcase
    end
  end

  // Ready to accept data if we are in reading states
  assign ready_out = (state == ST_READ_V0 || state == ST_READ_V1 || state == ST_READ_V2);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= ST_READ_V0;
      cycle_cnt <= '0;
    end else begin
      state <= next_state;
      if (state == ST_CALC) begin
        if (cycle_cnt == CYC_W'(CYC_LATCH_INVAREA)) begin
          cycle_cnt <= '0;
        end else begin
          cycle_cnt <= cycle_cnt + 1;
        end
      end else if (next_state == ST_CALC) begin
        cycle_cnt <= CYC_W'(1);
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
      ST_CALC:    if (cycle_cnt == CYC_W'(CYC_LATCH_INVAREA)) begin
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
        end
        ST_READ_V1: v1_reg <= vertex_in;
        ST_READ_V2: v2_reg <= vertex_in;
        default: ;
      endcase
    end
  end


  always_ff @(posedge clk) begin
    if (!rst_n) begin
      out_data_valid <= 1'b0;
      out_e0_row     <= 32'b0;
      out_e1_row     <= 32'b0;
      out_e2_row     <= 32'b0;
      out_e0_10      <= 32'b0;
      out_e1_10      <= 32'b0;
      out_e2_10      <= 32'b0;
      out_e0_01      <= 32'b0;
      out_e1_01      <= 32'b0;
      out_e2_01      <= 32'b0;
      out_e0_11      <= 32'b0;
      out_e1_11      <= 32'b0;
      out_e2_11      <= 32'b0;
      out_e0_dx      <= 32'b0;
      out_e0_dy      <= 32'b0;
      out_e1_dx      <= 32'b0;
      out_e1_dy      <= 32'b0;
      out_e2_dx      <= 32'b0;
      out_e2_dy      <= 32'b0;
      out_invArea    <= 32'b0;
      out_v0         <= '0;
      out_v1         <= '0;
      out_v2         <= '0;
      out_minX_local <= 7'b0;
      out_minY_local <= 7'b0;
      out_width      <= 8'b0;
      out_height     <= 8'b0;
    end else begin
      if (state == ST_CALC && cycle_cnt == CYC_W'(CYC_LATCH_INVAREA)) begin
        out_data_valid <= 1'b1;
        out_e0_row     <= e0_row_reg;
        out_e1_row     <= e1_row_reg;
        out_e2_row     <= e2_row_reg;
        out_e0_10      <= e0_10_reg;
        out_e1_10      <= e1_10_reg;
        out_e2_10      <= e2_10_reg;
        out_e0_01      <= e0_01_reg;
        out_e1_01      <= e1_01_reg;
        out_e2_01      <= e2_01_reg;
        out_e0_11      <= e0_11_reg;
        out_e1_11      <= e1_11_reg;
        out_e2_11      <= add_sub0_res;
        out_e0_dx      <= e0_dx_reg;
        out_e0_dy      <= e0_dy_reg;
        out_e1_dx      <= e1_dx_reg;
        out_e1_dy      <= e1_dy_reg;
        out_e2_dx      <= e2_dx_reg;
        out_e2_dy      <= e2_dy_reg;
        out_invArea    <= recip0_res;
        out_v0         <= v0_reg;
        out_v1         <= v1_reg;
        out_v2         <= v2_reg;
        out_minX_local <= x_start_reg;
        out_minY_local <= y_start_reg;
        out_width      <= x_size_reg;
        out_height     <= y_size_reg;
      end else if (state == ST_STALL && ready_in) begin
        out_data_valid <= 1'b0;
      end
    end
  end

  assign valid_out = out_data_valid;

endmodule
