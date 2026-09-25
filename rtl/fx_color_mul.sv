// Unsigned UQ8.0 x UQ2.23 multiply: q = a * b
// Full-precision product is UQ10.23.
(* use_dsp = "yes" *)
module fx_color_mul (
    input  logic        clk,
    input  logic        clken,
    input  logic [ 7:0] a,      // UQ8.0 color
    input  logic [24:0] b,      // UQ2.23 coefficient
    output logic [32:0] q       // UQ10.23 full-precision product
);
  logic [ 7:0] a_reg;
  logic [24:0] b_reg;

  always_ff @(posedge clk) begin
    if (clken) begin
      // Stage 1: register inputs.
      a_reg <= a;
      b_reg <= b;

      // Stage 2: full-precision multiply.
      q <= {17'd0, a_reg} * b_reg;
    end
  end
endmodule
