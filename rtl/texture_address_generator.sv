`timescale 1ns / 1ps

import gpu_types_pkg::*;

module texture_address_generator (
    input logic clk,
    input logic clken,

    input logic [7:0] tex_idx,
    input logic signed [47:0] u_in,
    input logic signed [47:0] v_in,
    input texture_address_mode_t texture_mode_u,
    input texture_address_mode_t texture_mode_v,

    output logic [31:0] addr_out,
    output logic no_texture,

    // Texture LUT interface
    output logic [ 6:0] lut_addr,
    input  logic [31:0] lut_base,
    input  logic [ 3:0] lut_size
);


  localparam int UvFracW = 12;
  localparam int MaxTexLog2 = 11;
  localparam int UvInFracW = 36;
  localparam int ScaledW = UvFracW + MaxTexLog2;

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
        if (uv[47]) begin
          normalize_uv = '0;
        end else if (|uv[46:UvInFracW]) begin
          normalize_uv = '1;
        end else begin
          normalize_uv = frac_q;
        end
      end
    endcase
  endfunction

  logic [7:0] tex_idx_q;
  logic signed [47:0] u_in_q, v_in_q;
  texture_address_mode_t texture_mode_u_q, texture_mode_v_q;

  always_ff @(posedge clk) begin
    if (clken) begin
      tex_idx_q <= tex_idx;
      u_in_q <= u_in;
      v_in_q <= v_in;
      texture_mode_u_q <= texture_mode_u;
      texture_mode_v_q <= texture_mode_v;
    end
  end

  (* shreg_extract = "no" *)logic [31:0] lut_base_q;
  (* shreg_extract = "no" *)logic [ 3:0] lut_size_q;
  (* shreg_extract = "no" *)logic [ 7:0] tex_idx_lut_q;
  (* shreg_extract = "no" *) logic signed [47:0] u_lut_q, v_lut_q;
  (* shreg_extract = "no" *) texture_address_mode_t texture_mode_u_lut_q, texture_mode_v_lut_q;

  always_ff @(posedge clk) begin
    if (clken) begin
      lut_base_q <= lut_base;
      lut_size_q <= lut_size;
      tex_idx_lut_q <= tex_idx_q;
      u_lut_q <= u_in_q;
      v_lut_q <= v_in_q;
      texture_mode_u_lut_q <= texture_mode_u_q;
      texture_mode_v_lut_q <= texture_mode_v_q;
    end
  end

  // *-------------------------------------------------------*
  // * Stage 1: Capture buffered LUT data and normalize UVs *
  // *-------------------------------------------------------*
  logic [3:0] texture_size;
  logic [7:0] tex_idx_s1;
  logic [UvFracW-1:0] u_norm_s1;
  logic [UvFracW-1:0] v_norm_s1;
  (* shreg_extract = "no" *) logic [31:0] base_addr_s1;

  assign lut_addr = tex_idx_q[6:0];

  always_ff @(posedge clk) begin
    if (clken) begin
      texture_size <= lut_size_q;
      base_addr_s1 <= lut_base_q;
      tex_idx_s1 <= tex_idx_lut_q;
      u_norm_s1 <= normalize_uv(u_lut_q, texture_mode_u_lut_q);
      v_norm_s1 <= normalize_uv(v_lut_q, texture_mode_v_lut_q);
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
  (* shreg_extract = "no" *) logic [31:0] base_addr_s2;
  logic [MaxTexLog2-1:0] max_idx_s2;

  always_comb begin
    // Any tex_idx with the MSB set (>= 128, outside the 128-entry LUT range) requests "no texture".
    if (!tex_idx_s1[7]) begin
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
      base_addr_s2 <= base_addr_s1;
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
      addr_out_swizzled[(2*bit_idx)]   = x_idx[bit_idx];
      addr_out_swizzled[(2*bit_idx)+1] = y_idx[bit_idx];
    end
  end

  // Assumes base_addr is aligned to the size of the texture (aka lower bits are 0)
  assign addr_out_comb = base_addr_s2 | addr_out_swizzled;

  always_ff @(posedge clk) begin
    if (clken) begin
      addr_out   <= addr_out_comb;
      no_texture <= no_texture_s2;
    end
  end

endmodule
