`timescale 1ns / 1ps

// =========================================================================
// fp_add_half_fast: Adds +0.5 to a 32-bit single-precision float (2-cycle latency)
// Optimized for non-negative integers (no fractional part) up to 8192.00.
// =========================================================================
module fp_add_half_fast (
    input  logic        clk,
    input  logic        clken,
    input  logic        rst_n,
    input  logic [31:0] f_in,
    output logic [31:0] f_out
);

  // =========================================================================
  // STAGE 1: Exponent Evaluation and Classification
  // =========================================================================
  logic [ 7:0] s1_exp;
  logic [22:0] s1_mant;
  logic        s1_is_zero;

  always_ff @(posedge clk) begin
    if (clken) begin
      s1_exp     <= f_in[30:23];
      s1_mant    <= f_in[22:0];
      s1_is_zero <= (f_in[30:23] < 8'd127);
    end
  end

  // =========================================================================
  // STAGE 2: Exponent-based Bit Injection and Packing
  // =========================================================================
  logic [31:0] final_output;
  logic [ 4:0] shift_amt;
  logic [22:0] bit_mask;
  assign shift_amt = 5'(8'd149 - s1_exp);
  assign bit_mask  = 23'd1 << shift_amt;

  always_comb begin
    if (s1_is_zero) begin
      // X = 0.0 -> X + 0.5 = 0.5 (32'h3F00_0000)
      final_output = 32'h3F00_0000;
    end else begin
      // 127 <= E <= 140
      // Set the bit at index k = 149 - E in the mantissa.
      final_output = {1'b0, s1_exp, s1_mant | bit_mask};
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      f_out     <= '0;
    end else if (clken) begin
      f_out     <= final_output;
    end
  end

endmodule
