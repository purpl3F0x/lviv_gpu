// AxiTileDma on its own, on Verilator (run in WSL): its tile RAMs four frame_buffer_ram as
// raster_core has them, DRAM an AXI write slave whose handshake lines go low at random. Every
// pixel written is checked against where it belongs, nothing else may be written, every burst
// against the AXI rules and the 4 KiB one:
//   - the registers: reset values, field widths, BASE_LOW's reserved bits
//   - the interrupts: INT_MASK, INT_STATUS, INT_FORCE, the lines
//   - a frame by auto-advance at a high base: CUR_POS stepping, frame_done, the wrap to (0, 0)
//   - tiles out of order (CUR_POS written), the frame's last among them; STRIDE's low bits ignored
//   - the origin's extremes: CUR_POS up to (254, 254), a stride of 255 tile lines, to the top of
//     4 GiB (past it with wider addresses)
//   - TILES_X and TILES_Y 0, taken as 1
//   - BASE, STRIDE, TILES and CLEAR_VALUE written during a transfer: the tile as of START
//   - CLEAR_VALUE left behind by a write-back; CLEAR, ignored while BUSY, START ignored during it
//   - SOFT_RESET: at once when idle, deferred while BUSY
//   - error responses: INT_RAW's error, LAST_BRESP, the tile still all written
// Plusargs: +STALL=<percent>, the chance of a DRAM handshake line low on a cycle (30); +ACLK_NS=,
// +RAM_NS=, the clocks' periods.

