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
  logic [31:0] a_buffer;
  logic [31:0] b_buffer;
  logic [2:0] cmp_result;

  // Returns {lt, gt, eq} for IEEE754 bit-pattern compare used by this pipeline; -0 equals +0.
  // Each output is computed on its own, so lt needs no equality compare in series with the
  // magnitude compare: two parallel carry-chain compares, two zero detects and one LUT.
  function automatic logic [2:0] fp32_cmp_lge(input logic [31:0] a, input logic [31:0] b);
    logic sa, sb, mag_lt, mag_gt, both_zero;
    begin
      sa = a[31];
      sb = b[31];
      mag_lt = a[30:0] < b[30:0];
      mag_gt = a[30:0] > b[30:0];
      both_zero = a[30:0] == '0 && b[30:0] == '0;

      // Different signs: the negative one is less. Same sign: magnitude order, reversed when
      // negative (equal magnitudes are neither lt nor gt).
      fp32_cmp_lge[2] = !both_zero && ((sa != sb) ? sa : (sa ? mag_gt : mag_lt));  // lt
      fp32_cmp_lge[1] = !both_zero && ((sa != sb) ? sb : (sa ? mag_lt : mag_gt));  // gt
      fp32_cmp_lge[0] = both_zero || a == b;  // eq
    end
  endfunction

  always_comb begin
    cmp_result = fp32_cmp_lge(a_buffer, b_buffer);
  end

  always_ff @(posedge aclk) begin
    if (aclken) begin
      a_buffer  <= s_axis_a;
      b_buffer  <= s_axis_b;
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
