(* use_dsp = "yes" *)
module fx_texture_fma (
    input  logic               clk,
    input  logic               clken,
    input  logic signed [24:0] a,      // SQ2.23
    input  logic signed [17:0] b,      // SQ5.13
    input  logic signed [47:0] c,      // 10.36 aligned addend
    output logic signed [47:0] q       // 10.36 full-precision a*b + c
);
  logic signed [24:0] b_ext;
  logic signed [49:0] prod_full_s0;
  logic signed [42:0] prod_s1;
  logic signed [47:0] prod_s1_ext;
  logic signed [47:0] c_reg_s1;

  assign b_ext = $signed({{7{b[17]}}, b});
  assign prod_full_s0 = a * b_ext;
  assign prod_s1_ext = $signed({{5{prod_s1[42]}}, prod_s1});

  always_ff @(posedge clk) begin
    if (clken) begin
      // Stage 1: signed SQ2.23 x SQ5.13 -> Q*.36 product, and delay c.
      prod_s1 <= $signed(prod_full_s0[42:0]);
      c_reg_s1 <= c;

      // Stage 2: full-precision accumulate.
      q <= prod_s1_ext + c_reg_s1;
    end
  end

endmodule
