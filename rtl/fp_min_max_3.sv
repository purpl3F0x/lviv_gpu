`timescale 1ns / 1ps

module fp_min_max_3 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        valid_in,
    input  logic [31:0] f_a,
    input  logic [31:0] f_b,
    input  logic [31:0] f_c,
    output logic        valid_out,
    output logic [31:0] f_min,
    output logic [31:0] f_max
);

  //-----------------------------------------------------------------
  // Combinational IEEE-754 Less-Than Function
  //-----------------------------------------------------------------
  function automatic logic fp_lt(input logic [31:0] x, input logic [31:0] y);
    logic sign_x, sign_y;
    logic [30:0] mag_x, mag_y;

    sign_x = x[31];
    sign_y = y[31];
    mag_x  = x[30:0];
    mag_y  = y[30:0];

    if (mag_x == 31'd0 && mag_y == 31'd0) begin
      return 1'b0;
    end else if (sign_x != sign_y) begin
      return sign_x;
    end else if (sign_x) begin
      return mag_x > mag_y;
    end else begin
      return mag_x < mag_y;
    end
  endfunction

  //-----------------------------------------------------------------
  // Pipeline Stage 1 Registers
  //-----------------------------------------------------------------
  logic        valid_s1;
  logic [31:0] s1_min_ab;
  logic [31:0] s1_max_ab;
  logic [31:0] s1_f_c;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_s1  <= 1'b0;
      s1_min_ab <= 32'd0;
      s1_max_ab <= 32'd0;
      s1_f_c    <= 32'd0;
    end else begin
      valid_s1 <= valid_in;

      // Compare A and B
      if (fp_lt(f_a, f_b)) begin
        s1_min_ab <= f_a;
        s1_max_ab <= f_b;
      end else begin
        s1_min_ab <= f_b;
        s1_max_ab <= f_a;
      end

      // Pass C through Stage 1
      s1_f_c <= f_c;
    end
  end

  //-----------------------------------------------------------------
  // Pipeline Stage 2 Registers (Outputs)
  //-----------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_out <= 1'b0;
      f_min     <= 32'd0;
      f_max     <= 32'd0;
    end else begin
      valid_out <= valid_s1;

      // Final Min Calculation: Min( Min(A,B), C )
      if (fp_lt(s1_min_ab, s1_f_c)) begin
        f_min <= s1_min_ab;
      end else begin
        f_min <= s1_f_c;
      end

      // Final Max Calculation: Max( Max(A,B), C )
      if (fp_lt(s1_max_ab, s1_f_c)) begin
        f_max <= s1_f_c;
      end else begin
        f_max <= s1_max_ab;
      end
    end
  end

endmodule
