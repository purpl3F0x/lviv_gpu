// Unsigned UQ8.0 x UQ2.23 FMA: q = a*b + c
// Full-precision product/add domain is UQ10.23.
(* use_dsp = "yes" *)
module fx_color_fma (
    input  logic        clk,
    input  logic        clken,
    input  logic [ 7:0] a,
    input  logic [24:0] b,
    input  logic [32:0] c,
    output logic [32:0] q
);
  logic [32:0] c_reg;
  logic [32:0] mul_res;


  always_ff @(posedge clk) begin
    if (clken) begin
      // Stage 1: full-precision UQ8.0 x UQ2.23 multiply and delay c.
      mul_res <= {17'd0, a} * b;
      c_reg <= c;

      // Stage 2: full-precision accumulate.
      q <= mul_res + c_reg;
    end
  end

endmodule
