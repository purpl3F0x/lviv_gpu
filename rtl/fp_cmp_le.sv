`timescale 1ns / 1ps

module fp_cmp_le (
    input aclk,
    input aclken,

    input logic [31:0] s_axis_a,
    // input logic s_axis_a_valid,

    input logic [31:0] s_axis_b,
    // input logic s_axis_b_valid,

    output logic m_axis_res
    // output logic m_axis_tvalid
);

  logic cmp_result;
  logic cmp_valid;

  function automatic logic fp32_le(input logic [31:0] a, input logic [31:0] b);
    logic sa, sb;
    begin
      sa = a[31];
      sb = b[31];
      if (a == b) begin
        fp32_le = 1'b1;
      end else if (sa != sb) begin
        // Negative values (including -0) are <= positive values (including +0).
        fp32_le = sa;
      end else if (!sa) begin
        // Positive domain preserves natural unsigned ordering.
        fp32_le = (a < b);
      end else begin
        // Negative domain reverses ordering.
        fp32_le = (a > b);
      end
    end
  endfunction

  always_ff @(posedge aclk) begin
    if (aclken) begin
      cmp_result <= fp32_le(s_axis_a, s_axis_b);
      // cmp_valid  <= s_axis_a_valid && s_axis_b_valid;
    end
  end

  assign m_axis_res = cmp_result;
  // assign m_axis_tvalid = cmp_valid;

endmodule
