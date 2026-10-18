`timescale 1ns / 1ns

module tb_thread_orchestrator #(
  // Frontend clock half period; the orchestrator and threads run with a half period of 5.
  parameter int IN_HALF_PERIOD = 10
);
  import gpu_types_pkg::*;

  logic in_clk = 0;
  logic clk = 0;
  logic in_rst_n = 0;
  logic rst_n = 0;
  logic valid_in = 0;
  logic ready_out;
  orchestrator_data_in_t in_data;
  logic ready_in[4];
  logic valid_out[4];
  thread_data_in_t out_data[4];
  logic empty;

  thread_orchestrator dut (.*);
  always #5 clk = ~clk;
  always #(IN_HALF_PERIOD) in_clk = ~in_clk;

  localparam int ThreadFifoDepthTb = 32;

  // 0: all ready, 1: random, 2: none, 3: per-lane skewed
  int ready_mode = 0;
  thread_data_in_t expected[4][$];
  int errors = 0;
  int tokens = 0;
  int triangles = 0;
  longint cycle = 0;
  longint lane0_accepts[$];
  longint pop_cycles[int];
  thread_data_in_t held_data[4];
  bit held_valid[4];
  int ready_low_cycles = 0;
  int max_fill = 0;

  // Round to nearest even, as the fx28_20_to_fp32 simulation model and the Xilinx IP.
  function automatic logic [31:0] to_float(input longint fixed);
    shortreal value;
    value = real'(fixed) / 1048576.0;
`ifdef VERILATOR
    return dpi_float_to_bits(value);
