`timescale 1ns / 1ps

import gpu_types_pkg::*;

module tb_thread_cache;
  localparam int AXI_ADDR_WIDTH = 16;
  localparam int AXI_DATA_WIDTH = 128;
  localparam int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;
  localparam int AXI_ID_WIDTH = 1;
  localparam int ZBUF_DEPTH = 1 << PIXEL_ADDR_W_THREAD;
  localparam int MaxWaitCycles = 10000;
  localparam int TextureSlot = 0;
  // Texture and AXI addresses are byte addresses. The AXI RAM stores one
  // 128-bit beat per memory entry, so its entry index is byte_addr / 16.
  localparam logic [31:0] TextureBaseAddr = 32'h0000_0100;
  localparam logic [31:0] TextureBaseWordAddr = TextureBaseAddr >> 2;
  localparam logic [3:0] TextureSizeLog2 = 4'd11;
  localparam logic [31:0] TextureWord0 = 32'hFF11_2233;
  localparam logic [31:0] TextureWord1 = 32'hFF44_5566;
  localparam logic [31:0] TextureWord2 = 32'hFF77_8899;
  localparam logic [31:0] TextureWord3 = 32'hFFAA_BBCC;
  localparam logic [31:0] ZDefault = 32'h3F80_0000;
  localparam logic [31:0] ZNear = 32'h3F00_0000;
  localparam logic [31:0] ZNearer = 32'h3E80_0000;
  localparam int BeatsPerLine = (8 * 8 * 4) / (AXI_DATA_WIDTH / 8);
  localparam int TextureMemBaseBeat = TextureBaseAddr / AXI_STRB_WIDTH;
  localparam int CacheLineCount = 65;

  logic clk;
  logic rst_n;

  logic valid_in;
  logic ready_out;
  thread_data_in_t in_data;

  logic [31:0] out_fb_color;
  logic [PIXEL_ADDR_W_THREAD-1:0] out_fb_addr;
  logic out_fb_valid;
  logic out_fb_we;

  logic z_buf_ready;
  logic z_rd_en;
  logic [PIXEL_ADDR_W_THREAD-1:0] z_rd_addr;
  logic [31:0] z_rd_data;
  logic z_wr_en;
  logic [PIXEL_ADDR_W_THREAD-1:0] z_wr_addr;
  logic [31:0] z_wr_data;

  logic [31:0] tex_m_axi_araddr;
  logic [7:0] tex_m_axi_arlen;
  logic [2:0] tex_m_axi_arsize;
  logic [1:0] tex_m_axi_arburst;
  logic tex_m_axi_arvalid;
  logic tex_m_axi_arready;
  logic [127:0] tex_m_axi_rdata;
  logic [1:0] tex_m_axi_rresp;
  logic tex_m_axi_rvalid;
  logic tex_m_axi_rready;
  logic tex_m_axi_rlast;

  logic lut_addr_wr_en;
  logic lut_size_wr_en;
  logic [6:0] lut_wr_addr;
  logic [31:0] lut_wr_data;

  logic [AXI_ID_WIDTH-1:0] axi_rid_unused;
  logic [AXI_ID_WIDTH-1:0] axi_bid_unused;
  logic [1:0] axi_bresp_unused;
  logic axi_bvalid_unused;

  int err_count;
  int ar_handshake_count;
  int out_write_count;
  int accepted_count;
  int l1_request_count;
  logic [31:0] last_l1_requested_word_addr;
  logic [31:0] last_l1_expected_color;

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
        .lut_addr_wr_en(lut_addr_wr_en),
        .lut_size_wr_en(lut_size_wr_en),
        .lut_wr_addr(lut_wr_addr),
        .lut_wr_data(lut_wr_data)
  );

  z_buffer_ram #(
      .ADDR_WIDTH(PIXEL_ADDR_W_THREAD),
      .RESET_Z_VALUE(ZDefault)
  ) u_z_buffer_ram (
      .clk(clk),
      .rst_n(1'b1),
      .ready(z_buf_ready),
      .wr_en(z_wr_en),
      .wr_addr(z_wr_addr),
      .din(z_wr_data),
      .rd_en(z_rd_en),
      .rd_addr(z_rd_addr),
      .dout(z_rd_data)
  );

  axi_ram #(
      .DATA_WIDTH(AXI_DATA_WIDTH),
      .ADDR_WIDTH(AXI_ADDR_WIDTH),
      .STRB_WIDTH(AXI_STRB_WIDTH),
      .ID_WIDTH(AXI_ID_WIDTH),
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
      .s_axi_bid(axi_bid_unused),
      .s_axi_bresp(axi_bresp_unused),
      .s_axi_bvalid(axi_bvalid_unused),
      .s_axi_bready(1'b1),
      .s_axi_arid('0),
      .s_axi_araddr(tex_m_axi_araddr[AXI_ADDR_WIDTH-1:0]),
      .s_axi_arlen(tex_m_axi_arlen),
      .s_axi_arsize(tex_m_axi_arsize),
      .s_axi_arburst(tex_m_axi_arburst),
      .s_axi_arlock('0),
      .s_axi_arcache('0),
      .s_axi_arprot('0),
      .s_axi_arvalid(tex_m_axi_arvalid),
      .s_axi_arready(tex_m_axi_arready),
      .s_axi_rid(axi_rid_unused),
      .s_axi_rdata(tex_m_axi_rdata),
      .s_axi_rresp(tex_m_axi_rresp),
      .s_axi_rlast(tex_m_axi_rlast),
      .s_axi_rvalid(tex_m_axi_rvalid),
      .s_axi_rready(tex_m_axi_rready)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    $dumpfile("waves.vcd");
    $dumpvars(0, tb_thread_cache);
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      ar_handshake_count <= 0;
      out_write_count <= 0;
      accepted_count <= 0;
      l1_request_count <= 0;
      last_l1_requested_word_addr <= '0;
      last_l1_expected_color <= '0;
    end else begin
      if (tex_m_axi_arvalid && tex_m_axi_arready) begin
        $display("[TRACE] AXI AR addr=%08h len=%0d mem0=%032h",
                 tex_m_axi_araddr, tex_m_axi_arlen + 1, u_axi_ram.mem[0]);
        ar_handshake_count <= ar_handshake_count + 1;
      end
      if (dut.l1_req_valid) begin
        l1_request_count <= l1_request_count + 1;
        last_l1_requested_word_addr <= dut.address_token_s3.texture_addr;
        last_l1_expected_color <= expected_texture_word(dut.address_token_s3.texture_addr);
        $display("[TRACE] L1 request addr=%08h token_tex=%0d mode_u=%b mode_v=%b no_texture=%b valid=%b",
                 dut.address_token_s3.texture_addr,
                 dut.address_token_s3.token.tex_id,
                 dut.address_token_s3.token.texture_mode_u,
                 dut.address_token_s3.token.texture_mode_v,
                 dut.address_token_s3.no_texture,
                 dut.address_pipe_valid);
      end
      if (dut.output_bundle_buf_tvalid) begin
        $display("[TRACE] gate token u=%012h v=%012h color=%08h comp=%b",
                 dut.post_skid_token.texcoord_u,
                 dut.post_skid_token.texcoord_v,
                 dut.post_skid_token.color,
                 dut.post_skid_token.comp_z);
      end
      if (tex_m_axi_rvalid && tex_m_axi_rready) begin
        $display("[TRACE] AXI R data=%032h last=%b", tex_m_axi_rdata, tex_m_axi_rlast);
      end
      if (dut.l1_resp_valid) begin
        $display("[TRACE] L1 data=%08h", dut.l1_resp_data);
      end
      if (dut.address_pipe_valid || dut.texture_wait_valid || dut.fragment_join_output_valid) begin
        $display("[TRACE] frag addr_valid=%b use_tex=%b addr_step=%b join_valid=%b join_ready=%b wait=%b resp=%b shader_valid=%b",
                 dut.address_pipe_valid, dut.address_use_texture, dut.address_step,
                 dut.fragment_join_output_valid, dut.fragment_join_input_ready,
                 dut.texture_wait_valid, dut.l1_resp_valid, dut.fragment_shader_input_valid);
      end
      if (out_fb_we) begin
        out_write_count <= out_write_count + 1;
      end
      if (valid_in && ready_out) begin
        accepted_count <= accepted_count + 1;
      end
    end
  end

  function automatic logic [31:0] fbits(input shortreal value);
    return $shortrealtobits(value);
  endfunction

  function automatic logic [17:0] to_uq5_13(input shortreal value);
    shortreal clamped;
    int unsigned q;
    begin
      if (value < 0.0) begin
        clamped = 0.0;
      end else if (value > 31.9998779) begin
        clamped = 31.9998779;
      end else begin
        clamped = value;
      end
      q = int'((clamped * 8192.0) + 0.5);
      if (q > 18'h3ffff) begin
        q = 18'h3ffff;
      end
      return q[17:0];
    end
  endfunction

  function automatic logic [31:0] texture_word_for_addr(input int unsigned word_addr);
    return {8'hFF, word_addr[15:8], word_addr[7:0], 8'h5A};
  endfunction

  function automatic logic [31:0] expected_texture_word(input logic [31:0] word_addr);
    logic [31:0] physical_word_addr;
    begin
      physical_word_addr = word_addr & ((1 << (AXI_ADDR_WIDTH - 2)) - 1);
      case (physical_word_addr[1:0])
        2'd0: expected_texture_word = (physical_word_addr == TextureBaseWordAddr) ? TextureWord0
                                                                                  : texture_word_for_addr(physical_word_addr);
        2'd1: expected_texture_word = (physical_word_addr == TextureBaseWordAddr + 1) ? TextureWord1
                                                                                      : texture_word_for_addr(physical_word_addr);
        2'd2: expected_texture_word = (physical_word_addr == TextureBaseWordAddr + 2) ? TextureWord2
                                                                                      : texture_word_for_addr(physical_word_addr);
        default: expected_texture_word = (physical_word_addr == TextureBaseWordAddr + 3) ? TextureWord3
                                                                                          : texture_word_for_addr(physical_word_addr);
      endcase
    end
  endfunction

  task automatic program_texture_lut;
    begin
      @(negedge clk);
      lut_addr_wr_en <= 1'b1;
      lut_size_wr_en <= 1'b0;
      lut_wr_addr <= TextureSlot[6:0];
      lut_wr_data <= TextureBaseWordAddr;

      @(negedge clk);
      lut_addr_wr_en <= 1'b0;
      lut_size_wr_en <= 1'b1;
      lut_wr_addr <= TextureSlot[6:0];
      lut_wr_data <= {28'd0, TextureSizeLog2};

      @(negedge clk);
      lut_addr_wr_en <= 1'b0;
      lut_size_wr_en <= 1'b0;
      lut_wr_addr <= '0;
      lut_wr_data <= '0;
    end
  endtask

  task automatic init_axi_texture_mem;
    int beat;
    begin
      for (beat = 0; beat < (1 << (AXI_ADDR_WIDTH - $clog2(AXI_STRB_WIDTH))); beat++) begin
        u_axi_ram.mem[beat] = {
            texture_word_for_addr((beat * 4) + 3),
            texture_word_for_addr((beat * 4) + 2),
            texture_word_for_addr((beat * 4) + 1),
            texture_word_for_addr(beat * 4)
        };
      end

      u_axi_ram.mem[TextureMemBaseBeat] = {TextureWord3, TextureWord2, TextureWord1, TextureWord0};
    end
  endtask

  task automatic init_zbuffer_mem;
    int idx;
    begin
      u_z_buffer_ram.zbuf_state = u_z_buffer_ram.ZBUF_READY;
      u_z_buffer_ram.scrub_addr = '0;
      u_z_buffer_ram.rd_addr_d1 = '0;
      u_z_buffer_ram.raw_bram_dout = ZDefault;
      for (idx = 0; idx < 3; idx++) begin
        u_z_buffer_ram.wr_en_q[idx] = 1'b0;
        u_z_buffer_ram.wr_addr_q[idx] = '0;
        u_z_buffer_ram.wr_din_q[idx] = '0;
      end
      for (idx = 0; idx < ZBUF_DEPTH; idx++) begin
        u_z_buffer_ram.gen_behav_ram.mem[idx] = ZDefault;
      end
    end
  endtask

  task automatic wait_cycles(input int cycles);
    int i;
    begin
      for (i = 0; i < cycles; i++) begin
        @(posedge clk);
      end
    end
  endtask

  task automatic build_token(output thread_data_in_t token,
                             input logic [PIXEL_ADDR_W_THREAD-1:0] pixel_addr);
    begin
      token = '0;
      token.addr = pixel_addr;
      token.tex_id = TextureSlot[6:0];
      token.texture_mode_u = TEXTURE_CLAMP;
      token.texture_mode_v = TEXTURE_CLAMP;
      token.texture_function = REPLACE;
      token.inv_area = fbits(1.0);
      token.e0 = fbits(1.0);
      token.e1 = fbits(0.0);
      token.e2 = fbits(0.0);
      token.v0_u = to_uq5_13(0.0);
      token.v1_u = to_uq5_13(0.0);
      token.v2_u = to_uq5_13(0.0);
      token.v0_v = to_uq5_13(0.0);
      token.v1_v = to_uq5_13(0.0);
      token.v2_v = to_uq5_13(0.0);
      token.v0_w = fbits(1.0);
      token.v1_w = fbits(1.0);
      token.v2_w = fbits(1.0);
      token.v0_z = ZNear;
      token.v1_z = ZNear;
      token.v2_z = ZNear;
      token.v0_color.a = 8'hFF;
      token.v0_color.r = 8'hFF;
      token.v0_color.g = 8'hFF;
      token.v0_color.b = 8'hFF;
      token.v1_color.a = 8'hFF;
      token.v1_color.r = 8'hFF;
      token.v1_color.g = 8'hFF;
      token.v1_color.b = 8'hFF;
      token.v2_color.a = 8'hFF;
      token.v2_color.r = 8'hFF;
      token.v2_color.g = 8'hFF;
      token.v2_color.b = 8'hFF;
    end
  endtask

  task automatic send_tokens_when_ready(input thread_data_in_t token0,
                                        input thread_data_in_t token1);
    int sent;
    int cycles;
    begin
      sent = 0;
      cycles = 0;
      while (sent < 2) begin
        @(negedge clk);
        if (ready_out) begin
          in_data <= (sent == 0) ? token0 : token1;
          valid_in <= 1'b1;
          sent = sent + 1;
          cycles = 0;
        end else begin
          valid_in <= 1'b0;
          in_data <= '0;
          cycles++;
          if (cycles > MaxWaitCycles) begin
            $display("[ERR] timeout waiting for ready_out during burst submit (sent=%0d)", sent);
            err_count = err_count + 1;
            disable send_tokens_when_ready;
          end
        end
      end
      @(negedge clk);
      valid_in <= 1'b0;
      in_data <= '0;
    end
  endtask

  task automatic send_token_when_ready(input thread_data_in_t token);
    int cycles;
    begin
      cycles = 0;
      while (1) begin
        @(negedge clk);
        if (ready_out) begin
          in_data <= token;
          valid_in <= 1'b1;
          break;
        end else begin
          cycles++;
          if (cycles > MaxWaitCycles) begin
            $display("[ERR] timeout waiting for ready_out during single submit");
            err_count = err_count + 1;
            disable send_token_when_ready;
          end
        end
      end

      @(negedge clk);
      valid_in <= 1'b0;
      in_data <= '0;
    end
  endtask

  task automatic wait_for_fb_write(input logic [PIXEL_ADDR_W_THREAD-1:0] expected_addr,
                                   input logic [31:0] expected_color,
                                   input string label);
    int cycles;
    begin
      cycles = 0;
      while (!(out_fb_valid === 1'b1 && out_fb_we === 1'b1)) begin
        @(posedge clk);
        cycles++;
        if (cycles > MaxWaitCycles) begin
          $display("[ERR] timeout waiting for out_fb_we (%s)", label);
          err_count = err_count + 1;
          disable wait_for_fb_write;
        end
      end

      if (out_fb_addr !== expected_addr) begin
        $display("[ERR] %s addr mismatch exp=%0d got=%0d", label, expected_addr, out_fb_addr);
        err_count = err_count + 1;
      end
      if (out_fb_color !== expected_color) begin
        $display("[ERR] %s color mismatch exp=%08h got=%08h", label, expected_color, out_fb_color);
        err_count = err_count + 1;
      end
      @(posedge clk);
    end
  endtask

  task automatic wait_for_l1_request(input int previous_request_count,
                                     output logic [31:0] requested_word_addr,
                                     output logic [31:0] expected_color);
    int cycles;
    begin
      cycles = 0;
      while (l1_request_count == previous_request_count) begin
        @(posedge clk);
        cycles++;
        if (cycles > MaxWaitCycles) begin
          $display("[ERR] timeout waiting for L1 request");
          err_count = err_count + 1;
          disable wait_for_l1_request;
        end
      end
      requested_word_addr = last_l1_requested_word_addr;
      expected_color = last_l1_expected_color;
    end
  endtask

  initial begin
    thread_data_in_t token0;
    thread_data_in_t token1;
    int ar_count_after_first;
    int ar_count_before_refetch;
    int l1_request_count_before_send;
    int line_index;
    logic [31:0] requested_word_addr;
    logic [31:0] expected_color;

    err_count = 0;
    valid_in = 1'b0;
    in_data = '0;
    rst_n = 1'b0;
    lut_addr_wr_en = 1'b0;
    lut_size_wr_en = 1'b0;
    lut_wr_addr = '0;
    lut_wr_data = '0;

    init_zbuffer_mem();

    wait_cycles(4);
    rst_n = 1'b1;
    wait_cycles(4);
    init_axi_texture_mem();
    program_texture_lut();
    wait_cycles(2);

    build_token(token0, PIXEL_ADDR_W_THREAD'(0));
    build_token(token1, PIXEL_ADDR_W_THREAD'(0));
    token1.v0_u = to_uq5_13(1.0 / (1 << TextureSizeLog2));
    token1.v1_u = to_uq5_13(1.0 / (1 << TextureSizeLog2));
    token1.v2_u = to_uq5_13(1.0 / (1 << TextureSizeLog2));
    token1.v0_z = ZNearer;
    token1.v1_z = ZNearer;
    token1.v2_z = ZNearer;

    send_tokens_when_ready(token0, token1);
    wait_for_fb_write(PIXEL_ADDR_W_THREAD'(0), TextureWord0, "first token");

    if (ar_handshake_count != 1) begin
      $display("[ERR] expected exactly one AXI read after first token, got %0d", ar_handshake_count);
      err_count = err_count + 1;
    end
    if (tex_m_axi_araddr !== TextureBaseAddr) begin
      $display("[ERR] expected byte AXI base address %08h, got %08h",
               TextureBaseAddr, tex_m_axi_araddr);
      err_count = err_count + 1;
    end
    if (tex_m_axi_arsize !== $clog2(AXI_STRB_WIDTH)) begin
      $display("[ERR] expected %0d-byte AXI beats, got arsize=%0d",
               AXI_STRB_WIDTH, tex_m_axi_arsize);
      err_count = err_count + 1;
    end
    if (tex_m_axi_arlen !== BeatsPerLine - 1) begin
      $display("[ERR] expected %0d-beat cache line request, got arlen=%0d",
               BeatsPerLine, tex_m_axi_arlen + 1);
      err_count = err_count + 1;
    end
    ar_count_after_first = ar_handshake_count;

    wait_for_fb_write(PIXEL_ADDR_W_THREAD'(0), TextureWord1, "second token");

    if (ar_handshake_count != ar_count_after_first) begin
      $display("[ERR] expected cache hit on second token, AXI reads advanced from %0d to %0d",
               ar_count_after_first, ar_handshake_count);
      err_count = err_count + 1;
    end

    // Fill one more unique line than the 32-line cache can retain. Each
    // x coordinate advances by eight texels, which advances one 8x8 cache line.
    for (line_index = 1; line_index < CacheLineCount; line_index++) begin
      build_token(token0, PIXEL_ADDR_W_THREAD'(line_index));
      token0.v0_u = to_uq5_13((line_index * 8.0) / (1 << TextureSizeLog2));
      token0.v1_u = to_uq5_13((line_index * 8.0) / (1 << TextureSizeLog2));
      token0.v2_u = to_uq5_13((line_index * 8.0) / (1 << TextureSizeLog2));
      l1_request_count_before_send = l1_request_count;
      send_token_when_ready(token0);
      wait_for_l1_request(l1_request_count_before_send, requested_word_addr, expected_color);
      wait_for_fb_write(PIXEL_ADDR_W_THREAD'(line_index), expected_color, "line refill");
    end

    ar_count_before_refetch = ar_handshake_count;
    build_token(token0, PIXEL_ADDR_W_THREAD'(128));
    send_token_when_ready(token0);
    wait_for_fb_write(PIXEL_ADDR_W_THREAD'(128), TextureWord0, "evicted line refetch");

    if (ar_handshake_count != ar_count_before_refetch + 1) begin
      $display("[ERR] expected line-zero refetch after cache pressure, AXI reads %0d to %0d",
               ar_count_before_refetch, ar_handshake_count);
      err_count = err_count + 1;
    end

    if (accepted_count != CacheLineCount + 2) begin
      $display("[ERR] expected %0d accepted inputs, got %0d", CacheLineCount + 2, accepted_count);
      err_count = err_count + 1;
    end

    if (out_write_count != CacheLineCount + 2) begin
      $display("[ERR] expected %0d framebuffer writes, got %0d", CacheLineCount + 2, out_write_count);
      err_count = err_count + 1;
    end

    if (err_count == 0) begin
      $display("[PASS] thread_cache miss-then-hit test passed (axi_reads=%0d)", ar_handshake_count);
    end else begin
      $display("[FAIL] thread_cache test failed with %0d errors", err_count);
    end
    $finish;
  end

endmodule