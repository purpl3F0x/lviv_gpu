`timescale 1ns / 1ps

module tb_fp_min_max_2 ();

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

  logic        valid_out_min;
  logic [31:0] f_min;

  logic        valid_out_max;
  logic [31:0] f_max;

  // =========================================================================
  // DUT Instantiations
  // =========================================================================
  fp_min_2 dut_min (
      .clk      (clk),
      .rst_n    (rst_n),
      .valid_in (valid_in),
      .f_a      (f_a),
      .f_b      (f_b),
      .valid_out(valid_out_min),
      .f_min    (f_min)
  );

  fp_max_2 dut_max (
      .clk      (clk),
      .rst_n    (rst_n),
      .valid_in (valid_in),
      .f_a      (f_a),
      .f_b      (f_b),
      .valid_out(valid_out_max),
      .f_max    (f_max)
  );

  // =========================================================================
  // Scoreboard / Verification Queues (Handles 1-Cycle Latency)
  // =========================================================================
  shortreal min_gold_queue[$];
  shortreal max_gold_queue[$];

  int error_count = 0;
  int test_count = 0;

  // Helper functions to get golden references
  function automatic shortreal get_min_gold(shortreal a, shortreal b);
    return (a < b) ? a : b;
  endfunction

  // Simple max helper (ignores nan for simple scoreboard float type checks)
  function automatic shortreal get_max_gold(shortreal a, shortreal b);
    return (a > b) ? a : b;
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

    // Hold reset over 10 cycles
    repeat (10) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);

    $display("[TB INFO] Starting Min/Max 2 Random Testing (%d cases)...", NUMBER_OF_TESTS);

    for (int_step = 0; int_step < NUMBER_OF_TESTS; int_step++) begin
      shortreal r_a, r_b;
      shortreal r_a_round, r_b_round;
      int choice;

      choice = $urandom_range(0, 9);
      if (choice == 0) begin
        // Test zeros (both positive and negative)
        r_a = ($urandom_range(0, 1) == 0) ? 0.0 : -0.0;
        r_b = ($urandom_range(0, 1) == 0) ? 0.0 : -0.0;
      end else if (choice == 1) begin
        // Test identical values with different/same signs
        shortreal val;
        val = (shortreal'($urandom()) / 4294967295.0) * 100.0;
        r_a = ($urandom_range(0, 1) == 0) ? val : -val;
        r_b = ($urandom_range(0, 1) == 0) ? val : -val;
      end else begin
        // General random values
        r_a = (shortreal'($urandom()) / 4294967295.0) * 20000.0 - 10000.0;
        r_b = (shortreal'($urandom()) / 4294967295.0) * 20000.0 - 10000.0;
      end

      @(posedge clk);
      valid_in <= 1;
      f_a      <= $shortrealtobits(r_a);
      f_b      <= $shortrealtobits(r_b);

      r_a_round = $bitstoshortreal($shortrealtobits(r_a));
      r_b_round = $bitstoshortreal($shortrealtobits(r_b));

      // Push exact golden evaluations into the tracker queues
      min_gold_queue.push_back(get_min_gold(r_a_round, r_b_round));
      max_gold_queue.push_back(get_max_gold(r_a_round, r_b_round));
      test_count++;
    end

    // Turn off stream driver
    @(posedge clk);
    valid_in <= 0;
    f_a      <= '0;
    f_b      <= '0;

    // Drain lingering pipeline tokens out of the verification queue
    while (min_gold_queue.size() > 0 || max_gold_queue.size() > 0) begin
      @(posedge clk);
    end

    // Output complete overview status report
    $display("\n==================================================");
    if (error_count == 0) begin
      $display("  SUCCESS: All %d Min/Max 2 Test Points Passed!", test_count);
    end else begin
      $display("  FAILURE: Encountered %d Errors during tracking.", error_count);
    end
    $display("==================================================");
    $finish;
  end

  // =========================================================================
  // Monitor / Checker Loop
  // =========================================================================
  shortreal expected_min;
  shortreal expected_max;
  shortreal actual_min;
  shortreal actual_max;

  always @(posedge clk) begin
    if (rst_n) begin
      // Both modules have the same valid latency, so we can verify them together
      if (valid_out_min && valid_out_max) begin
        expected_min = min_gold_queue.pop_front();
        expected_max = max_gold_queue.pop_front();

        actual_min = $bitstoshortreal(f_min);
        actual_max = $bitstoshortreal(f_max);

        // Assert strict value matching
        if (actual_min != expected_min) begin
          $display("[ERROR MIN MISMATCH] Expected: %f | Got: %f (Raw bits: 32'h%h)", expected_min,
                   actual_min, f_min);
          error_count++;
        end

        if (actual_max != expected_max) begin
          $display("[ERROR MAX MISMATCH] Expected: %f | Got: %f (Raw bits: 32'h%h)", expected_max,
                   actual_max, f_max);
          error_count++;
        end
      end
    end
  end

endmodule
