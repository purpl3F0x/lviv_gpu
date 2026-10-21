`timescale 1ns / 1ps

import gpu_types_pkg::*;

// Self-checking testbench for one thread with the real Xilinx FP IP (run with Makefile.vivado).
//
//   1. clear the depth buffer over APB and wait for the scrub to finish
//   2. colour: covered and uncovered pixels on fresh addresses, untextured, blended with random
//      factors against a pre-filled tile buffer
//   3. depth: revisit the covered addresses with nearer or farther depth
//   4. texture: REPLACE and MODULATE through the L1 cache from an AXI RAM, wrap and clamp modes;
//      the texture spans 64 cache lines, so the 32-line cache also evicts
//
// A reference model predicts every depth-buffer write and every tile-buffer write. Results that
// depend on the floating-point interpolation are compared with a tolerance of a few LSBs; results
// built from texels only are compared exactly. Inside a phase every pixel address is used once:
// the thread does not forward between its depth read and write, nor between its tile-buffer read
// and write, so revisiting a pixel within a few cycles is outside what it supports.
module tb_thread;
  localparam int AddrW = PIXEL_ADDR_W_THREAD;
  localparam int Pixels = 1 << AddrW;
  localparam real ClkHalf = 0.75;  // 1.5 ns thread clock
  localparam real ApbHalf = 5.0;  // 100 MHz APB clock

  localparam int ColourTokens = 300;
  localparam int TextureTokens = 400;
  localparam int ColourTol = 3;  // LSBs allowed where the result depends on interpolated colour

  // Texture 0: 64 x 64 texels at word address 4096, aligned to its 4^6-word footprint.
  localparam logic [6:0] TexId = 7'd0;
  localparam int TexLog2 = 6;
  localparam int TexSize = 1 << TexLog2;
  localparam int TexBaseWord = 4096;
  localparam int AxiAddrW = 16;  // 64 KiB of texture memory
  localparam int AxiBeats = 1 << (AxiAddrW - 4);

  localparam logic [7:0] RegBusy = 8'h00, RegZbufClear = 8'h04;

  // -------------------------------------------------------------------------
  // Clocks, DUT and environment
  // -------------------------------------------------------------------------

  logic clk = 1'b0, apb_clk = 1'b0;
  logic rst_n = 1'b0, apb_rst_n = 1'b0;
  always #(ClkHalf) clk = ~clk;
  always #(ApbHalf) apb_clk = ~apb_clk;

  logic valid_in, ready_out, empty, zbuf_ready;
  thread_data_in_t in_data;

  logic [31:0] out_fb_color;
  logic [AddrW-1:0] out_fb_addr, out_fb_rd_addr;
  logic out_fb_valid, out_fb_we, out_fb_rd_en;
  color_argb_t in_fb_rd_color;

  logic [7:0] s_apb_PADDR;
  logic [0:0] s_apb_PSEL;
  logic s_apb_PENABLE, s_apb_PREADY, s_apb_PWRITE, s_apb_PSLVERROR;
  logic [31:0] s_apb_PWDATA, s_apb_PRDATA;

  logic [31:0] tex_m_axi_araddr;
  logic [7:0] tex_m_axi_arlen;
  logic [2:0] tex_m_axi_arsize;
  logic [1:0] tex_m_axi_arburst;
  logic tex_m_axi_arvalid, tex_m_axi_arready;
  logic [127:0] tex_m_axi_rdata;
  logic [1:0] tex_m_axi_rresp;
  logic tex_m_axi_rvalid, tex_m_axi_rready, tex_m_axi_rlast;

  logic [6:0] lut_addr;
  logic [31:0] lut_base;
  logic [3:0] lut_size;

  thread dut (
      .clk(clk),
      .rst_n(rst_n),
      .valid_in(valid_in),
      .ready_out(ready_out),
      .in_data(in_data),
      .empty(empty),
      .out_fb_color(out_fb_color),
      .out_fb_addr(out_fb_addr),
      .out_fb_valid(out_fb_valid),
      .out_fb_we(out_fb_we),
      .out_fb_rd_en(out_fb_rd_en),
      .out_fb_rd_addr(out_fb_rd_addr),
      .in_fb_rd_color(in_fb_rd_color),
      .apb_clk(apb_clk),
      .apb_rst_n(apb_rst_n),
      .s_apb_PADDR(s_apb_PADDR),
      .s_apb_PSEL(s_apb_PSEL),
      .s_apb_PENABLE(s_apb_PENABLE),
      .s_apb_PREADY(s_apb_PREADY),
      .s_apb_PWRITE(s_apb_PWRITE),
      .s_apb_PWDATA(s_apb_PWDATA),
      .s_apb_PRDATA(s_apb_PRDATA),
      .s_apb_PSLVERROR(s_apb_PSLVERROR),
      .zbuf_ready(zbuf_ready),
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
      .lut_addr(lut_addr),
      .lut_base(lut_base),
      .lut_size(lut_size)
  );

  // Texture descriptor table: only texture 0 is defined (asynchronous read, like the LUTRAM).
  assign lut_base = (lut_addr == TexId) ? 32'(TexBaseWord) : 32'd0;
  assign lut_size = (lut_addr == TexId) ? 4'(TexLog2) : 4'd0;

  // Texture memory.
  logic [1:0] axi_bresp_unused;
  logic axi_bvalid_unused;
  logic [0:0] axi_bid_unused, axi_rid_unused;

  axi_ram #(
      .DATA_WIDTH(128),
      .ADDR_WIDTH(AxiAddrW),
      .ID_WIDTH(1),
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
      .s_axi_araddr(tex_m_axi_araddr[AxiAddrW-1:0]),
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

  // -------------------------------------------------------------------------
  // Reference model
  // -------------------------------------------------------------------------

  // Packed, and without reals, so that Icarus accepts it too.
  typedef struct packed {
    logic [AddrW-1:0] addr;
    logic pass;          // depth test result
    fragment_op_t op;    // texture function the shader applies
    color_argb_t cf;     // interpolated vertex colour
    color_argb_t texel;
    blend_op_t sf;
    blend_op_t df;
    logic [7:0] tol;
  } frag_t;

  logic [$bits(frag_t)-1:0] frag_q[$];  // frag_t, stored as bits: Icarus has no struct queues
  logic [AddrW-1:0] depth_addr_q[$];  // expected depth writes, address and value
  real depth_z_q[$];
  real z_model[Pixels];
  color_argb_t fb_mem[Pixels];
  bit line_touched[(TexBaseWord + TexSize * TexSize) / 64];

  int errors, accepted, fragments, fb_writes, depth_writes, depth_fails, lines_touched;
  int l1_expected, l1_requests, ar_bursts, max_colour_err;
  logic [AddrW-1:0] colour_addrs[$];

  function automatic void error(input string msg);
    errors++;
    if (errors <= 20) $display("[%0t] ERROR: %s", $time, msg);
  endfunction

  function automatic real fr(input logic [31:0] bits);
    return $bitstoshortreal(bits);
  endfunction

  function automatic logic [31:0] fbits(input real value);
    shortreal s;
    s = value;
    return $shortrealtobits(s);
  endfunction

  function automatic logic [AddrW-1:0] addr_of(input int index);
    return AddrW'(index * 37 + 5);  // a permutation of the 4096 pixel addresses
  endfunction

  // Normalised 8-bit product, (a * b + 128) / 256, as in the shader and blend unit.
  function automatic logic [7:0] mul8(input logic [7:0] a, input logic [7:0] b);
    return 8'((16'(a) * 16'(b) + 16'd128) >> 8);
  endfunction

  function automatic color_argb_t shade(input fragment_op_t op, input color_argb_t cf,
                                        input color_argb_t ct);
    logic [31:0] f, t, result;
    f = cf;
    t = ct;
    case (op)
      REPLACE: result = t;
      MODULATE: for (int b = 0; b < 4; b++) result[8*b+:8] = mul8(f[8*b+:8], t[8*b+:8]);
      default: result = f;  // COLOR
    endcase
    return result;
  endfunction

  function automatic logic [31:0] blend_coeff(input blend_op_t op, input logic [31:0] s,
                                              input logic [31:0] d, input logic [31:0] dflt);
    case (op)
      ZERO: return 32'h0;
      ONE: return 32'hFFFF_FFFF;
      SRC_COLOR: return s;
      ONE_MINUS_SRC_COLOR: return ~s;
      DST_COLOR: return d;
      ONE_MINUS_DST_COLOR: return ~d;
      SRC_ALPHA: return {4{s[31:24]}};
      ONE_MINUS_SRC_ALPHA: return {4{~s[31:24]}};
      DST_ALPHA: return {4{d[31:24]}};
      ONE_MINUS_DST_ALPHA: return {4{~d[31:24]}};
      default: return dflt;
    endcase
  endfunction

  function automatic color_argb_t blend(input blend_op_t sf, input blend_op_t df,
                                        input color_argb_t src, input color_argb_t dst);
    logic [31:0] s, d, s_coeff, d_coeff, result;
    int sum;
    s = src;
    d = dst;
    s_coeff = blend_coeff(sf, s, d, 32'hFFFF_FFFF);
    d_coeff = blend_coeff(df, s, d, 32'h0);
    for (int b = 0; b < 4; b++) begin
      sum = int'(s[8*b+:8]) * int'(s_coeff[8*b+:8]) + 128 + int'(d[8*b+:8]) * int'(d_coeff[8*b+:8]);
      result[8*b+:8] = (sum >= 65536) ? 8'hFF : 8'(sum >> 8);
    end
    return result;
  endfunction

  function automatic logic [31:0] texel_value(input int word);
    logic [31:0] h;
    h = 32'(word) * 32'h9E37_79B1;
    return h ^ (h >> 15);
  endfunction

  function automatic int morton(input int x, input int y);
    int m;
    m = 0;
    for (int b = 0; b < TexLog2; b++) begin
      m |= ((x >> b) & 1) << (2 * b);
      m |= ((y >> b) & 1) << (2 * b + 1);
    end
    return m;
  endfunction

  // A random triangle seen from one pixel. Uncovered pixels get one negative edge value.
  function automatic thread_data_in_t random_pixel(input logic [AddrW-1:0] addr, input bit covered,
                                                   input real z);
    thread_data_in_t tok;
    real lam[3], inv_area, r0, r1;
    tok = '0;
    r0 = $urandom_range(0, 1000) / 1000.0;
    r1 = $urandom_range(0, 1000) / 1000.0;
    if (r0 + r1 > 1.0) begin
      r0 = 1.0 - r0;
      r1 = 1.0 - r1;
    end
    lam[0] = r0;
    lam[1] = r1;
    lam[2] = 1.0 - r0 - r1;
    if (lam[2] < 0.0) lam[2] = 0.0;  // rounding must not turn a zero weight negative
    if (!covered) lam[$urandom_range(0, 2)] = -($urandom_range(1, 500) / 1000.0);
    inv_area = $urandom_range(100, 2000) / 1000.0;

    tok.addr = addr;
    tok.inv_area = fbits(inv_area);
    tok.e0 = fbits(lam[0] / inv_area);
    tok.e1 = fbits(lam[1] / inv_area);
    tok.e2 = fbits(lam[2] / inv_area);
    tok.v0_z = fbits(z);
    tok.v1_z = fbits(z);
    tok.v2_z = fbits(z);
    tok.v0_w = fbits($urandom_range(100, 2000) / 1000.0);
    tok.v1_w = fbits($urandom_range(100, 2000) / 1000.0);
    tok.v2_w = fbits($urandom_range(100, 2000) / 1000.0);
    tok.v0_color = $urandom();
    tok.v1_color = $urandom();
    tok.v2_color = $urandom();
    tok.tex_id = 8'h80;
    tok.texture_function = COLOR;
    tok.texture_mode_u = TEXTURE_TILE;
    tok.texture_mode_v = TEXTURE_TILE;
    tok.sfactor_op = ONE;
    tok.dfactor_op = ZERO;
    tok.depth_func = DEPTH_LESS;
    return tok;
  endfunction

  // Depth test model: func is a mask of the {gt, eq, lt} results that pass.
  function automatic bit depth_pass(input depth_func_t func, input real z, input real stored);
    return (func[0] && z < stored) || (func[1] && z == stored) || (func[2] && z > stored);
  endfunction

  task automatic random_blend(inout thread_data_in_t tok);
    case ($urandom_range(0, 3))
      0: begin
        tok.sfactor_op = ONE;
        tok.dfactor_op = ZERO;
      end
      1: begin
        tok.sfactor_op = SRC_ALPHA;
        tok.dfactor_op = ONE_MINUS_SRC_ALPHA;
      end
      2: begin
        tok.sfactor_op = ONE;
        tok.dfactor_op = ONE;
      end
      default: begin
        tok.sfactor_op = DST_COLOR;
        tok.dfactor_op = ZERO;
      end
    endcase
  endtask

  // fx 5.13 texture coordinate for a random texel under `mode`, and the texel index it must fetch.
  // Coordinates sit on texel centres, or clearly outside [0, 1) to exercise wrap and clamp.
  task automatic random_coord(input texture_address_mode_t mode, output logic [17:0] raw,
                              output int index);
    int centre, pick;
    index = $urandom_range(0, TexSize - 1);
    centre = index * (8192 / TexSize) + (8192 / TexSize) / 2;
    pick = $urandom_range(0, 3);
    if (mode == TEXTURE_TILE) begin
      raw = 18'(centre + (pick - 1) * 8192);  // shifted by -1 to +2 whole repeats
    end else begin
      case (pick)
        0: begin
          raw = 18'(-2048);  // -0.25 clamps to the first texel
          index = 0;
        end
        1: begin
          raw = 18'(8192 + 2048);  // 1.25 clamps to the last texel
          index = TexSize - 1;
        end
        default: raw = 18'(centre);
      endcase
    end
  endtask

  // Predicts the thread's depth write and tile-buffer output for a covered pixel, using the
  // screen-space weights lambda_i and the perspective-correct weights t_i as the thread does.
  task automatic expect_fragment(input thread_data_in_t tok, input bit textured,
                                 input logic [31:0] texel, input int tol);
    real e[3], q[3], lam[3], t[3], q_sum, w, z, acc;
    logic [31:0] c[3];
    logic [31:0] cf;
    int value;
    frag_t f;
    e[0] = fr(tok.e0);
    e[1] = fr(tok.e1);
    e[2] = fr(tok.e2);
    q[0] = fr(tok.v0_w);
    q[1] = fr(tok.v1_w);
    q[2] = fr(tok.v2_w);
    c[0] = tok.v0_color;
    c[1] = tok.v1_color;
    c[2] = tok.v2_color;
    q_sum = 0.0;
    for (int i = 0; i < 3; i++) begin
      lam[i] = e[i] * fr(tok.inv_area);
      q_sum += q[i] * lam[i];
    end
    w = 1.0 / q_sum;
    for (int i = 0; i < 3; i++) t[i] = w * q[i] * lam[i];
    for (int b = 0; b < 4; b++) begin
      acc = 0.0;
      for (int i = 0; i < 3; i++) acc += t[i] * c[i][8*b+:8];
      value = int'($floor(acc + 0.5));
      cf[8*b+:8] = value > 255 ? 8'd255 : (value < 0 ? 8'd0 : 8'(value));
    end

    z = fr(tok.v0_z) * lam[0] + fr(tok.v1_z) * lam[1] + fr(tok.v2_z) * lam[2];
    f.addr = tok.addr;
    f.pass = depth_pass(depth_func_t'(tok.depth_func), z, z_model[tok.addr]);
    if (f.pass) begin
      z_model[tok.addr] = z;
      depth_addr_q.push_back(tok.addr);
      depth_z_q.push_back(z);
    end
    // Failed and untextured fragments never reach the cache; the shader applies COLOR to them.
    if (f.pass && textured) f.op = tok.texture_function;
    else f.op = COLOR;
    if (f.op != COLOR) l1_expected++;
    f.cf = cf;
    f.texel = texel;
    f.sf = blend_op_t'(tok.sfactor_op);
    f.df = blend_op_t'(tok.dfactor_op);
    f.tol = tol;
    frag_q.push_back(f);
  endtask

  // -------------------------------------------------------------------------
  // Drivers
  // -------------------------------------------------------------------------

  function automatic void report_stall(input string where);
    $display("[%0t] %s: accepted %0d, fragments %0d, queued %0d/%0d", $time, where, accepted,
             fragments, frag_q.size(), depth_addr_q.size());
    $display("  ready_out %b pipe_en %b out_bundle v/r %b/%b req_ready %b tex_wait %b l1_ready %b",
             ready_out, dut.pipe_en_internal, dut.output_bundle_buf_tvalid,
             dut.output_bundle_buf_tready, dut.fragment_request_input_ready,
             dut.delayed_texture_wait, dut.l1_cache_req_ready);
  endfunction

  task automatic send(input thread_data_in_t tok);
    int cycles;
    in_data  <= tok;
    valid_in <= 1'b1;
    cycles = 0;
    do begin
      @(posedge clk);
      if (++cycles > 5000) begin
        report_stall("send");
        $fatal(1, "thread input stalled for %0d cycles", cycles);
      end
    end while (!ready_out);
    valid_in <= 1'b0;
    accepted++;
  endtask

  task automatic apb_write(input logic [7:0] addr, input logic [31:0] data);
    @(posedge apb_clk);
    s_apb_PADDR <= addr;
    s_apb_PWDATA <= data;
    s_apb_PWRITE <= 1'b1;
    s_apb_PSEL <= 1'b1;
    s_apb_PENABLE <= 1'b0;
    @(posedge apb_clk);
    s_apb_PENABLE <= 1'b1;
    @(posedge apb_clk);
    s_apb_PSEL <= 1'b0;
    s_apb_PENABLE <= 1'b0;
    s_apb_PWRITE <= 1'b0;
  endtask

  task automatic apb_read(input logic [7:0] addr, output logic [31:0] data);
    @(posedge apb_clk);
    s_apb_PADDR <= addr;
    s_apb_PWRITE <= 1'b0;
    s_apb_PSEL <= 1'b1;
    s_apb_PENABLE <= 1'b0;
    @(posedge apb_clk);
    s_apb_PENABLE <= 1'b1;
    @(negedge apb_clk);
    data = s_apb_PRDATA;
    if (s_apb_PSLVERROR) error($sformatf("APB read of 0x%02h returned an error", addr));
    @(posedge apb_clk);
    s_apb_PSEL <= 1'b0;
    s_apb_PENABLE <= 1'b0;
  endtask

  task automatic clear_zbuffer();
    logic [31:0] data;
    int polls;
    apb_write(RegZbufClear, 32'h1);
    polls = 0;
    while (zbuf_ready !== 1'b0) begin
      @(posedge clk);
      if (++polls > 1000) $fatal(1, "z-buffer clear never started");
    end
    repeat (5) @(posedge apb_clk);
    polls = 0;
    do begin
      apb_read(RegZbufClear, data);
      if (++polls > 2000) $fatal(1, "z-buffer clear never finished");
    end while (data[0] !== 1'b0);
    if (zbuf_ready !== 1'b1) error("zbuf_ready low after the APB clear-busy bit cleared");
  endtask

  task automatic drain(input string phase);
    logic [31:0] data;
    int cycles;
    cycles = 0;
    while (frag_q.size() != 0 || depth_addr_q.size() != 0 || empty !== 1'b1) begin
      @(posedge clk);
      if (++cycles > 50000) begin
        report_stall(phase);
        $fatal(1, "%s: drain timeout", phase);
      end
    end
    repeat (100) @(posedge clk);
    if (frag_q.size() != 0 || depth_addr_q.size() != 0)
      error($sformatf("%s: late outputs", phase));
    apb_read(RegBusy, data);
    if (data[0] !== 1'b0) error($sformatf("%s: APB busy bit still set after drain", phase));
    $display("[%0t] %s phase done: %0d pixels accepted, %0d fragments, %0d errors", $time, phase,
             accepted, fragments, errors);
  endtask

  // -------------------------------------------------------------------------
  // Phases
  // -------------------------------------------------------------------------

  task automatic phase_colour();
    thread_data_in_t tok;
    bit covered;
    for (int i = 0; i < ColourTokens; i++) begin
      covered = $urandom_range(0, 99) >= 15;
      tok = random_pixel(addr_of(i), covered, $urandom_range(100, 900) / 1000.0);
      // Untextured either way: no texture id, or a texture with the COLOR function.
      if ($urandom_range(0, 1)) tok.texture_function = fragment_op_t'($urandom_range(0, 5));
      else tok.tex_id = {1'b0, TexId};
      random_blend(tok);
      if (covered) begin
        expect_fragment(tok, 1'b0, 32'h0, ColourTol);
        colour_addrs.push_back(tok.addr);
      end
      send(tok);
    end
    drain("colour");
  endtask

  task automatic phase_depth();
    thread_data_in_t tok;
    logic [AddrW-1:0] addr;
    real z;
    for (int i = colour_addrs.size() - 1; i >= 0; i--) begin
      addr = colour_addrs[i];
      z = z_model[addr] + ($urandom_range(0, 1) ? 0.05 : -0.05);
      tok = random_pixel(addr, 1'b1, z);
      random_blend(tok);
      // Every depth function; z differs from the stored value by +-0.05, so lt / gt decide it.
      tok.depth_func = depth_func_t'($urandom_range(0, 7));
      expect_fragment(tok, 1'b0, 32'h0, ColourTol);
      send(tok);
    end
    drain("depth");
  endtask

  task automatic phase_texture();
    thread_data_in_t tok;
    logic [17:0] u, v;
    int x, y, word;
    for (int i = 0; i < TextureTokens; i++) begin
      tok = random_pixel(addr_of(ColourTokens + i), 1'b1, $urandom_range(100, 900) / 1000.0);
      tok.tex_id = {1'b0, TexId};
      if ($urandom_range(0, 1)) tok.texture_function = REPLACE;
      else tok.texture_function = MODULATE;
      tok.texture_mode_u = texture_address_mode_t'($urandom_range(0, 1));
      tok.texture_mode_v = texture_address_mode_t'($urandom_range(0, 1));
      random_coord(tok.texture_mode_u, u, x);
      random_coord(tok.texture_mode_v, v, y);
      // Equal coordinates on all vertices: the interpolated value is the coordinate itself.
      tok.v0_u = u;
      tok.v1_u = u;
      tok.v2_u = u;
      tok.v0_v = v;
      tok.v1_v = v;
      tok.v2_v = v;
      random_blend(tok);
      word = TexBaseWord | morton(x, y);
      if (!line_touched[word>>6]) lines_touched++;
      line_touched[word>>6] = 1'b1;
      expect_fragment(tok, 1'b1, texel_value(word),
                      tok.texture_function == REPLACE ? 0 : ColourTol);
      send(tok);
    end
    drain("texture");
  endtask

  // -------------------------------------------------------------------------
  // Monitors
  // -------------------------------------------------------------------------

  // Interpolated colour of each fragment as it leaves the arithmetic pipeline, for error reports.
  logic [31:0] hw_cf_q[$];
  always @(posedge clk) begin
    if (rst_n && dut.output_bundle_buf_tvalid && dut.output_bundle_buf_tready)
      hw_cf_q.push_back(dut.post_skid_bundle.color);
  end

  // Tile buffer: 4-cycle read latency, read-before-write; checks every fragment the thread emits.
  color_argb_t fb_rd_pipe[4];
  assign in_fb_rd_color = fb_rd_pipe[3];

  always @(posedge clk) begin
    frag_t f;
    fragment_op_t op;
    blend_op_t sf, df;
    logic [31:0] expected, got, hw_cf;
    int diff, worst;
    fb_rd_pipe[0] <= out_fb_rd_en ? fb_mem[out_fb_rd_addr] : 'x;
    fb_rd_pipe[1] <= fb_rd_pipe[0];
    fb_rd_pipe[2] <= fb_rd_pipe[1];
    fb_rd_pipe[3] <= fb_rd_pipe[2];

    if (rst_n && out_fb_valid === 1'b1) begin
      fragments++;
      if (frag_q.size() == 0) begin
        error($sformatf("unexpected fragment at address %0d", out_fb_addr));
      end else begin
        f = frag_t'(frag_q.pop_front());
        op = f.op;
        sf = f.sf;
        df = f.df;
        hw_cf = hw_cf_q.size() != 0 ? hw_cf_q.pop_front() : 'x;
        if (out_fb_addr !== f.addr)
          error($sformatf("fragment address %0d, expected %0d", out_fb_addr, f.addr));
        if (out_fb_we !== f.pass)
          error($sformatf("write enable %b at address %0d, expected %b", out_fb_we, f.addr,
                          f.pass));
        if (f.pass) begin
          expected = blend(sf, df, shade(op, f.cf, f.texel), fb_mem[f.addr]);
          got = out_fb_color;
          worst = 0;
          for (int b = 0; b < 4; b++) begin
            diff = int'(got[8*b+:8]) - int'(expected[8*b+:8]);
            if (diff < 0) diff = -diff;
            if (diff > worst) worst = diff;
          end
          if (f.tol != 0 && worst > max_colour_err) max_colour_err = worst;
          if (worst > f.tol || $isunknown(got))
            error($sformatf({"colour 0x%08h at address %0d, expected 0x%08h (op %s, blend %s/%s, ",
                             "interpolated 0x%08h, model 0x%08h, dst 0x%08h)"},
                            got, f.addr, expected, op.name(), sf.name(), df.name(), hw_cf,
                            f.cf, fb_mem[f.addr]));
          fb_mem[f.addr] = got;
          fb_writes++;
        end
      end
    end else if (rst_n && out_fb_we === 1'b1) begin
      error("frame-buffer write enable without a valid fragment");
    end
  end

  // Depth-buffer writes, observed inside the thread.
  always @(posedge clk) begin
    logic [AddrW-1:0] addr;
    real z, got, tol;
    if (rst_n && dut.z_wr_en === 1'b1) begin
      depth_writes++;
      if (depth_addr_q.size() == 0) begin
        error($sformatf("unexpected depth write to %0d", dut.z_wr_addr));
      end else begin
        addr = depth_addr_q.pop_front();
        z = depth_z_q.pop_front();
        got = fr(dut.z_wr_data);
        tol = 1e-5 * (z > 1.0 ? z : 1.0);
        if (dut.z_wr_addr !== addr)
          error($sformatf("depth write to %0d, expected %0d", dut.z_wr_addr, addr));
        if (got - z > tol || z - got > tol)
          error($sformatf("depth %f written to %0d, expected %f", got, addr, z));
      end
    end
  end

  always @(posedge clk) begin
    if (rst_n) begin
      if (dut.l1_req_valid && dut.l1_cache_req_ready) l1_requests++;
      if (tex_m_axi_arvalid && tex_m_axi_arready) ar_bursts++;
    end
  end

  // -------------------------------------------------------------------------
  // Test sequence
  // -------------------------------------------------------------------------

  initial begin
    #300us;
    report_stall("global timeout");
    $fatal(1, "global timeout");
  end

  initial begin
    int seed, rng_seed, seed_given, unused;
    seed = 1;
    seed_given = $value$plusargs("SEED=%d", seed);
    rng_seed = seed;  // Icarus updates the argument of $urandom
    unused = $urandom(rng_seed);  // seeds this process, which drives every phase

    errors = 0;
    accepted = 0;
    fragments = 0;
    fb_writes = 0;
    depth_writes = 0;
    l1_expected = 0;
    l1_requests = 0;
    ar_bursts = 0;
    max_colour_err = 0;
    lines_touched = 0;
    valid_in = 1'b0;
    in_data = '0;
    s_apb_PADDR = '0;
    s_apb_PSEL = '0;
    s_apb_PENABLE = 1'b0;
    s_apb_PWRITE = 1'b0;
    s_apb_PWDATA = '0;
    for (int i = 0; i < Pixels; i++) begin
      z_model[i] = 1.0;  // the clear value
      fb_mem[i] = $urandom();
    end

    // After axi_ram's own initial block has zeroed its memory.
    #20;
    for (int beat = 0; beat < AxiBeats; beat++)
      u_axi_ram.mem[beat] = {
        texel_value(beat * 4 + 3), texel_value(beat * 4 + 2),
        texel_value(beat * 4 + 1), texel_value(beat * 4)
      };

    repeat (10) @(posedge apb_clk);
    apb_rst_n = 1'b1;
    rst_n = 1'b1;
    repeat (20) @(posedge clk);

    clear_zbuffer();
    $display("[%0t] depth buffer cleared", $time);
    phase_colour();
    phase_depth();
    phase_texture();

    depth_fails = fragments - fb_writes;
    if (l1_requests != l1_expected)
      error($sformatf("%0d L1 requests, expected %0d", l1_requests, l1_expected));
    if (ar_bursts < lines_touched)
      error($sformatf("%0d AXI bursts for %0d texture lines", ar_bursts, lines_touched));

    $display("Seed %0d: %0d pixels, %0d fragments, %0d tile writes, %0d depth fails",
             seed, accepted, fragments, fb_writes, depth_fails);
    $display("Depth writes %0d; L1 requests %0d, AXI bursts %0d, lines touched %0d",
             depth_writes, l1_requests, ar_bursts, lines_touched);
    $display("Max colour error %0d LSB", max_colour_err);
    if (errors) $fatal(1, "FAIL: %0d errors", errors);
    $display("PASS: thread");
    $finish;
  end

endmodule
