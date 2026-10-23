`timescale 1ns / 1ps

import gpu_types_pkg::*;

// triangle_stream_adapter on its own. Commands of whole triangles start on either half of a beat and
// stream as the DataMover without DRE streams them: whole beats, not realigned, TKEEP over the
// command's bytes. Every triangle that comes out is checked, in order, against its record through
// triangle_unpack.
//   1. full rate: a beat offered every cycle and the output always ready; the adapter must never
//      drop TREADY
//   2. random gaps on the input and back-pressure on the output
module tb_triangle_stream_adapter #(
    parameter int TRIANGLE_STRIDE = 96
);
  localparam int Triangles = 256;
  localparam int CommandsPerPhase = 150;
  localparam int MaxRun = 8;  // triangles per command
  localparam int MemBytes = 64 + Triangles * TRIANGLE_STRIDE + 128;

  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  logic [511:0] s_tdata = '0;
  logic [63:0] s_tkeep = '0;
  logic s_tvalid = 1'b0, s_tready;
  logic m_valid, m_ready = 1'b1;
  frontend_data_in_t m_data;

  triangle_stream_adapter #(
      .TRIANGLE_STRIDE(TRIANGLE_STRIDE)
  ) dut (
      .aclk(clk),
      .aresetn(rst_n),
      .s_axis_tdata(s_tdata),
      .s_axis_tkeep(s_tkeep),
      .s_axis_tvalid(s_tvalid),
      .s_axis_tready(s_tready),
      .m_tri_valid(m_valid),
      .m_tri_ready(m_ready),
      .m_tri_data(m_data)
  );

  logic [7:0] mem[MemBytes];

  // The record as the adapter must deliver it, through the RTL's own unpack.
  logic [767:0] unpack_in;
  frontend_data_in_t unpack_out;
  triangle_unpack u_expected_unpack (
      .packed_triangle(unpack_in),
      .triangle(unpack_out)
  );

  typedef struct packed {
    logic [63:0]  keep;
    logic [511:0] data;
  } beat_t;

  beat_t beats[$];
  frontend_data_in_t expected[$];

  // n triangles from triangle first, of the triangle array at byte base (0 or 32): its beats, and
  // the triangles it must produce.
  task automatic add_command(input int base, input int first, input int n, ref beat_t phase[$]);
    int start, stop;
    beat_t b;
    logic [767:0] record;
    start = base + first * TRIANGLE_STRIDE;
    stop  = start + n * TRIANGLE_STRIDE;
    for (int a = start / 64 * 64; a < stop; a += 64) begin
      for (int k = 0; k < 64; k++) begin
        b.data[8*k+:8] = mem[a+k];
        b.keep[k] = a + k >= start && a + k < stop;
      end
      phase.push_back(b);
    end
    for (int t = first; t < first + n; t++) begin
      for (int k = 0; k < 96; k++) record[8*k+:8] = mem[base+t*TRIANGLE_STRIDE+k];
      unpack_in = record;
      #1;
      expected.push_back(unpack_out);
    end
  endtask

  // Random gaps on the input, back-pressure on the output.
  bit gaps, backpressure;

  always @(posedge clk) begin
    if (!rst_n) begin
      s_tvalid <= 1'b0;
    end else if (!s_tvalid || s_tready) begin
      if (beats.size() != 0 && !(gaps && $urandom_range(3) == 0)) begin
        beat_t b;
        b = beats.pop_front();
        s_tdata  <= b.data;
        s_tkeep  <= b.keep;
        s_tvalid <= 1'b1;
      end else begin
        s_tvalid <= 1'b0;
      end
    end
  end

  always @(posedge clk) m_ready <= !backpressure || $urandom_range(2) != 0;

  int received, errors, stalls;
  bit count_stalls;

  always @(posedge clk) begin
    if (rst_n && m_valid && m_ready) begin
      if (received >= expected.size()) begin
        error($sformatf("triangle %0d: more triangles than the commands hold", received));
      end else if (m_data !== expected[received]) begin
        error($sformatf("triangle %0d: wrong data", received));
      end
      received++;
    end
    if (count_stalls && s_tvalid && !s_tready) stalls++;
  end

  function automatic void error(input string msg);
    errors++;
    if (errors <= 10) $display("[%0t] ERROR: %s", $time, msg);
  endfunction

  task automatic run_phase(input string name);
    beat_t phase[$];
    int base, n, first, beat_count, start_time, earlier;
    earlier = expected.size();
    for (int c = 0; c < CommandsPerPhase; c++) begin
      base  = 32 * $urandom_range(1);
      n     = $urandom_range(MaxRun, 1);
      first = $urandom_range(Triangles - n);
      add_command(base, first, n, phase);
    end
    beat_count = phase.size();
    @(posedge clk);
    start_time = $time;
    beats = phase;  // all at once, so the input never waits on the testbench at full rate
    while (beats.size() != 0 || received < expected.size()) begin
      @(posedge clk);
      if ($time - start_time > 100 * (beat_count + 100)) $fatal(1, "%s: timeout", name);
    end
    $display("[%0t] %s: %0d beats, %0d triangles", $time, name, beat_count,
             expected.size() - earlier);
  endtask

  initial begin
    for (int k = 0; k < MemBytes; k++) mem[k] = 8'($urandom());
    errors = 0;
    received = 0;
    stalls = 0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    gaps = 0;
    backpressure = 0;
    count_stalls = 1;
    run_phase("full rate");
    count_stalls = 0;
    if (stalls != 0) error($sformatf("full rate: TREADY low on %0d cycles", stalls));

    gaps = 1;
    backpressure = 1;
    run_phase("gaps and back-pressure");

    if (errors == 0)
      $display("PASS: stride %0d, %0d triangles, a beat per cycle at full rate", TRIANGLE_STRIDE,
               received);
    else $display("FAIL: %0d errors", errors);
    $finish;
  end
endmodule
