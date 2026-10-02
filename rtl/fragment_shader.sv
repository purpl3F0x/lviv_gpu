// Fragment Shader (Wasabi)
// Copyright (c) 2026 Stavros Avramidis

// See:
//  - https://www.talisman.org/opengl-1.1/Reference/glTexEnv.html#Description
//  - https://registry.khronos.org/OpenGL-Refpages/gl2.1/xhtml/glTexEnv.xml

`timescale 1ns / 1ns

import gpu_types_pkg::*;

(* use_dsp = "simd" *)
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


  // Stage 1: Capture inputs before shader datapath processing.
  logic valid_s0;
  fragment_op_t op_s0;
  color_argb_t pixel_color_s0;
  color_argb_t texture_color_s0_a, texture_color_s0_b; // This is important to force using DSP in SIMD mode
  color_argb_t env_color_s0;

  // --------------------------------------------------------
  // Stage 2: Saturate ADD op, setup multipliers
  // --------------------------------------------------------
  logic valid_s1;
  fragment_op_t op_s1;
  logic [7:0] C_pass_a_s1, C_pass_r_s1, C_pass_g_s1, C_pass_b_s1;
  logic [7:0] add_pixel_r_s1, add_pixel_g_s1, add_pixel_b_s1;
  logic [7:0] add_texture_r_s1, add_texture_g_s1, add_texture_b_s1;
  logic [8:0] add_sum_r_s3, add_sum_g_s3, add_sum_b_s3;

  logic [7:0] m1_a_r_s2, m1_b_r_s2, m2_a_r_s2, m2_b_r_s2;
  logic [7:0] m1_a_g_s2, m1_b_g_s2, m2_a_g_s2, m2_b_g_s2;
  logic [7:0] m1_a_b_s2, m1_b_b_s2, m2_a_b_s2, m2_b_b_s2;
  logic [7:0] m2_a_r_s3, m2_b_r_s3;
  logic [7:0] m2_a_g_s3, m2_b_g_s3;
  logic [7:0] m2_a_b_s3, m2_b_b_s3;
  logic [7:0] m_a_a_s2, m_a_b_s2;

  // --------------------------------------------------------
  // Stage 2: Multiplications
  // --------------------------------------------------------
  logic valid_s2;
  fragment_op_t op_s2;
  logic [7:0] C_pass_a_s2, C_pass_r_s2, C_pass_g_s2, C_pass_b_s2;
  logic valid_s3;
  fragment_op_t op_s3;
  logic [7:0] C_pass_a_s3, C_pass_r_s3, C_pass_g_s3, C_pass_b_s3;
  logic [7:0] add_r_s3, add_g_s3, add_b_s3;

  logic [15:0] prod_a_s3;

  logic valid_s4;
  fragment_op_t op_s4;
  logic [7:0] C_pass_a_s4, C_pass_r_s4, C_pass_g_s4, C_pass_b_s4;
  logic [7:0] add_r_s4, add_g_s4, add_b_s4;
  logic [15:0] src_prod_r_s3, src_prod_g_s3, src_prod_b_s3;
  logic [15:0] src_prod_r_s4, src_prod_g_s4, src_prod_b_s4;
  logic [15:0] second_prod_r_s4, second_prod_g_s4, second_prod_b_s4;
  logic [16:0] sum_r_s5, sum_g_s5, sum_b_s5;
  logic [15:0] prod_a_s4;
  logic [15:0] prod_a_s5;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s0 <= 1'b0;
      valid_s1 <= 1'b0;
      valid_s2 <= 1'b0;
      valid_s3 <= 1'b0;
      valid_s4 <= 1'b0;
      valid_out <= 1'b0;
      fragment_color <= '0;
    end else begin
      // ========================================================
      // STAGE 0: Input buffer
      // ========================================================
      valid_s0 <= valid_in;
      op_s0 <= op;
      pixel_color_s0 <= pixel_color;
      texture_color_s0_a <= texture_color;
      texture_color_s0_b <= texture_color;
      env_color_s0 <= env_color;

      // ========================================================
      // STAGE 1
      // ========================================================
      valid_s1 <= valid_s0;
      op_s1 <= op_s0;

      if (op_s0 == REPLACE) begin
        C_pass_a_s1 <= texture_color_s0_a.a;
        C_pass_r_s1 <= texture_color_s0_a.r;
        C_pass_g_s1 <= texture_color_s0_a.g;
        C_pass_b_s1 <= texture_color_s0_a.b;
      end else begin
        C_pass_a_s1 <= pixel_color_s0.a;
        C_pass_r_s1 <= pixel_color_s0.r;
        C_pass_g_s1 <= pixel_color_s0.g;
        C_pass_b_s1 <= pixel_color_s0.b;
      end

      // Buffer both DSP operands before registering the SIMD sum.
      add_pixel_r_s1 <= pixel_color_s0.r;
      add_pixel_g_s1 <= pixel_color_s0.g;
      add_pixel_b_s1 <= pixel_color_s0.b;
      add_texture_r_s1 <= texture_color_s0_b.r;
      add_texture_g_s1 <= texture_color_s0_b.g;
      add_texture_b_s1 <= texture_color_s0_b.b;

      // Setup Multipliers
      m1_a_r_s2 <= pixel_color_s0.r;
      m1_a_g_s2 <= pixel_color_s0.g;
      m1_a_b_s2 <= pixel_color_s0.b;

      case (op_s0)
        DECAL: begin
          m1_b_r_s2 <= ~texture_color_s0_a.a;  // 255 - A
          m1_b_g_s2 <= ~texture_color_s0_a.a;  // 255 - A
          m1_b_b_s2 <= ~texture_color_s0_a.a;  // 255 - A

          m2_a_r_s2 <= texture_color_s0_a.r;
          m2_a_g_s2 <= texture_color_s0_a.g;
          m2_a_b_s2 <= texture_color_s0_a.b;

          m2_b_r_s2 <= texture_color_s0_a.a;
          m2_b_g_s2 <= texture_color_s0_a.a;
          m2_b_b_s2 <= texture_color_s0_a.a;
        end
        BLEND: begin
          m1_b_r_s2 <= ~texture_color_s0_a.r;
          m1_b_g_s2 <= ~texture_color_s0_a.g;
          m1_b_b_s2 <= ~texture_color_s0_a.b;

          m2_a_r_s2 <= env_color_s0.r;
          m2_a_g_s2 <= env_color_s0.g;
          m2_a_b_s2 <= env_color_s0.b;

          m2_b_r_s2 <= texture_color_s0_a.r;
          m2_b_g_s2 <= texture_color_s0_a.g;
          m2_b_b_s2 <= texture_color_s0_a.b;
        end
        default: begin
          m1_b_r_s2 <= texture_color_s0_a.r;
          m1_b_g_s2 <= texture_color_s0_a.g;
          m1_b_b_s2 <= texture_color_s0_a.b;

          m2_a_r_s2 <= 8'd0;
          m2_a_g_s2 <= 8'd0;
          m2_a_b_s2 <= 8'd0;

          m2_b_r_s2 <= 8'd0;
          m2_b_g_s2 <= 8'd0;
          m2_b_b_s2 <= 8'd0;
        end
      endcase

      // Setup Multiplier for A
      m_a_a_s2 <= pixel_color_s0.a;
      m_a_b_s2 <= texture_color_s0_a.a;

      // ========================================================
      // STAGE 2
      // ========================================================
      valid_s2 <= valid_s1;
      op_s2 <= op_s1;
      C_pass_a_s2 <= C_pass_a_s1;
      C_pass_r_s2 <= C_pass_r_s1;
      C_pass_g_s2 <= C_pass_g_s1;
      C_pass_b_s2 <= C_pass_b_s1;
      add_sum_r_s3 <= {1'b0, add_pixel_r_s1} + {1'b0, add_texture_r_s1};
      add_sum_g_s3 <= {1'b0, add_pixel_g_s1} + {1'b0, add_texture_g_s1};
      add_sum_b_s3 <= {1'b0, add_pixel_b_s1} + {1'b0, add_texture_b_s1};

      src_prod_r_s3 <= m1_a_r_s2 * m1_b_r_s2;
      src_prod_g_s3 <= m1_a_g_s2 * m1_b_g_s2;
      src_prod_b_s3 <= m1_a_b_s2 * m1_b_b_s2;
      m2_a_r_s3 <= m2_a_r_s2;
      m2_b_r_s3 <= m2_b_r_s2;
      m2_a_g_s3 <= m2_a_g_s2;
      m2_b_g_s3 <= m2_b_g_s2;
      m2_a_b_s3 <= m2_a_b_s2;
      m2_b_b_s3 <= m2_b_b_s2;
      prod_a_s3 <= m_a_a_s2 * m_a_b_s2;

      // ========================================================
      // STAGE 3
      // ========================================================
      valid_s3 <= valid_s2;
      op_s3 <= op_s2;
      C_pass_a_s3 <= C_pass_a_s2;
      C_pass_r_s3 <= C_pass_r_s2;
      C_pass_g_s3 <= C_pass_g_s2;
      C_pass_b_s3 <= C_pass_b_s2;
      add_r_s3 <= add_sum_r_s3[8] ? 8'd255 : add_sum_r_s3[7:0];
      add_g_s3 <= add_sum_g_s3[8] ? 8'd255 : add_sum_g_s3[7:0];
      add_b_s3 <= add_sum_b_s3[8] ? 8'd255 : add_sum_b_s3[7:0];

      src_prod_r_s4 <= src_prod_r_s3 + 16'd128 ;
      src_prod_g_s4 <= src_prod_g_s3 + 16'd128;
      src_prod_b_s4 <= src_prod_b_s3 + 16'd128;
      second_prod_r_s4 <= m2_a_r_s3 * m2_b_r_s3;
      second_prod_g_s4 <= m2_a_g_s3 * m2_b_g_s3;
      second_prod_b_s4 <= m2_a_b_s3 * m2_b_b_s3;
      prod_a_s4 <= prod_a_s3 + 16'd128;

      // ========================================================
      // STAGE 4: Accumulate products and align output controls.
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
      sum_r_s5 <= src_prod_r_s4 + second_prod_r_s4;
      sum_g_s5 <= src_prod_g_s4 + second_prod_g_s4;
      sum_b_s5 <= src_prod_b_s4 + second_prod_b_s4;
      prod_a_s5 <= prod_a_s4;

      // ========================================================
      // STAGE 5: Final output selection.
      // ========================================================
      valid_out <= valid_s4;

      case (op_s4)
        REPLACE: fragment_color <= {C_pass_a_s4, C_pass_r_s4, C_pass_g_s4, C_pass_b_s4};
        MODULATE:
        fragment_color <= {prod_a_s5[15:8], sum_r_s5[15:8], sum_g_s5[15:8], sum_b_s5[15:8]};
        DECAL: fragment_color <= {C_pass_a_s4, sum_r_s5[15:8], sum_g_s5[15:8], sum_b_s5[15:8]};
        BLEND: fragment_color <= {prod_a_s5[15:8], sum_r_s5[15:8], sum_g_s5[15:8], sum_b_s5[15:8]};
        ADD: fragment_color <= {prod_a_s5[15:8], add_r_s4, add_g_s4, add_b_s4};
        COLOR: fragment_color <= {C_pass_a_s4, C_pass_r_s4, C_pass_g_s4, C_pass_b_s4};
        default: fragment_color <= '0;
      endcase
    end
  end

endmodule