`timescale 1ns / 1ps

module tb_axi_tile_dma;

  localparam int Lanes = 4;  // the quad's threads, a tile RAM each: (y & 1) * 2 + (x & 1)
  localparam int TileSize = 128;
  localparam int TileWords = TileSize * TileSize;  // a tile's pixels, 32-bit words in DRAM
  localparam int RamWords = TileWords / Lanes;  // a tile RAM's pixels, its port 0 words
  localparam int RamReadLatency = 4;  // frame_buffer_ram's
  localparam int BurstBeats = 32;  // a tile line, 512 bytes
  localparam int BurstsPerTile = TileSize;
  localparam int AddrW = 32;  // AxiTileDmaVerilog's addressWidth

  // The register map (axi_tile_dma_regmap.h)
  localparam logic [6:0] Ctrl = 7'h00, Status = 7'h04, BaseLow = 7'h08, BaseHigh = 7'h0C;
  localparam logic [6:0] Stride = 7'h10, TilesX = 7'h14, TilesY = 7'h18, CurPos = 7'h1C;
  localparam logic [6:0] Line = 7'h20, Perf = 7'h24, ClearValue = 7'h28;
  localparam logic [6:0] IntRaw = 7'h40, IntForce = 7'h44, IntMask = 7'h48, IntStatus = 7'h4C;
  localparam logic [31:0] Start = 32'h1, ResetPos = 32'h2, SoftReset = 32'h4, Clear = 32'h8;
  localparam logic [31:0] Busy = 32'h1, LastBresp = 32'h6, SoftResetPending = 32'h8;
  localparam logic [31:0] ClearBusy = 32'h10;
  localparam logic [31:0] Done = 32'h1, Error = 32'h2, FrameDone = 32'h4;
  localparam logic [1:0] Okay = 2'b00, SlvErr = 2'b10, DecErr = 2'b11;
  // BASE_HIGH's bits: the address's above 32; none, the register reserved, with 32-bit addresses
  localparam logic [31:0] BaseHighBits = 32'((64'd1 << (AddrW > 32 ? AddrW - 32 : 0)) - 1);

  // aclk (DRAM's side) and ram_clk (the tile RAMs') at 300 MHz as on the board, ram_clk a hair
  // faster so that their phases drift as two separate clocks' do
  int stall = 30;
  real aclk_ns = 3.334, ram_ns = 3.332;
  logic aclk = 1'b0, ram_clk = 1'b0, aresetn = 1'b0, ram_resetn = 1'b0;
  initial begin
    void'($value$plusargs("STALL=%d", stall));
    void'($value$plusargs("ACLK_NS=%f", aclk_ns));
    void'($value$plusargs("RAM_NS=%f", ram_ns));
    /* verilator lint_off ZERODLY */  // set at run time, never 0
    fork
      forever #(aclk_ns / 2) aclk = ~aclk;
      forever #(ram_ns / 2) ram_clk = ~ram_clk;
    join_none
    /* verilator lint_on ZERODLY */
  end

  longint cycle = 0;  // aclk's
  always @(posedge aclk) cycle++;

  int errors = 0;
  task automatic fail(input string what);
    if (errors < 20) $display("[%0t] ERROR: %s", $time, what);
    errors++;
  endtask

  // ---------------------------------------------------------------------------------------------
  // The DUT

  logic [6:0] paddr = '0;
  logic psel = 1'b0, penable = 1'b0, pwrite = 1'b0;
  logic [31:0] pwdata = '0, prdata;
  logic pready, pslverror;
  logic awvalid, awready = 1'b0, wvalid, wready = 1'b0, wlast, bvalid = 1'b0, bready;
  logic [AddrW-1:0] awaddr;
  logic [3:0] awid, awregion, awcache, awqos;
  logic [7:0] awlen;
  logic [2:0] awsize, awprot;
  logic [1:0] awburst, bresp = 2'b00;
  logic awlock;
  logic [127:0] wdata;
  logic [15:0] wstrb;
  logic [Lanes-1:0] ram_en, ram_wr_en;
  logic [13:0] ram_addr[Lanes], ram_wr_addr[Lanes];
  logic [63:0] ram_dout[Lanes], ram_wr_data[Lanes];
  logic irq, irq_done, irq_error, irq_frame_done;

  AxiTileDma dut (
      .s_apb_PADDR(paddr),
      .s_apb_PSEL(psel),
      .s_apb_PENABLE(penable),
      .s_apb_PREADY(pready),
      .s_apb_PWRITE(pwrite),
      .s_apb_PWDATA(pwdata),
      .s_apb_PRDATA(prdata),
      .s_apb_PSLVERROR(pslverror),
      .m_axi_awvalid(awvalid),
      .m_axi_awready(awready),
      .m_axi_awaddr(awaddr),
      .m_axi_awid(awid),
      .m_axi_awregion(awregion),
      .m_axi_awlen(awlen),
      .m_axi_awsize(awsize),
      .m_axi_awburst(awburst),
      .m_axi_awlock(awlock),
      .m_axi_awcache(awcache),
      .m_axi_awqos(awqos),
      .m_axi_awprot(awprot),
      .m_axi_wvalid(wvalid),
      .m_axi_wready(wready),
      .m_axi_wdata(wdata),
      .m_axi_wstrb(wstrb),
      .m_axi_wlast(wlast),
      .m_axi_bvalid(bvalid),
      .m_axi_bready(bready),
      .m_axi_bid(4'h0),
      .m_axi_bresp(bresp),
      .tile_ram_0_clk(),
      .tile_ram_0_rst(),
      .tile_ram_0_en(ram_en[0]),
      .tile_ram_0_addr(ram_addr[0]),
      .tile_ram_0_dout(ram_dout[0]),
      .tile_ram_0_wr_en(ram_wr_en[0]),
      .tile_ram_0_wr_addr(ram_wr_addr[0]),
      .tile_ram_0_wr_data(ram_wr_data[0]),
      .tile_ram_1_clk(),
      .tile_ram_1_rst(),
      .tile_ram_1_en(ram_en[1]),
      .tile_ram_1_addr(ram_addr[1]),
      .tile_ram_1_dout(ram_dout[1]),
      .tile_ram_1_wr_en(ram_wr_en[1]),
      .tile_ram_1_wr_addr(ram_wr_addr[1]),
      .tile_ram_1_wr_data(ram_wr_data[1]),
      .tile_ram_2_clk(),
      .tile_ram_2_rst(),
      .tile_ram_2_en(ram_en[2]),
      .tile_ram_2_addr(ram_addr[2]),
      .tile_ram_2_dout(ram_dout[2]),
      .tile_ram_2_wr_en(ram_wr_en[2]),
      .tile_ram_2_wr_addr(ram_wr_addr[2]),
      .tile_ram_2_wr_data(ram_wr_data[2]),
      .tile_ram_3_clk(),
      .tile_ram_3_rst(),
      .tile_ram_3_en(ram_en[3]),
      .tile_ram_3_addr(ram_addr[3]),
      .tile_ram_3_dout(ram_dout[3]),
      .tile_ram_3_wr_en(ram_wr_en[3]),
      .tile_ram_3_wr_addr(ram_wr_addr[3]),
      .tile_ram_3_wr_data(ram_wr_data[3]),
      .irq(irq),
      .irq_done(irq_done),
      .irq_error(irq_error),
      .irq_frame_done(irq_frame_done),
      .ram_clk(ram_clk),
      .ram_resetn(ram_resetn),
      .aclk(aclk),
      .aresetn(aresetn)
  );

  // ---------------------------------------------------------------------------------------------
  // The tile RAMs as raster_core has them: the DMA on port 1, the testbench on port 0 (the
  // thread's), filling and reading them while the DMA is idle

  logic [Lanes-1:0] fill_en = '0, peek_en = '0;
  logic [11:0] fill_addr[Lanes], peek_addr[Lanes];
  logic [31:0] fill_data[Lanes], peek_data[Lanes];

  for (genvar l = 0; l < Lanes; l++) begin : g_ram
    frame_buffer_ram #(
        .ADDR_WIDTH(12)
    ) u_ram (
        .clk(ram_clk),
        .rst_n(ram_resetn),
        .w0_en(fill_en[l]),
        .w0_addr(fill_addr[l]),
        .w0_din(fill_data[l]),
        .w1_en(ram_wr_en[l]),
        .w1_addr(ram_wr_addr[l][13:3]),
        .w1_din(ram_wr_data[l]),
        .r0_en(peek_en[l]),
        .r0_addr(peek_addr[l]),
        .r0_dout(peek_data[l]),
        .r1_en(ram_en[l]),
        .r1_addr(ram_addr[l][13:3]),
        .r1_dout(ram_dout[l])
    );
  end

  always @(posedge ram_clk)
    if ((fill_en | peek_en) != 0 && (ram_en | ram_wr_en) != 0)
      fail("the DMA at its tile RAMs while idle");

  // Tile (tx, ty)'s pixels, each its coordinates
  function automatic logic [31:0] pattern(input int tx, input int ty, input int x, input int y);
    return {8'(tx), 8'(ty), 8'(y), 8'(x)};
  endfunction

  // Port 0 word a of RAM l: the thread's pixel of quad (a % 64, a / 64)
  task automatic fill_tile(input int tx, input int ty);
    for (int a = 0; a < RamWords; a++) begin
      for (int l = 0; l < Lanes; l++) begin
        fill_en[l]   <= 1'b1;
        fill_addr[l] <= 12'(a);
        fill_data[l] <= pattern(tx, ty, a % 64 * 2 + (l & 1), a / 64 * 2 + (l >> 1));
      end
      @(posedge ram_clk);
    end
    fill_en <= '0;
    repeat (2) @(posedge ram_clk);  // the last writes in
  endtask

  // The tile RAMs' pixels other than value
  task automatic count_rams_not(input logic [31:0] value, output int bad);
    bad = 0;
    for (int a = 0; a < RamWords + RamReadLatency; a++) begin
      for (int l = 0; l < Lanes; l++) begin
        peek_en[l]   <= a < RamWords;
        peek_addr[l] <= 12'(a);
      end
      @(posedge ram_clk);
      if (a >= RamReadLatency) for (int l = 0; l < Lanes; l++) if (peek_data[l] !== value) bad++;
    end
  endtask

  // ---------------------------------------------------------------------------------------------
  // DRAM, by 32-bit word address: an AXI write slave, W taken only for bursts whose AW is in

  logic [31:0] dram[logic [AddrW-3:0]];
  logic [AddrW-1:0] burst_at[$];  // bursts whose AW is in, waiting for their data
  logic [1:0] responses[$];  // bursts whose data is in, waiting for their B
  int beat = 0;  // of the burst at burst_at[0]
  int aw_count = 0, w_count = 0;  // bursts in: their AW, all their data
  int error_burst = -1;  // a burst, by w_count, answered with error_resp
  logic [1:0] error_resp = Okay;

  always @(posedge aclk)
    if (!aresetn) begin
      awready <= 1'b0;
      wready  <= 1'b0;
      bvalid  <= 1'b0;
    end else begin
      if (awvalid && awready) begin
        if (awlen != 8'(BurstBeats - 1) || awsize != 3'd4 || awburst != 2'b01)
          fail($sformatf("burst at %h: len %0d, size %0d, type %0d", awaddr, awlen, awsize,
                         awburst));
        if ({awid, awregion, awlock, awcache, awqos, awprot} != {4'h0, 4'h0, 1'b0, 4'b0011, 7'h0})
          fail($sformatf("burst at %h: id %0d region %0d lock %0d cache %0d qos %0d prot %0d",
                         awaddr, awid, awregion, awlock, awcache, awqos, awprot));
        if (int'(awaddr[11:0]) % 16 != 0 || int'(awaddr[11:0]) + BurstBeats * 16 > 4096)
          fail($sformatf("burst at %h unaligned or across 4 KiB", awaddr));
        burst_at.push_back(awaddr);
        aw_count++;
      end
      if (wvalid && wready) begin
        if (wstrb != 16'hFFFF) fail("a W beat with strobes off");
        if (wlast != (beat == BurstBeats - 1))
          fail($sformatf("WLAST %0d on beat %0d", wlast, beat));
        for (int w = 0; w < 4; w++)
          dram[(AddrW-2)'(burst_at[0] >> 2)+(AddrW-2)'(beat*4+w)] = wdata[32*w+:32];
        if (beat == BurstBeats - 1) begin
          void'(burst_at.pop_front());
          responses.push_back(w_count == error_burst ? error_resp : Okay);
          w_count++;
          beat = 0;
        end else beat++;
      end
      if (bvalid && bready) void'(responses.pop_front());
      if (!bvalid || bready) begin
        bvalid <= responses.size() > 0 && $urandom_range(99) >= stall;
        bresp  <= responses.size() > 0 ? responses[0] : Okay;
      end
      awready <= $urandom_range(99) >= stall;
      wready  <= burst_at.size() > 0 && $urandom_range(99) >= stall;
    end

  // A valid line, once up, stays up with its payload until its handshake
  logic aw_waiting = 1'b0, w_waiting = 1'b0;
  logic [AddrW-1:0] aw_held;
  logic [128:0] w_held;
  always @(posedge aclk) begin
    if (aw_waiting && (!awvalid || awaddr != aw_held))
      fail("AW dropped or changed before AWREADY");
    if (w_waiting && (!wvalid || {wlast, wdata} != w_held))
      fail("W dropped or changed before WREADY");
    aw_waiting <= aresetn && awvalid && !awready;
    w_waiting <= aresetn && wvalid && !wready;
    aw_held <= awaddr;
    w_held <= {wlast, wdata};
  end

  // ---------------------------------------------------------------------------------------------
  // APB, the DMA's commands, the checks

  task automatic apb(input logic write, input logic [6:0] addr, input logic [31:0] data,
                     output logic [31:0] read);
    @(posedge aclk);
    psel   <= 1'b1;
    pwrite <= write;
    paddr  <= addr;
    pwdata <= data;
    @(posedge aclk);
    penable <= 1'b1;
    do @(posedge aclk); while (!pready);
    if (pslverror) fail($sformatf("PSLVERROR at %02h", addr));
    read = prdata;
    psel <= 1'b0;
    penable <= 1'b0;
  endtask

  task automatic apb_write(input logic [6:0] addr, input logic [31:0] data);
    logic [31:0] unused;
    apb(1'b1, addr, data, unused);
  endtask

  task automatic apb_read(input logic [6:0] addr, output logic [31:0] data);
    apb(1'b0, addr, 32'h0, data);
  endtask

  task automatic expect_read(input logic [6:0] addr, input logic [31:0] value, input string what);
    logic [31:0] data;
    apb_read(addr, data);
    if (data !== value) fail($sformatf("%s: %08h, expected %08h", what, data, value));
  endtask

  task automatic expect_status(input logic [31:0] mask, input logic [31:0] value,
                               input string what);
    logic [31:0] status;
    apb_read(Status, status);
    if ((status & mask) != value) fail($sformatf("%s: STATUS %08h", what, status));
  endtask

  // The frame: base, stride, tiles; CUR_POS at (0, 0); DRAM empty
  task automatic set_frame(input logic [AddrW-1:0] base, input logic [31:0] stride,
                           input int tiles_x, input int tiles_y);
    apb_write(BaseLow, base[31:0]);
    apb_write(BaseHigh, 32'(64'(base) >> 32));
    apb_write(Stride, stride);
    apb_write(TilesX, tiles_x);
    apb_write(TilesY, tiles_y);
    apb_write(Ctrl, ResetPos);
    dram.delete();
  endtask

  // START for the tile at CUR_POS, events from before cleared
  task automatic start();
    apb_write(IntRaw, Done | Error | FrameDone);
    apb_write(Ctrl, Start);
  endtask

  // Until done; INT_RAW then
  task automatic wait_done(output logic [31:0] raw);
    int polls = 0;
    do begin
      apb_read(IntRaw, raw);
      if (++polls > 100000) $fatal(1, "tile DMA: no done");
    end while ((raw & Done) == 0);
  endtask

  int tiles = 0;
  logic [31:0] perf_min = '1, perf_max = '0;

  // The tile at CUR_POS (tx, ty) filled, written back and checked: its bursts, INT_RAW and the
  // lines (frame_done if the frame's last, error if the slave answered one of its bursts so),
  // PERF, LINE, CUR_POS moved on to (next_x, next_y)
  task automatic tile(input int tx, input int ty, input bit last, input int next_x,
                      input int next_y, input string what);
    logic [31:0] raw, expected, perf;
    int aw0 = aw_count, w0 = w_count;
    longint cycle0;
    fill_tile(tx, ty);
    cycle0 = cycle;
    start();
    wait_done(raw);
    expected = Done | (last ? FrameDone : 0) |
        (error_burst >= w0 && error_burst < w0 + BurstsPerTile && error_resp != Okay ? Error : 0);
    if (raw != expected)
      fail($sformatf("%s: tile (%0d, %0d): INT_RAW %08h, expected %08h", what, tx, ty, raw,
                     expected));
    if ({irq_frame_done, irq_error, irq_done} != raw[2:0] || irq != (raw != 0))
      fail($sformatf("%s: tile (%0d, %0d): irq %0d, done %0d, error %0d, frame_done %0d", what,
                     tx, ty, irq, irq_done, irq_error, irq_frame_done));
    if (aw_count - aw0 != BurstsPerTile || w_count - w0 != BurstsPerTile || responses.size() != 0)
      fail($sformatf("%s: tile (%0d, %0d): %0d bursts, %0d with their data, %0d unanswered", what,
                     tx, ty, aw_count - aw0, w_count - w0, responses.size()));
    expect_read(CurPos, {8'h0, 8'(next_y), 8'h0, 8'(next_x)},
                $sformatf("%s: CUR_POS after tile (%0d, %0d)", what, tx, ty));
    expect_read(Line, TileSize - 1, $sformatf("%s: LINE after tile (%0d, %0d)", what, tx, ty));
    apb_read(Perf, perf);
    if (perf < TileWords / 4 || longint'(perf) > cycle - cycle0)
      fail($sformatf("%s: tile (%0d, %0d): PERF %0d cycles", what, tx, ty, perf));
    perf_min = perf < perf_min ? perf : perf_min;
    perf_max = perf > perf_max ? perf : perf_max;
    tiles++;
  endtask

  // Tile (tx, ty) in DRAM: its pattern, or clear in every pixel
  task automatic check_tile(input logic [AddrW-1:0] base, input logic [31:0] stride, input int tx,
                            input int ty, input bit cleared, input logic [31:0] clear,
                            input string what);
    int bad = 0;
    for (int y = 0; y < TileSize; y++)
      for (int x = 0; x < TileSize; x++) begin
        logic [AddrW-1:0] at;
        logic [31:0] expected;
        at = base + AddrW'(ty * TileSize + y) * AddrW'(stride) + AddrW'((tx * TileSize + x) * 4);
        expected = cleared ? clear : pattern(tx, ty, x, y);
        if (!dram.exists(at[AddrW-1:2]) || dram[at[AddrW-1:2]] !== expected) begin
          if (bad < 4)
            fail($sformatf("%s: tile (%0d, %0d)'s pixel (%0d, %0d) at %h: %s, not %08h", what,
                           tx, ty, x, y, at,
                           dram.exists(at[AddrW-1:2]) ? $sformatf("%08h", dram[at[AddrW-1:2]]) :
                                                        "none", expected));
          bad++;
        end
      end
  endtask

  // Nothing but the tiles written
  task automatic check_written(input int count, input string what);
    if (dram.num() != count * TileWords)
      fail($sformatf("%s: %0d words written, %0d tiles' %0d expected", what, dram.num(), count,
                     count * TileWords));
  endtask

  // ---------------------------------------------------------------------------------------------
  // The tests

  task automatic test_registers();
    expect_read(Status, 32'h0, "STATUS after reset");
    expect_read(BaseLow, 32'h0, "BASE_LOW after reset");
    expect_read(BaseHigh, 32'h0, "BASE_HIGH after reset");
    expect_read(Stride, 32'h0, "STRIDE after reset");
    expect_read(TilesX, 32'h1, "TILES_X after reset");
    expect_read(TilesY, 32'h1, "TILES_Y after reset");
    expect_read(CurPos, 32'h0, "CUR_POS after reset");
    expect_read(ClearValue, 32'h0, "CLEAR_VALUE after reset");
    expect_read(IntRaw, 32'h0, "INT_RAW after reset");
    expect_read(IntMask, 32'h0, "INT_MASK after reset");
    apb_write(BaseLow, '1);
    expect_read(BaseLow, 32'hFFFE_0000, "BASE_LOW, bits 16..0 reserved");
    apb_write(BaseHigh, '1);
    expect_read(BaseHigh, BaseHighBits, "BASE_HIGH's bits");
    apb_write(Stride, '1);
    expect_read(Stride, 32'hFFFF_FFFF, "STRIDE, 32 bits");
    apb_write(TilesX, '1);
    expect_read(TilesX, 32'h0000_00FF, "TILES_X, 8 bits");
    apb_write(TilesY, '1);
    expect_read(TilesY, 32'h0000_00FF, "TILES_Y, 8 bits");
    apb_write(CurPos, '1);
    expect_read(CurPos, 32'h00FF_00FF, "CUR_POS, 8 bits each");
    apb_write(ClearValue, '1);
    expect_read(ClearValue, 32'hFFFF_FFFF, "CLEAR_VALUE, 32 bits");
    apb_write(Ctrl, ResetPos);
    expect_read(CurPos, 32'h0, "CUR_POS after RESET_POS");
    $display("[%0t] registers: %0d errors", $time, errors);
  endtask

  // INT_RAW raw, INT_STATUS status (INT_RAW not masked by INT_MASK's 1s), irq status's OR, the
  // event lines INT_RAW's
  task automatic expect_interrupts(input logic [2:0] raw, input logic [2:0] status,
                                   input string what);
    expect_read(IntRaw, 32'(raw), {what, ": INT_RAW"});
    expect_read(IntStatus, 32'(status), {what, ": INT_STATUS"});
    if ({irq_frame_done, irq_error, irq_done} != raw || irq != (status != 0))
      fail($sformatf("%s: irq %0d, done %0d, error %0d, frame_done %0d", what, irq, irq_done,
                     irq_error, irq_frame_done));
  endtask

  task automatic test_interrupts();
    apb_write(IntForce, Done);
    expect_interrupts(3'b001, 3'b001, "done forced");
    apb_write(IntMask, Done);
    expect_interrupts(3'b001, 3'b000, "done masked");
    apb_write(IntForce, Error | FrameDone);
    expect_interrupts(3'b111, 3'b110, "error and frame_done forced");
    apb_write(IntMask, Done | Error | FrameDone);
    expect_interrupts(3'b111, 3'b000, "all masked");
    apb_write(IntRaw, Done | FrameDone);
    expect_interrupts(3'b010, 3'b000, "done and frame_done cleared");
    apb_write(IntMask, 32'h0);
    expect_interrupts(3'b010, 3'b010, "none masked");
    apb_write(IntRaw, Error);
    expect_interrupts(3'b000, 3'b000, "all cleared");
    $display("[%0t] interrupts: %0d errors", $time, errors);
  endtask

  // 3 x 2 tiles in order by auto-advance at a high base, a stride a tile line wider than the frame
  task automatic test_frame();
    const logic [AddrW-1:0] base = AddrW'(64'h00AB_CDE2_0000);  // 0xCDE2_0000 in 32 bits
    const logic [31:0] stride = 4 * 512;
    set_frame(base, stride, 3, 2);
    for (int ty = 0; ty < 2; ty++)
      for (int tx = 0; tx < 3; tx++)
        tile(tx, ty, tx == 2 && ty == 1, tx == 2 ? 0 : tx + 1, tx == 2 ? (ty + 1) % 2 : ty,
             "frame");
    for (int ty = 0; ty < 2; ty++)
      for (int tx = 0; tx < 3; tx++) check_tile(base, stride, tx, ty, 1'b0, '0, "frame");
    check_written(6, "frame");
    $display("[%0t] a frame by auto-advance: %0d errors", $time, errors);
  endtask

  // 4 of 4 x 3 tiles out of order, CUR_POS written each time, the frame's last among them; STRIDE
  // with its low bits set, which it ignores
  task automatic test_out_of_order();
    const logic [AddrW-1:0] base = 'h4006_0000;
    const logic [31:0] stride = 5 * 512;
    int order[4][2] = '{'{2, 1}, '{3, 2}, '{0, 2}, '{3, 0}};
    set_frame(base, stride | 32'h123, 4, 3);
    foreach (order[i]) begin
      int tx, ty;
      bit last;
      tx = order[i][0];
      ty = order[i][1];
      last = tx == 3 && ty == 2;
      apb_write(CurPos, {8'h0, 8'(ty), 8'h0, 8'(tx)});
      tile(tx, ty, last, tx == 3 ? 0 : tx + 1, tx == 3 ? (last ? 0 : ty + 1) : ty, "out of order");
    end
    foreach (order[i])
      check_tile(base, stride, order[i][0], order[i][1], 1'b0, '0, "out of order");
    check_written(4, "out of order");
    $display("[%0t] tiles out of order: %0d errors", $time, errors);
  endtask

  // The origin's extremes: tile (254, 254), the last of 255 x 255, and (254, 0), (0, 254); the
  // stride 255 tile lines. With 32-bit addresses the last row ends just below 4 GiB; with wider
  // ones, rows run past 4 GiB from a base just below it.
  task automatic test_extremes();
    const logic [AddrW-1:0] base = AddrW > 32 ? AddrW'(64'hFFFE_0000) : AddrW'(64'h01FE_0000);
    const logic [31:0] stride = 255 * 512;
    set_frame(base, stride, 255, 255);
    apb_write(CurPos, {8'h0, 8'd254, 8'h0, 8'd254});
    tile(254, 254, 1'b1, 0, 0, "extremes");
    apb_write(CurPos, {8'h0, 8'd0, 8'h0, 8'd254});
    tile(254, 0, 1'b0, 0, 1, "extremes");
    apb_write(CurPos, {8'h0, 8'd254, 8'h0, 8'd0});
    tile(0, 254, 1'b0, 1, 254, "extremes");
    check_tile(base, stride, 254, 254, 1'b0, '0, "extremes");
    check_tile(base, stride, 254, 0, 1'b0, '0, "extremes");
    check_tile(base, stride, 0, 254, 1'b0, '0, "extremes");
    check_written(3, "extremes");
    $display("[%0t] the origin's extremes: %0d errors", $time, errors);
  endtask

  task automatic test_zero_tiles();
    const logic [AddrW-1:0] base = 'h1234_0000;
    const logic [31:0] stride = 512;
    set_frame(base, stride, 0, 2);
    tile(0, 0, 1'b0, 0, 1, "TILES_X 0");
    tile(0, 1, 1'b1, 0, 0, "TILES_X 0");
    check_tile(base, stride, 0, 0, 1'b0, '0, "TILES_X 0");
    check_tile(base, stride, 0, 1, 1'b0, '0, "TILES_X 0");
    check_written(2, "TILES_X 0");
    set_frame(base, stride, 0, 0);
    tile(0, 0, 1'b1, 0, 0, "TILES 0 x 0");
    check_tile(base, stride, 0, 0, 1'b0, '0, "TILES 0 x 0");
    check_written(1, "TILES 0 x 0");
    $display("[%0t] TILES 0: %0d errors", $time, errors);
  endtask

  // BASE, STRIDE, TILES and CLEAR_VALUE written during a transfer: the tile, its advance and what
  // it leaves behind as at START, CLEAR ignored; the next tile by the new values
  task automatic test_busy_writes();
    const logic [AddrW-1:0] base = 'h0010_0000, new_base = AddrW'(64'h0001_8000_0000);
    const logic [31:0] stride = 3 * 512, new_stride = 6 * 512;
    logic [31:0] raw;
    int bad;
    set_frame(base, stride, 3, 2);
    apb_write(CurPos, {8'h0, 8'd0, 8'h0, 8'd2});
    apb_write(ClearValue, 32'h5EED_0001);
    fill_tile(2, 0);
    start();
    apb_write(BaseLow, new_base[31:0]);
    apb_write(BaseHigh, 32'(64'(new_base) >> 32));
    apb_write(Stride, new_stride);
    apb_write(TilesX, 5);
    apb_write(TilesY, 7);
    apb_write(ClearValue, 32'h5EED_0002);
    apb_write(Ctrl, Clear);
    expect_status(Busy | ClearBusy, Busy, "busy writes: during the transfer");
    wait_done(raw);
    if (raw != Done) fail($sformatf("busy writes: INT_RAW %08h", raw));
    expect_read(CurPos, {8'h0, 8'd1, 8'h0, 8'd0}, "busy writes: CUR_POS, by TILES as at START");
    expect_status(Busy | ClearBusy, 32'h0, "busy writes: after, CLEAR ignored");
    check_tile(base, stride, 2, 0, 1'b0, '0, "busy writes");
    count_rams_not(32'h5EED_0001, bad);
    if (bad != 0) fail($sformatf("busy writes: %0d pixels left behind not as at START", bad));
    tile(0, 1, 1'b0, 1, 1, "busy writes, the next tile");
    check_tile(new_base, new_stride, 0, 1, 1'b0, '0, "busy writes, the next tile");
    check_written(2, "busy writes");
    $display("[%0t] registers written during a transfer: %0d errors", $time, errors);
  endtask

  // A write-back leaves CLEAR_VALUE behind it, so the next of a tile left as it is writes that;
  // CLEAR fills the tile RAMs with it, START ignored meanwhile
  task automatic test_clear();
    const logic [AddrW-1:0] base = 'h0002_0000;
    const logic [31:0] stride = 2 * 512;
    logic [31:0] raw, status;
    int polls = 0, bad, aw0;
    set_frame(base, stride, 2, 1);
    apb_write(ClearValue, 32'hC1EA_0001);
    tile(0, 0, 1'b0, 1, 0, "clear");
    start();  // tile (1, 0), not filled
    wait_done(raw);
    check_tile(base, stride, 0, 0, 1'b0, '0, "clear");
    check_tile(base, stride, 1, 0, 1'b1, 32'hC1EA_0001, "clear, left behind");
    check_written(2, "clear");

    apb_write(ClearValue, 32'h0BAD_F00D);
    apb_write(IntRaw, Done | Error | FrameDone);
    aw0 = aw_count;
    apb_write(Ctrl, Clear);
    apb_write(Ctrl, Start);
    do begin
      apb_read(Status, status);
      if (++polls > 100000) $fatal(1, "tile DMA: CLEAR never done");
    end while (status & ClearBusy);
    if (polls < 2) fail("CLEAR: CLEAR_BUSY never seen");
    if (status & Busy || aw_count != aw0) fail("CLEAR: START taken during it");
    expect_read(IntRaw, 32'h0, "CLEAR: INT_RAW");
    count_rams_not(32'h0BAD_F00D, bad);
    if (bad != 0) fail($sformatf("CLEAR: %0d pixels not CLEAR_VALUE", bad));
    $display("[%0t] CLEAR_VALUE left behind, CLEAR: %0d errors", $time, errors);
  endtask

  task automatic test_soft_reset();
    const logic [AddrW-1:0] base = 'h0004_0000;
    const logic [31:0] stride = 2 * 512;
    logic [31:0] raw;
    set_frame(base, stride, 2, 2);
    apb_write(CurPos, {8'h0, 8'd1, 8'h0, 8'd1});
    apb_write(Ctrl, SoftReset);
    expect_read(CurPos, 32'h0, "SOFT_RESET idle: CUR_POS");
    expect_status(SoftResetPending, 32'h0, "SOFT_RESET idle");

    apb_write(CurPos, {8'h0, 8'd0, 8'h0, 8'd1});
    fill_tile(1, 0);
    start();
    apb_write(Ctrl, SoftReset);
    expect_status(Busy | SoftResetPending, Busy | SoftResetPending, "SOFT_RESET busy: pending");
    expect_read(CurPos, {8'h0, 8'd0, 8'h0, 8'd1}, "SOFT_RESET busy: CUR_POS during the tile");
    wait_done(raw);
    expect_read(CurPos, 32'h0, "SOFT_RESET busy: CUR_POS after the tile");
    expect_status(Busy | SoftResetPending, 32'h0, "SOFT_RESET busy: after the tile");
    tile(0, 0, 1'b0, 1, 0, "after SOFT_RESET");
    check_tile(base, stride, 1, 0, 1'b0, '0, "SOFT_RESET busy");
    check_tile(base, stride, 0, 0, 1'b0, '0, "after SOFT_RESET");
    check_written(2, "SOFT_RESET");
    $display("[%0t] SOFT_RESET: %0d errors", $time, errors);
  endtask

  // SLVERR on a tile's 41st burst, DECERR on its last, then none: the error event, LAST_BRESP the
  // last error's, kept; every tile still all written
  task automatic test_errors();
    const logic [AddrW-1:0] base = 'h0006_0000;
    const logic [31:0] stride = 512;
    set_frame(base, stride, 1, 3);
    error_burst = w_count + 40;
    error_resp = SlvErr;
    tile(0, 0, 1'b0, 0, 1, "SLVERR");
    expect_status(LastBresp, 32'(SlvErr) << 1, "SLVERR: LAST_BRESP");
    error_burst = w_count + BurstsPerTile - 1;
    error_resp = DecErr;
    tile(0, 1, 1'b0, 0, 2, "DECERR on the last burst");
    expect_status(LastBresp, 32'(DecErr) << 1, "DECERR: LAST_BRESP");
    error_burst = -1;
    tile(0, 2, 1'b1, 0, 0, "after the errors");
    expect_status(LastBresp, 32'(DecErr) << 1, "after the errors: LAST_BRESP kept");
    for (int ty = 0; ty < 3; ty++) check_tile(base, stride, 0, ty, 1'b0, '0, "errors");
    check_written(3, "errors");
    $display("[%0t] error responses: %0d errors", $time, errors);
  endtask

  initial begin
    repeat (10) @(posedge aclk);
    aresetn = 1'b1;
    ram_resetn = 1'b1;
    repeat (10) @(posedge aclk);
    $display("STALL %0d%%, clocks (ns): aclk %0.3f, ram_clk %0.3f", stall, aclk_ns, ram_ns);
    test_registers();
    test_interrupts();
    test_frame();
    test_out_of_order();
    test_extremes();
    test_zero_tiles();
    test_busy_writes();
    test_clear();
    test_soft_reset();
    test_errors();
    $display("%0d tiles (%0d bursts), PERF %0d..%0d cycles a tile (4096 beats)", tiles, aw_count,
             perf_min, perf_max);
    if (errors != 0) $fatal(1, "FAIL: %0d errors", errors);
    $display("PASS");
    $finish;
  end

  initial begin
    #100ms;
    $fatal(1, "testbench timeout");
  end

endmodule
