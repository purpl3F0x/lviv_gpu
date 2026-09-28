`timescale 1ns / 1ps

module tb_blend_unit;
  import gpu_types_pkg::*;
  logic clk = 0;
  blend_op_t sfactor_op;
  blend_op_t dfactor_op;
  color_argb_t src_color;
  color_argb_t dst_color;
  color_argb_t blend_color;
  logic [31:0] expected [7];

  blend_unit dut (.*);
  always #5 clk = ~clk;

  function automatic logic [31:0] reference_color(
      input logic [31:0] source, input logic [31:0] destination, input bit alpha_blend);
    int unsigned source_factor, destination_factor, channel_sum;
    logic [31:0] result;
    source_factor = alpha_blend ? int'(source[31:24]) : 255;
    destination_factor = alpha_blend ? 255 - source_factor : 0;
    for (int channel = 0; channel < 4; channel++) begin
      channel_sum = int'(source[channel*8 +: 8]) * source_factor
                  + int'(destination[channel*8 +: 8]) * destination_factor + 128;
      result[channel*8 +: 8] = 8'((channel_sum >> 8) > 255 ? 255 : channel_sum >> 8);
    end
    return result;
  endfunction

  initial begin
    for (int cycle = 0; cycle < 300; cycle++) begin
      @(negedge clk);
      src_color = color_argb_t'({8'(cycle), 8'(cycle*3), 8'(cycle*7), 8'(cycle*11)});
      dst_color = color_argb_t'({8'(255-cycle), 8'(cycle*13), 8'(cycle*17), 8'(cycle*19)});
      sfactor_op = cycle % 3 == 0 ? ONE : SRC_ALPHA;
      dfactor_op = cycle % 3 == 0 ? ZERO : ONE_MINUS_SRC_ALPHA;
      @(posedge clk);
      for (int stage = 6; stage > 0; stage--) expected[stage] = expected[stage-1];
      expected[0] = reference_color(src_color, dst_color, sfactor_op == SRC_ALPHA);
      #1;
      if (cycle >= 6 && blend_color !== expected[6])
        $fatal(1, "Blend mismatch cycle=%0d expected=%h got=%h", cycle, expected[6], blend_color);
    end
    $display("PASS: 294 consecutive blend results, changing alpha, destination and factors");
    $finish;
  end
endmodule
