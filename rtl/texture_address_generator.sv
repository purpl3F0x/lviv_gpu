`timescale 1ns / 1ps

typedef enum logic {
  TEXTURE_CLAMP = 1'b0,
  TEXTURE_TILE  = 1'b1
} texture_address_mode_t;

module texture_address_generator (
    input logic clk,
    input logic clken,

    input logic [6:0] tex_idx,
    input logic signed [47:0] u_in,
    input logic signed [47:0] v_in,
    input texture_address_mode_t texture_mode_u,
    input texture_address_mode_t texture_mode_v,

    output logic [31:0] addr_out,
    output logic no_texture,

    // Texture LUT write interface
    input logic        lut_addr_wr_en,
    input logic        lut_size_wr_en,
    input logic [ 6:0] lut_wr_addr,
    input logic [31:0] lut_wr_data
);
  // Texture LUT: 128 entries of aligned base address and 4-bit size
  (* ramstyle = "distributed" *) reg [31:0] texture_lut[128];
  (* ramstyle = "distributed" *) reg [3:0] texture_size_lut[128];

  // Default all entries to "no texture" until software/testbench programs LUT.
  initial begin : init_texture_luts
    int i;
    for (i = 0; i < 128; i++) begin
      texture_lut[i] = 32'd0;
      texture_size_lut[i] = 4'hF;
    end
  end

  localparam int UvFracW = 12;
  localparam int MaxTexLog2 = 12;
  localparam int UvInFracW = 36;
  localparam int ScaledW = UvFracW + MaxTexLog2;
  localparam logic [3:0] MaxTexSizeLog2 = 4'd11;
  localparam logic signed [47:0] UvOne = 48'sd1 <<< UvInFracW;

  function automatic logic [UvFracW-1:0] normalize_uv(input logic signed [47:0] uv,
                                                      input texture_address_mode_t mode);
    logic [UvInFracW-1:0] frac_full;
    logic [  UvFracW-1:0] frac_q;

    frac_full = uv[UvInFracW-1:0];
    // Quantize 10.36 fraction to 0.12 by taking the most-significant fractional bits.
    frac_q = frac_full[UvInFracW-1-:UvFracW];

    unique case (mode)
      TEXTURE_TILE: begin
        normalize_uv = frac_q;
      end
      TEXTURE_CLAMP: begin
        if (uv <= 48'sd0) begin
          normalize_uv = '0;
        end else if (uv >= UvOne) begin
          normalize_uv = '1;
        end else begin
          normalize_uv = frac_q;
        end
      end
    endcase
  endfunction

  // *-------------------------------------------------------*
  // * Texture LUT write interface *
  // *-------------------------------------------------------*
  always_ff @(posedge clk) begin
    if (lut_addr_wr_en) begin
      texture_lut[lut_wr_addr] <= lut_wr_data;
    end else if (lut_size_wr_en) begin
      texture_size_lut[lut_wr_addr] <= lut_wr_data[3:0];
    end
  end

  // *-------------------------------------------------------*
  // * Stage 1: Fetch texture size and normalize UVs *
  // *-------------------------------------------------------*
  logic [3:0] texture_size;
  logic [6:0] tex_idx_s1;
  logic [UvFracW-1:0] u_norm_s1;
  logic [UvFracW-1:0] v_norm_s1;

  always_ff @(posedge clk) begin
    if (clken) begin
      texture_size <= texture_size_lut[tex_idx];
      tex_idx_s1 <= tex_idx;
      u_norm_s1 <= normalize_uv(u_in, texture_mode_u);
      v_norm_s1 <= normalize_uv(v_in, texture_mode_v);
    end
  end

  // *-------------------------------------------------------*
  // * Stage 2: Scale normalized UV and Check for No-Texture *
  // *-------------------------------------------------------*
  logic [ScaledW-1:0] x_scaled_comb, y_scaled_comb;
  logic [ScaledW-1:0] x_scaled, y_scaled;
  logic [MaxTexLog2-1:0] max_idx_comb;
  logic no_texture_s2_comb;
  logic no_texture_s2;
  logic [31:0] base_addr;
  logic [MaxTexLog2-1:0] max_idx_s2;

  always_comb begin
    if (texture_size <= MaxTexSizeLog2) begin
      x_scaled_comb = {{MaxTexLog2{1'b0}}, u_norm_s1} << texture_size;
      y_scaled_comb = {{MaxTexLog2{1'b0}}, v_norm_s1} << texture_size;
      max_idx_comb = ({{(MaxTexLog2 - 1) {1'b0}}, 1'b1} << texture_size) - 1'b1;
      no_texture_s2_comb = 1'b0;
    end else begin
      x_scaled_comb = '0;
      y_scaled_comb = '0;
      max_idx_comb = '0;
      no_texture_s2_comb = 1'b1;
    end
  end

  always_ff @(posedge clk) begin
    if (clken) begin
      base_addr <= texture_lut[tex_idx_s1];
      no_texture_s2 <= no_texture_s2_comb;
      x_scaled <= x_scaled_comb;
      y_scaled <= y_scaled_comb;
      max_idx_s2 <= max_idx_comb;
    end
  end

  // *-------------------------------------------------------*
  // * Stage 3: Merge with base address (aligned) *
  // *-------------------------------------------------------*
  logic [31:0] addr_out_comb, addr_out_swizzled;

  always_comb begin
    logic [MaxTexLog2-1:0] x_idx_raw, y_idx_raw;
    logic [MaxTexLog2-1:0] x_idx, y_idx;
    integer bit_idx;

    x_idx_raw = x_scaled[ScaledW-1:UvFracW];
    y_idx_raw = y_scaled[ScaledW-1:UvFracW];

    if (x_idx_raw > max_idx_s2) begin
      x_idx = max_idx_s2;
    end else begin
      x_idx = x_idx_raw;
    end

    if (y_idx_raw > max_idx_s2) begin
      y_idx = max_idx_s2;
    end else begin
      y_idx = y_idx_raw;
    end

    addr_out_swizzled = 32'd0;
    for (bit_idx = 0; bit_idx < MaxTexLog2; bit_idx++) begin
      addr_out_swizzled[(2*bit_idx)+2] = x_idx[bit_idx];
      addr_out_swizzled[(2*bit_idx)+3] = y_idx[bit_idx];
    end
  end

  assign addr_out_comb = base_addr | addr_out_swizzled;

  always_ff @(posedge clk) begin
    if (clken) begin
      addr_out   <= addr_out_comb;
      no_texture <= no_texture_s2;
    end
  end

endmodule
