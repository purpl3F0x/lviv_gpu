`timescale 1ns / 1ns

module tb_thread_orchestrator #(
  parameter int THREAD_HALF_PERIOD = 7
);
  import gpu_types_pkg::*;

  logic clk = 0;
  logic thread_clk = 0;
  logic rst_n = 0;
  logic valid_in = 0;
  logic ready_out;
  orchestrator_data_in_t in_data;
  logic ready_in[4];
  logic valid_out[4];
  thread_data_in_t out_data[4];

  thread_orchestrator dut (.*);
  always #5 clk = ~clk;
  always #(THREAD_HALF_PERIOD) thread_clk = ~thread_clk;

  localparam int ThreadFifoDepthTb = 32;

  // 0: all ready, 1: random, 2: none, 3: per-lane skewed
  int ready_mode = 0;
  thread_data_in_t expected[4][$];
  int errors = 0;
  int tokens = 0;
  int triangles = 0;
  longint cycle = 0;
  longint thread_cycle = 0;
  longint lane0_accepts[$];
  longint group_issue_cycles[$];
  thread_data_in_t held_data[4];
  bit held_valid[4];
  longint final_issue_cycles[$];
  bit final_issue_prefetched[$];
  int ready_low_cycles = 0;
  int max_fill = 0;

  function automatic logic [31:0] to_float(input longint fixed);
    shortreal value;
    value = real'(fixed) / 4294967296.0;
    return dpi_float_to_bits(value);
  endfunction

  function automatic longint rand_fixed(input int range);
    longint whole, frac;
    whole = longint'($urandom_range(2 * range)) - longint'(range);
    frac = longint'($urandom);
    return (whole <<< 32) + frac;
  endfunction

  task automatic send_triangle(input int w, input int h, input int min_x, input int min_y);
    orchestrator_data_in_t tdata;
    thread_data_in_t base, token;
    longint init[3], dx[3], dy[3], value;
    int gx, lx, ly;

    for (int e = 0; e < 3; e++) begin
      init[e] = rand_fixed(1000);
      dx[e] = rand_fixed(60);
      dy[e] = rand_fixed(60);
    end

    base = '0;
    base.tex_id = 8'(triangles);
    base.inv_area = $urandom;
    base.v0_z = $urandom;
    base.v2_color_b = 8'($urandom);

    tdata = '0;
    tdata.init_e0 = edge_fixed_t'(init[0]);
    tdata.init_e1 = edge_fixed_t'(init[1]);
    tdata.init_e2 = edge_fixed_t'(init[2]);
    tdata.e0_dx = edge_fixed_t'(dx[0]);
    tdata.e1_dx = edge_fixed_t'(dx[1]);
    tdata.e2_dx = edge_fixed_t'(dx[2]);
    tdata.e0_dy = edge_fixed_t'(dy[0]);
    tdata.e1_dy = edge_fixed_t'(dy[1]);
    tdata.e2_dy = edge_fixed_t'(dy[2]);
    tdata.minX_local = TILE_ADDR_X'(min_x);
    tdata.minY_local = TILE_ADDR_Y'(min_y);
    tdata.width = (TILE_ADDR_X + 1)'(w + 1);
    tdata.height = (TILE_ADDR_Y + 1)'(h + 1);
    tdata.thread_data = base;

    for (int gy = 0; gy <= h; gy++) begin
      for (int k = 0; k <= w; k++) begin
        gx = (gy % 2 == 0) ? k : w - k;
        for (int lane = 0; lane < 4; lane++) begin
          lx = lane & 1;
          ly = lane >> 1;
          token = base;
          value = init[0] + lx * dx[0] + ly * dy[0] + 2 * gx * dx[0] + 2 * gy * dy[0];
          token.e0 = to_float(value);
          value = init[1] + lx * dx[1] + ly * dy[1] + 2 * gx * dx[1] + 2 * gy * dy[1];
          token.e1 = to_float(value);
          value = init[2] + lx * dx[2] + ly * dy[2] + 2 * gx * dx[2] + 2 * gy * dy[2];
          token.e2 = to_float(value);
          token.addr = {TILE_ADDR_Y'(min_y + gy), TILE_ADDR_X'(min_x + gx)};
          expected[lane].push_back(token);
        end
      end
    end

    // Called at a negedge; the handshake happens on the next posedge with ready_out high.
    in_data  = tdata;
    valid_in = 1;
    while (!ready_out) @(negedge clk);
    @(negedge clk);
    valid_in = 0;
    triangles++;
  endtask

  task automatic send_random(input int count, input int max_size);
    int w, h;
    for (int i = 0; i < count; i++) begin
      w = $urandom_range(max_size);
      h = $urandom_range(max_size);
      send_triangle(w, h, $urandom_range(63 - w), $urandom_range(63 - h));
    end
  endtask

  task automatic drain(input string name);
    int timeout = 0;
    while (expected[0].size() || expected[1].size() || expected[2].size()
      || expected[3].size() || dut.triangle_count != 0) begin
      @(negedge clk);
      if (++timeout > 500000) $fatal(1, "%s: drain timeout", name);
    end
    repeat (20) @(negedge clk);
    for (int lane = 0; lane < 4; lane++)
      if (valid_out[lane]) $fatal(1, "%s: extra token on lane %0d", name, lane);
    if (!ready_out) $fatal(1, "%s: ready_out low after drain", name);
    $display("  %-28s ok  (%0d triangles, %0d tokens so far)", name, triangles, tokens);
  endtask

  always @(negedge thread_clk) begin
    for (int lane = 0; lane < 4; lane++) begin
      case (ready_mode)
        0: ready_in[lane] = 1'b1;
        1: ready_in[lane] = ($urandom_range(3) != 0);
        2: ready_in[lane] = 1'b0;
        default: ready_in[lane] = ($urandom_range(lane * 3 + 1) == 0);
      endcase
    end
  end

  always @(posedge clk) begin
    if (rst_n) begin
      cycle++;
      if (dut.advance && dut.issue_valid) group_issue_cycles.push_back(cycle);
      if (dut.advance && dut.issue_valid && dut.issue_last) begin
        final_issue_cycles.push_back(cycle);
        final_issue_prefetched.push_back(dut.prefetch_valid);
      end
      if (!ready_out) ready_low_cycles++;
      if (dut.triangle_count > dut.TriangleSlots
          || (dut.triangle_push && dut.triangle_count == dut.TriangleSlots))
        $fatal(1, "triangle stack overflow at cycle %0d", cycle);
      if (dut.triangle_pop && dut.triangle_count == 0)
        $fatal(1, "triangle stack underflow at cycle %0d", cycle);
      if (dut.out_fire && (dut.g_thread_fifo[0].u_fifo.fifo_full
          || dut.g_thread_fifo[1].u_fifo.fifo_full || dut.g_thread_fifo[2].u_fifo.fifo_full
          || dut.g_thread_fifo[3].u_fifo.fifo_full))
        $fatal(1, "write into a full FIFO at cycle %0d", cycle);
      if (int'(dut.g_thread_fifo[0].u_fifo.fill_cnt) > max_fill)
        max_fill = int'(dut.g_thread_fifo[0].u_fifo.fill_cnt);
    end
  end

  always @(posedge thread_clk) begin
    thread_data_in_t exp;
    if (!rst_n) begin
      for (int lane = 0; lane < 4; lane++) held_valid[lane] = 0;
    end else begin
      thread_cycle++;
      for (int lane = 0; lane < 4; lane++) begin
        if (held_valid[lane] && (!valid_out[lane] || out_data[lane] !== held_data[lane]))
          $fatal(1, "stalled thread output changed on lane %0d", lane);
        if (valid_out[lane] && ready_in[lane]) begin
          if (expected[lane].size() == 0) $fatal(1, "unexpected token on lane %0d", lane);
          exp = expected[lane].pop_front();
          if (out_data[lane] !== exp) begin
            errors++;
            if (errors <= 10)
              $display("MISMATCH lane %0d cycle %0d: addr %h/%h e0 %h/%h e1 %h/%h e2 %h/%h tex %h/%h",
                       lane, cycle, out_data[lane].addr, exp.addr, out_data[lane].e0, exp.e0,
                       out_data[lane].e1, exp.e1, out_data[lane].e2, exp.e2,
                       out_data[lane].tex_id, exp.tex_id);
          end
          if (lane == 0) begin
            tokens++;
            lane0_accepts.push_back(thread_cycle);
          end
        end
        held_valid[lane] = valid_out[lane] && !ready_in[lane];
        held_data[lane] = out_data[lane];
      end
    end
  end

  initial begin
    in_data = '0;
    repeat (5) @(negedge clk);
    rst_n = 1;
    @(negedge clk);

    // 32x32 groups with every thread ready must stream one group per cycle.
    ready_mode = 0;
    lane0_accepts.delete();
    group_issue_cycles.delete();
    send_triangle(31, 31, 0, 0);
    drain("throughput 32x32");
    if (THREAD_HALF_PERIOD >= 5 && lane0_accepts[$] - lane0_accepts[0] != 1023)
      $fatal(1, "throughput: 1024 groups took %0d cycles", lane0_accepts[$] - lane0_accepts[0] + 1);
    if (THREAD_HALF_PERIOD < 5 && group_issue_cycles[$] - group_issue_cycles[0] != 1023)
      $fatal(1, "throughput: producer did not sustain one group per cycle");

    send_triangle(0, 0, 5, 7);
    send_triangle(63, 0, 0, 3);
    send_triangle(0, 63, 9, 0);
    drain("degenerate shapes");

    lane0_accepts.delete();
    final_issue_cycles.delete();
    final_issue_prefetched.delete();
    for (int triangle_idx = 0; triangle_idx < 32; triangle_idx++)
      send_triangle(0, 0, triangle_idx, 0);
    drain("single-group cadence");
    if (final_issue_cycles.size() != 32)
      $fatal(1, "single-group issue count was %0d, expected 32", final_issue_cycles.size());
    for (int issue_idx = 1; issue_idx < final_issue_cycles.size(); issue_idx++)
      if (final_issue_cycles[issue_idx] - final_issue_cycles[issue_idx-1] < 2
          || final_issue_cycles[issue_idx] - final_issue_cycles[issue_idx-1]
          > dut.PipeLatency + 1
          || (final_issue_prefetched[issue_idx-1]
              && final_issue_cycles[issue_idx] - final_issue_cycles[issue_idx-1] != 2))
        $fatal(1, "single-group cadence outside stack bound at %0d: cycles %0d to %0d",
            issue_idx, final_issue_cycles[issue_idx-1], final_issue_cycles[issue_idx]);

    ready_mode = 1;
    for (int empty_idx = 0; empty_idx < 8; empty_idx++) begin
      send_triangle(-1, 2, 0, 0);
      send_triangle(1, 1, empty_idx, 0);
      send_triangle(2, -1, 0, 0);
    end
    drain("interleaved empty boxes");
    ready_mode = 0;

    ready_low_cycles = 0;
    send_random(60, 1);
    drain("tiny back-to-back");
    if (ready_low_cycles == 0) $fatal(1, "triangle stack never filled");

    ready_mode = 1;
    send_random(80, 20);
    drain("random thread stalls");

    ready_mode = 3;
    send_random(40, 12);
    drain("per-lane skewed stalls");

    // Threads stop accepting; FIFOs must fill and stall without dropping.
    ready_mode = 2;
    max_fill = 0;
    fork
      send_triangle(39, 39, 4, 4);
      repeat (400) @(negedge clk);
    join
    if (max_fill < ThreadFifoDepthTb - 1) $fatal(1, "FIFO only reached %0d entries", max_fill);
    ready_mode = 0;
    drain("long thread stall");

    ready_mode = 1;
    send_triangle(63, 63, 0, 0);
    drain("full tile, random stalls");

    if (errors) $fatal(1, "FAIL: %0d mismatches", errors);
    $display("PASS: thread_orchestrator, %0d triangles, %0d groups, max FIFO fill %0d",
             triangles, tokens, max_fill);
    $finish;
  end

endmodule
