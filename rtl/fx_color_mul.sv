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


  always_ff @(posedge clk) begin
    if (clken) begin
      q <= {17'd0, a} * b;
    end
  end
endmodule
