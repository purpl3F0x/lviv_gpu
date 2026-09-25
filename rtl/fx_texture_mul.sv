(* use_dsp = "yes" *)
module fx_texture_mul (
    input  logic               clk,
    input  logic               clken,
    input  logic signed [24:0] a,      // SQ2.23
    input  logic signed [17:0] b,      // SQ5.13
    output logic signed [47:0] q       // SQ7.36 product sign-extended to 48 bits
);
  logic signed [24:0] a_reg;
  logic signed [17:0] b_reg;
  logic signed [24:0] b_ext;
  logic signed [49:0] prod_full;
  logic signed [42:0] prod;

  assign b_ext = $signed({{7{b_reg[17]}}, b_reg});
  assign prod_full = a_reg * b_ext;
  assign prod = $signed(prod_full[42:0]);

  always_ff @(posedge clk) begin
    if (clken) begin
      // Stage 1: register inputs.
      a_reg <= a;
      b_reg <= b;

      // Stage 2: signed SQ2.23 x SQ5.13 -> Q*.36 product.
      q <= $signed({{5{prod[42]}}, prod});
    end
  end

endmodule