`else
    return $shortrealtobits(value);
`endif
  endfunction

  function automatic longint rand_fixed(input int range, input int frac_bits);
    longint whole, frac;
    whole = longint'($urandom_range(2 * range)) - longint'(range);
    frac = longint'($urandom_range((1 << frac_bits) - 1));
    return (whole <<< frac_bits) + frac;
  endfunction

  task automatic send_triangle(input int w, input int h, input int min_x, input int min_y);
    orchestrator_data_in_t tdata;
    thread_data_in_t token;
    longint init[3], dx[3], dy[3], value;
    int gx, lx, ly;

    for (int e = 0; e < 3; e++) begin
      init[e] = rand_fixed(1000, 20);
      dx[e] = rand_fixed(60, 10);
      dy[e] = rand_fixed(60, 10);
    end

    tdata = '0;
    tdata.init_e0 = fx_28_20_t'(init[0]);
    tdata.init_e1 = fx_28_20_t'(init[1]);
    tdata.init_e2 = fx_28_20_t'(init[2]);
    tdata.e0_dx = fx_14_10_t'(dx[0]);
    tdata.e1_dx = fx_14_10_t'(dx[1]);
    tdata.e2_dx = fx_14_10_t'(dx[2]);
    tdata.e0_dy = fx_14_10_t'(dy[0]);
    tdata.e1_dy = fx_14_10_t'(dy[1]);
    tdata.e2_dy = fx_14_10_t'(dy[2]);
    tdata.minX_local = TILE_ADDR_X'(min_x);
    tdata.minY_local = TILE_ADDR_Y'(min_y);
    tdata.width = TILE_ADDR_X'(w);
    tdata.height = TILE_ADDR_Y'(h);
    tdata.v0_u = 18'($urandom);
    tdata.v0_v = 18'($urandom);
    tdata.v1_u = 18'($urandom);
    tdata.v1_v = 18'($urandom);
    tdata.v2_u = 18'($urandom);
    tdata.v2_v = 18'($urandom);
    tdata.tex_id = 8'(triangles);
    tdata.texture_mode_u = texture_address_mode_t'($urandom_range(1));
    tdata.texture_mode_v = texture_address_mode_t'($urandom_range(1));
    tdata.texture_function = fragment_op_t'($urandom_range(5));
    tdata.sfactor_op = blend_op_t'($urandom_range(9));
    tdata.dfactor_op = blend_op_t'($urandom_range(9));
    tdata.inv_area = $urandom;
    tdata.v0_w = $urandom;
    tdata.v0_z = $urandom;
    tdata.v1_w = $urandom;
    tdata.v1_z = $urandom;
    tdata.v2_w = $urandom;
    tdata.v2_z = $urandom;
    tdata.v0_color = $urandom;
    tdata.v1_color = $urandom;
    tdata.v2_color = $urandom;

    token = '0;
    token.tex_id = tdata.tex_id;
    token.texture_mode_u = tdata.texture_mode_u;
    token.texture_mode_v = tdata.texture_mode_v;
    token.texture_function = tdata.texture_function;
    token.sfactor_op = tdata.sfactor_op;
    token.dfactor_op = tdata.dfactor_op;
    token.inv_area = tdata.inv_area;
    token.v0_u = tdata.v0_u;
    token.v0_v = tdata.v0_v;
    token.v1_u = tdata.v1_u;
    token.v1_v = tdata.v1_v;
    token.v2_u = tdata.v2_u;
    token.v2_v = tdata.v2_v;
    token.v0_w = tdata.v0_w;
    token.v0_z = tdata.v0_z;
    token.v1_w = tdata.v1_w;
    token.v1_z = tdata.v1_z;
    token.v2_w = tdata.v2_w;
    token.v2_z = tdata.v2_z;
    token.v0_color = tdata.v0_color;
    token.v1_color = tdata.v1_color;
    token.v2_color = tdata.v2_color;

    // w and h are the last group offsets (group count - 1).
    for (int gy = 0; gy <= h; gy++) begin
      for (int k = 0; k <= w; k++) begin
        gx = (gy % 2 == 0) ? k : w - k;
        for (int lane = 0; lane < 4; lane++) begin
          lx = lane & 1;
          ly = lane >> 1;
          value = init[0] + ((lx + 2 * gx) * dx[0] + (ly + 2 * gy) * dy[0]) * 1024;
          token.e0 = to_float(value);
          value = init[1] + ((lx + 2 * gx) * dx[1] + (ly + 2 * gy) * dy[1]) * 1024;
          token.e1 = to_float(value);
          value = init[2] + ((lx + 2 * gx) * dx[2] + (ly + 2 * gy) * dy[2]) * 1024;
          token.e2 = to_float(value);
          token.addr = {TILE_ADDR_Y'(min_y + gy), TILE_ADDR_X'(min_x + gx)};
          expected[lane].push_back(token);
        end
      end
    end

    // Drive from the low phase of in_clk; the handshake happens on the next posedge with
    // ready_out high.
    if (in_clk) @(negedge in_clk);
    in_data  = tdata;
    valid_in = 1;
    while (!ready_out) @(negedge in_clk);
    @(negedge in_clk);
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
      || expected[3].size() || dut.triangle_valid || dut.busy) begin
      @(negedge clk);
      if (++timeout > 500000)
        $fatal(1, "%s: drain timeout, expected %0d/%0d/%0d/%0d, triangle_valid %0d busy %0d",
               name, expected[0].size(), expected[1].size(), expected[2].size(),
               expected[3].size(), dut.triangle_valid, dut.busy);
    end
    repeat (20) @(negedge clk);
    for (int lane = 0; lane < 4; lane++)
      if (valid_out[lane]) $fatal(1, "%s: extra token on lane %0d", name, lane);
    if (!ready_out) $fatal(1, "%s: ready_out low after drain", name);
    if (!empty) $fatal(1, "%s: empty low after drain", name);
    $display("  %-28s ok  (%0d triangles, %0d tokens so far)", name, triangles, tokens);
  endtask

  always @(negedge clk) begin
    for (int lane = 0; lane < 4; lane++) begin
      case (ready_mode)
        0: ready_in[lane] = 1'b1;
        1: ready_in[lane] = ($urandom_range(3) != 0);
        2: ready_in[lane] = 1'b0;
        default: ready_in[lane] = ($urandom_range(lane * 3 + 1) == 0);
      endcase
    end
  end

  always @(posedge in_clk) begin
    if (in_rst_n && valid_in && !ready_out) ready_low_cycles++;
  end

  always @(posedge clk) begin
    thread_data_in_t exp;
    if (!rst_n) begin
      for (int lane = 0; lane < 4; lane++) held_valid[lane] = 0;
    end else begin
      cycle++;
      if (dut.triangle_pop) pop_cycles[int'(dut.triangle.tex_id)] = cycle;
      if (dut.out_fire && (dut.g_thread_fifo[0].u_fifo.fifo_full
          || dut.g_thread_fifo[1].u_fifo.fifo_full || dut.g_thread_fifo[2].u_fifo.fifo_full
          || dut.g_thread_fifo[3].u_fifo.fifo_full))
        $fatal(1, "write into a full FIFO at cycle %0d", cycle);
      if (int'(dut.g_thread_fifo[0].u_fifo.fill_cnt) > max_fill)
        max_fill = int'(dut.g_thread_fifo[0].u_fifo.fill_cnt);

      for (int lane = 0; lane < 4; lane++) begin
        if (empty && valid_out[lane]) $fatal(1, "empty high with a token on lane %0d", lane);
        if (held_valid[lane] && (!valid_out[lane] || out_data[lane] !== held_data[lane]))
          $fatal(1, "stalled thread output changed on lane %0d", lane);
        if (valid_out[lane] && ready_in[lane]) begin
          if (expected[lane].size() == 0) $fatal(1, "unexpected token on lane %0d", lane);
          exp = expected[lane].pop_front();
          if (out_data[lane] !== exp) begin
            errors++;
            if (errors <= 10)
              $display("MISMATCH lane %0d @%0d: addr %h/%h e0 %h/%h e1 %h/%h e2 %h/%h tex %h/%h",
                       lane, cycle, out_data[lane].addr, exp.addr, out_data[lane].e0, exp.e0,
                       out_data[lane].e1, exp.e1, out_data[lane].e2, exp.e2,
                       out_data[lane].tex_id, exp.tex_id);
          end
          if (lane == 0) begin
            tokens++;
            lane0_accepts.push_back(cycle);
          end
        end
        held_valid[lane] = valid_out[lane] && !ready_in[lane];
        held_data[lane] = out_data[lane];
      end
    end
  end

  initial begin
    int first_id;

    in_data = '0;
    repeat (5) @(negedge in_clk);
    in_rst_n = 1;
    rst_n = 1;
    repeat (2) @(negedge in_clk);

    // 32x32 groups with every thread ready must stream one group per cycle.
    ready_mode = 0;
    lane0_accepts.delete();
    send_triangle(31, 31, 0, 0);
    drain("throughput 32x32");
    if (lane0_accepts[$] - lane0_accepts[0] != 1023)
      $fatal(1, "throughput: 1024 groups took %0d cycles", lane0_accepts[$] - lane0_accepts[0] + 1);

    send_triangle(0, 0, 5, 7);
    send_triangle(63, 0, 0, 3);
    send_triangle(0, 63, 9, 0);
    drain("degenerate shapes");

    // Single-group triangles at the full frontend rate must never back-pressure the frontend.
    ready_low_cycles = 0;
    for (int triangle_idx = 0; triangle_idx < 64; triangle_idx++)
      send_triangle(0, 0, triangle_idx, triangle_idx);
    drain("single-group stream");
    if (IN_HALF_PERIOD >= 5 && ready_low_cycles != 0)
      $fatal(1, "single-group stream: ready_out low for %0d frontend cycles", ready_low_cycles);

    // Queue single-group triangles behind a stalled one; once released they issue one per cycle.
    ready_mode = 2;
    send_triangle(15, 15, 0, 0);
    repeat (300) @(negedge clk);
    first_id = triangles;
    pop_cycles.delete();
    for (int triangle_idx = 0; triangle_idx < 12; triangle_idx++)
      send_triangle(0, 0, triangle_idx, 40);
    repeat (50) @(negedge clk);
    ready_mode = 0;
    drain("single-group burst");
    for (int id = first_id + 1; id < first_id + 12; id++)
      if (pop_cycles[id % 256] - pop_cycles[(id - 1) % 256] != 1)
        $fatal(1, "single-group burst: triangle %0d issued %0d cycles after the previous one",
               id, pop_cycles[id % 256] - pop_cycles[(id - 1) % 256]);

    send_random(60, 1);
    drain("tiny back-to-back");

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
    if (empty) $fatal(1, "empty high while the thread FIFOs are stalled full");
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
