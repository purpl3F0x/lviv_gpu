`timescale 1ns / 1ps

module tb_texture_cache;

  localparam int AddrWidth = 32;
  localparam int PixelBits = 32;
  localparam int CacheLines = 32;
  localparam int LinePixelsX = 8;
  localparam int LinePixelsY = 8;
  localparam int AxiDataWidth = 128;

  localparam int PixelBytes = PixelBits / 8;
  localparam int LineBytes = LinePixelsX * LinePixelsY * PixelBytes;
  localparam int AxiBytes = AxiDataWidth / 8;
  localparam int AxiAddrWidth = 16;
  localparam int AxiIdWidth = 8;
  localparam int MemBeats = 4096;
  localparam int MaxWaitCycles = 10000;
  localparam int WayBits = $clog2(CacheLines);
  localparam int PlruBits = CacheLines - 1;
  localparam int TagBits = AddrWidth - $clog2(LineBytes);

  logic                    clk;
  logic                    rst_n;
  logic                    flush;

  logic                    req_valid;
  logic                    req_ready;
  logic [   AddrWidth-1:0] req_addr;

  logic                    resp_valid;
  logic [   PixelBits-1:0] resp_data;

  logic [   AddrWidth-1:0] m_axi_araddr;
  logic [             7:0] m_axi_arlen;
  logic [             2:0] m_axi_arsize;
  logic [             1:0] m_axi_arburst;
  logic                    m_axi_arvalid;
  logic                    m_axi_arready;

  logic [AxiDataWidth-1:0] m_axi_rdata;
  logic [             1:0] m_axi_rresp;
  logic                    m_axi_rvalid;
  logic                    m_axi_rready;
  logic                    m_axi_rlast;
  logic [            31:0] perf_total_req;
  logic [            31:0] perf_hit_req;
  logic [            31:0] perf_miss_req;
  logic                    perf_re;
  logic [             2:0] perf_addr;
  logic [            31:0] perf_rdata;
  logic                    perf_rvalid;

  int                      err_count;
  int                      axi_read_count;
  logic [AddrWidth-1:0]    first_axi_addr;
  logic                    first_axi_seen;

  texture_cache #(
      .ADDR_WIDTH(AddrWidth),
      .PIXEL_BITS(PixelBits),
      .CACHE_LINES(CacheLines),
      .LINE_PIXELS_X(LinePixelsX),
      .LINE_PIXELS_Y(LinePixelsY),
      .AXI_DATA_WIDTH(AxiDataWidth)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .flush(flush),
      .req_valid(req_valid),
      .req_ready(req_ready),
      .req_addr(req_addr),
      .resp_valid(resp_valid),
      .resp_data(resp_data),
      .m_axi_araddr(m_axi_araddr),
      .m_axi_arlen(m_axi_arlen),
      .m_axi_arsize(m_axi_arsize),
      .m_axi_arburst(m_axi_arburst),
      .m_axi_arvalid(m_axi_arvalid),
      .m_axi_arready(m_axi_arready),
      .m_axi_rdata(m_axi_rdata),
      .m_axi_rresp(m_axi_rresp),
      .m_axi_rvalid(m_axi_rvalid),
      .m_axi_rready(m_axi_rready),
      .m_axi_rlast(m_axi_rlast),
      .perf_total_req(perf_total_req),
      .perf_hit_req(perf_hit_req),
      .perf_miss_req(perf_miss_req),
      .perf_re(perf_re),
      .perf_addr(perf_addr),
      .perf_rdata(perf_rdata),
      .perf_rvalid(perf_rvalid)
  );

  axi_ram #(
      .DATA_WIDTH(AxiDataWidth),
      .ADDR_WIDTH(AxiAddrWidth),
      .STRB_WIDTH(AxiBytes),
      .ID_WIDTH(AxiIdWidth),
      .PIPELINE_OUTPUT(0)
  ) u_axi_ram (
      .clk(clk),
      .rst(~rst_n),
      .s_axi_awid('0),
      .s_axi_awaddr('0),
      .s_axi_awlen('0),
      .s_axi_awsize('0),
      .s_axi_awburst('0),
      .s_axi_awlock('0),
      .s_axi_awcache('0),
      .s_axi_awprot('0),
      .s_axi_awvalid(1'b0),
      .s_axi_awready(),
      .s_axi_wdata('0),
      .s_axi_wstrb('0),
      .s_axi_wlast(1'b0),
      .s_axi_wvalid(1'b0),
      .s_axi_wready(),
      .s_axi_bid(),
      .s_axi_bresp(),
      .s_axi_bvalid(),
      .s_axi_bready(1'b1),
      .s_axi_arid('0),
      .s_axi_araddr(m_axi_araddr[AxiAddrWidth-1:0]),
      .s_axi_arlen(m_axi_arlen),
      .s_axi_arsize(m_axi_arsize),
      .s_axi_arburst(m_axi_arburst),
      .s_axi_arlock('0),
      .s_axi_arcache('0),
      .s_axi_arprot('0),
      .s_axi_arvalid(m_axi_arvalid),
      .s_axi_arready(m_axi_arready),
      .s_axi_rid(),
      .s_axi_rdata(m_axi_rdata),
      .s_axi_rresp(m_axi_rresp),
      .s_axi_rlast(m_axi_rlast),
      .s_axi_rvalid(m_axi_rvalid),
      .s_axi_rready(m_axi_rready)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    int dump_enable;
    if ($value$plusargs("dump=%d", dump_enable)) begin
      $dumpfile("waves.vcd");
      $dumpvars(0, tb_texture_cache);
    end
  end

  function automatic logic [31:0] expected_word(input logic [AddrWidth-1:0] pixel_addr);
    begin
      expected_word = 32'h1000_0000 + pixel_addr;
    end
  endfunction

  function automatic logic [WayBits-1:0] tb_select_victim(input logic [PlruBits-1:0] tree);
    int node;
    logic [WayBits-1:0] victim;
    begin
      node = 0;
      victim = '0;
      for (int level = 0; level < WayBits; level++) begin
        victim[WayBits-1-level] = tree[node];
        if (tree[node] == 1'b0) begin
          node = (node << 1) + 1;
        end else begin
          node = (node << 1) + 2;
        end
      end
      tb_select_victim = victim;
    end
  endfunction

  // Drive requests on negedge so all simulators see stable setup before posedge sampling.
  task automatic drive_req(input logic [AddrWidth-1:0] addr);
    int wait_cycles;
    begin
      wait_cycles = 0;
      while (!req_ready) begin
        @(negedge clk);
        wait_cycles++;
        if (wait_cycles > MaxWaitCycles) begin
          $display("[ERR] drive_req timeout waiting for req_ready addr=%08h", addr);
          err_count = err_count + 1;
          disable drive_req;
        end
      end
      @(negedge clk);
      req_addr  <= addr;
      req_valid <= 1'b1;
      @(negedge clk);
      req_valid <= 1'b0;
    end
  endtask

  task automatic wait_resp(output logic [PixelBits-1:0] data, output int cycles);
    begin
      cycles = 0;
      while (!resp_valid) begin
        @(posedge clk);
        cycles++;
        if (cycles > MaxWaitCycles) begin
          $display("[ERR] wait_resp timeout waiting for resp_valid");
          err_count = err_count + 1;
          data = '0;
          disable wait_resp;
        end
      end
      data = resp_data;
    end
  endtask

  task automatic check_access(input logic [AddrWidth-1:0] addr, input string tag);
    logic [PixelBits-1:0] got;
    int cycles;
    begin
      drive_req(addr);
      wait_resp(got, cycles);
      if (got !== expected_word(addr)) begin
        $display("[ERR] %s addr=%08h exp=%08h got=%08h", tag, addr, expected_word(addr), got);
        err_count = err_count + 1;
      end
    end
  endtask

  task automatic check_access_min_latency(input logic [AddrWidth-1:0] addr,
                                          input int min_cycles,
                                          input string tag);
    logic [PixelBits-1:0] got;
    int cycles;
    begin
      drive_req(addr);
      wait_resp(got, cycles);
      if (got !== expected_word(addr)) begin
        $display("[ERR] %s addr=%08h exp=%08h got=%08h", tag, addr, expected_word(addr), got);
        err_count = err_count + 1;
      end
      if (cycles < min_cycles) begin
        $display("[ERR] %s expected min latency=%0d got=%0d", tag, min_cycles, cycles);
        err_count = err_count + 1;
      end
    end
  endtask

  task automatic check_miss_hit_miss_miss_sequence;
    logic [AddrWidth-1:0] sequence_addrs[4];
    logic [PixelBits-1:0] got;
    int sent;
    int recv;
    int reads_before;
    begin
      sequence_addrs[0] = 32'h0000_004B;
      sequence_addrs[1] = 32'h0000_004B;
      sequence_addrs[2] = 32'h0000_012B;
      sequence_addrs[3] = 32'h0000_020B;
      sent = 0;
      recv = 0;
      reads_before = axi_read_count;

      fork
        begin : send_sequence
          int send_wait_cycles;
          send_wait_cycles = 0;
          while (sent < 4) begin
            @(negedge clk);
            req_addr  <= sequence_addrs[sent];
            req_valid <= 1'b1;
            do begin
              @(posedge clk);
              send_wait_cycles++;
              if (send_wait_cycles > MaxWaitCycles) begin
                $display("[ERR] directed sequence timed out sending request %0d", sent);
                err_count = err_count + 1;
                disable send_sequence;
              end
            end while (!(req_valid && req_ready));
            sent++;
          end

          @(negedge clk);
          req_valid <= 1'b0;
        end

        begin : receive_sequence
          int response_wait_cycles;
          response_wait_cycles = 0;
          while (recv < 4) begin
            @(posedge clk);
            response_wait_cycles++;
            if (resp_valid) begin
              got = resp_data;
              if (got !== expected_word(sequence_addrs[recv])) begin
                $display("[ERR] directed sequence[%0d] addr=%08h exp=%08h got=%08h", recv,
                         sequence_addrs[recv], expected_word(sequence_addrs[recv]), got);
                err_count = err_count + 1;
              end
              recv++;
            end

            if (response_wait_cycles > MaxWaitCycles) begin
              $display("[ERR] directed sequence timed out receiving response %0d", recv);
              err_count = err_count + 1;
              disable receive_sequence;
            end
          end
        end
      join

      if (axi_read_count - reads_before != 3) begin
        $display("[ERR] directed miss-hit-miss-miss expected 3 refills got %0d",
                 axi_read_count - reads_before);
        err_count = err_count + 1;
      end
    end
  endtask

  task automatic check_miss_then_evicted_line;
    logic [AddrWidth-1:0] pair_addrs[2];
    logic [AddrWidth-1:0] fill_addr;
    logic [TagBits-1:0] victim_tag;
    logic [WayBits-1:0] victim_way;
    logic [PixelBits-1:0] got;
    int sent;
    int recv;
    int reads_before;
    begin
      @(negedge clk);
      flush <= 1'b1;
      @(negedge clk);
      flush <= 1'b0;

      for (int line = 0; line < CacheLines; line++) begin
        fill_addr = 32'h0000_1000 + (AddrWidth'(line) << $clog2(LinePixelsX * LinePixelsY));
        check_access(fill_addr, "replacement-fill");
      end

      victim_way = tb_select_victim(dut.plru_tree);
      if (dut.u_cache_tags.valid_mem[victim_way] !== 1'b1) begin
        $display("[ERR] replacement victim way %0d is not valid before miss", victim_way);
        err_count = err_count + 1;
      end
      victim_tag = dut.u_cache_tags.tag_mem[victim_way];
      pair_addrs[0] = 32'h0000_3000;
      pair_addrs[1] = AddrWidth'(victim_tag) << $clog2(LinePixelsX * LinePixelsY);
      sent = 0;
      recv = 0;
      reads_before = axi_read_count;

      fork
        begin : send_replacement_pair
          int send_wait_cycles;
          send_wait_cycles = 0;
          while (sent < 2) begin
            @(negedge clk);
            req_addr  <= pair_addrs[sent];
            req_valid <= 1'b1;
            do begin
              @(posedge clk);
              send_wait_cycles++;
              if (send_wait_cycles > MaxWaitCycles) begin
                $display("[ERR] replacement race timed out sending request %0d", sent);
                err_count = err_count + 1;
                disable send_replacement_pair;
              end
            end while (!(req_valid && req_ready));
            sent++;
          end

          @(negedge clk);
          req_valid <= 1'b0;
        end

        begin : receive_replacement_pair
          int response_wait_cycles;
          response_wait_cycles = 0;
          while (recv < 2) begin
            @(posedge clk);
            response_wait_cycles++;
            if (resp_valid) begin
              got = resp_data;
              if (got !== expected_word(pair_addrs[recv])) begin
                $display("[ERR] replacement race[%0d] addr=%08h exp=%08h got=%08h", recv,
                         pair_addrs[recv], expected_word(pair_addrs[recv]), got);
                err_count = err_count + 1;
              end
              recv++;
            end

            if (response_wait_cycles > MaxWaitCycles) begin
              $display("[ERR] replacement race timed out receiving response %0d", recv);
              err_count = err_count + 1;
              disable receive_replacement_pair;
            end
          end
        end
      join

      if (axi_read_count - reads_before != 2) begin
        $display("[ERR] replacement race expected 2 refills (new line + evicted line), got %0d",
                 axi_read_count - reads_before);
        err_count = err_count + 1;
      end
    end
  endtask

  task automatic perf_read_reg(input logic [2:0] addr, output logic [31:0] data);
    int wait_cycles;
    begin
      wait_cycles = 0;
      @(negedge clk);
      perf_addr <= addr;
      perf_re   <= 1'b1;
      @(negedge clk);
      perf_re <= 1'b0;

      while (!perf_rvalid) begin
        @(posedge clk);
        wait_cycles++;
        if (wait_cycles > MaxWaitCycles) begin
          $display("[ERR] perf_read_reg timeout addr=%0d", addr);
          err_count = err_count + 1;
          data = '0;
          disable perf_read_reg;
        end
      end
      data = perf_rdata;
    end
  endtask

  task automatic check_burst_one_req_per_cycle(input logic [AddrWidth-1:0] base_addr,
                                               input int count, input string tag);
    logic [AddrWidth-1:0] reqs[64];
    logic [PixelBits-1:0] got;
    int sent;
    int recv;
    int wait_cycles;
    bit ready_stall_seen;
    begin
      if (count > 64) begin
        $display("[ERR] %s count=%0d exceeds max supported 64", tag, count);
        err_count = err_count + 1;
        disable check_burst_one_req_per_cycle;
      end

      sent = 0;
      recv = 0;
      wait_cycles = 0;
      ready_stall_seen = 1'b0;

      // Issue and collect concurrently so early hit responses are not missed.
      fork
        begin : send_path
          while (sent < count) begin
            @(negedge clk);
            if (!req_ready) begin
              ready_stall_seen = 1'b1;
            end

            while (!req_ready) begin
              @(negedge clk);
            end

            reqs[sent] = base_addr + 32'(sent);
            req_addr  <= reqs[sent];
            req_valid <= 1'b1;
            sent = sent + 1;
          end

          @(negedge clk);
          req_valid <= 1'b0;
        end

        begin : recv_path
          while (recv < count) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
            if (resp_valid) begin
              got = resp_data;
              if (got !== expected_word(reqs[recv])) begin
                $display("[ERR] %s[%0d] addr=%08h exp=%08h got=%08h", tag, recv, reqs[recv],
                         expected_word(reqs[recv]), got);
                err_count = err_count + 1;
              end
              recv = recv + 1;
            end

            if (wait_cycles > MaxWaitCycles) begin
              $display("[ERR] %s timeout waiting for burst responses recv=%0d sent=%0d", tag, recv,
                       sent);
              err_count = err_count + 1;
              disable recv_path;
            end
          end
        end
      join

      if (ready_stall_seen) begin
        $display("[ERR] %s req_ready stalled during one-req-per-cycle issue phase", tag);
        err_count = err_count + 1;
      end
    end
  endtask

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      axi_read_count <= 0;
      first_axi_addr <= '0;
      first_axi_seen <= 1'b0;
    end else if (m_axi_arvalid && m_axi_arready) begin
      axi_read_count <= axi_read_count + 1;
      if (!first_axi_seen) begin
        first_axi_addr <= m_axi_araddr;
        first_axi_seen <= 1'b1;
      end
    end
  end

  initial begin : main
    int unsigned i;

    rst_n = 1'b0;
    flush = 1'b0;
    req_valid = 1'b0;
    req_addr = '0;
    perf_re = 1'b0;
    perf_addr = '0;
    err_count = 0;

    for (i = 0; i < MemBeats; i++) begin
      int unsigned base_word;
      base_word = i * (AxiDataWidth / PixelBits);
      u_axi_ram.mem[i] = {
        32'h1000_0000 + base_word + 32'd3,
        32'h1000_0000 + base_word + 32'd2,
        32'h1000_0000 + base_word + 32'd1,
        32'h1000_0000 + base_word + 32'd0
      };
    end

    repeat (6) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    check_miss_hit_miss_miss_sequence();
    if (first_axi_addr !== (32'h0000_004B << 2 & ~(LineBytes - 1))) begin
      $display("[ERR] first refill AXI address expected byte line base=%08h got=%08h",
               (32'h0000_004B << 2 & ~(LineBytes - 1)), first_axi_addr);
      err_count = err_count + 1;
    end
    check_access(32'h0000_004B, "same-addr-hit");
    check_access(32'h0000_004C, "same-line-hit");
    check_access(32'h0000_012B, "different-line");

    // Flush must take priority and invalidate cache state.
    @(negedge clk);
    flush <= 1'b1;
    req_valid <= 1'b1;
    req_addr <= 32'h0000_0100;
    @(posedge clk);
    if (req_ready !== 1'b0) begin
      $display("[ERR] flush-priority req_ready should be low while flush is asserted");
      err_count = err_count + 1;
    end
    @(negedge clk);
    flush <= 1'b0;
    req_valid <= 1'b0;
    check_access_min_latency(32'h0000_004B, 3, "post-flush-miss");

    // Fill one line, then issue one request per cycle across that line.
    check_access(32'h0000_0080, "burst-preload-line");
    check_burst_one_req_per_cycle(32'h0000_0080, 64, "one-req-per-cycle-hit-burst");

    // A pending request to the selected victim must be rechecked after refill replaces it.
    check_miss_then_evicted_line();

    // Perf CSR readback checks.
    begin
      logic [31:0] csr_total;
      logic [31:0] csr_hit;
      logic [31:0] csr_miss;
      perf_read_reg(3'd0, csr_total);
      perf_read_reg(3'd1, csr_hit);
      perf_read_reg(3'd2, csr_miss);
      if ((csr_total !== perf_total_req) || (csr_hit !== perf_hit_req) ||
          (csr_miss !== perf_miss_req)) begin
        $display("[ERR] perf CSR mismatch total=%0d/%0d hit=%0d/%0d miss=%0d/%0d",
                 perf_total_req, csr_total, perf_hit_req, csr_hit, perf_miss_req, csr_miss);
        err_count = err_count + 1;
      end
    end

    if (err_count == 0) begin
      $display("[TB PASS] texture_cache");
      $display("[TB PERF] total=%0d hit=%0d miss=%0d", perf_total_req, perf_hit_req,
               perf_miss_req);
    end else begin
      $display("[TB FAIL] texture_cache errors=%0d", err_count);
    end

    if (perf_total_req !== (perf_hit_req + perf_miss_req)) begin
      $display("[ERR] perf consistency total(%0d) != hit(%0d)+miss(%0d)",
               perf_total_req, perf_hit_req, perf_miss_req);
      err_count = err_count + 1;
    end

    $finish;
  end

  initial begin : watchdog
    repeat (200000) @(posedge clk);
    $display("[ERR] watchdog timeout: simulation did not finish");
    $finish;
  end

endmodule
