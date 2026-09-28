// Blend unit interface shell

`timescale 1ns / 1ns

import gpu_types_pkg::*;

(* use_dsp = "simd" *)
module blend_unit (
    input  logic        clk,
    input  blend_op_t   sfactor_op,
    input  blend_op_t   dfactor_op,
    input  color_argb_t src_color,
    input  color_argb_t dst_color,
    output color_argb_t blend_color
);

  blend_op_t   sfactor_op_s1;
  blend_op_t   dfactor_op_s1;
  color_argb_t src_color_s1;
  color_argb_t dst_color_s1;
  color_argb_t src_coeff_s2;
  color_argb_t dst_coeff_s2;
  color_argb_t src_color_s2;
  color_argb_t dst_color_s2;
  color_argb_t src_coeff_s3;
  color_argb_t dst_coeff_s3;
  color_argb_t src_color_s3;
  color_argb_t dst_color_s3;

  typedef struct packed {
    logic [15:0] a;
    logic [15:0] r;
    logic [15:0] g;
    logic [15:0] b;
  } color_product_t;

  typedef struct packed {
    logic [16:0] a;
    logic [16:0] r;
    logic [16:0] g;
    logic [16:0] b;
  } color_sum_t;

  color_product_t src_product_s4;
  color_product_t dst_product_s5;
  color_sum_t src_sum_s5;
  color_sum_t color_sum_s6;

  // Stage 1: Register the blend controls and color inputs.
  always_ff @(posedge clk) begin
    sfactor_op_s1 <= sfactor_op;
    dfactor_op_s1 <= dfactor_op;
    src_color_s1  <= src_color;
    dst_color_s1  <= dst_color;
  end

  function automatic color_argb_t calculate_coefficient(
      input blend_op_t operation, input color_argb_t source, input color_argb_t destination,
      input color_argb_t default_coefficient);
    color_argb_t coefficient;

    coefficient = default_coefficient;
    case (operation)
      ZERO: begin
        coefficient = '0;
      end
      ONE: begin
        coefficient = '{a: 8'hff, r: 8'hff, g: 8'hff, b: 8'hff};
      end
      SRC_COLOR: begin
        coefficient = source;
      end
      ONE_MINUS_SRC_COLOR: begin
        coefficient = '{a: ~source.a, r: ~source.r, g: ~source.g, b: ~source.b};
      end
      DST_COLOR: begin
        coefficient = destination;
      end
      ONE_MINUS_DST_COLOR: begin
        coefficient = '{
            a: ~destination.a,
            r: ~destination.r,
            g: ~destination.g,
            b: ~destination.b
        };
      end
      SRC_ALPHA: begin
        coefficient = '{a: source.a, r: source.a, g: source.a, b: source.a};
      end
      ONE_MINUS_SRC_ALPHA: begin
        coefficient = '{a: ~source.a, r: ~source.a, g: ~source.a, b: ~source.a};
      end
      DST_ALPHA: begin
        coefficient = '{a: destination.a, r: destination.a, g: destination.a, b: destination.a};
      end
      ONE_MINUS_DST_ALPHA: begin
        coefficient = '{
            a: ~destination.a,
            r: ~destination.a,
            g: ~destination.a,
            b: ~destination.a
        };
      end
      default: begin
        coefficient = default_coefficient;
      end
    endcase

    return coefficient;
  endfunction

  // Stage 2: Register coefficients and delay colors for the blend stage.
  always_ff @(posedge clk) begin
    src_coeff_s2 <= calculate_coefficient(
        sfactor_op_s1, src_color_s1, dst_color_s1, '{a: 8'hff, r: 8'hff, g: 8'hff, b: 8'hff}
    );
    dst_coeff_s2 <= calculate_coefficient(dfactor_op_s1, src_color_s1, dst_color_s1, '0);
    src_color_s2 <= src_color_s1;
    dst_color_s2 <= dst_color_s1;
  end

  // Stage 3: Buffer operands between coefficient generation and multiplication.
  always_ff @(posedge clk) begin
    src_coeff_s3 <= src_coeff_s2;
    dst_coeff_s3 <= dst_coeff_s2;
    src_color_s3 <= src_color_s2;
    dst_color_s3 <= dst_color_s2;
  end

  // Stage 4: Perform multiplication 1 (N+1).
  always_ff @(posedge clk) begin
    src_product_s4.a <= src_color_s3.a * src_coeff_s3.a;
    src_product_s4.r <= src_color_s3.r * src_coeff_s3.r;
    src_product_s4.g <= src_color_s3.g * src_coeff_s3.g;
    src_product_s4.b <= src_color_s3.b * src_coeff_s3.b;
  end

  // Stage 5: Add rounding bias and perform multiplication 2 (N+2).
  always_ff @(posedge clk) begin
    src_sum_s5.a <= {1'b0, src_product_s4.a} + 17'd128;
    src_sum_s5.r <= {1'b0, src_product_s4.r} + 17'd128;
    src_sum_s5.g <= {1'b0, src_product_s4.g} + 17'd128;
    src_sum_s5.b <= {1'b0, src_product_s4.b} + 17'd128;
    dst_product_s5.a <= dst_color_s3.a * dst_coeff_s3.a;
    dst_product_s5.r <= dst_color_s3.r * dst_coeff_s3.r;
    dst_product_s5.g <= dst_color_s3.g * dst_coeff_s3.g;
    dst_product_s5.b <= dst_color_s3.b * dst_coeff_s3.b;
  end

  // Stage 6: Add the two products (N+3).
  always_ff @(posedge clk) begin
    color_sum_s6.a <= src_sum_s5.a + {1'b0, dst_product_s5.a};
    color_sum_s6.r <= src_sum_s5.r + {1'b0, dst_product_s5.r};
    color_sum_s6.g <= src_sum_s5.g + {1'b0, dst_product_s5.g};
    color_sum_s6.b <= src_sum_s5.b + {1'b0, dst_product_s5.b};
  end

  // Stage 7: Convert the sum to 8-bit saturated ARGB (N+4).
  always_ff @(posedge clk) begin
    blend_color.a <= color_sum_s6.a[16] ? 8'hff : color_sum_s6.a[15:8];
    blend_color.r <= color_sum_s6.r[16] ? 8'hff : color_sum_s6.r[15:8];
    blend_color.g <= color_sum_s6.g[16] ? 8'hff : color_sum_s6.g[15:8];
    blend_color.b <= color_sum_s6.b[16] ? 8'hff : color_sum_s6.b[15:8];
  end

endmodule
