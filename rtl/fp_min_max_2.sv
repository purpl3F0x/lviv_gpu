`timescale 1ns / 1ps

// =========================================================================
// fp_min_2: Finds the minimum of two 32-bit single-precision floats (1-cycle latency)
// =========================================================================
module fp_min_2 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        valid_in,
    input  logic [31:0] f_a,
    input  logic [31:0] f_b,
    output logic        valid_out,
    output logic [31:0] f_min
);

  // Combinational comparison
  logic a_lt_b;
  always_comb begin
    if (f_a[31] != f_b[31]) begin
      a_lt_b = f_a[31];  // If signs differ, the negative one is smaller
    end else if (f_a[31]) begin
      a_lt_b = (f_a[30:0] > f_b[30:0]);  // Both negative: larger magnitude is smaller
    end else begin
      a_lt_b = (f_a[30:0] < f_b[30:0]);  // Both positive: smaller magnitude is smaller
    end
  end

  // Register output (1-cycle latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_out <= 1'b0;
      f_min     <= '0;
    end else begin
      valid_out <= valid_in;
      f_min     <= a_lt_b ? f_a : f_b;
    end
  end

endmodule


// =========================================================================
// fp_max_2: Finds the maximum of two 32-bit single-precision floats (1-cycle latency)
// =========================================================================
module fp_max_2 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        valid_in,
    input  logic [31:0] f_a,
    input  logic [31:0] f_b,
    output logic        valid_out,
    output logic [31:0] f_max
);

  // Combinational comparison
  logic a_lt_b;
  always_comb begin
    if (f_a[31] != f_b[31]) begin
      a_lt_b = f_a[31];  // If signs differ, the negative one is smaller
    end else if (f_a[31]) begin
      a_lt_b = (f_a[30:0] > f_b[30:0]);  // Both negative: larger magnitude is smaller
    end else begin
      a_lt_b = (f_a[30:0] < f_b[30:0]);  // Both positive: smaller magnitude is smaller
    end
  end

  // Register output (1-cycle latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_out <= 1'b0;
      f_max     <= '0;
    end else begin
      valid_out <= valid_in;
      f_max     <= a_lt_b ? f_b : f_a;
    end
  end

endmodule
