(* use_dsp = "yes" *)
module fx_texture_mul (
    input  logic               clk,
    input  logic               clken,
    input  logic signed [24:0] a,      // SQ2.23
    input  logic signed [17:0] b,      // SQ5.13
    output logic signed [47:0] q       // SQ7.36 product sign-extended to 48 bits
);
  logic signed [24:0] b_ext;
  logic signed [49:0] prod_full;
  logic signed [42:0] prod;

  assign b_ext = $signed({{7{b[17]}}, b});
  assign prod_full = a * b_ext;
  assign prod = $signed(prod_full[42:0]);

  always_ff @(posedge clk) begin
    if (clken) begin
      // Stage 1: signed SQ2.23 x SQ5.13 -> Q*.36 product.
      q <= $signed({{5{prod[42]}}, prod});
    end
  end

endmodule
