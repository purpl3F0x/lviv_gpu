`timescale 1ns / 1ps

module fp_ceil_n_clamp_to_odd (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        valid_in,
    input  logic [31:0] f_in,
    output logic        valid_out,
    output logic [31:0] f_out
);

  logic [ 2:0] v_pipe;

  // =========================================================================
  // STAGE 1: Lookahead Parity & Mask Analysis
  // =========================================================================
  logic        s1_sign;
  logic [ 7:0] s1_exp;
  logic [22:0] s1_mant;
  logic [22:0] s1_frac_mask;
  logic        s1_has_frac;
  logic        s1_int_lsb;
  logic        s1_is_small;
  logic        s1_is_huge;

  // XSIM Fix: Unpack the extended mantissa and shift it combinationally
  logic [23:0] s1_ext_mant_shifted;
  assign s1_ext_mant_shifted = {1'b1, f_in[22:0]} >> (8'd150 - f_in[30:23]);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      v_pipe <= '0;
    end else begin
      v_pipe[0] <= valid_in;
      v_pipe[1] <= v_pipe[0];
      v_pipe[2] <= v_pipe[1];
    end
  end

  always_ff @(posedge clk) begin
    s1_sign     <= f_in[31];
    s1_exp      <= f_in[30:23];
    s1_mant     <= f_in[22:0];
    s1_is_small <= (f_in[30:23] < 8'd127);
    s1_is_huge  <= (f_in[30:23] >= 8'd150);

    if (f_in[30:23] < 8'd127) begin
      s1_frac_mask <= 23'h7FFFFF;
      s1_has_frac  <= |f_in[22:0];
      s1_int_lsb   <= 1'b0;
    end else if (f_in[30:23] >= 8'd150) begin
      s1_frac_mask <= 23'h000000;
      s1_has_frac  <= 1'b0;
      s1_int_lsb   <= f_in[0];
    end else begin
      s1_frac_mask <= 23'h7FFFFF >> (f_in[30:23] - 8'd127);
      s1_has_frac  <= |(f_in[22:0] & (23'h7FFFFF >> (f_in[30:23] - 8'd127)));
      // Safely grab the shifted LSB bit without triggering the indexed expression bug
      s1_int_lsb   <= s1_ext_mant_shifted[0];
    end
  end

  // =========================================================================
  // STAGE 2: Pipelined Execution Matrix Adder
  // =========================================================================
  logic        s2_sign;
  logic [ 7:0] s2_exp;
  logic        s2_is_small;
  logic        s2_is_huge;
  logic [24:0] s2_adder_res;

  always_ff @(posedge clk) begin
    s2_sign            <= s1_sign;
    s2_exp             <= s1_exp;
    s2_is_small        <= s1_is_small;
    s2_is_huge         <= s1_is_huge;

    if (!s1_is_small && !s1_is_huge) begin
      if (!s1_sign) begin
        if (!s1_int_lsb) begin
          s2_adder_res <= {1'b1, s1_mant & ~s1_frac_mask} + (24'h000001 << (8'd150 - s1_exp));
        end else begin
          s2_adder_res <= {1'b1, s1_mant & ~s1_frac_mask} + (s1_has_frac ? (24'h000002 << (8'd150 - s1_exp)) : 24'h0);
        end
      end else begin
        if (!s1_int_lsb) begin
          s2_adder_res <= {1'b1, s1_mant & ~s1_frac_mask} - (24'h000001 << (8'd150 - s1_exp));
        end else begin
          s2_adder_res <= {1'b0, 1'b1, s1_mant & ~s1_frac_mask};
        end
      end
    end else begin
      s2_adder_res <= {1'b0, 1'b1, s1_mant & ~s1_frac_mask};
    end
  end

  // =========================================================================
  // STAGE 3: Dual Bound Renormalization & Pack Output
  // =========================================================================
  logic [31:0] final_output;

  always_comb begin
    if (s2_is_small) begin
      final_output = s2_sign ? 32'hBF80_0000 : 32'h3F80_0000;
    end else if (s2_is_huge) begin
      if (!s2_adder_res[0]) final_output = {s2_sign, s2_exp, s2_adder_res[22:1], 1'b1};
      else final_output = {s2_sign, s2_exp, s2_adder_res[22:0]};
    end else begin
      if (s2_adder_res[24]) begin
        final_output = {s2_sign, s2_exp + 8'd1, s2_adder_res[23:1]};
      end else if (!s2_adder_res[23]) begin
        final_output = {s2_sign, s2_exp - 8'd1, s2_adder_res[22:0], 1'b0};
      end else begin
        final_output = {s2_sign, s2_exp, s2_adder_res[22:0]};
      end
    end
  end

  always_ff @(posedge clk) begin
    valid_out <= v_pipe[1];
    f_out     <= final_output;
  end

endmodule



module fp_floor_n_clamp_to_even (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        valid_in,
    input  logic [31:0] f_in,
    output logic        valid_out,
    output logic [31:0] f_out
);

  logic [ 2:0] v_pipe;

  // =========================================================================
  // STAGE 1: Lookahead Parity & Mask Analysis
  // =========================================================================
  logic        s1_sign;
  logic [ 7:0] s1_exp;
  logic [22:0] s1_mant;
  logic [22:0] s1_frac_mask;
  logic        s1_has_frac;
  logic        s1_int_lsb;
  logic        s1_is_small;
  logic        s1_is_huge;

  // XSIM Fix: Unpack the extended mantissa and shift it combinationally
  logic [23:0] s1_ext_mant_shifted;
  assign s1_ext_mant_shifted = {1'b1, f_in[22:0]} >> (8'd150 - f_in[30:23]);

  always_ff @(posedge clk) begin
    v_pipe[0] <= valid_in;
    v_pipe[1] <= v_pipe[0];
    v_pipe[2] <= v_pipe[1];
  end

  always_ff @(posedge clk) begin
    s1_sign     <= f_in[31];
    s1_exp      <= f_in[30:23];
    s1_mant     <= f_in[22:0];
    s1_is_small <= (f_in[30:23] < 8'd127);
    s1_is_huge  <= (f_in[30:23] >= 8'd150);

    if (f_in[30:23] < 8'd127) begin
      s1_frac_mask <= 23'h7FFFFF;
      s1_has_frac  <= |f_in[22:0];
      s1_int_lsb   <= 1'b0;
    end else if (f_in[30:23] >= 8'd150) begin
      s1_frac_mask <= 23'h000000;
      s1_has_frac  <= 1'b0;
      s1_int_lsb   <= f_in[0];
    end else begin
      s1_frac_mask <= 23'h7FFFFF >> (f_in[30:23] - 8'd127);
      s1_has_frac  <= |(f_in[22:0] & (23'h7FFFFF >> (f_in[30:23] - 8'd127)));
      // Safely grab the shifted LSB bit without triggering the indexed expression bug
      s1_int_lsb   <= s1_ext_mant_shifted[0];
    end
  end

  // =========================================================================
  // STAGE 2: Pipelined Execution Matrix Adder
  // =========================================================================
  logic        s2_sign;
  logic [ 7:0] s2_exp;
  logic        s2_is_small;
  logic        s2_is_huge;
  logic [24:0] s2_adder_res;

  always_ff @(posedge clk) begin
    s2_sign            <= s1_sign;
    s2_exp             <= s1_exp;
    s2_is_small        <= s1_is_small;
    s2_is_huge         <= s1_is_huge;

    if (!s1_is_small && !s1_is_huge) begin
      if (!s1_sign) begin
        if (s1_int_lsb) begin
          s2_adder_res <= {1'b1, s1_mant & ~s1_frac_mask} - (24'h000001 << (8'd150 - s1_exp));
        end else begin
          s2_adder_res <= {1'b0, 1'b1, s1_mant & ~s1_frac_mask};
        end
      end else begin
        if (!s1_int_lsb) begin
          s2_adder_res <= {1'b1, s1_mant & ~s1_frac_mask} + (s1_has_frac ? (24'h000002 << (8'd150 - s1_exp)) : 24'h0);
        end else begin
          s2_adder_res <= {1'b1, s1_mant & ~s1_frac_mask} + (24'h000001 << (8'd150 - s1_exp));
        end
      end
    end else begin
      s2_adder_res <= {1'b0, 1'b1, s1_mant & ~s1_frac_mask};
    end
  end

  // =========================================================================
  // STAGE 3: Renormalization & Pack Output
  // =========================================================================
  logic [31:0] final_output;

  always_comb begin
    if (s2_is_small) begin
      if (s2_sign) final_output = 32'hC000_0000;
      else final_output = 32'h0000_0000;
    end else if (s2_is_huge) begin
      final_output = {s2_sign, s2_exp, s2_adder_res[22:1], 1'b0};
    end else begin
      if (s2_adder_res[24]) begin
        final_output = {s2_sign, s2_exp + 8'd1, s2_adder_res[23:1]};
      end else if (!s2_adder_res[23]) begin
        if (s2_adder_res[22:0] == '0) begin
          final_output = {s2_sign, 31'h0};
        end else begin
          final_output = {s2_sign, s2_exp - 8'd1, s2_adder_res[22:0], 1'b0};
        end
      end else begin
        final_output = {s2_sign, s2_exp, s2_adder_res[22:0]};
      end
    end
  end

  always_ff @(posedge clk) begin
    valid_out <= v_pipe[1];
    f_out     <= final_output;
  end

endmodule
