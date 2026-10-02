`timescale 1ns / 1ps

(* use_dsp = "yes" *)
module fx_texture_interpolator (
    input  logic        clk,
    input  logic        clken,
    input  logic signed [17:0] coord0,
    input  logic [24:0] weight0,
    input  logic signed [17:0] coord1,
    input  logic [24:0] weight1,
    input  logic signed [17:0] coord2,
    input  logic [24:0] weight2,
    output logic signed [47:0] result
);
  logic signed [17:0] coord0_s1;
  logic signed [17:0] coord1_s1;
  logic signed [17:0] coord2_s1;
  logic signed [24:0] weight0_s1;
  logic signed [24:0] weight1_s1;
  logic signed [24:0] weight2_s1;
  logic signed [17:0] coord1_s2;
  logic signed [24:0] weight1_s2;
  logic signed [17:0] coord2_s2;
  logic signed [24:0] weight2_s2;
  logic signed [17:0] coord2_s3;
  logic signed [24:0] weight2_s3;

  logic signed [47:0] product0_s2;
  logic signed [47:0] product0_s3;
  logic signed [47:0] product1_s3;
  logic signed [47:0] partial_sum_s4;
  logic signed [47:0] product2_s4;
  logic signed [47:0] final_sum_s5;

  always_ff @(posedge clk) begin
    if (clken) begin
      coord0_s1 <= $signed(coord0);
      weight0_s1 <= {1'b0, weight0[23:0]};
      coord1_s1 <= $signed(coord1);
      weight1_s1 <= {1'b0, weight1[23:0]};
      coord2_s1 <= $signed(coord2);
      weight2_s1 <= {1'b0, weight2[23:0]};

      // Stage 2: first product and align the later operands.
      product0_s2 <= weight0_s1 * coord0_s1;
      coord1_s2 <= coord1_s1;
      weight1_s2 <= weight1_s1;
      coord2_s2 <= coord2_s1;
      weight2_s2 <= weight2_s1;

      // Stage 3: buffer product 0 and start product 1.
      product0_s3 <= product0_s2;
      product1_s3 <= weight1_s2 * coord1_s2;
      coord2_s3 <= coord2_s2;
      weight2_s3 <= weight2_s2;

      // Stage 4: sum products 0/1 and start product 2.
      partial_sum_s4 <= product0_s3 + product1_s3;
      product2_s4 <= weight2_s3 * coord2_s3;

      // Stage 5: accumulate product 2 without rounding or saturation.
      final_sum_s5 <= partial_sum_s4 + product2_s4;

      // Stage 6: register the full-precision texture-coordinate result.
      result <= final_sum_s5;
    end
  end
endmodule
