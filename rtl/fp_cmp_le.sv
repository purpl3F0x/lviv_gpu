`timescale 1ns / 1ps

module fp_cmp_le (
  input aclk,
  input aclken,

    input logic [31:0] s_axis_a,
    input logic [31:0] s_axis_b,

    output logic m_axis_res  // TODO: This is a temp fix to not break stuff.
    // output logic m_axis_lt,
    // output logic m_axis_gt,
    // output logic m_axis_eq
);

  logic lt_result;
  logic gt_result;
  logic eq_result;
  logic [2:0] cmp_result;

  // Returns {lt, gt, eq} for IEEE754 bit-pattern compare used by this pipeline.
  function automatic logic [2:0] fp32_cmp_lge(input logic [31:0] a, input logic [31:0] b);
    logic sa, sb;
    begin
      sa = a[31];
      sb = b[31];

      if (a == b) begin
        fp32_cmp_lge = 3'b001;
      end else if (sa != sb) begin
        // Any negative is less than any positive.
        fp32_cmp_lge = sa ? 3'b100 : 3'b010;
      end else if (!sa) begin
        // Positive domain preserves natural unsigned ordering.
        fp32_cmp_lge = (a < b) ? 3'b100 : 3'b010;
      end else begin
        // Negative domain reverses ordering.
        fp32_cmp_lge = (a > b) ? 3'b100 : 3'b010;
      end
    end
  endfunction

  always_comb begin
    cmp_result = fp32_cmp_lge(s_axis_a, s_axis_b);
  end

  always_ff @(posedge aclk) begin
    if (aclken) begin
      lt_result  <= cmp_result[2];
      gt_result  <= cmp_result[1];
      eq_result  <= cmp_result[0];
    end
  end

  assign m_axis_res = lt_result;
  // assign m_axis_lt = lt_result;
  // assign m_axis_gt = gt_result;
  // assign m_axis_eq = eq_result;

endmodule
