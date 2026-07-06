(* use_dsp = "yes" *)
module fx_2_23_fma (
    input  logic        clk,
    input  logic        clken,
    input  logic [24:0] a,      // UQ2.23
    input  logic [24:0] b,      // UQ2.23
    input  logic [24:0] c,      // UQ2.23
    output logic [24:0] q       // UQ2.23
);
  logic [17:0] a_lo;
  logic [ 6:0] a_hi;
  logic [42:0] mult_lo_s1;
  logic [31:0] mult_hi_s1;
  logic [24:0] c_reg_s1;
  logic [24:0] c_reg_s2;
  logic [49:0] product_s2;
  logic [50:0] c_plus_round_s2;
  logic [50:0] res;

  assign a_lo = a[17:0];
  assign a_hi = a[24:18];

  always_ff @(posedge clk) begin
    if (clken) begin
      // Stage 1: two DSP-friendly partial products and delayed c.
      mult_lo_s1 <= a_lo * b;
      mult_hi_s1 <= a_hi * b;
      c_reg_s1 <= c;

      // Stage 2: combine partials and accumulate in Q4.46.
      product_s2 <= mult_lo_s1 + (mult_hi_s1 << 18);
      c_reg_s2 <= c_reg_s1;

      // Stage 3: round and shift back to Q2.23.
      res <= product_s2 + ((c_reg_s2 << 23) + 51'd4194304);  // rounding constant
    end
  end

  assign q = res[47:23];  // truncate to Q2.23

endmodule
