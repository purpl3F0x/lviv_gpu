// Unsigned UQ9.8 FMA: q = a*b + c
// Stage1 computes in UQ18.16, stage2 rounds/truncates back to UQ9.8.
(* use_dsp = "yes" *)
module fx_9_8_fma (
    input  logic        clk,
    input  logic        clken,
    input  logic [16:0] a,
    input  logic [16:0] b,
    input  logic [16:0] c,
    output logic [16:0] q
);
  logic [16:0] c_reg;
  logic [34:0] mul_res;
  logic [34:0] res;


  always_ff @(posedge clk) begin
    if (clken) begin
      // Stage 1: a * b
      mul_res <= a * b;
      c_reg <= c;

      // Stage 2: Add C
      res <= mul_res + {10'd0, c_reg, 8'd0} + 35'd128;
    end
  end

  assign q = res[24:8];

endmodule
