`timescale 1ns / 1ps

import gpu_types_pkg::*;

// Programmable IEEE754 single-precision compare for the depth test (latency 3, all stages on
// aclken): m_axis_res = a <func> b, where func is a depth_func_t mask of {gt, eq, lt}.
//   stage 1: register a, b and func
//   stage 2: lt / gt / eq (-0 equals +0; NaNs are not handled)
//   stage 3: pass = |(func & {gt, eq, lt}), one LUT from registers
module fp_depth_func (
    input aclk,
    input aclken,

    input logic        [31:0] s_axis_a,
    input logic        [31:0] s_axis_b,
    input depth_func_t        func,

    output logic m_axis_res
);

  logic        lt_result;
  logic        gt_result;
  logic        eq_result;
  logic        pass_result;
  logic [31:0] a_buffer;
  logic [31:0] b_buffer;
  logic [ 2:0] func_buffer;
  logic [ 2:0] func_result;
  logic [ 2:0] cmp_result;

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
      a_buffer    <= s_axis_a;
      b_buffer    <= s_axis_b;
      func_buffer <= func;
      lt_result   <= cmp_result[2];
      gt_result   <= cmp_result[1];
      eq_result   <= cmp_result[0];
      func_result <= func_buffer;
      pass_result <= |(func_result & {gt_result, eq_result, lt_result});
    end
  end

  assign m_axis_res = pass_result;

endmodule
