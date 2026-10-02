`timescale 1ns / 1ps

import gpu_types_pkg::*;

(* use_dsp = "yes" *)
module fx_color_interpolator (
    input  logic               clk,
    input  logic               clken,
    input  color_argb_t        color0,
    input  color_argb_t        color1,
    input  color_argb_t        color2,
    input  logic        [24:0] weight0,
    input  logic        [24:0] weight1,
    input  logic        [24:0] weight2,
    output color_argb_t        result
);
  localparam logic [34:0] ROUND_BIAS = 35'd4194304;

  color_argb_t color0_s1, color1_s1, color2_s1;
  logic [23:0] weight0_s1, weight1_s1, weight2_s1;
  color_argb_t color1_s2, color2_s2;
  logic [23:0] weight1_s2, weight2_s2;
  color_argb_t color2_s3;
  logic [23:0] weight2_s3;
  logic [31:0] product0_a_s2, product0_r_s2;
  logic [31:0] product0_g_s2, product0_b_s2;
  logic [34:0] acc0_a_s3, acc0_r_s3, acc0_g_s3, acc0_b_s3;
  logic [31:0] product1_a_s3, product1_r_s3;
  logic [31:0] product1_g_s3, product1_b_s3;
  logic [34:0] partial_a_s4, partial_r_s4;
  logic [34:0] partial_g_s4, partial_b_s4;
  logic [31:0] product2_a_s4, product2_r_s4;
  logic [31:0] product2_g_s4, product2_b_s4;
  logic [34:0] final_a_s5, final_r_s5, final_g_s5, final_b_s5;

  always_ff @(posedge clk) begin
    if (clken) begin
      color0_s1 <= color0;
      color1_s1 <= color1;
      color2_s1 <= color2;
      weight0_s1 <= weight0[23:0];
      weight1_s1 <= weight1[23:0];
      weight2_s1 <= weight2[23:0];

      // Stage 2: product 0; delay operands for the next products.
      product0_a_s2 <= {8'd0, weight0_s1} * {24'd0, color0_s1.a};
      product0_r_s2 <= {8'd0, weight0_s1} * {24'd0, color0_s1.r};
      product0_g_s2 <= {8'd0, weight0_s1} * {24'd0, color0_s1.g};
      product0_b_s2 <= {8'd0, weight0_s1} * {24'd0, color0_s1.b};
      color1_s2 <= color1_s1;
      weight1_s2 <= weight1_s1;
      color2_s2 <= color2_s1;
      weight2_s2 <= weight2_s1;

      // Stage 3: accumulate product 0 with bias while starting product 1.
      acc0_a_s3 <= {2'b0, product0_a_s2} + ROUND_BIAS;
      acc0_r_s3 <= {2'b0, product0_r_s2} + ROUND_BIAS;
      acc0_g_s3 <= {2'b0, product0_g_s2} + ROUND_BIAS;
      acc0_b_s3 <= {2'b0, product0_b_s2} + ROUND_BIAS;
      product1_a_s3 <= {8'd0, weight1_s2} * {24'd0, color1_s2.a};
      product1_r_s3 <= {8'd0, weight1_s2} * {24'd0, color1_s2.r};
      product1_g_s3 <= {8'd0, weight1_s2} * {24'd0, color1_s2.g};
      product1_b_s3 <= {8'd0, weight1_s2} * {24'd0, color1_s2.b};
      color2_s3 <= color2_s2;
      weight2_s3 <= weight2_s2;

      // Stage 4: accumulate product 1 while starting product 2.
      partial_a_s4 <= acc0_a_s3 + {3'b0, product1_a_s3};
      partial_r_s4 <= acc0_r_s3 + {3'b0, product1_r_s3};
      partial_g_s4 <= acc0_g_s3 + {3'b0, product1_g_s3};
      partial_b_s4 <= acc0_b_s3 + {3'b0, product1_b_s3};
      product2_a_s4 <= {8'd0, weight2_s3} * {24'd0, color2_s3.a};
      product2_r_s4 <= {8'd0, weight2_s3} * {24'd0, color2_s3.r};
      product2_g_s4 <= {8'd0, weight2_s3} * {24'd0, color2_s3.g};
      product2_b_s4 <= {8'd0, weight2_s3} * {24'd0, color2_s3.b};

      // Stage 5: accumulate product 2.
      final_a_s5 <= partial_a_s4 + {3'b0, product2_a_s4};
      final_r_s5 <= partial_r_s4 + {3'b0, product2_r_s4};
      final_g_s5 <= partial_g_s4 + {3'b0, product2_g_s4};
      final_b_s5 <= partial_b_s4 + {3'b0, product2_b_s4};

      // Stage 6: register the rounded and saturated output.
      result.a <= final_a_s5[31] ? 8'hff : final_a_s5[30:23];
      result.r <= final_r_s5[31] ? 8'hff : final_r_s5[30:23];
      result.g <= final_g_s5[31] ? 8'hff : final_g_s5[30:23];
      result.b <= final_b_s5[31] ? 8'hff : final_b_s5[30:23];
    end
  end
endmodule
