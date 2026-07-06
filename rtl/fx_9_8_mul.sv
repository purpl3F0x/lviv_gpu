// Unsigned UQ9.8 multiply: q = a * b
// Product is UQ18.16, then rounded and shifted back to UQ9.8.
(* use_dsp = "yes" *)
module fx_9_8_mul (
    input  logic        clk,
    input  logic        clken,
    input  logic [16:0] a,      // UQ9.8
    input  logic [16:0] b,      // UQ9.8
    output logic [16:0] q       // UQ9.8
);
  logic [33:0] product_full;
  logic [33:0] product_rounded;


  always_ff @(posedge clk) begin
    if (clken) begin
      product_full <= a * b;
      product_rounded <= product_full + 34'd128;
    end
  end

  assign q = product_rounded[24:8];
endmodule
