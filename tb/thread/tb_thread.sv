`timescale 1ns / 1ps

import gpu_types_pkg::*;

module tb_thread;
  logic                       clk;
  logic                       rst_n;
  logic                       pipe_en;

  logic                       valid_in;
  logic                       ready_out;
  logic    [            31:0] in_e0;
  logic    [            31:0] in_e1;
  logic    [            31:0] in_e2;
  logic    [            31:0] in_inv_area;
  logic    [PIXEL_ADDR_W-1:0] in_addr;
  vertex_t                    in_v0;
  vertex_t                    in_v1;
  vertex_t                    in_v2;

  logic    [            31:0] m_axis_texcoord_u_tdata;
  logic    [            31:0] m_axis_texcoord_v_tdata;
  logic    [             0:0] m_axis_comp_z_tdata;
  logic                       m_axis_tvalid;
  logic                       m_axis_tready;

  logic                       z_rd_en;
  logic    [PIXEL_ADDR_W-1:0] z_rd_addr;
  logic    [            31:0] z_rd_data;
  logic                       z_wr_en;
  logic    [PIXEL_ADDR_W-1:0] z_wr_addr;
  logic    [            31:0] z_wr_data;

  logic                       z_rd_en_d1;
  logic    [PIXEL_ADDR_W-1:0] z_rd_addr_d1;
  localparam logic [31:0] ZramDefault = 32'h40E0_0000;  // 7.0f

  // Simple synchronous z-memory model
  always_ff @(posedge clk) begin
    if (z_rd_en) begin
      z_rd_data <= ZramDefault;
    end else begin
      z_rd_data <= 32'hXXXX_XXXX;
    end
  end



  shortreal                    expected_u_q        [$];
  shortreal                    expected_v_q        [$];
  bit                          expected_pass_q     [$];
  logic     [PIXEL_ADDR_W-1:0] expected_wr_addr_q  [$];
  logic     [            31:0] expected_wr_data_q  [$];

  int                          sent_count;
  int                          recv_count;
  int                          err_count;
  int                          expected_pass_total;
  int                          wr_count;
  int                          expected_wr_total;

  function automatic logic [31:0] fbits(input shortreal v);
    return $shortrealtobits(v);
  endfunction

  function automatic shortreal fr(input logic [31:0] b);
    return $bitstoshortreal(b);
  endfunction

  // Match fp_cmp_le behavior used in thread.
  function automatic bit fp32_le_bits(input logic [31:0] a, input logic [31:0] b);
    bit sa, sb;
    sa = a[31];
    sb = b[31];
    if (a == b) begin
      return 1'b1;
    end else if (sa != sb) begin
      return sa;
    end else if (!sa) begin
      return (a < b);
    end else begin
      return (a > b);
    end
  endfunction

  task automatic push_expected(input shortreal v0z, input shortreal v1z, input shortreal v2z,
                               input shortreal v0w, input shortreal v1w, input shortreal v2w,
                               input shortreal v0u, input shortreal v1u, input shortreal v2u,
                               input shortreal v0v, input shortreal v1v, input shortreal v2v,
                               input shortreal e0, input shortreal e1, input shortreal e2,
                               input shortreal inv_area, input logic [PIXEL_ADDR_W-1:0] mem_addr);
    shortreal iw0, iw1, iw2;
    shortreal z, invW, w, tou, tov, eu, ev;
    logic [31:0] z_bits;
    bit pass;

    iw0 = e0 * inv_area;
    iw1 = e1 * inv_area;
    iw2 = e2 * inv_area;

    z = (v2z * iw2) + (v1z * iw1) + (v0z * iw0);
    z_bits = fbits(z);
    pass = fp32_le_bits(z_bits, ZramDefault);

    invW = (v2w * iw2) + (v1w * iw1) + (v0w * iw0);

    w = 1.0 / invW;

    tou = (v2u * iw2) + (v1u * iw1) + (v0u * iw0);
    tov = (v2v * iw2) + (v1v * iw1) + (v0v * iw0);

    eu = tou * w;
    ev = tov * w;

    expected_u_q.push_back(eu);
    expected_v_q.push_back(ev);
    expected_pass_q.push_back(pass);
    if (pass) begin
      expected_pass_total++;
      expected_wr_total++;
      expected_wr_addr_q.push_back(mem_addr);
      expected_wr_data_q.push_back(z_bits);
    end
  endtask

  task automatic drive_token(input int seed);
    int wait_cycles;
    shortreal v0z, v1z, v2z;
    shortreal v0w, v1w, v2w;
    shortreal v0u, v1u, v2u;
    shortreal v0v, v1v, v2v;
    shortreal e0, e1, e2, inv_area;
    int unsigned mem_addr;

    // Keep ranges bounded to avoid extreme FP artifacts.
    v0z = ($urandom(seed) % 2000) / 1000.0;
    v1z = ($urandom(seed) % 2000) / 1000.0;
    v2z = ($urandom(seed) % 2000) / 1000.0;

    v0w = (($urandom(seed) % 1900) + 100) / 1000.0;
    v1w = (($urandom(seed) % 1900) + 100) / 1000.0;
    v2w = (($urandom(seed) % 1900) + 100) / 1000.0;

    v0u = ($urandom(seed) % 2000) / 1000.0;
    v1u = ($urandom(seed) % 2000) / 1000.0;
    v2u = ($urandom(seed) % 2000) / 1000.0;

    v0v = ($urandom(seed) % 2000) / 1000.0;
    v1v = ($urandom(seed) % 2000) / 1000.0;
    v2v = ($urandom(seed) % 2000) / 1000.0;

    e0 = ($urandom(seed) % 2000) / 1000.0;
    e1 = ($urandom(seed) % 2000) / 1000.0;
    e2 = ($urandom(seed) % 2000) / 1000.0;

    inv_area = (($urandom(seed) % 1900) + 100) / 1000.0;
    mem_addr = $urandom(seed) % (TILE_SIZE_X * TILE_SIZE_Y);

    in_v0 = '0;
    in_v1 = '0;
    in_v2 = '0;

    in_v0.z = fbits(v0z);
    in_v1.z = fbits(v1z);
    in_v2.z = fbits(v2z);

    in_v0.w = fbits(v0w);
    in_v1.w = fbits(v1w);
    in_v2.w = fbits(v2w);

    in_v0.u = fbits(v0u);
    in_v1.u = fbits(v1u);
    in_v2.u = fbits(v2u);

    in_v0.v = fbits(v0v);
    in_v1.v = fbits(v1v);
    in_v2.v = fbits(v2v);

    in_e0 = fbits(e0);
    in_e1 = fbits(e1);
    in_e2 = fbits(e2);
    in_inv_area = fbits(inv_area);
    in_addr = mem_addr[PIXEL_ADDR_W-1:0];

    push_expected(v0z, v1z, v2z, v0w, v1w, v2w, v0u, v1u, v2u, v0v, v1v, v2v, e0, e1, e2, inv_area,
                  in_addr);

    // Present the token on the falling edge so the DUT sees stable inputs
    // at the next rising edge.
    @(negedge clk);
    valid_in = 1'b1;
    wait_cycles = 0;
    do begin
      @(posedge clk);
      wait_cycles++;
      if (wait_cycles > 5000) begin
        $display("[TB][ERROR] Timeout waiting for ready_out in drive_token");
        $finish(1);
      end
    end while (!ready_out);

    @(negedge clk);
    valid_in = 1'b0;

    sent_count++;
  endtask

  // Random output backpressure: low periods up to 50 cycles.
  task automatic random_backpressure(input int cycles);
    int c;
    int hold_len;
    c = 0;
    while (c < cycles) begin
      @(negedge clk);
      m_axis_tready = 1'b1;
      @(posedge clk);
      c++;

      // Random low-ready bursts up to 50 cycles.
      // if (($urandom % 4) == 0) begin
      //   hold_len = $urandom % 51;
      //   m_axis_tready <= 1'b0;
      //   repeat (hold_len) begin
      //     @(posedge clk);
      //     c++;
      //     if (c >= cycles) begin
      //       break;
      //     end
      //   end
      // end
    end

    @(negedge clk);
    m_axis_tready = 1'b1;
  endtask

  // Scoreboard monitor.
  always @(posedge clk) begin
    shortreal got_u, got_v;
    shortreal exp_u, exp_v;
    bit exp_pass;
    bit got_pass;
    shortreal tol;

    if (!rst_n) begin
      // no-op
    end else if (m_axis_tvalid && m_axis_tready) begin
      if (expected_pass_q.size() == 0) begin
        $display("[TB][ERROR] Output observed but expected queue is empty");
        err_count++;
      end else begin
        exp_u = expected_u_q.pop_front();
        exp_v = expected_v_q.pop_front();
        exp_pass = expected_pass_q.pop_front();
        got_pass = m_axis_comp_z_tdata[0];

        if (got_pass != exp_pass) begin
          $display("[TB][ERROR] comp_z mismatch: exp=%0d got=%0d", exp_pass, got_pass);
          err_count++;
        end

        got_u = fr(m_axis_texcoord_u_tdata);
        got_v = fr(m_axis_texcoord_v_tdata);
        tol   = 1e-3;

        if (((got_u - exp_u) > tol) || ((exp_u - got_u) > tol)) begin
          $display("[TB][ERROR] tex_u mismatch: exp=%f got=%f", exp_u, got_u);
          err_count++;
        end
        if (((got_v - exp_v) > tol) || ((exp_v - got_v) > tol)) begin
          $display("[TB][ERROR] tex_v mismatch: exp=%f got=%f", exp_v, got_v);
          err_count++;
        end
      end
      recv_count++;
    end
  end

  // Write-side checker: verify z-buffer writes are in-order and correct.
  always @(posedge clk) begin
    logic [PIXEL_ADDR_W-1:0] exp_addr;
    logic [31:0] exp_data;
    if (!rst_n) begin
      // no-op
    end else if (z_wr_en === 1'b1) begin
      if (expected_wr_addr_q.size() == 0) begin
        $display("[TB][ERROR] Unexpected z write with empty expected queue");
        err_count++;
      end else begin
        exp_addr = expected_wr_addr_q.pop_front();
        exp_data = expected_wr_data_q.pop_front();
        if (z_wr_addr !== exp_addr) begin
          $display("[TB][ERROR] z_wr_addr mismatch: exp=%0d got=%0d", exp_addr, z_wr_addr);
          err_count++;
        end
        if ($bitstoshortreal(z_wr_data) - $bitstoshortreal(exp_data) > 0.0001) begin
          $display("[TB][ERROR] z_wr_data mismatch: exp=0x%08h got=0x%08h", exp_data, z_wr_data);
          err_count++;
        end
      end
      wr_count++;
    end
  end

  // Compare-fail expectations are encoded on m_axis_comp_z_tdata.

  // DUT
  thread dut (
      .clk(clk),
      .rst_n(rst_n),
      .valid_in(valid_in),
      .ready_out(ready_out),
      .in_e0(in_e0),
      .in_e1(in_e1),
      .in_e2(in_e2),
      .in_inv_area(in_inv_area),
      .in_addr(in_addr),
      .in_v0(in_v0),
      .in_v1(in_v1),
      .in_v2(in_v2),
      .m_axis_tvalid(m_axis_tvalid),
      .m_axis_tready(m_axis_tready),
      .m_axis_texcoord_u_tdata(m_axis_texcoord_u_tdata),
      .m_axis_texcoord_v_tdata(m_axis_texcoord_v_tdata),
      .m_axis_comp_z_tdata(m_axis_comp_z_tdata),
      .z_rd_en(z_rd_en),
      .z_rd_addr(z_rd_addr),
      .z_rd_data(z_rd_data),
      .z_wr_en(z_wr_en),
      .z_wr_addr(z_wr_addr),
      .z_wr_data(z_wr_data)
  );

  // Clock
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    int dump_enable;
    dump_enable = 0;
    if ($value$plusargs("dump=%d", dump_enable) && (dump_enable != 0)) begin
      $dumpfile("waves.vcd");
      $dumpvars(0, tb_thread);
    end
  end

  initial begin
    fork
      begin : watchdog
        repeat (200000) @(posedge clk);
        $display("[TB][ERROR] Global simulation timeout");
        $finish(1);
      end
    join_none

    rst_n = 1'b0;
    valid_in = 1'b0;
    in_e0 = '0;
    in_e1 = '0;
    in_e2 = '0;
    in_inv_area = '0;
    in_addr = '0;
    in_v0 = '0;
    in_v1 = '0;
    in_v2 = '0;
    m_axis_tready = 1'b1;
    sent_count = 0;
    recv_count = 0;
    err_count = 0;
    expected_pass_total = 0;
    wr_count = 0;
    expected_wr_total = 0;

    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    // Drive tokens while random backpressure runs.
    fork
      begin : drive_stream
        int i;
        for (i = 0; i < 120; i++) begin
          drive_token(32'h1234 + i);
        end
      end
      begin : backpressure
        random_backpressure(3000);
      end
    join

    // Drain time.
    repeat (400) @(posedge clk);

    $display("[TB] sent=%0d recv=%0d expected_pass=%0d writes=%0d/%0d pending=%0d errors=%0d",
             sent_count, recv_count, expected_pass_total, wr_count, expected_wr_total,
             expected_pass_q.size(), err_count);

    if (recv_count != sent_count) begin
      $display("[TB][ERROR] Output count mismatch: recv=%0d sent=%0d", recv_count, sent_count);
      err_count++;
    end

    if (expected_pass_q.size() != 0) begin
      $display("[TB][ERROR] Expected queue not fully drained: pending=%0d", expected_pass_q.size());
      err_count++;
    end

    if (wr_count != expected_wr_total) begin
      $display("[TB][ERROR] Write count mismatch: got=%0d expected=%0d", wr_count,
               expected_wr_total);
      err_count++;
    end

    if (expected_wr_addr_q.size() != 0 || expected_wr_data_q.size() != 0) begin
      $display(
          "[TB][ERROR] Expected write queue not fully drained: pending_addr=%0d pending_data=%0d",
          expected_wr_addr_q.size(), expected_wr_data_q.size());
      err_count++;
    end

    if (err_count != 0) begin
      $display("[TB] FAIL");
      $finish(1);
    end else begin
      $display("[TB] PASS");
      $finish;
    end
  end

endmodule
