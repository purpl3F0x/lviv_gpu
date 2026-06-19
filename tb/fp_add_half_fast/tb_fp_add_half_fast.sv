`timescale 1ns / 1ps

module tb_fp_add_half_fast ();

  localparam int NUMBER_OF_TESTS = 8194;

  // 500 MHz Clock Generation (2.0 ns period)
  logic clk;
  logic rst_n;

  initial begin
    clk = 0;
    forever #1.0 clk = ~clk;
  end

  // Interconnect Signals
  logic        valid_in;  // Corrected name
  logic [31:0] f_in;

  logic        valid_out;  // Corrected name
  logic [31:0] f_out;

  // =========================================================================
  // Device Under Test (DUT) Instantiation
  // =========================================================================
  fp_add_half_fast dut (
      .clk      (clk),
      .rst_n    (rst_n),
      .valid_in (valid_in),   // Fixed port connection
      .f_in     (f_in),
      .valid_out(valid_out),  // Fixed port connection
      .f_out    (f_out)
  );

  // =========================================================================
  // Scoreboard / Verification Queues
  // =========================================================================
  shortreal expected_queue[$];
  logic [31:0] input_bits_queue[$];  // New queue to perfectly track input patterns

  int error_count = 0;
  int test_count = 0;

  // Helper function to get golden reference
  function automatic shortreal get_add_half_fast_gold(shortreal val);
    shortreal sum_val;
    sum_val = val + 0.5;
    return $bitstoshortreal($shortrealtobits(sum_val));
  endfunction

  // =========================================================================
  // Driver Stimulus Loop
  // =========================================================================
  initial begin
    rst_n    = 0;
    valid_in = 0;
    f_in     = '0;

    repeat (10) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);

    $display("[TB INFO] Starting FP Add Half Exhaustive Testing (%d cases)...", NUMBER_OF_TESTS);

    for (int unsigned i = 0; i < NUMBER_OF_TESTS; i++) begin
      shortreal r;
      logic [31:0] rand_bits;

      r = shortreal'(i);
      rand_bits = $shortrealtobits(r);

      @(posedge clk);
      valid_in <= 1;
      f_in     <= rand_bits;

      input_bits_queue.push_back(rand_bits);
      expected_queue.push_back(get_add_half_fast_gold(r));
      test_count++;
    end

    @(posedge clk);
    valid_in <= 0;
    f_in     <= '0;

    while (expected_queue.size() > 0) begin
      @(posedge clk);
    end

    $display("\n==================================================");
    if (error_count == 0) begin
      $display("  SUCCESS: All %d Add Half Test Points Passed!", test_count);
    end else begin
      $display("  FAILURE: Encountered %d Errors during tracking.", error_count);
    end
    $display("==================================================");
    $finish;
  end

  // =========================================================================
  // Monitor / Checker Loop
  // =========================================================================
  shortreal expected_val;
  shortreal actual_val;
  logic [31:0] orig_in_bits;

  always @(posedge clk) begin
    if (rst_n) begin
      if (valid_out) begin
        expected_val = expected_queue.pop_front();
        orig_in_bits = input_bits_queue.pop_front();  // Pull raw historical input bits
        actual_val   = $bitstoshortreal(f_out);

        // Assert strict value matching
        if (actual_val != expected_val) begin
          $display(
              "[ERROR MISMATCH] Input bits: 32'h%h | Expected: %f | Got: %f (Raw bits: 32'h%h)",
              orig_in_bits, expected_val, actual_val, f_out);
          error_count++;
        end
      end
    end
  end

endmodule
