// Convert unsigned UQ2.23 to unsigned UQ2.8 with round-to-nearest.
// Drops 15 fractional bits and rounds by +2^14 before shifting.
// out_fx2_8 carries UQ2.8 in bits [9:0] and is zero-extended above that.
module fx_2_23_to_fx_2_8 (
    input  logic        clk,
    input  logic        clken,
    input  logic [24:0] in_fx2_23,
    output logic [9:0] out_fx2_8
);
  logic [25:0] rounded;
  logic [ 9:0] uq2_8;

  always_comb begin
    rounded = {1'b0, in_fx2_23} + 26'd16384;
    uq2_8 = rounded[24:15];
  end

  always_ff @(posedge clk) begin
    if (clken) out_fx2_8 <= {uq2_8};
  end
endmodule
