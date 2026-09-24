// Fragment Shader (Wasabi)
// Copyright (c) 2026 Stavros Avramidis

// See:
//  - https://www.talisman.org/opengl-1.1/Reference/glTexEnv.html#Description
//  - https://registry.khronos.org/OpenGL-Refpages/gl2.1/xhtml/glTexEnv.xml

`timescale 1ns / 1ns

import gpu_types_pkg::*;

(*use_dsp = "yes"*)
module fragment_shader (
    input logic clk,
    input logic rst_n,

    // Input Data
    input color_argb_t  pixel_color,
    input color_argb_t  texture_color,
    input color_argb_t  env_color,
    input fragment_op_t op,

    // Handshake
    input logic valid_in,

    // Output Data
    output color_argb_t fragment_color,
    output logic valid_out
);


  // Combinatorial adders for ADD operation
  logic [8:0] sum_add_r, sum_add_g, sum_add_b;
  assign sum_add_r = {1'b0, pixel_color.r} + {1'b0, texture_color.r};
  assign sum_add_g = {1'b0, pixel_color.g} + {1'b0, texture_color.g};
  assign sum_add_b = {1'b0, pixel_color.b} + {1'b0, texture_color.b};

  // --------------------------------------------------------
  // Stage 1: Register inputs, saturate ADD op, setup multipliers
  // --------------------------------------------------------
  logic valid_s1;
  fragment_op_t op_s1;
  logic [7:0] C_pass_a_s1, C_pass_r_s1, C_pass_g_s1, C_pass_b_s1;
  logic [7:0] add_r_s1, add_g_s1, add_b_s1;

  logic [7:0] m1_a_r, m1_b_r, m2_a_r, m2_b_r;
  logic [7:0] m1_a_g, m1_b_g, m2_a_g, m2_b_g;
  logic [7:0] m1_a_b, m1_b_b, m2_a_b, m2_b_b;
  logic [7:0] m_a_a, m_a_b;

  // --------------------------------------------------------
  // Stage 2: Multiplications
  // --------------------------------------------------------
  logic valid_s2;
  fragment_op_t op_s2;
  logic [7:0] C_pass_a_s2, C_pass_r_s2, C_pass_g_s2, C_pass_b_s2;
  logic [7:0] add_r_s2, add_g_s2, add_b_s2;

  logic [15:0] prod1_r, prod2_r;
  logic [15:0] prod1_g, prod2_g;
  logic [15:0] prod1_b, prod2_b;
  logic [15:0] prod_a;

  // --------------------------------------------------------
  // Stage 3: Additions
  // --------------------------------------------------------
  logic valid_s3;
  fragment_op_t op_s3;
  logic [7:0] C_pass_a_s3, C_pass_r_s3, C_pass_g_s3, C_pass_b_s3;
  logic [7:0] add_r_s3, add_g_s3, add_b_s3;

  logic [16:0] sum_r, sum_g, sum_b;
  logic [15:0] prod_a_s3;

  // --------------------------------------------------------
  // Stage 4: Division by 255
  // --------------------------------------------------------
  logic valid_s4;
  fragment_op_t op_s4;
  logic [7:0] C_pass_a_s4, C_pass_r_s4, C_pass_g_s4, C_pass_b_s4;
  logic [7:0] add_r_s4, add_g_s4, add_b_s4;

  logic [7:0] div_r, div_g, div_b, div_a;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s1 <= 1'b0;
      valid_s2 <= 1'b0;
      valid_s3 <= 1'b0;
      valid_s4 <= 1'b0;
      valid_out <= 1'b0;
      fragment_color <= '0;
    end else begin
      // ========================================================
      // STAGE 1
      // ========================================================
      valid_s1 <= valid_in;
      op_s1 <= op;

      if (op == REPLACE) begin
        C_pass_a_s1 <= texture_color.a;
        C_pass_r_s1 <= texture_color.r;
        C_pass_g_s1 <= texture_color.g;
        C_pass_b_s1 <= texture_color.b;
      end else begin
        C_pass_a_s1 <= pixel_color.a;
        C_pass_r_s1 <= pixel_color.r;
        C_pass_g_s1 <= pixel_color.g;
        C_pass_b_s1 <= pixel_color.b;
      end

      // Addition with saturation for ADD op
      add_r_s1 <= (sum_add_r > 9'd255) ? 8'd255 : sum_add_r[7:0];
      add_g_s1 <= (sum_add_g > 9'd255) ? 8'd255 : sum_add_g[7:0];
      add_b_s1 <= (sum_add_b > 9'd255) ? 8'd255 : sum_add_b[7:0];

      // Setup Multipliers
      m1_a_r   <= pixel_color.r;
      m1_a_g   <= pixel_color.g;
      m1_a_b   <= pixel_color.b;

      case (op)
        DECAL: begin
          m1_b_r <= 8'd255 - texture_color.a;
          m1_b_g <= 8'd255 - texture_color.a;
          m1_b_b <= 8'd255 - texture_color.a;

          m2_a_r <= texture_color.r;
          m2_a_g <= texture_color.g;
          m2_a_b <= texture_color.b;

          m2_b_r <= texture_color.a;
          m2_b_g <= texture_color.a;
          m2_b_b <= texture_color.a;
        end
        BLEND: begin
          m1_b_r <= 8'd255 - texture_color.r;
          m1_b_g <= 8'd255 - texture_color.g;
          m1_b_b <= 8'd255 - texture_color.b;

          m2_a_r <= env_color.r;
          m2_a_g <= env_color.g;
          m2_a_b <= env_color.b;

          m2_b_r <= texture_color.r;
          m2_b_g <= texture_color.g;
          m2_b_b <= texture_color.b;
        end
        default: begin
          m1_b_r <= texture_color.r;
          m1_b_g <= texture_color.g;
          m1_b_b <= texture_color.b;

          m2_a_r <= 8'd0;
          m2_a_g <= 8'd0;
          m2_a_b <= 8'd0;

          m2_b_r <= 8'd0;
          m2_b_g <= 8'd0;
          m2_b_b <= 8'd0;
        end
      endcase

      // Setup Multiplier for A
      m_a_a <= pixel_color.a;
      m_a_b <= texture_color.a;

      // ========================================================
      // STAGE 2
      // ========================================================
      valid_s2 <= valid_s1;
      op_s2 <= op_s1;
      C_pass_a_s2 <= C_pass_a_s1;
      C_pass_r_s2 <= C_pass_r_s1;
      C_pass_g_s2 <= C_pass_g_s1;
      C_pass_b_s2 <= C_pass_b_s1;
      add_r_s2 <= add_r_s1;
      add_g_s2 <= add_g_s1;
      add_b_s2 <= add_b_s1;

      prod1_r <= m1_a_r * m1_b_r;
      prod2_r <= m2_a_r * m2_b_r;

      prod1_g <= m1_a_g * m1_b_g;
      prod2_g <= m2_a_g * m2_b_g;

      prod1_b <= m1_a_b * m1_b_b;
      prod2_b <= m2_a_b * m2_b_b;

      prod_a <= m_a_a * m_a_b;

      // ========================================================
      // STAGE 3
      // ========================================================
      valid_s3 <= valid_s2;
      op_s3 <= op_s2;
      C_pass_a_s3 <= C_pass_a_s2;
      C_pass_r_s3 <= C_pass_r_s2;
      C_pass_g_s3 <= C_pass_g_s2;
      C_pass_b_s3 <= C_pass_b_s2;
      add_r_s3 <= add_r_s2;
      add_g_s3 <= add_g_s2;
      add_b_s3 <= add_b_s2;

      sum_r <= prod1_r + prod2_r;
      sum_g <= prod1_g + prod2_g;
      sum_b <= prod1_b + prod2_b;
      prod_a_s3 <= prod_a;

      // ========================================================
      // STAGE 4
      // ========================================================
      valid_s4 <= valid_s3;
      op_s4 <= op_s3;
      C_pass_a_s4 <= C_pass_a_s3;
      C_pass_r_s4 <= C_pass_r_s3;
      C_pass_g_s4 <= C_pass_g_s3;
      C_pass_b_s4 <= C_pass_b_s3;
      add_r_s4 <= add_r_s3;
      add_g_s4 <= add_g_s3;
      add_b_s4 <= add_b_s3;

      /* verilator lint_off WIDTHTRUNC */
      div_r <= (sum_r + 17'd128) >> 8;
      div_g <= (sum_g + 17'd128) >> 8;
      div_b <= (sum_b + 17'd128) >> 8;
      div_a <= (prod_a_s3 + 16'd128) >> 8;
      /* verilator lint_on WIDTHTRUNC */

      // ========================================================
      // STAGE 5 (Final Output Selection)
      // ========================================================
      valid_out <= valid_s4;

      case (op_s4)
        REPLACE: fragment_color <= {C_pass_a_s4, C_pass_r_s4, C_pass_g_s4, C_pass_b_s4};
        MODULATE: fragment_color <= {div_a, div_r, div_g, div_b};
        DECAL: fragment_color <= {C_pass_a_s4, div_r, div_g, div_b};
        BLEND: fragment_color <= {div_a, div_r, div_g, div_b};
        ADD: fragment_color <= {div_a, add_r_s4, add_g_s4, add_b_s4};
        COLOR: fragment_color <= {C_pass_a_s4, C_pass_r_s4, C_pass_g_s4, C_pass_b_s4};
        default: fragment_color <= '0;
      endcase
    end
  end

endmodule
