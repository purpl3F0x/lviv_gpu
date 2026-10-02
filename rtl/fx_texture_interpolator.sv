`timescale 1ns / 1ps

(* use_dsp = "yes" *)
module fx_texture_interpolator (
    input  logic        clk,
    input  logic        clken,
    input  logic [17:0] coord0,
    input  logic [24:0] weight0,
    input  logic [17:0] coord1,
    input  logic [24:0] weight1,
    input  logic [17:0] coord2,
    input  logic [24:0] weight2,
    output logic [47:0] result
);
  logic [17:0] coord0_s1;
  logic [17:0] coord1_s1;
  logic [17:0] coord2_s1;
  logic [23:0] weight0_s1;
  logic [23:0] weight1_s1;
  logic [23:0] weight2_s1;
  logic [17:0] coord1_s2;
  logic [23:0] weight1_s2;
  logic [17:0] coord2_s2;
  logic [23:0] weight2_s2;
  logic [17:0] coord2_s3;
  logic [23:0] weight2_s3;

  logic [42:0] product0_s2;
  logic [42:0] product0_s3;
  logic [42:0] product1_s3;
  logic [43:0] partial_sum_s4;
  logic [42:0] product2_s4;
  logic [44:0] final_sum_s5;

  always_ff @(posedge clk) begin
    if (clken) begin
      coord0_s1 <= coord0;
      weight0_s1 <= weight0[23:0];
      coord1_s1 <= coord1;
      weight1_s1 <= weight1[23:0];
      coord2_s1 <= coord2;
      weight2_s1 <= weight2[23:0];

      // Stage 2: first product and align the later operands.
      product0_s2 <= {18'd0, weight0_s1} * {24'd0, coord0_s1};
      coord1_s2 <= coord1_s1;
      weight1_s2 <= weight1_s1;
      coord2_s2 <= coord2_s1;
      weight2_s2 <= weight2_s1;

      // Stage 3: buffer product 0 and start product 1.
      product0_s3 <= product0_s2;
      product1_s3 <= {18'd0, weight1_s2} * {24'd0, coord1_s2};
      coord2_s3 <= coord2_s2;
      weight2_s3 <= weight2_s2;

      // Stage 4: sum products 0/1 and start product 2.
      partial_sum_s4 <= {1'b0, product0_s3} + {1'b0, product1_s3};
      product2_s4 <= {18'd0, weight2_s3} * {24'd0, coord2_s3};

      // Stage 5: accumulate product 2 without rounding or saturation.
      final_sum_s5 <= {1'b0, partial_sum_s4} + {2'b0, product2_s4};

      // Stage 6: register the full-precision texture-coordinate result.
      result <= {3'b0, final_sum_s5};
    end
  end
endmodule
