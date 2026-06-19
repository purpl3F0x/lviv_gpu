`timescale 1ns / 1ps

module tb_fp_clamping ();

  // 500 MHz Clock Generation (2.0 ns period)
  logic clk;
  logic rst_n;

  initial begin
    clk = 0;
    forever #1.0 clk = ~clk;
  end

  initial begin
    if ($test$plusargs("dump")) begin
      $dumpfile("waves.vcd");
      $dumpvars(0, tb_fp_clamping);
    end
  end

  // Interconnect Signals
  logic        valid_in;
  logic [31:0] f_in;

  logic        ceil_valid_out;
  logic [31:0] ceil_f_out;

  logic        floor_valid_out;
  logic [31:0] floor_f_out;

  // =========================================================================
  // Device Under Test (DUT) Instantiations
  // =========================================================================
  fp_ceil_n_clamp_to_odd dut_ceil (
      .clk      (clk),
      .rst_n    (rst_n),
      .valid_in (valid_in),
      .f_in     (f_in),
      .valid_out(ceil_valid_out),
      .f_out    (ceil_f_out)
  );

  fp_floor_n_clamp_to_even dut_floor (
      .clk      (clk),
      .rst_n    (rst_n),
      .valid_in (valid_in),
      .f_in     (f_in),
      .valid_out(floor_valid_out),
      .f_out    (floor_f_out)
  );

  // =========================================================================
  // Scoreboard / Verification Queue Structures
  // =========================================================================
  // Queues to track inputs across the 3-cycle pipeline delay latency
  shortreal input_ceil_queue[$];
  shortreal input_floor_queue[$];
  // shortreal ceil_gold_queue[$];
  // shortreal floor_gold_queue[$];
  shortreal r_rounded;

  int error_count = 0;
  int test_count = 0;

  // Helper functions to calculate golden outputs using behavioral rules
  function automatic shortreal get_ceil_to_odd_gold(shortreal val);
    int integer_part;
    shortreal ceiled_val;

    ceiled_val   = $ceil(val);
    integer_part = int'(ceiled_val);

    if ((integer_part & 1) == 0) begin
      return ceiled_val + 1.0;
    end else begin
      return ceiled_val;
    end
  endfunction

  function automatic shortreal get_floor_to_even_gold(shortreal val);
    int integer_part;
    shortreal floored_val;

    floored_val  = $floor(val);
    integer_part = int'(floored_val);

    if ((integer_part & 1) != 0) begin
      return floored_val - 1.0;
    end else begin
      return floored_val;
    end
  endfunction

  // =========================================================================
  // Driver Stimulus Thread
  // =========================================================================
  initial begin
    rst_n    = 0;
    valid_in = 0;
    f_in     = '0;

    // Assert reset over 10 cycles
    repeat (10) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);

    $display("[TB INFO] Starting Float Sweep from 0.0 to 4096.0...");

    // Sweep loop with fractional steps
    for (shortreal r = 0.0; r <= 4096.0; r += 0.000001) begin
      @(posedge clk);
      valid_in <= 1;
      r_rounded = $bitstoshortreal($shortrealtobits(r));
      f_in <= $shortrealtobits(r_rounded);

      // Push expected values into checking queues
      input_ceil_queue.push_back(r_rounded);
      input_floor_queue.push_back(r_rounded);
      // ceil_gold_queue.push_back(get_ceil_to_odd_gold(r_rounded));
      // floor_gold_queue.push_back(get_floor_to_even_gold(r_rounded));
      test_count++;
    end

    // Turn off input streaming
    @(posedge clk);
    valid_in <= 0;
    f_in     <= '0;

    // Wait out pipeline draining trailing cycles
    while (input_ceil_queue.size() > 0 || input_floor_queue.size() > 0) begin
      @(posedge clk);
    end

    // Final Assessment report
    $display("\n==================================================");
    if (error_count == 0) begin
      $display("  SUCCESS: All %d Verification Points Passed!", test_count);
    end else begin
      $display("  FAILURE: Found %d Errors during checking loop.", error_count);
    end
    $display("==================================================");
    $finish;
  end

  // =========================================================================
  // Monitor / Scoreboard Checker Thread
  // =========================================================================
  shortreal expected_ceil;
  shortreal actual_ceil;
  shortreal expected_floor;
  shortreal actual_floor;
  shortreal input_val_ceil;
  shortreal input_val_floor;

  always @(posedge clk) begin
    if (rst_n) begin
      // Check Ceil to Odd Output
      if (ceil_valid_out) begin
        input_val_ceil = input_ceil_queue.pop_front();
        expected_ceil = get_ceil_to_odd_gold(input_val_ceil);
        actual_ceil = $bitstoshortreal(ceil_f_out);

        if (actual_ceil != expected_ceil) begin
          $display(
              "[ERROR Mismatch Ceil] Input: %.15f (32'h%h) | Expected: %.15f | Got: %.15f (Raw bits: 32'h%h)",
              input_val_ceil, $shortrealtobits(input_val_ceil), expected_ceil, actual_ceil,
              ceil_f_out);
          error_count++;
        end
      end

      // Check Floor to Even Output
      if (floor_valid_out) begin
        input_val_floor = input_floor_queue.pop_front();
        expected_floor = get_floor_to_even_gold(input_val_floor);
        actual_floor = $bitstoshortreal(floor_f_out);

        if (actual_floor != expected_floor) begin
          $display(
              "[ERROR Mismatch Floor] %.15f (32'h%h) | Expected: %.15f | Got: %.15f (Raw bits: 32'h%h)",
              input_val_floor, $shortrealtobits(input_val_floor), expected_floor, actual_floor,
              floor_f_out);
          error_count++;
        end
      end
    end
  end

endmodule
