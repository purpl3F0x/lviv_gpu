`timescale 1ns / 1ps

module tb_texture_address_generator;

  localparam int UvFracW = 12;
  localparam int MaxTexLog2 = 11;
  localparam int UvInFracW = 36;
  localparam int ScaledW = UvFracW + MaxTexLog2;
  localparam logic signed [47:0] UvOne = 48'sd1 <<< UvInFracW;
  localparam int PipelineLatency = 3;
  localparam logic [7:0] NoTextureId = 8'd128;

  typedef struct packed {
    logic [31:0] addr;
    logic        no_texture;
  } exp_t;

  logic clk;
  logic clken;

  logic [7:0] tex_idx;
  logic signed [47:0] u_in;
  logic signed [47:0] v_in;
  texture_address_mode_t texture_mode_u;
  texture_address_mode_t texture_mode_v;

  logic [31:0] addr_out;
  logic no_texture;

  logic        lut_addr_wr_en;
  logic        lut_size_wr_en;
  logic [ 6:0] lut_wr_addr;
  logic [31:0] lut_wr_data;

  logic [31:0] texture_lut_model[0:127];
  logic [3:0]  texture_size_lut_model[0:127];

  logic [31:0] exp_addr_q[$];
  logic        exp_no_tex_q[$];
  int err_count;
  int check_count;
  int cyc;

  texture_address_generator dut (
      .clk(clk),
      .clken(clken),
      .tex_idx(tex_idx),
      .u_in(u_in),
      .v_in(v_in),
      .texture_mode_u(texture_mode_u),
      .texture_mode_v(texture_mode_v),
      .addr_out(addr_out),
      .no_texture(no_texture),
      .lut_addr_wr_en(lut_addr_wr_en),
      .lut_size_wr_en(lut_size_wr_en),
      .lut_wr_addr(lut_wr_addr),
      .lut_wr_data(lut_wr_data)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    if ($test$plusargs("dump")) begin
      $dumpfile("waves.vcd");
      $dumpvars(0, tb_texture_address_generator);
    end
  end

  function automatic logic [UvFracW-1:0] normalize_uv_model(input logic signed [47:0] uv,
                                                             input texture_address_mode_t mode);
    logic [UvInFracW-1:0] frac_full;
    logic [UvFracW-1:0] frac_q;

    frac_full = uv[UvInFracW-1:0];
    frac_q = frac_full[UvInFracW-1 -: UvFracW];

    unique case (mode)
      TEXTURE_TILE: begin
        normalize_uv_model = frac_q;
      end
      TEXTURE_CLAMP: begin
        if (uv <= 48'sd0) begin
          normalize_uv_model = '0;
        end else if (uv >= UvOne) begin
          normalize_uv_model = '1;
        end else begin
          normalize_uv_model = frac_q;
        end
      end
    endcase
  endfunction

  function automatic exp_t model_addr(input logic [7:0] idx,
                                      input logic signed [47:0] u,
                                      input logic signed [47:0] v,
                                      input texture_address_mode_t mode_u,
                                      input texture_address_mode_t mode_v);
    exp_t e;
    logic [3:0] tex_size;
    logic [UvFracW-1:0] u_norm;
    logic [UvFracW-1:0] v_norm;
    logic [ScaledW-1:0] x_scaled;
    logic [ScaledW-1:0] y_scaled;
    logic [MaxTexLog2-1:0] max_idx;
    logic [MaxTexLog2-1:0] x_idx_raw;
    logic [MaxTexLog2-1:0] y_idx_raw;
    logic [MaxTexLog2-1:0] x_idx;
    logic [MaxTexLog2-1:0] y_idx;
    logic [31:0] swz;
    int bit_idx;

    tex_size = texture_size_lut_model[idx[6:0]];
    u_norm = normalize_uv_model(u, mode_u);
    v_norm = normalize_uv_model(v, mode_v);

    if (!idx[7]) begin
      x_scaled = {{MaxTexLog2{1'b0}}, u_norm} << tex_size;
      y_scaled = {{MaxTexLog2{1'b0}}, v_norm} << tex_size;
      max_idx = ({{(MaxTexLog2-1){1'b0}}, 1'b1} << tex_size) - 1'b1;
      e.no_texture = 1'b0;
    end else begin
      x_scaled = '0;
      y_scaled = '0;
      max_idx = '0;
      e.no_texture = 1'b1;
    end

    x_idx_raw = x_scaled[ScaledW-1:UvFracW];
    y_idx_raw = y_scaled[ScaledW-1:UvFracW];

    if (x_idx_raw > max_idx) begin
      x_idx = max_idx;
    end else begin
      x_idx = x_idx_raw;
    end

    if (y_idx_raw > max_idx) begin
      y_idx = max_idx;
    end else begin
      y_idx = y_idx_raw;
    end

    swz = 32'd0;
    for (bit_idx = 0; bit_idx < MaxTexLog2; bit_idx++) begin
      swz[(2*bit_idx)] = x_idx[bit_idx];
      swz[(2*bit_idx)+1] = y_idx[bit_idx];
    end

    // DUT now ORs the word-addressed swizzle directly with a word-addressed LUT base.
    e.addr = texture_lut_model[idx[6:0]] | swz;
    return e;
  endfunction

  task automatic drive_input(input logic [7:0] idx,
                             input logic signed [47:0] u,
                             input logic signed [47:0] v,
                             input texture_address_mode_t mode_u,
                             input texture_address_mode_t mode_v);
    exp_t e;
    begin
      @(negedge clk);
      tex_idx = idx;
      u_in = u;
      v_in = v;
      texture_mode_u = mode_u;
      texture_mode_v = mode_v;

      e = model_addr(idx, u, v, mode_u, mode_v);
      exp_addr_q.push_back(e.addr);
      exp_no_tex_q.push_back(e.no_texture);
    end
  endtask

  task automatic write_lut_addr(input logic [6:0] idx, input logic [31:0] addr);
    begin
      @(negedge clk);
      lut_wr_addr = idx;
      lut_wr_data = addr;
      lut_addr_wr_en = 1'b1;
      lut_size_wr_en = 1'b0;
      texture_lut_model[idx] = addr;
      @(negedge clk);
      lut_addr_wr_en = 1'b0;
      lut_wr_data = '0;
    end
  endtask

  task automatic write_lut_size(input logic [6:0] idx, input logic [3:0] sz);
    begin
      @(negedge clk);
      lut_wr_addr = idx;
      lut_wr_data = {28'd0, sz};
      lut_addr_wr_en = 1'b0;
      lut_size_wr_en = 1'b1;
      texture_size_lut_model[idx] = sz;
      @(negedge clk);
      lut_size_wr_en = 1'b0;
      lut_wr_data = '0;
    end
  endtask

  always_ff @(posedge clk) begin
    if (clken) begin
      cyc <= cyc + 1;
      if (exp_addr_q.size() > PipelineLatency) begin
        logic [31:0] exp_addr;
        logic exp_no_texture;

        exp_addr = exp_addr_q.pop_front();
        exp_no_texture = exp_no_tex_q.pop_front();
        check_count <= check_count + 1;
        if ((addr_out !== exp_addr) || (no_texture !== exp_no_texture)) begin
          $display("[ERR] cyc=%0d exp_addr=%08h got_addr=%08h exp_no_tex=%0d got_no_tex=%0d",
                   cyc, exp_addr, addr_out, exp_no_texture, no_texture);
          err_count <= err_count + 1;
        end
      end
    end
  end

  initial begin : main
    int i;

    clken = 1'b1;
    tex_idx = '0;
    u_in = '0;
    v_in = '0;
    texture_mode_u = TEXTURE_CLAMP;
    texture_mode_v = TEXTURE_CLAMP;
    lut_addr_wr_en = 1'b0;
    lut_size_wr_en = 1'b0;
    lut_wr_addr = '0;
    lut_wr_data = '0;
    err_count = 0;
    check_count = 0;
    cyc = 0;

    for (i = 0; i < 128; i++) begin
      texture_lut_model[i] = 32'd0;
      texture_size_lut_model[i] = 4'd15; // invalid until programmed
    end

    repeat (4) @(negedge clk);

    // Program LUT entries (base aligned in swizzle field).
    write_lut_addr(7'd3, 32'h0400_0000);
    write_lut_size(7'd3, 4'd10); // 1024

    write_lut_addr(7'd4, 32'h0800_0000);
    write_lut_size(7'd4, 4'd11); // 2048

    write_lut_addr(7'd5, 32'h0C00_0000);
    write_lut_size(7'd5, 4'd12); // oversized but real id -> no longer no_texture

    // Clamp mode checks (edge and in-range).
    drive_input(7'd3, 48'sd0, 48'sd0, TEXTURE_CLAMP, TEXTURE_CLAMP);
    drive_input(7'd3, (48'sd1 <<< 36) >>> 1, (48'sd1 <<< 36) >>> 2, TEXTURE_CLAMP, TEXTURE_CLAMP);
    drive_input(7'd3, 48'sd1 <<< 36, 48'sd1 <<< 36, TEXTURE_CLAMP, TEXTURE_CLAMP);
    drive_input(7'd3, -((48'sd1 <<< 36) >>> 2), 48'sd0, TEXTURE_CLAMP, TEXTURE_CLAMP);

    // Tile mode checks (negative and >1 wrap).
    drive_input(7'd4, -((48'sd1 <<< 36) >>> 2), ((48'sd1 <<< 36) + ((48'sd1 <<< 36) >>> 2)),
                TEXTURE_TILE, TEXTURE_TILE);
    drive_input(7'd4, (48'sd1 <<< 36) + ((48'sd1 <<< 36) >>> 1), (48'sd1 <<< 36) >>> 1,
                TEXTURE_TILE, TEXTURE_TILE);

    // Separate modes per axis.
    drive_input(7'd4, 48'sd1 <<< 36, -((48'sd1 <<< 36) >>> 2), TEXTURE_CLAMP, TEXTURE_TILE);
    drive_input(7'd4, -((48'sd1 <<< 36) >>> 2), 48'sd1 <<< 36, TEXTURE_TILE, TEXTURE_CLAMP);

    // Oversized size on a real id is no longer treated as no_texture.
    drive_input(7'd5, 48'sd0, 48'sd0, TEXTURE_CLAMP, TEXTURE_CLAMP);

    // Any idx with the MSB set produces no_texture now, not just a single sentinel.
    drive_input(8'd128, 48'sd0, 48'sd0, TEXTURE_CLAMP, TEXTURE_CLAMP);
    drive_input(8'd200, 48'sd0, 48'sd0, TEXTURE_CLAMP, TEXTURE_CLAMP);

    // Flush pipeline.
    repeat (8) begin
      drive_input(7'd3, 48'sd0, 48'sd0, TEXTURE_CLAMP, TEXTURE_CLAMP);
    end

    repeat (4) @(posedge clk);

    if (err_count == 0) begin
      $display("[TB PASS] texture_address_generator checks=%0d", check_count);
    end else begin
      $display("[TB FAIL] texture_address_generator errors=%0d checks=%0d", err_count, check_count);
    end

    $finish;
  end

endmodule
