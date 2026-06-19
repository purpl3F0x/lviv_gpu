`timescale 1ns / 1ps

// =========================================================================
// Triangle Bounding Box Min/Max (tri_bb_min_max)
//
// Latency: 5 cycles (2 cycles min/max comparison + 3 cycles rounding)
//
// Description:
// - Takes 3 floating-point inputs (f_a, f_b, f_c).
// - Finds the minimum and maximum among them using fp_min_max_3.
// - Floors the minimum value and clamps it to even using fp_floor_n_clamp_to_even.
// - Ceils the maximum value and clamps it to odd using fp_ceil_n_clamp_to_odd.
// - Outputs the two rounded results (f_min_floor, f_max_ceil) along with
//   valid pipeline control signals.
// =========================================================================
module tri_bb_min_max (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        valid_in,
    input  logic [31:0] f_a,
    input  logic [31:0] f_b,
    input  logic [31:0] f_c,
    output logic        valid_out,
    output logic [31:0] f_min_floor,
    output logic [31:0] f_max_ceil
);

  logic        min_max_valid;
  logic [31:0] f_min_raw;
  logic [31:0] f_max_raw;

  // Instantiate the 3-input min/max unit (2-cycle latency)
  fp_min_max_3 u_min_max_3 (
      .clk      (clk),
      .rst_n    (rst_n),
      .valid_in (valid_in),
      .f_a      (f_a),
      .f_b      (f_b),
      .f_c      (f_c),
      .valid_out(min_max_valid),
      .f_min    (f_min_raw),
      .f_max    (f_max_raw)
  );

  // Instantiate the floor unit (3-cycle latency)
  logic floor_valid;
  fp_floor_n_clamp_to_even u_floor (
      .clk      (clk),
      .rst_n    (rst_n),
      .valid_in (min_max_valid),
      .f_in     (f_min_raw),
      .valid_out(floor_valid),
      .f_out    (f_min_floor)
  );

  // Instantiate the ceil unit (3-cycle latency)
  logic ceil_valid;
  fp_ceil_n_clamp_to_odd u_ceil (
      .clk      (clk),
      .rst_n    (rst_n),
      .valid_in (min_max_valid),
      .f_in     (f_max_raw),
      .valid_out(ceil_valid),
      .f_out    (f_max_ceil)
  );

  // Both rounding units have a 3-cycle latency, so their valids should align.
  assign valid_out = floor_valid;

endmodule
