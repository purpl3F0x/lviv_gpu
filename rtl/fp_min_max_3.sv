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

  // Pipeline tracking
  logic [1:0] v_pipe;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) v_pipe <= '0;
    else v_pipe <= {v_pipe[0], valid_in};
  end

  // =========================================================================
  // STAGE 1: Parallel Pairwise Comparisons
  // =========================================================================
  // Helper signals to evaluate magnitude properties for IEEE-754 signed floats
  logic a_lt_b, a_lt_c;

  // Combinatorial comparison lookahead (handles negative signs correctly)
  always_comb begin
    // A < B evaluation
    if (f_a[31] != f_b[31]) begin
      a_lt_b = f_a[31];  // If signs differ, the negative one is smaller
    end else if (f_a[31]) begin
      a_lt_b = (f_a[30:0] > f_b[30:0]);  // Both negative: larger magnitude is smaller
    end else begin
      a_lt_b = (f_a[30:0] < f_b[30:0]);  // Both positive: smaller magnitude is smaller
    end

    // A < C evaluation
    if (f_a[31] != f_c[31]) begin
      a_lt_c = f_a[31];
    end else if (f_a[31]) begin
      a_lt_c = (f_a[30:0] > f_c[30:0]);
    end else begin
      a_lt_c = (f_a[30:0] < f_c[30:0]);
    end
  end

  // Stage 1 Registers
  logic [31:0] s1_max_ab, s1_min_ab;
  logic [31:0] f_c_r1;
  logic        s1_a_lt_c;

  always_ff @(posedge clk) begin
    s1_max_ab <= a_lt_b ? f_b : f_a;
    s1_min_ab <= a_lt_b ? f_a : f_b;
    f_c_r1    <= f_c;
    s1_a_lt_c <= a_lt_c;
  end

  // =========================================================================
  // STAGE 2: Final Sorting and Resolution
  // =========================================================================
  logic max_ab_lt_c, min_ab_lt_c;

  always_comb begin
    // Compare max(A,B) vs C
    if (s1_max_ab[31] != f_c_r1[31]) begin
      max_ab_lt_c = s1_max_ab[31];
    end else if (s1_max_ab[31]) begin
      max_ab_lt_c = (s1_max_ab[30:0] > f_c_r1[30:0]);
    end else begin
      max_ab_lt_c = (s1_max_ab[30:0] < f_c_r1[30:0]);
    end

    // Compare min(A,B) vs C
    if (s1_min_ab[31] != f_c_r1[31]) begin
      min_ab_lt_c = s1_min_ab[31];
    end else if (s1_min_ab[31]) begin
      min_ab_lt_c = (s1_min_ab[30:0] > f_c_r1[30:0]);
    end else begin
      min_ab_lt_c = (s1_min_ab[30:0] < f_c_r1[30:0]);
    end
  end

  // Stage 2 Output Multiplexing Registers
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_out <= 1'b0;
      f_min     <= '0;
      f_max     <= '0;
    end else begin
      valid_out <= v_pipe[0];
      f_max     <= max_ab_lt_c ? f_c_r1 : s1_max_ab;
      f_min     <= min_ab_lt_c ? s1_min_ab : f_c_r1;
    end
  end

endmodule
