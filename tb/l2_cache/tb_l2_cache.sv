// L2Cache on its own, on Verilator (run in WSL): four L1-like masters (one 256 B block a request,
// 16 x 128-bit beats, rready low at random) and DDR as an AXI read slave (random latency, beats
// of different IDs interleaved, handshake lines low at random). Every beat is checked against
// what DDR holds, and every DDR burst against the AXI rules:
//   - the registers: INFO, CNT_COUNT, the reset's flush sweep
//   - one block asked for by every port at once: one lookup, one DDR read
//   - a line asked for while DDR reads it: the requests join it, still one DDR read
//   - every way of a set being filled: the next line waits (set_full), its data still right
//   - random traffic: a few hot blocks (sharing, merges), then 4 MiB (evictions)
//   - flush (CTRL.FLUSH, twice): DDR changed behind the cache, every block read again
//   - a line read with an error: SLVERR to its ports, not kept, read again
//   - the counters (frozen, CNT_PENDING 0, then their registers) against the testbench's own
//     counts; CLEAR
// Plusargs: +STALL=<percent> (DDR handshakes, 30), +RSTALL=<percent> (L1 rready, 20),
// +CORE_NS=, +MEM_NS=, +AXIL_NS= (2.0, 3.333, 7.5), +LAT_MIN=, +LAT_MAX= (DDR latency, mem
// clocks: 20, 80),
// +INTERLEAVE=0|1 (DDR beats of different IDs interleaved, 1), +REQS= (random requests a port
// a phase, 1500).
// Ways, SizeKib, OnMemClock, LineBytes: the L2Cache's (L2CacheVerilog's arguments; the default's
// here).

