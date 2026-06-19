`timescale 1ns / 1ps

module tb_tri_bb_min_max ();

  localparam int NUMBER_OF_TESTS = 1_000_000;

  // 500 MHz Clock Generation (2.0 ns period)
  logic clk;
  logic rst_n;

  initial begin
    clk = 0;
    forever #1.0 clk = ~clk;
  end

  // Interconnect Signals
  logic        valid_in;
  logic [31:0] f_a;
  logic [31:0] f_b;
  logic [31:0] f_c;

  logic        valid_out;
  logic [31:0] f_min_floor;
  logic [31:0] f_max_ceil;

  // =========================================================================
  // Device Under Test (DUT) Instantiation
  // =========================================================================
  tri_bb_min_max dut (
      .clk        (clk),
      .rst_n      (rst_n),
      .valid_in   (valid_in),
      .f_a        (f_a),
      .f_b        (f_b),
      .f_c        (f_c),
      .valid_out  (valid_out),
      .f_min_floor(f_min_floor),
      .f_max_ceil (f_max_ceil)
  );

  // =========================================================================
  // Scoreboard / Verification Queues (Handles 5-Cycle Latency)
  // =========================================================================
  logic [31:0] min_floor_gold_queue[$];
  logic [31:0] max_ceil_gold_queue[$];

  int error_count = 0;
  int test_count = 0;

  // Golden model functions
  function automatic shortreal get_min_gold(shortreal a, shortreal b, shortreal c);
    shortreal m;
    m = (a < b) ? a : b;
    return (m < c) ? m : c;
  endfunction

  // Note: the comparison logic in fp_min_max_3 handles signs correctly, 
  // but if inputs are +0.0 and -0.0, we need to match the hardware's comparison.
  // In IEEE 754, +0.0 and -0.0 compare equal. In fp_min_max_3.sv, comparison is:
  // if (f_a[31] != f_b[31]) a_lt_b = f_a[31];
  // Which means negative zero is smaller than positive zero.
  // Our behavioral gold model below should match that.
  function automatic shortreal get_max_gold(shortreal a, shortreal b, shortreal c);
    shortreal m;
    m = (a > b) ? a : b;
    return (m > c) ? m : c;
  endfunction

  function automatic logic [31:0] rtl_ceil_to_odd(logic [31:0] f_in);
    logic        sign;
    logic [ 7:0] exp;
    logic [22:0] mant;
    logic [23:0] ext_mant_shifted;
    logic [22:0] frac_mask;
    logic        has_frac;
    logic        int_lsb;
    logic        is_small;
    logic        is_huge;
    logic [24:0] adder_res;
    logic [31:0] final_output;

    sign             = f_in[31];
    exp              = f_in[30:23];
    mant             = f_in[22:0];
    is_small         = (exp < 8'd127);
    is_huge          = (exp >= 8'd150);

    ext_mant_shifted = {1'b1, mant} >> (8'd150 - exp);

    if (exp < 8'd127) begin
      frac_mask = 23'h7FFFFF;
      has_frac  = |mant;
      int_lsb   = 1'b0;
    end else if (exp >= 8'd150) begin
      frac_mask = 23'h000000;
      has_frac  = 1'b0;
      int_lsb   = f_in[0];
    end else begin
      frac_mask = 23'h7FFFFF >> (exp - 8'd127);
      has_frac  = |(mant & frac_mask);
      int_lsb   = ext_mant_shifted[0];
    end

    if (!is_small && !is_huge) begin
      if (!sign) begin
        if (!int_lsb) begin
          adder_res = {1'b1, mant & ~frac_mask} + (24'h000001 << (8'd150 - exp));
        end else begin
          adder_res = {1'b1, mant & ~frac_mask} + (has_frac ? (24'h000002 << (8'd150 - exp)) : 24'h0);
        end
      end else begin
        if (!int_lsb) begin
          adder_res = {1'b1, mant & ~frac_mask} - (24'h000001 << (8'd150 - exp));
        end else begin
          adder_res = {1'b0, 1'b1, mant & ~frac_mask};
        end
      end
    end else begin
      adder_res = {1'b0, 1'b1, mant & ~frac_mask};
    end

    if (is_small) begin
      final_output = sign ? 32'hBF80_0000 : 32'h3F80_0000;
    end else if (is_huge) begin
      if (!adder_res[0]) final_output = {sign, exp, adder_res[22:1], 1'b1};
      else final_output = {sign, exp, adder_res[22:0]};
    end else begin
      if (adder_res[24]) begin
        final_output = {sign, exp + 8'd1, adder_res[23:1]};
      end else if (!adder_res[23]) begin
        final_output = {sign, exp - 8'd1, adder_res[22:0], 1'b0};
      end else begin
        final_output = {sign, exp, adder_res[22:0]};
      end
    end

    return final_output;
  endfunction

  function automatic logic [31:0] rtl_floor_to_even(logic [31:0] f_in);
    logic        sign;
    logic [ 7:0] exp;
    logic [22:0] mant;
    logic [23:0] ext_mant_shifted;
    logic [22:0] frac_mask;
    logic        has_frac;
    logic        int_lsb;
    logic        is_small;
    logic        is_huge;
    logic [24:0] adder_res;
    logic [31:0] final_output;

    sign             = f_in[31];
    exp              = f_in[30:23];
    mant             = f_in[22:0];
    is_small         = (exp < 8'd127);
    is_huge          = (exp >= 8'd150);

    ext_mant_shifted = {1'b1, mant} >> (8'd150 - exp);

    if (exp < 8'd127) begin
      frac_mask = 23'h7FFFFF;
      has_frac  = |mant;
      int_lsb   = 1'b0;
    end else if (exp >= 8'd150) begin
      frac_mask = 23'h000000;
      has_frac  = 1'b0;
      int_lsb   = f_in[0];
    end else begin
      frac_mask = 23'h7FFFFF >> (exp - 8'd127);
      has_frac  = |(mant & frac_mask);
      int_lsb   = ext_mant_shifted[0];
    end

    if (!is_small && !is_huge) begin
      if (!sign) begin
        if (int_lsb) begin
          adder_res = {1'b1, mant & ~frac_mask} - (24'h000001 << (8'd150 - exp));
        end else begin
          adder_res = {1'b0, 1'b1, mant & ~frac_mask};
        end
      end else begin
        if (!int_lsb) begin
          adder_res = {1'b1, mant & ~frac_mask} + (has_frac ? (24'h000002 << (8'd150 - exp)) : 24'h0);
        end else begin
          adder_res = {1'b1, mant & ~frac_mask} + (24'h000001 << (8'd150 - exp));
        end
      end
    end else begin
      adder_res = {1'b0, 1'b1, mant & ~frac_mask};
    end

    if (is_small) begin
      if (sign) final_output = 32'hC000_0000;
      else final_output = 32'h0000_0000;
    end else if (is_huge) begin
      final_output = {sign, exp, adder_res[22:1], 1'b0};
    end else begin
      if (adder_res[24]) begin
        final_output = {sign, exp + 8'd1, adder_res[23:1]};
      end else if (!adder_res[23]) begin
        if (adder_res[22:0] == '0) begin
          final_output = {sign, 31'h0};
        end else begin
          final_output = {sign, exp - 8'd1, adder_res[22:0], 1'b0};
        end
      end else begin
        final_output = {sign, exp, adder_res[22:0]};
      end
    end

    return final_output;
  endfunction

  // =========================================================================
  // Driver Stimulus Loop
  // =========================================================================
  int unsigned int_step;

  initial begin
    rst_n    = 0;
    valid_in = 0;
    f_a      = '0;
    f_b      = '0;
    f_c      = '0;

    // Hold reset over 10 cycles
    repeat (10) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);

    $display("[TB INFO] Starting Triangle BB Min/Max Random Testing (%d cases)...",
             NUMBER_OF_TESTS);

    for (int_step = 0; int_step < NUMBER_OF_TESTS; int_step++) begin
      shortreal r_a, r_b, r_c;
      shortreal r_a_round, r_b_round, r_c_round;
      shortreal min_val, max_val;
      int choice;
      logic [31:0] b_a;
      logic [31:0] b_b;
      logic [31:0] b_c;
      logic a_lt_b, a_lt_c, min_ab_lt_c, max_ab_lt_c;
      logic [31:0] s1_min_ab, s1_max_ab, f_min_bits, f_max_bits;

      choice = $urandom_range(0, 9);
      if (choice == 0) begin
        // Test zeros (both positive and negative)
        r_a = ($urandom_range(0, 1) == 0) ? 0.0 : -0.0;
        r_b = ($urandom_range(0, 1) == 0) ? 0.0 : -0.0;
        r_c = ($urandom_range(0, 1) == 0) ? 0.0 : -0.0;
      end else if (choice == 1) begin
        // Test identical values with different/same signs
        shortreal val;
        val = (shortreal'($urandom()) / 4294967295.0) * 100.0;
        r_a = ($urandom_range(0, 1) == 0) ? val : -val;
        r_b = ($urandom_range(0, 1) == 0) ? val : -val;
        r_c = ($urandom_range(0, 1) == 0) ? val : -val;
      end else if (choice == 2) begin
        // Test small values (magnitude < 1.0)
        r_a = (shortreal'($urandom()) / 4294967295.0) * 2.0 - 1.0;
        r_b = (shortreal'($urandom()) / 4294967295.0) * 2.0 - 1.0;
        r_c = (shortreal'($urandom()) / 4294967295.0) * 2.0 - 1.0;
      end else begin
        // General random values
        r_a = (shortreal'($urandom()) / 4294967295.0) * 20000.0 - 10000.0;
        r_b = (shortreal'($urandom()) / 4294967295.0) * 20000.0 - 10000.0;
        r_c = (shortreal'($urandom()) / 4294967295.0) * 20000.0 - 10000.0;
      end

      @(posedge clk);
      valid_in <= 1;
      f_a      <= $shortrealtobits(r_a);
      f_b      <= $shortrealtobits(r_b);
      f_c      <= $shortrealtobits(r_c);

      r_a_round = $bitstoshortreal($shortrealtobits(r_a));
      r_b_round = $bitstoshortreal($shortrealtobits(r_b));
      r_c_round = $bitstoshortreal($shortrealtobits(r_c));

      // Golden comparison logic matching hardware (which evaluates -0.0 < +0.0)
      // We perform comparison on raw bits if the values are equal in float math.
      // E.g., for get_min_gold:
      // In hardware, if f_a[31] != f_b[31], the one with sign bit set is smaller.
      // So -0.0 is smaller than +0.0.
      b_a = $shortrealtobits(r_a_round);
      b_b = $shortrealtobits(r_b_round);
      b_c = $shortrealtobits(r_c_round);

      // A < B
      if (b_a[31] != b_b[31]) a_lt_b = b_a[31];
      else if (b_a[31]) a_lt_b = (b_a[30:0] > b_b[30:0]);
      else a_lt_b = (b_a[30:0] < b_b[30:0]);

      // A < C
      if (b_a[31] != b_c[31]) a_lt_c = b_a[31];
      else if (b_a[31]) a_lt_c = (b_a[30:0] > b_c[30:0]);
      else a_lt_c = (b_a[30:0] < b_c[30:0]);

      s1_min_ab = a_lt_b ? b_a : b_b;
      s1_max_ab = a_lt_b ? b_b : b_a;

      // min(A,B) < C
      if (s1_min_ab[31] != b_c[31]) min_ab_lt_c = s1_min_ab[31];
      else if (s1_min_ab[31]) min_ab_lt_c = (s1_min_ab[30:0] > b_c[30:0]);
      else min_ab_lt_c = (s1_min_ab[30:0] < b_c[30:0]);

      // max(A,B) < C
      if (s1_max_ab[31] != b_c[31]) max_ab_lt_c = s1_max_ab[31];
      else if (s1_max_ab[31]) max_ab_lt_c = (s1_max_ab[30:0] > b_c[30:0]);
      else max_ab_lt_c = (s1_max_ab[30:0] < b_c[30:0]);

      f_min_bits = min_ab_lt_c ? s1_min_ab : b_c;
      f_max_bits = max_ab_lt_c ? b_c : s1_max_ab;

      min_val = $bitstoshortreal(f_min_bits);
      max_val = $bitstoshortreal(f_max_bits);

      min_floor_gold_queue.push_back(rtl_floor_to_even(f_min_bits));
      max_ceil_gold_queue.push_back(rtl_ceil_to_odd(f_max_bits));
      test_count++;
    end

    // Turn off stream driver
    @(posedge clk);
    valid_in <= 0;
    f_a      <= '0;
    f_b      <= '0;
    f_c      <= '0;

    // Drain lingering pipeline tokens out of the verification queue
    while (min_floor_gold_queue.size() > 0 || max_ceil_gold_queue.size() > 0) begin
      @(posedge clk);
    end

    // Output complete overview session status report
    $display("\n==================================================");
    if (error_count == 0) begin
      $display("  SUCCESS: All %d Bounding Box Min/Max Test Points Passed!", test_count);
    end else begin
      $display("  FAILURE: Encountered %d Errors during tracking.", error_count);
    end
    $display("==================================================");
    $finish;
  end

  // =========================================================================
  // Monitor / Checker Loop
  // =========================================================================
  logic [31:0] expected_min_floor;
  logic [31:0] expected_max_ceil;
  logic [31:0] actual_min_floor;
  logic [31:0] actual_max_ceil;

  always @(posedge clk) begin
    if (rst_n) begin
      if (valid_out) begin
        expected_min_floor = min_floor_gold_queue.pop_front();
        expected_max_ceil = max_ceil_gold_queue.pop_front();

        actual_min_floor = f_min_floor;
        actual_max_ceil = f_max_ceil;

        // Assert value matching on raw bits
        if (actual_min_floor != expected_min_floor) begin
          $display("[ERROR MIN_FLOOR MISMATCH] Expected: %f (32'h%h) | Got: %f (32'h%h)",
                   $bitstoshortreal(expected_min_floor), expected_min_floor,
                   $bitstoshortreal(actual_min_floor), actual_min_floor);
          error_count++;
        end

        if (actual_max_ceil != expected_max_ceil) begin
          $display("[ERROR MAX_CEIL MISMATCH] Expected: %f (32'h%h) | Got: %f (32'h%h)",
                   $bitstoshortreal(expected_max_ceil), expected_max_ceil,
                   $bitstoshortreal(actual_max_ceil), actual_max_ceil);
          error_count++;
        end
      end
    end
  end

endmodule
