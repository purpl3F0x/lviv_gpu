`timescale 1ns / 1ps

// =========================================================================
// fp_add_half_fast: Adds +0.5 to a 32-bit single-precision float (2-cycle latency)
// Optimized for non-negative integers (no fractional part) up to 8192.00.
// =========================================================================
module fp_add_half_fast (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        valid_in,
    input  logic [31:0] f_in,
    output logic        valid_out,
    output logic [31:0] f_out
);

  logic v_pipe;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) v_pipe <= 1'b0;
    else v_pipe <= valid_in;
  end

  // =========================================================================
  // STAGE 1: Exponent Evaluation and Classification
  // =========================================================================
  logic [ 7:0] s1_exp;
  logic [22:0] s1_mant;
  logic        s1_is_zero;

  always_ff @(posedge clk) begin
    s1_exp     <= f_in[30:23];
    s1_mant    <= f_in[22:0];
    s1_is_zero <= (f_in[30:23] < 8'd127);
  end

  // =========================================================================
  // STAGE 2: Exponent-based Bit Injection and Packing
  // =========================================================================
  logic [31:0] final_output;

  always_comb begin
    if (s1_is_zero) begin
      // X = 0.0 -> X + 0.5 = 0.5 (32'h3F00_0000)
      final_output = 32'h3F00_0000;
    end else begin
      // 127 <= E <= 140
      // Set the bit at index k = 149 - E in the mantissa.
      logic [ 4:0] shift_amt;
      logic [22:0] bit_mask;
      shift_amt = 5'(8'd149 - s1_exp);
      bit_mask  = 23'd1 << shift_amt;
      final_output = {1'b0, s1_exp, s1_mant | bit_mask};
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_out <= 1'b0;
      f_out     <= '0;
    end else begin
      valid_out <= v_pipe;
      f_out     <= final_output;
    end
  end

endmodule