`timescale 1ns / 1ps

module tb_l2_cache #(
    parameter int Ways = 2,
    parameter int SizeKib = 1024,
    parameter bit OnMemClock = 1'b0,
    parameter int LineBytes = 512
);

  localparam int N = 4;
  localparam int LineBeats = LineBytes / 64;
  localparam int Sets = SizeKib * 1024 / LineBytes / Ways;
  localparam int BlockBytes = 256, BlockBeats = 16;
  localparam int NextBlock = BlockBytes % LineBytes;  // a line's next block (none in 256 B: 0)

  // The register map (l2_cache_regmap.h): CYCLES (40 bits) at Counter0 and Counter0 + 4, counter
  // i > 0 (32 bits) at Counter0 + 4 + 4 * i
  localparam logic [7:0] Ctrl = 8'h00, Info = 8'h04, CntCtrl = 8'h08, CntCount = 8'h0C;
  localparam logic [7:0] Counter0 = 8'h40;
  localparam logic [31:0] Flush = 32'h1, Freeze = 32'h1, Clear = 32'h2, Pending = 32'h4;

  // The counters, in the register map's order; a port's at CPort + PerPort * p + {requests, hits,
  // misses, merges, replays}
  localparam int CCycles = 0, CLookups = 1, CHits = 2, CMisses = 3, CMerges = 4, CReplays = 5;
  localparam int CSetFull = 6, CMulticast = 7, CEvictions = 8, CDdrReads = 9, CDdrErrors = 10;
  localparam int CMshrFull = 11, CPort = 12;
  localparam int PRequests = 0, PHits = 1, PMisses = 2, PMerges = 3, PReplays = 4, PerPort = 5;
  localparam int Counters = CPort + PerPort * N;

  int stall = 30, rstall = 20, lat_min = 20, lat_max = 80, interleave = 1, reqs = 1500;
  real core_ns = 2.0, mem_ns = 3.333, axil_ns = 7.5;
  logic core_clk = 1'b0, mem_clk = 1'b0, axil_clk = 1'b0;
  logic core_resetn = 1'b0, mem_resetn = 1'b0, axil_resetn = 1'b0;
  initial begin
    void'($value$plusargs("STALL=%d", stall));
    void'($value$plusargs("RSTALL=%d", rstall));
    void'($value$plusargs("LAT_MIN=%d", lat_min));
    void'($value$plusargs("LAT_MAX=%d", lat_max));
    void'($value$plusargs("INTERLEAVE=%d", interleave));
    void'($value$plusargs("REQS=%d", reqs));
    void'($value$plusargs("CORE_NS=%f", core_ns));
    void'($value$plusargs("MEM_NS=%f", mem_ns));
    void'($value$plusargs("AXIL_NS=%f", axil_ns));
    /* verilator lint_off ZERODLY */  // set at run time, never 0
    fork
      forever #(core_ns / 2) core_clk = ~core_clk;
      forever #(mem_ns / 2) mem_clk = ~mem_clk;
      forever #(axil_ns / 2) axil_clk = ~axil_clk;
    join_none
    /* verilator lint_on ZERODLY */
  end

  longint ccycle = 0, mcycle = 0;
  always @(posedge core_clk) ccycle++;
  always @(posedge mem_clk) mcycle++;

  int errors = 0;
  task automatic fail(input string what);
    if (errors < 20) $display("[%0t] ERROR: %s", $time, what);
    errors++;
  endtask

  // What DDR holds: a word of each address, changed by gen
  int unsigned gen = 0;
  function automatic logic [31:0] word_at(input logic [31:0] a, input int unsigned g);
    return a ^ (g * 32'h9E3779B9) ^ 32'h5A5A_0000;
  endfunction

  // ---------------------------------------------------------------------------------------------
  // The DUT

  logic awvalid = 1'b0, awready, wvalid = 1'b0, wready, bvalid, bready = 1'b0;
  logic arvalid_r = 1'b0, arready_r, rvalid_r, rready_r = 1'b0;  // the register port's
  logic [7:0] awaddr = '0, araddr_r = '0;
  logic [31:0] wdata = '0, rdata_r;
  logic [1:0] bresp, rresp_r;

  logic arvalid[N], arready[N], rvalid[N], rready[N], rlast[N];
  logic [31:0] araddr[N];
  logic [127:0] rdata[N];
  logic [1:0] rresp[N];
  initial
    for (int p = 0; p < N; p++) begin
      arvalid[p] = 1'b0;
      araddr[p]  = '0;
      rready[p]  = 1'b0;
    end

  logic m_arvalid, m_arready = 1'b0, m_rvalid = 1'b0, m_rready, m_rlast = 1'b0;
  logic [31:0] m_araddr;
  logic [2:0] m_arid, m_rid = '0;  // 2 x N MSHRs
  logic [1:0] m_arburst, m_rresp = '0;
  logic [7:0] m_arlen;
  logic [2:0] m_arsize;
  logic [511:0] m_rdata = '0;

  `define L2_PORT(n) \
      .s_axi_``n``_arvalid(arvalid[n]), \
      .s_axi_``n``_arready(arready[n]), \
      .s_axi_``n``_araddr(araddr[n]), \
      .s_axi_``n``_arlen(8'd15), \
      .s_axi_``n``_arsize(3'd4), \
      .s_axi_``n``_arburst(2'b01), \
      .s_axi_``n``_rvalid(rvalid[n]), \
      .s_axi_``n``_rready(rready[n]), \
      .s_axi_``n``_rdata(rdata[n]), \
      .s_axi_``n``_rresp(rresp[n]), \
      .s_axi_``n``_rlast(rlast[n]),

  L2Cache dut (
      .s_axil_awvalid(awvalid),
      .s_axil_awready(awready),
      .s_axil_awaddr(awaddr),
      .s_axil_awprot(3'b000),
      .s_axil_wvalid(wvalid),
      .s_axil_wready(wready),
      .s_axil_wdata(wdata),
      .s_axil_wstrb(4'hF),
      .s_axil_bvalid(bvalid),
      .s_axil_bready(bready),
      .s_axil_bresp(bresp),
      .s_axil_arvalid(arvalid_r),
      .s_axil_arready(arready_r),
      .s_axil_araddr(araddr_r),
      .s_axil_arprot(3'b000),
      .s_axil_rvalid(rvalid_r),
      .s_axil_rready(rready_r),
      .s_axil_rdata(rdata_r),
      .s_axil_rresp(rresp_r),
      `L2_PORT(0)
      `L2_PORT(1)
      `L2_PORT(2)
      `L2_PORT(3)
      .m_axi_arvalid(m_arvalid),
      .m_axi_arready(m_arready),
      .m_axi_araddr(m_araddr),
      .m_axi_arid(m_arid),
      .m_axi_arlen(m_arlen),
      .m_axi_arsize(m_arsize),
      .m_axi_arburst(m_arburst),
      .m_axi_rvalid(m_rvalid),
      .m_axi_rready(m_rready),
      .m_axi_rdata(m_rdata),
      .m_axi_rid(m_rid),
      .m_axi_rresp(m_rresp),
      .m_axi_rlast(m_rlast),
      .core_clk(core_clk),
      .core_resetn(core_resetn),
      .mem_clk(mem_clk),
      .mem_resetn(mem_resetn),
      .axil_clk(axil_clk),
      .axil_resetn(axil_resetn)
  );

`ifdef TRACE
  always @(posedge core_clk) begin
    for (int p = 0; p < N; p++)
      if (arvalid[p] && arready[p]) $display("[%0d] AR port %0d %08h", ccycle, p, araddr[p]);
    if (dut.seq_state == 3'd4)
      $display("[%0d] ACT block %05h mask %b inFlight %b hit %b mshr %b%b%b%b", ccycle,
               dut.seq_block, dut.seq_mask, dut.seq_inFlight, dut.seq_hitOh, dut.mshr_3_valid,
               dut.mshr_2_valid, dut.mshr_1_valid, dut.mshr_0_valid);
    if (dut.fill_in_valid)
      $display("[%0d] FILL id %0d last %b word %08h", ccycle, dut.fill_in_payload_id,
               dut.fill_in_payload_last, dut.fill_in_payload_data[31:0]);
  end
  always @(posedge mem_clk) begin
    if (m_arvalid && m_arready) $display("[m%0d] DDR AR %08h id %0d", mcycle, m_araddr, m_arid);
    if (m_rvalid && m_rready)
      $display("[m%0d] DDR R id %0d last %b word %08h", mcycle, m_rid, m_rlast, m_rdata[31:0]);
  end
`endif

  // ---------------------------------------------------------------------------------------------
  // DDR: bursts wait their latency, then go out a beat at a time; with INTERLEAVE, any ready
  // burst's next beat

  logic [31:0] q_addr[$];
  int q_id[$], q_beat[$];
  longint q_ready[$];
  int cur = -1;
  longint ddr_reads = 0, ddr_beats = 0, ddr_err_beats = 0;
  logic [31:0] err_line = '1;  // a line DDR answers with SLVERR (none)
  int line_reads[int unsigned];  // DDR reads of each line

  function automatic logic [511:0] beat_data(input logic [31:0] line, input int beat);
    logic [511:0] d;
    for (int i = 0; i < 16; i++) d[32*i+:32] = word_at(line + 32'(64 * beat + 4 * i), gen);
    return d;
  endfunction

  always @(posedge mem_clk) begin
    if (mem_resetn && m_arvalid && m_arready) begin
      if (m_arlen != 8'(LineBeats - 1) || m_arsize != 3'd6 || m_arburst != 2'b01)
        fail($sformatf("DDR AR: len %0d size %0d burst %0d", m_arlen, m_arsize, m_arburst));
      if (m_araddr % LineBytes != 0 || m_araddr >= 32'h0800_0000)
        fail($sformatf("DDR AR: address %08h", m_araddr));
      foreach (q_id[i])
        if (q_id[i] == int'(m_arid)) fail($sformatf("DDR AR: ID %0d already in flight", m_arid));
      q_addr.push_back(m_araddr);
      q_id.push_back(int'(m_arid));
      q_beat.push_back(0);
      q_ready.push_back(mcycle + longint'($urandom_range(lat_max, lat_min)));
      ddr_reads++;
      if (line_reads.exists(m_araddr)) line_reads[m_araddr]++;
      else line_reads[m_araddr] = 1;
    end
    m_arready <= mem_resetn && ($urandom_range(99) >= stall);

    if (m_rvalid && m_rready) begin
      ddr_beats++;
      if (m_rresp != 2'b00) ddr_err_beats++;
      q_beat[cur]++;
      if (q_beat[cur] == LineBeats) begin
        q_addr.delete(cur);
        q_id.delete(cur);
        q_beat.delete(cur);
        q_ready.delete(cur);
      end
      cur = -1;
    end
    if (!(m_rvalid && !m_rready)) begin  // free to present another beat
      automatic int pick = -1, ready_n = 0;
      if (cur >= 0) pick = cur;
      else begin
        if (!interleave)
          foreach (q_beat[i])
            if (q_beat[i] > 0) pick = i;  // the burst under way finishes first
        if (pick < 0) begin
          foreach (q_ready[i]) if (q_ready[i] <= mcycle) ready_n++;
          if (ready_n > 0) begin
            automatic int nth = interleave ? int'($urandom_range(ready_n - 1)) : 0;
            foreach (q_ready[i])
              if (q_ready[i] <= mcycle) begin
                if (nth == 0 && pick < 0) pick = i;
                nth--;
              end
          end
        end
      end
      if (pick >= 0 && $urandom_range(99) >= stall) begin
        cur = pick;
        m_rvalid <= 1'b1;
        m_rid <= 3'(q_id[pick]);
        m_rdata <= beat_data(q_addr[pick], q_beat[pick]);
        m_rresp <= q_addr[pick] == err_line ? 2'b10 : 2'b00;
        m_rlast <= q_beat[pick] == LineBeats - 1;
      end else begin
        cur = -1;
        m_rvalid <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------------------------------------------------
  // The L1s: a request, its 16 beats checked

  longint tb_requests[N], worst_latency = 0;
  initial for (int p = 0; p < N; p++) tb_requests[p] = 0;

  task automatic request(input int p, input logic [31:0] addr, input logic [1:0] resp = 2'b00);
    longint t0;
    @(posedge core_clk);
    arvalid[p] <= 1'b1;
    araddr[p]  <= addr;
    do @(posedge core_clk); while (!arready[p]);
    arvalid[p] <= 1'b0;
    t0 = ccycle;
    for (int b = 0; b < BlockBeats;) begin
      rready[p] <= $urandom_range(99) >= rstall;
      @(posedge core_clk);
      if (ccycle - t0 > 20000) begin
        fail($sformatf("port %0d: block %08h, no data after 20000 clocks", p, addr));
        break;
      end
      if (rvalid[p] && rready[p]) begin
        if (b == 0 && ccycle - t0 > worst_latency) worst_latency = ccycle - t0;
        for (int i = 0; i < 4; i++)
          if (rdata[p][32*i+:32] !== word_at(addr + 32'(16 * b + 4 * i), gen))
            fail($sformatf("port %0d: block %08h beat %0d word %0d: %08h, expected %08h", p,
                           addr, b, i, rdata[p][32*i+:32],
                           word_at(addr + 32'(16 * b + 4 * i), gen)));
        if (rlast[p] !== (b == BlockBeats - 1))
          fail($sformatf("port %0d: block %08h beat %0d: RLAST %b", p, addr, b, rlast[p]));
        if (rresp[p] !== resp)
          fail($sformatf("port %0d: RRESP %b, expected %b", p, rresp[p], resp));
        b++;
      end
    end
    rready[p] <= 1'b0;
    tb_requests[p]++;
  endtask

  // Random requests from every port: blocks below footprint, or one of hot blocks from base
  task automatic traffic(input int n, input logic [31:0] base, input int hot, input int footprint);
    for (int p = 0; p < N; p++)
      fork
        automatic int pp = p;
        for (int i = 0; i < n; i++) begin
          logic [31:0] a;
          if (hot > 0) a = base + 32'(BlockBytes * $urandom_range(hot - 1));
          else a = base + 32'(BlockBytes * $urandom_range(footprint / BlockBytes - 1));
          request(pp, a);
          repeat ($urandom_range(8)) @(posedge core_clk);
        end
      join_none
    wait fork;
  endtask

  // ---------------------------------------------------------------------------------------------
  // The register port (AXI-Lite) and the counters

  task automatic reg_write(input logic [7:0] addr, input logic [31:0] data);
    @(posedge axil_clk);
    awvalid <= 1'b1;
    awaddr  <= addr;
    wvalid  <= 1'b1;
    wdata   <= data;
    fork
      begin
        do @(posedge axil_clk); while (!awready);
        awvalid <= 1'b0;
      end
      begin
        do @(posedge axil_clk); while (!wready);
        wvalid <= 1'b0;
      end
    join
    bready <= 1'b1;
    do @(posedge axil_clk); while (!bvalid);
    if (bresp !== 2'b00) fail($sformatf("BRESP %b at %03h", bresp, addr));
    bready <= 1'b0;
  endtask

  task automatic reg_read(input logic [7:0] addr, output logic [31:0] data);
    @(posedge axil_clk);
    arvalid_r <= 1'b1;
    araddr_r  <= addr;
    do @(posedge axil_clk); while (!arready_r);
    arvalid_r <= 1'b0;
    rready_r  <= 1'b1;
    do @(posedge axil_clk); while (!rvalid_r);
    if (rresp_r !== 2'b00) fail($sformatf("RRESP %b at %03h", rresp_r, addr));
    data = rdata_r;
    rready_r <= 1'b0;
  endtask

  task automatic expect_read(input logic [7:0] addr, input logic [31:0] value, input string what);
    logic [31:0] data;
    reg_read(addr, data);
    if (data !== value) fail($sformatf("%s: %08h, expected %08h", what, data, value));
  endtask

  task automatic wait_clear(input logic [7:0] addr, input logic [31:0] mask, input string what);
    logic [31:0] data;
    for (int i = 0; i < 1000; i++) begin
      reg_read(addr, data);
      if ((data & mask) == 0) return;
    end
    fail($sformatf("%s never done", what));
  endtask

  // Every counter, once their carries are in the RAM
  longint cnt[Counters];
  task automatic read_counters();
    logic [31:0] lo, hi;
    wait_clear(CntCtrl, Pending, "CNT_PENDING");
    reg_read(Counter0, lo);
    reg_read(Counter0 + 8'd4, hi);
    cnt[CCycles] = {24'h0, hi[7:0], lo};
    for (int i = 1; i < Counters; i++) begin
      reg_read(Counter0 + 8'(4 + 4 * i), lo);
      cnt[i] = {32'h0, lo};
    end
  endtask

  // What the cycles counter should hold: the cache's clocks neither clearing nor frozen; as of the
  // last snapshot
  longint counted = 0, counted_at_read;
  logic cache_clk;
  assign cache_clk = OnMemClock ? mem_clk : core_clk;
  always @(posedge cache_clk)
    if (dut.perf_clearing) counted <= 0;
    else if (!dut.CNT_FREEZE) counted <= counted + 1;

  // Counters frozen, read; then counting again
  task automatic snapshot();
    // A port is done with its block while the rest of its line may still be coming, and frozen
    // counters miss it: DDR idle and the crossing empty first
    wait (q_addr.size() == 0);
    repeat (64) @(posedge core_clk);
    reg_write(CntCtrl, Freeze);
    read_counters();
    counted_at_read = counted;
    reg_write(CntCtrl, 0);
  endtask

  // ---------------------------------------------------------------------------------------------
  // The tests

  task automatic test_registers();
    expect_read(Info, (SizeKib << 16) | (N << 8) | ($clog2(LineBytes) << 4) | Ways, "INFO");
    expect_read(CntCount, Counters, "CNT_COUNT");
    wait_clear(Ctrl, Flush, "reset sweep");
    wait_clear(CntCtrl, Clear, "reset counter clear");
  endtask

  // Every port asks for one block at the same clock
  task automatic test_same_block();
    longint prev[Counters];
    logic [31:0] a = 32'h0010_0000;
    snapshot();
    prev = cnt;
    for (int p = 0; p < N; p++)
      fork
        automatic int pp = p;
        request(pp, a);
      join_none
    wait fork;
    snapshot();
    if (line_reads[a] != 1) fail($sformatf("same block: %0d DDR reads", line_reads[a]));
    if (cnt[CLookups] - prev[CLookups] != 1)
      fail($sformatf("same block: %0d lookups", cnt[CLookups] - prev[CLookups]));
    if (cnt[CMulticast] - prev[CMulticast] != N - 1)
      fail($sformatf("same block: multicast %0d", cnt[CMulticast] - prev[CMulticast]));
  endtask

  // A line asked for while DDR reads it: both its blocks, by the other ports, one after another
  task automatic test_join_in_flight();
    longint prev[Counters];
    logic [31:0] a = 32'h0020_0000;
    int lmin = lat_min, lmax = lat_max;
    lat_min = 400;
    lat_max = 400;
    snapshot();
    prev = cnt;
    fork
      request(0, a);
      begin
        repeat (40) @(posedge core_clk);
        request(1, a);
      end
      begin
        repeat (60) @(posedge core_clk);
        request(2, a + NextBlock);
      end
      begin
        repeat (80) @(posedge core_clk);
        request(3, a);
      end
    join
    lat_min = lmin;
    lat_max = lmax;
    snapshot();
    if (line_reads[a] != 1) fail($sformatf("join: %0d DDR reads", line_reads[a]));
    if (cnt[CMerges] - prev[CMerges] != N - 1)
      fail($sformatf("join: %0d merges", cnt[CMerges] - prev[CMerges]));
  endtask

  // Ways + 1 lines of one set at once, DDR slow: the last waits for a way (a port each: not with
  // N ways or more)
  task automatic test_set_full();
    longint prev[Counters];
    logic [31:0] a = 32'h0000_3000;  // set 24, then a set's stride on
    int lmin = lat_min, lmax = lat_max;
    if (Ways >= N) begin
      $display("set full: not tested, %0d ways and %0d ports", Ways, N);
      return;
    end
    lat_min = 300;
    lat_max = 300;
    snapshot();
    prev = cnt;
    for (int p = 0; p <= Ways; p++)
      fork
        automatic int pp = p;
        automatic logic [31:0] aa = a + 32'(pp * Sets * LineBytes);
        begin
          repeat (pp * 10) @(posedge core_clk);
          request(pp, aa);
        end
      join_none
    wait fork;
    lat_min = lmin;
    lat_max = lmax;
    snapshot();
    if (cnt[CSetFull] == prev[CSetFull]) fail("set full: never counted");
  endtask

  // DDR changed: after a flush every block comes from DDR again
  task automatic test_flush();
    longint reads;
    for (int i = 0; i < 16; i++) request(i % N, 32'h0030_0000 + 32'(i * BlockBytes));
    reads = ddr_reads;
    for (int i = 0; i < 16; i++) request(i % N, 32'h0030_0000 + 32'(i * BlockBytes));
    if (ddr_reads != reads) fail("flush: cached blocks read from DDR");
    gen++;
    reg_write(Ctrl, Flush);
    wait_clear(Ctrl, Flush, "flush");
    reads = ddr_reads;
    for (int i = 0; i < 16; i++) request(i % N, 32'h0030_0000 + 32'(i * BlockBytes));
    if (ddr_reads - reads != 16 * BlockBytes / LineBytes)
      fail($sformatf("flush: %0d DDR reads, expected %0d", ddr_reads - reads,
                     16 * BlockBytes / LineBytes));
  endtask

  // A line read with an error: SLVERR to its ports, its other block too (read again: the line
  // is not kept); without the error, read once more and then kept
  task automatic test_error();
    longint reads = ddr_reads;
    logic [31:0] a = 32'h0050_0000;
    err_line = a;
    request(0, a, 2'b10);
    request(1, a + NextBlock, 2'b10);
    err_line = '1;
    request(2, a);
    request(3, a);
    if (ddr_reads - reads != 3)
      fail($sformatf("error: %0d DDR reads, expected 3", ddr_reads - reads));
  endtask

  // Every counter against the testbench's own counts, then CLEAR
  task automatic test_counters();
    longint lookups, ends;
    snapshot();
    lookups = cnt[CHits] + cnt[CMisses] + cnt[CMerges] + cnt[CReplays];
    if (cnt[CLookups] != lookups)
      fail($sformatf("lookups %0d != hits + misses + merges + replays %0d", cnt[CLookups],
                     lookups));
    if (cnt[CDdrReads] != ddr_reads)
      fail($sformatf("ddr_reads %0d, DDR saw %0d", cnt[CDdrReads], ddr_reads));
    if (cnt[CMisses] != ddr_reads)
      fail($sformatf("misses %0d, DDR reads %0d", cnt[CMisses], ddr_reads));
    if (cnt[CDdrErrors] != ddr_err_beats)
      fail($sformatf("ddr_errors %0d, DDR sent %0d", cnt[CDdrErrors], ddr_err_beats));
    if (cnt[CCycles] != counted_at_read)
      fail($sformatf("cycles %0d, testbench %0d", cnt[CCycles], counted_at_read));
    for (int p = 0; p < N; p++) begin
      int c = CPort + PerPort * p;
      if (cnt[c+PRequests] != tb_requests[p])
        fail($sformatf("port %0d requests %0d, expected %0d", p, cnt[c+PRequests], tb_requests[p]));
      ends = cnt[c+PHits] + cnt[c+PMisses] + cnt[c+PMerges];
      if (ends != tb_requests[p])
        fail($sformatf("port %0d hits + misses + merges %0d, requests %0d", p, ends,
                       tb_requests[p]));
    end
    $display("lookups %0d: hits %0d, misses %0d, merges %0d, replays %0d (set full %0d, MSHRs %0d)",
             cnt[CLookups], cnt[CHits], cnt[CMisses], cnt[CMerges], cnt[CReplays], cnt[CSetFull],
             cnt[CMshrFull]);
    $display("multicast %0d", cnt[CMulticast]);
    $display("evictions %0d, DDR reads %0d, cycles %0d", cnt[CEvictions], cnt[CDdrReads],
             cnt[CCycles]);

    reg_write(CntCtrl, Freeze | Clear);
    wait_clear(CntCtrl, Clear, "CLEAR");
    read_counters();
    foreach (cnt[i]) if (cnt[i] != 0) fail($sformatf("counter %0d %0d after CLEAR", i, cnt[i]));
    reg_write(CntCtrl, 0);
  endtask

  initial begin
    repeat (10) @(posedge core_clk);
    core_resetn = 1'b1;
    mem_resetn  = 1'b1;
    axil_resetn = 1'b1;
    $display("STALL %0d%%, RSTALL %0d%%, latency %0d..%0d, interleave %0d", stall, rstall, lat_min,
             lat_max, interleave);
    $display("clocks (ns): core %0.3f, mem %0.3f, axil %0.3f", core_ns, mem_ns, axil_ns);
    test_registers();
    reg_write(CntCtrl, Clear);
    wait_clear(CntCtrl, Clear, "CLEAR");
    test_same_block();
    test_join_in_flight();
    test_set_full();
    traffic(reqs, 32'h0040_0000, 64, 0);  // hot blocks
    traffic(reqs, 32'h0100_0000, 0, 4 << 20);  // 4 MiB
    test_flush();
    test_flush();
    test_error();
    test_counters();
    $display("%0d requests, %0d DDR reads, worst latency %0d clocks",
             tb_requests[0] + tb_requests[1] + tb_requests[2] + tb_requests[3], ddr_reads,
             worst_latency);
    if (errors != 0) $fatal(1, "FAIL: %0d errors", errors);
    $display("PASS");
    $finish;
  end

  initial begin
    #200ms;
    $fatal(1, "testbench timeout");
  end

endmodule
