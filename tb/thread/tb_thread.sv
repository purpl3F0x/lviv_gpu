`timescale 1ns / 1ps

import gpu_types_pkg::*;

module tb_thread;
  localparam int THREAD_ADDR_W = PIXEL_ADDR_W_THREAD;
  localparam int ZBufDepth = (1 << THREAD_ADDR_W);
  logic                       clk;
  logic                       rst_n;

  logic                       valid_in;
  logic                       ready_out;
  thread_data_in_t            in_data;

  logic    [            31:0] out_fb_color;
  logic    [THREAD_ADDR_W-1:0] out_fb_addr;
  logic                       out_fb_valid;
  logic                       out_fb_we;

  logic                       z_rd_en;
  logic    [THREAD_ADDR_W-1:0] z_rd_addr;
  logic    [            31:0] z_rd_data;
  logic                       z_wr_en;
  logic    [THREAD_ADDR_W-1:0] z_wr_addr;
  logic    [            31:0] z_wr_data;
  logic    [            31:0] tex_m_axi_araddr;
  logic    [             7:0] tex_m_axi_arlen;
  logic    [             2:0] tex_m_axi_arsize;
  logic    [             1:0] tex_m_axi_arburst;
  logic                       tex_m_axi_arvalid;
  logic                       tex_m_axi_arready;
  logic    [           127:0] tex_m_axi_rdata;
  logic    [             1:0] tex_m_axi_rresp;
  logic                       tex_m_axi_rvalid;
  logic                       tex_m_axi_rready;
  logic                       tex_m_axi_rlast;
  localparam logic [31:0] ZramDefault = 32'h3F80_0000;  // 1.0f

  assign tex_m_axi_arready = 1'b1;
  assign tex_m_axi_rdata = '0;
  assign tex_m_axi_rresp = '0;
  assign tex_m_axi_rvalid = 1'b0;
  assign tex_m_axi_rlast = 1'b0;

  // Use the shared z-buffer module in behavioral mode for simulation.
  z_buffer_ram #(
      .ADDR_WIDTH(THREAD_ADDR_W),
      .USE_XPM(1'b0)
  ) u_z_buffer_ram (
      .clk(clk),
      .rst_n(1'b1),
      .ready(),
      .wr_en(z_wr_en),
      .wr_addr(z_wr_addr),
      .din(z_wr_data),
      .rd_en(z_rd_en),
      .rd_addr(z_rd_addr),
      .dout(z_rd_data)
  );

  task automatic init_zbuffer_mem;
    int i;
    begin
      for (i = 0; i < ZBufDepth; i++) begin
        u_z_buffer_ram.gen_behav_ram.mem[i] = ZramDefault;
      end
    end
  endtask



  logic     [THREAD_ADDR_W-1:0] expected_wr_addr_q  [$];
  logic     [            31:0] expected_wr_data_q  [$];
  logic     [THREAD_ADDR_W-1:0] expected_fb_addr_q  [$];
  logic     [            31:0] expected_fb_color_q [$];
  logic     [            31:0] expected_z_mem[ZBufDepth];

  int                          sent_count;
  int                          recv_count;
  int                          err_count;
  int                          warn_count;
  int                          expected_pass_total;
  int                          wr_count;
  int                          expected_wr_total;
  int                          rd_count;
  bit                          rd_logged;
  int                          gen_reject_count;
  int                          pipe_en_count;
  int                          v0_count;
  int                          v36_count;
  int                          fb_we_count;
  int                          expected_fb_total;
  int                          l1_req_count;

  localparam int FB_BUNDLE_WIDTH = 48 + 48 + THREAD_ADDR_W + 7 + 1 + 1 + 3 + 8 + 8 + 8 + 8 + 1;

  function automatic logic [31:0] fbits(input shortreal v);
    return $shortrealtobits(v);
  endfunction

  function automatic shortreal fr(input logic [31:0] b);
    return $bitstoshortreal(b);
  endfunction

  function automatic logic [24:0] to_uq2_23(input shortreal v);
    shortreal c;
    int unsigned q;
    if (v < 0.0) begin
      c = 0.0;
    end else if (v > 3.99999988) begin
      c = 3.99999988;
    end else begin
      c = v;
    end
    q = int'((c * 8388608.0) + 0.5);
    if (q > 25'h1ff_ffff) begin
      q = 25'h1ff_ffff;
    end
    return q[24:0];
  endfunction

  function automatic logic [17:0] to_uq5_13(input shortreal v);
    shortreal c;
    int unsigned q;
    if (v < 0.0) begin
      c = 0.0;
    end else if (v > 31.9998779) begin
      c = 31.9998779;
    end else begin
      c = v;
    end
    q = int'((c * 8192.0) + 0.5);
    if (q > 18'h3ffff) begin
      q = 18'h3ffff;
    end
    return q[17:0];
  endfunction

  function automatic shortreal uq5_13_to_real(input logic [17:0] b);
    int unsigned q;
    q = b;
    return q / 8192.0;
  endfunction

  function automatic shortreal uq10_36_to_real(input logic [47:0] b);
    longint unsigned q;
    q = b;
    return q / 68719476736.0;
  endfunction

  function automatic shortreal u8_to_real(input logic [7:0] b);
    int unsigned q;
    q = b;
    return q;
  endfunction

  function automatic shortreal abs_sr(input shortreal v);
    if (v < 0.0) begin
      return -v;
    end
    return v;
  endfunction

  // Match fp_cmp_le ordering used in RTL.
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
                               input shortreal v0r, input shortreal v1r, input shortreal v2r,
                               input shortreal v0g, input shortreal v1g, input shortreal v2g,
                               input shortreal v0b, input shortreal v1b, input shortreal v2b,
                               input shortreal v0a, input shortreal v1a, input shortreal v2a,
                               input shortreal e0, input shortreal e1, input shortreal e2,
                               input shortreal inv_area, input logic [THREAD_ADDR_W-1:0] mem_addr);
    shortreal iw0, iw1, iw2;
    shortreal z, invW, w;
    shortreal pw0, pw1, pw2;
    shortreal eu, ev, er, eg, eb, ea;
    logic [31:0] z_bits;
    logic [31:0] z_ref_bits;
    bit pass;

    iw0 = e0 * inv_area;
    iw1 = e1 * inv_area;
    iw2 = e2 * inv_area;

    z = (v2z * iw2) + (v1z * iw1) + (v0z * iw0);
    z_bits = fbits(z);
    z_ref_bits = expected_z_mem[mem_addr];
    pass = fp32_le_bits(z_bits, z_ref_bits);

    invW = (v2w * iw2) + (v1w * iw1) + (v0w * iw0);

    w = 1.0 / invW;
    pw0 = w * (v0w * iw0);
    pw1 = w * (v1w * iw1);
    pw2 = w * (v2w * iw2);

    eu = (v2u * pw2) + (v1u * pw1) + (v0u * pw0);
    ev = (v2v * pw2) + (v1v * pw1) + (v0v * pw0);
    er = (v2r * pw2) + (v1r * pw1) + (v0r * pw0);
    eg = (v2g * pw2) + (v1g * pw1) + (v0g * pw0);
    eb = (v2b * pw2) + (v1b * pw1) + (v0b * pw0);
    ea = (v2a * pw2) + (v1a * pw1) + (v0a * pw0);

    if (pass) begin
      expected_pass_total++;
    end

    if (pass) begin
      expected_wr_total++;
      expected_wr_addr_q.push_back(mem_addr);
      expected_wr_data_q.push_back(z_bits);
      expected_z_mem[mem_addr] = z_bits;
    end
  endtask

  task automatic drive_token(input int seed);
    int wait_cycles;
    shortreal v0z, v1z, v2z;
    shortreal v0w, v1w, v2w;
    shortreal v0u, v1u, v2u;
    shortreal v0v, v1v, v2v;
    shortreal iw0, iw1, iw2;
    shortreal r0, r1;
    int unsigned c0r, c1r, c2r;
    int unsigned c0g, c1g, c2g;
    int unsigned c0b, c1b, c2b;
    int unsigned c0a, c1a, c2a;
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

    c0r = $urandom(seed) % 256;
    c1r = $urandom(seed) % 256;
    c2r = $urandom(seed) % 256;
    c0g = $urandom(seed) % 256;
    c1g = $urandom(seed) % 256;
    c2g = $urandom(seed) % 256;
    c0b = $urandom(seed) % 256;
    c1b = $urandom(seed) % 256;
    c2b = $urandom(seed) % 256;
    c0a = $urandom(seed) % 256;
    c1a = $urandom(seed) % 256;
    c2a = $urandom(seed) % 256;

    // Generate two barycentric coefficients and derive the third so
    // coefficients are in [0,1] and sum to exactly 1.
    r0 = ($urandom(seed) % 1001) / 1000.0;
    r1 = ($urandom(seed) % 1001) / 1000.0;
    if ((r0 + r1) > 1.0) begin
      r0 = 1.0 - r0;
      r1 = 1.0 - r1;
    end
    iw0 = r0;
    iw1 = r1;
    iw2 = 1.0 - iw0 - iw1;

    // Keep inv_area in a sane positive range and derive edge terms so that
    // (e*inv_area) equals the barycentric coefficients above.
    inv_area = (($urandom(seed) % 1900) + 100) / 1000.0;
    e0 = iw0 / inv_area;
    e1 = iw1 / inv_area;
    e2 = iw2 / inv_area;

    mem_addr = $urandom(seed) % (TILE_SIZE_X * TILE_SIZE_Y);

    in_data = '0;
    in_data.v0_z = fbits(v0z);
    in_data.v1_z = fbits(v1z);
    in_data.v2_z = fbits(v2z);

    in_data.v0_w = fbits(v0w);
    in_data.v1_w = fbits(v1w);
    in_data.v2_w = fbits(v2w);

    in_data.v0_u = to_uq5_13(v0u);
    in_data.v1_u = to_uq5_13(v1u);
    in_data.v2_u = to_uq5_13(v2u);

    in_data.v0_v = to_uq5_13(v0v);
    in_data.v1_v = to_uq5_13(v1v);
    in_data.v2_v = to_uq5_13(v2v);

    in_data.v0_color_r = c0r[7:0];
    in_data.v1_color_r = c1r[7:0];
    in_data.v2_color_r = c2r[7:0];
    in_data.v0_color_g = c0g[7:0];
    in_data.v1_color_g = c1g[7:0];
    in_data.v2_color_g = c2g[7:0];
    in_data.v0_color_b = c0b[7:0];
    in_data.v1_color_b = c1b[7:0];
    in_data.v2_color_b = c2b[7:0];
    in_data.v0_color_a = c0a[7:0];
    in_data.v1_color_a = c1a[7:0];
    in_data.v2_color_a = c2a[7:0];

    in_data.e0 = fbits(e0);
    in_data.e1 = fbits(e1);
    in_data.e2 = fbits(e2);
    in_data.inv_area = fbits(inv_area);
    in_data.addr = mem_addr[THREAD_ADDR_W-1:0];

    // Color-only mode for now: force texturing off.
    in_data.tex_id = '0;
    in_data.texture_function = fragment_op_t'(ADD);

    if (in_data.e0[31] || in_data.e1[31] || in_data.e2[31]) begin
      gen_reject_count++;
    end

        push_expected(v0z, v1z, v2z, v0w, v1w, v2w,
          uq5_13_to_real(in_data.v0_u), uq5_13_to_real(in_data.v1_u), uq5_13_to_real(in_data.v2_u),
          uq5_13_to_real(in_data.v0_v), uq5_13_to_real(in_data.v1_v), uq5_13_to_real(in_data.v2_v),
            c0r, c1r, c2r, c0g, c1g, c2g, c0b, c1b, c2b, c0a, c1a, c2a,
            e0, e1, e2, inv_area, in_data.addr);

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

  // Keep a timing companion process without driving external backpressure.
  task automatic random_backpressure(input int cycles);
    int c;
    c = 0;
    while (c < cycles) begin
      @(posedge clk);
      c++;
    end
  endtask

  // Pre-skid monitor: validate internal signals before the output skid buffer.
  always @(posedge clk) begin
    if (!rst_n) begin
      // no-op
    end else if (dut.output_bundle_tvalid && dut.output_bundle_s_axis_tready) begin
      // comp_z is metadata and may be 0 or 1. It must be known when valid fires.
      if (dut.output_bundle_tdata[0] === 1'bx || dut.output_bundle_tdata[0] === 1'bz) begin
        $display("[TB][ERROR] pre-skid output bundle carried unknown comp_z");
        err_count++;
      end
    end
  end

  // Post-skid handshake monitor: build expected framebuffer outputs.
  always @(posedge clk) begin
    logic [47:0] exp_texcoord_u;
    logic [47:0] exp_texcoord_v;
    logic [THREAD_ADDR_W-1:0] exp_addr;
    logic [6:0] exp_tex_id;
    logic exp_mode_u;
    logic exp_mode_v;
    logic [2:0] exp_op;
    logic [7:0] exp_r;
    logic [7:0] exp_g;
    logic [7:0] exp_b;
    logic [7:0] exp_a;
    logic exp_comp_z;
    logic [7:0] exp_out_a;
    logic [31:0] exp_out_color;
    if (!rst_n) begin
      // no-op
    end else if (dut.output_bundle_buf_tvalid && dut.output_bundle_buf_tready) begin
      {
          exp_texcoord_u,
          exp_texcoord_v,
          exp_addr,
          exp_tex_id,
          exp_mode_u,
          exp_mode_v,
          exp_op,
          exp_r,
          exp_g,
          exp_b,
          exp_a,
          exp_comp_z
      } = dut.output_bundle_buf_tdata[FB_BUNDLE_WIDTH-1:0];

      // No-texture path maps to REPLACE in RTL, so color (including alpha) passes through.
      exp_out_a = exp_a;
      exp_out_color = {exp_out_a, exp_r, exp_g, exp_b};

      // Keep all tokens in flight, but only passing fragments should write FB.
      if (exp_comp_z) begin
        expected_fb_addr_q.push_back(exp_addr);
        expected_fb_color_q.push_back(exp_out_color);
        expected_fb_total++;
      end
    end
  end

  // Write-side checker: verify z-buffer writes are in-order and correct.
  always @(posedge clk) begin
    logic [THREAD_ADDR_W-1:0] exp_addr;
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
        if ($bitstoshortreal(z_wr_data) - $bitstoshortreal(exp_data) > 0.0001 ||
            $bitstoshortreal(exp_data) - $bitstoshortreal(z_wr_data) > 0.0001) begin
          $display("[TB][ERROR] z_wr_data mismatch: exp=0x%08h got=0x%08h", exp_data, z_wr_data);
          err_count++;
        end
      end
      wr_count++;
    end
  end

  // Read-side probe: helps debug z-compare gating issues.
  always @(posedge clk) begin
    if (!rst_n) begin
      // no-op
    end else if (z_rd_en === 1'b1) begin
      rd_count++;
      if (!rd_logged) begin
        $display("[TB][DBG] first z read: addr=%0d data=0x%08h", z_rd_addr, z_rd_data);
        rd_logged = 1'b1;
      end
    end
  end

  // Framebuffer output checker: verify full post-cache/fragment datapath outputs.
  always @(posedge clk) begin
    logic [THREAD_ADDR_W-1:0] exp_fb_addr;
    logic [31:0] exp_fb_color;
    if (!rst_n) begin
      // no-op
    end else if (out_fb_we === 1'b1) begin
      if (out_fb_valid !== 1'b1) begin
        $display("[TB][ERROR] out_fb_we asserted while out_fb_valid is not high");
        err_count++;
      end
      if (expected_fb_addr_q.size() == 0 || expected_fb_color_q.size() == 0) begin
        $display("[TB][ERROR] Unexpected framebuffer write with empty expected queue");
        err_count++;
      end else begin
        exp_fb_addr = expected_fb_addr_q.pop_front();
        exp_fb_color = expected_fb_color_q.pop_front();
        if (out_fb_addr !== exp_fb_addr) begin
          $display("[TB][ERROR] out_fb_addr mismatch: exp=%0d got=%0d", exp_fb_addr, out_fb_addr);
          err_count++;
        end
        if (out_fb_color !== exp_fb_color) begin
          $display("[TB][ERROR] out_fb_color mismatch: exp=0x%08h got=0x%08h", exp_fb_color,
                   out_fb_color);
          err_count++;
        end
      end
      fb_we_count++;
      recv_count++;
    end
  end

  // In color-only mode we expect no L1 texture requests.
  always @(posedge clk) begin
    if (!rst_n) begin
      // no-op
    end else if (dut.l1_req_valid && dut.l1_cache_req_ready) begin
      l1_req_count++;
      $display("[TB][ERROR] Unexpected L1 texture request in color-only mode");
      err_count++;
    end
  end

  // Internal flow probes.
  always @(posedge clk) begin
    if (!rst_n) begin
      // no-op
    end else begin
      if (dut.pipe_en_internal === 1'b1) pipe_en_count++;
      if (dut.valid_pipe[0] === 1'b1) v0_count++;
      if (dut.valid_pipe[36] === 1'b1) v36_count++;
    end
  end

  // DUT
  thread dut (
      .clk(clk),
      .rst_n(rst_n),
      .valid_in(valid_in),
      .ready_out(ready_out),
      .in_data(in_data),
      .out_fb_color(out_fb_color),
      .out_fb_addr(out_fb_addr),
      .out_fb_valid(out_fb_valid),
      .out_fb_we(out_fb_we),
      .z_rd_en(z_rd_en),
      .z_rd_addr(z_rd_addr),
      .z_rd_data(z_rd_data),
      .z_wr_en(z_wr_en),
      .z_wr_addr(z_wr_addr),
        .z_wr_data(z_wr_data),
        .tex_m_axi_araddr(tex_m_axi_araddr),
        .tex_m_axi_arlen(tex_m_axi_arlen),
        .tex_m_axi_arsize(tex_m_axi_arsize),
        .tex_m_axi_arburst(tex_m_axi_arburst),
        .tex_m_axi_arvalid(tex_m_axi_arvalid),
        .tex_m_axi_arready(tex_m_axi_arready),
        .tex_m_axi_rdata(tex_m_axi_rdata),
        .tex_m_axi_rresp(tex_m_axi_rresp),
        .tex_m_axi_rvalid(tex_m_axi_rvalid),
        .tex_m_axi_rready(tex_m_axi_rready),
          .tex_m_axi_rlast(tex_m_axi_rlast),
          .lut_addr_wr_en(1'b0),
          .lut_size_wr_en(1'b0),
          .lut_wr_addr('0),
          .lut_wr_data('0)
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
    in_data = '0;
    sent_count = 0;
    recv_count = 0;
    err_count = 0;
    warn_count = 0;
    expected_pass_total = 0;
    wr_count = 0;
    expected_wr_total = 0;
    rd_count = 0;
    rd_logged = 1'b0;
    gen_reject_count = 0;
    pipe_en_count = 0;
    v0_count = 0;
    v36_count = 0;
    fb_we_count = 0;
    expected_fb_total = 0;
    l1_req_count = 0;

    init_zbuffer_mem();
    begin
      int i;
      for (i = 0; i < ZBufDepth; i++) begin
        expected_z_mem[i] = ZramDefault;
      end
    end

    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

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

    $display({
      "[TB] sent=%0d recv=%0d expected_pass=%0d reads=%0d writes=%0d/%0d ",
      "fb_writes=%0d/%0d l1_req=%0d gen_reject=%0d pipe_en=%0d v0=%0d v36=%0d warns=%0d errors=%0d"
    }, sent_count, recv_count, expected_pass_total, rd_count, wr_count, expected_wr_total,
        fb_we_count, expected_fb_total, l1_req_count,
        gen_reject_count, pipe_en_count, v0_count, v36_count, warn_count, err_count);

    if (recv_count != expected_pass_total) begin
      $display("[TB][ERROR] Output count mismatch: recv=%0d expected_pass=%0d", recv_count,
               expected_pass_total);
      err_count++;
    end

    if (wr_count != expected_wr_total) begin
      $display("[TB][ERROR] Write count mismatch: got=%0d expected=%0d", wr_count,
               expected_wr_total);
      err_count++;
    end

    if (fb_we_count != expected_fb_total) begin
      $display("[TB][ERROR] FB write count mismatch: got=%0d expected=%0d", fb_we_count,
               expected_fb_total);
      err_count++;
    end

    if (expected_wr_addr_q.size() != 0 || expected_wr_data_q.size() != 0) begin
      $display(
          "[TB][ERROR] Expected write queue not fully drained: pending_addr=%0d pending_data=%0d",
          expected_wr_addr_q.size(), expected_wr_data_q.size());
      err_count++;
    end

    if (expected_fb_addr_q.size() != 0 || expected_fb_color_q.size() != 0) begin
      $display("[TB][ERROR] Expected FB queue not fully drained: pending_addr=%0d pending_color=%0d",
               expected_fb_addr_q.size(), expected_fb_color_q.size());
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
