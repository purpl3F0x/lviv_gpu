`timescale 1ns / 1ps

import gpu_types_pkg::*;

module thread (
    input logic clk,
    input logic rst_n,

    // Orchestrator-style input bundle (single lane)
    input logic valid_in,
    output logic ready_out,
    input thread_data_in_t in_data,

    output logic empty,

    output logic [                   31:0] out_fb_color,
    output logic [PIXEL_ADDR_W_THREAD-1:0] out_fb_addr,
    output logic                           out_fb_valid,
    output logic                           out_fb_we,

    // Z-buffer memory interface
    output logic                           z_rd_en,
    output logic [PIXEL_ADDR_W_THREAD-1:0] z_rd_addr,
    input  logic [                   31:0] z_rd_data,
    output logic                           z_wr_en,
    output logic [PIXEL_ADDR_W_THREAD-1:0] z_wr_addr,
    output logic [                   31:0] z_wr_data,

    // L1 texture cache AXI read channel
    output logic [ 31:0] tex_m_axi_araddr,
    output logic [  7:0] tex_m_axi_arlen,
    output logic [  2:0] tex_m_axi_arsize,
    output logic [  1:0] tex_m_axi_arburst,
    output logic         tex_m_axi_arvalid,
    input  logic         tex_m_axi_arready,
    input  logic [127:0] tex_m_axi_rdata,
    input  logic [  1:0] tex_m_axi_rresp,
    input  logic         tex_m_axi_rvalid,
    output logic         tex_m_axi_rready,
    input  logic         tex_m_axi_rlast,

    // Texture LUT programming interface
    input logic        lut_addr_wr_en,
    input logic        lut_size_wr_en,
    input logic [ 6:0] lut_wr_addr,
    input logic [31:0] lut_wr_data

);

  localparam int THREAD_ADDR_W = PIXEL_ADDR_W_THREAD;

  logic [THREAD_ADDR_W-1:0] s_axis_addr_tdata;

  // Single ingress skid buffer for the whole orchestrator token.
  localparam int INBUNDLEWIDTH = $bits(thread_data_in_t);

  logic input_bundle_s_axis_tready;
  logic [INBUNDLEWIDTH-1:0] input_bundle_buf_tdata;
  logic input_bundle_buf_tvalid;
  logic input_bundle_m_axis_tready;
  (* max_fanout = 250 *) logic pipe_en_internal;
  thread_data_in_t thread_data_buf;

  // Reject triangles with e0 < 0 or e1 < 0 or e2 < 0
  logic skid_valid_in;
  assign skid_valid_in = valid_in & (
    (in_data.e0[31] == 0) & (in_data.e1[31] == 0) & (in_data.e2[31] == 0)
    );

  axis_skid_buffer #(
      .WIDTH(INBUNDLEWIDTH)
  ) u_input_bundle_skid (
      .aclk(clk),
      .aresetn(rst_n),
      .s_axis_tdata(in_data),
      .s_axis_tvalid(skid_valid_in),
      .s_axis_tready(input_bundle_s_axis_tready),
      .m_axis_tdata(input_bundle_buf_tdata),
      .m_axis_tvalid(input_bundle_buf_tvalid),
      .m_axis_tready(input_bundle_m_axis_tready)
  );

  assign thread_data_buf   = input_bundle_buf_tdata;
  assign s_axis_addr_tdata = thread_data_buf.addr[THREAD_ADDR_W-1:0];

  // -------------------------------
  // ---- Master valid pipeline ----
  // -------------------------------
  logic [93:0] valid_pipe;
  assign valid_pipe[0] = input_bundle_buf_tvalid;
  always_ff @(posedge clk) begin
    if (~rst_n) valid_pipe[93:1] <= '0;
    else if (pipe_en_internal) valid_pipe[93:1] <= valid_pipe[92:0];
  end

  // AUTO-GENERATED FROM scripts/create_thread.py
// Thread pipeline autogen block

// ---- Unit output wires ----
logic [31:0] fp_mul_1_res;
logic [31:0] fp_mul_2_res;
logic [31:0] fp_mul_3_res;
logic [31:0] fp_mul_4_res;
logic [31:0] fp_mul_5_res;
logic [31:0] fp_mul_6_res;
logic [31:0] fp_mul_7_res;
logic [31:0] fp_fma_1_res;
logic [31:0] fp_fma_2_res;
logic [31:0] fp_fma_3_res;
logic [31:0] fp_fma_4_res;
logic [31:0] fp_recip_1_out;
logic [31:0] mem_read_1_rdata;
logic [0:0] fp_cmp_1_pred;
logic fp_cmp_1_pred_valid;
logic [0:0] mem_write_1_pred;
logic mem_write_1_fire;
logic [31:0] fp_mul_8_res;
logic [31:0] fp_mul_9_res;
logic [31:0] fp_mul_10_res;
logic [24:0] fp_to_fx2_23_1_res;
logic [24:0] fp_to_fx2_23_2_res;
logic [24:0] fp_to_fx2_23_3_res;
logic [32:0] fx_color_mul_1_res;
logic [32:0] fx_color_mul_2_res;
logic [32:0] fx_color_mul_3_res;
logic [32:0] fx_color_mul_4_res;
logic [47:0] fx_texture_mul_1_res;
logic [47:0] fx_texture_mul_2_res;
logic [32:0] fx_color_fma_1_res;
logic [32:0] fx_color_fma_2_res;
logic [32:0] fx_color_fma_3_res;
logic [32:0] fx_color_fma_4_res;
logic [47:0] fx_texture_fma_1_res;
logic [47:0] fx_texture_fma_2_res;
logic [32:0] fx_color_fma_5_res;
logic [32:0] fx_color_fma_6_res;
logic [32:0] fx_color_fma_7_res;
logic [32:0] fx_color_fma_8_res;
logic [47:0] fx_texture_fma_3_res;
logic [47:0] fx_texture_fma_4_res;
logic [7:0] fx_color_to_u8_1_res;
logic [7:0] fx_color_to_u8_2_res;
logic [7:0] fx_color_to_u8_3_res;
logic [7:0] fx_color_to_u8_4_res;

// ---- Selected outputs ----
logic [47:0] texcoord_u_tdata;
assign texcoord_u_tdata = fx_texture_fma_3_res;
logic [47:0] texcoord_v_tdata;
assign texcoord_v_tdata = fx_texture_fma_4_res;
logic [THREAD_ADDR_W-1:0] addr_tdata;
assign addr_tdata = thread_data_buf.addr[THREAD_ADDR_W-1:0];
logic [7:0] tex_id_tdata;
assign tex_id_tdata = thread_data_buf.tex_id;
logic texture_mode_u_tdata;
assign texture_mode_u_tdata = thread_data_buf.texture_mode_u;
logic texture_mode_v_tdata;
assign texture_mode_v_tdata = thread_data_buf.texture_mode_v;
logic [2:0] texture_function_tdata;
assign texture_function_tdata = thread_data_buf.texture_function;
logic [7:0] color_r_tdata;
assign color_r_tdata = fx_color_to_u8_1_res;
logic [7:0] color_g_tdata;
assign color_g_tdata = fx_color_to_u8_2_res;
logic [7:0] color_b_tdata;
assign color_b_tdata = fx_color_to_u8_3_res;
logic [7:0] color_a_tdata;
assign color_a_tdata = fx_color_to_u8_4_res;
logic comp_z_tdata;
assign comp_z_tdata = fp_cmp_1_pred;

// ---- Unit input ready wires ----
// None (non-blocking FP modules use aclken/valid_in)

// ---- Unit mapping summary ----
// fp_mul_1         -> fp_mul_1          out=fp_mul_1_res        start=  0  end=  8  valid=(pipe_en)  expr=(e0 * inv_area)
// fp_mul_2         -> fp_mul_2          out=fp_mul_2_res        start=  0  end=  8  valid=(pipe_en)  expr=(e1 * inv_area)
// fp_mul_3         -> fp_mul_3          out=fp_mul_3_res        start=  0  end=  8  valid=(pipe_en)  expr=(e2 * inv_area)
// fp_mul_10        -> fp_mul_4          out=fp_mul_4_res        start=  8  end= 16  valid=(pipe_en)  expr=(v0_z * (e0 * inv_area))
// fp_mul_4         -> fp_mul_5          out=fp_mul_5_res        start=  8  end= 16  valid=(pipe_en)  expr=(v0_w * (e0 * inv_area))
// fp_mul_6         -> fp_mul_6          out=fp_mul_6_res        start=  8  end= 16  valid=(pipe_en)  expr=(v1_w * (e1 * inv_area))
// fp_mul_8         -> fp_mul_7          out=fp_mul_7_res        start=  8  end= 16  valid=(pipe_en)  expr=(v2_w * (e2 * inv_area))
// fp_fma_1         -> fp_fma_1          out=fp_fma_1_res        start= 16  end= 32  valid=(pipe_en)  expr=fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area)))
// fp_fma_3         -> fp_fma_2          out=fp_fma_2_res        start= 16  end= 32  valid=(pipe_en)  expr=fma(v1_z, (e1 * inv_area), (v0_z * (e0 * inv_area)))
// fp_fma_2         -> fp_fma_3          out=fp_fma_3_res        start= 32  end= 48  valid=(pipe_en)  expr=fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))
// fp_fma_4         -> fp_fma_4          out=fp_fma_4_res        start= 32  end= 48  valid=(pipe_en)  expr=fma(v2_z, (e2 * inv_area), fma(v1_z, (e1 * inv_area), (v0_z * (e0 * inv_area))))
// fp_recip_1       -> fp_recip_1        out=fp_recip_1_out      start= 48  end= 77  valid=(pipe_en)  expr=(1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area)))))
// mem_read_1       -> mem_read_1        out=mem_read_1_rdata    start= 47  end= 49  valid=(pipe_en)  expr=mem_read(addr)
// fp_cmp_1         -> fp_cmp_1          out=fp_cmp_1_pred       start= 49  end= 50  valid=(pipe_en)  expr=(fma(v2_z, (e2 * inv_area), fma(v1_z, (e1 * inv_area), (v0_z * (e0 * inv_area)))) <= mem_read(addr))
// mem_write_1      -> mem_write_1       out=mem_write_1_pred    start= 50  end= 51  valid=(pipe_en)  expr=mem_write(addr, fma(v2_z, (e2 * inv_area), fma(v1_z, (e1 * inv_area), (v0_z * (e0 * inv_area)))))
// fp_mul_5         -> fp_mul_8          out=fp_mul_8_res        start= 77  end= 85  valid=(pipe_en)  expr=((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area)))
// fp_mul_7         -> fp_mul_9          out=fp_mul_9_res        start= 77  end= 85  valid=(pipe_en)  expr=((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area)))
// fp_mul_9         -> fp_mul_10         out=fp_mul_10_res       start= 77  end= 85  valid=(pipe_en)  expr=((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v2_w * (e2 * inv_area)))
// fp_to_fx2_23_1   -> fp_to_fx2_23_1    out=fp_to_fx2_23_1_res  start= 85  end= 87  valid=(pipe_en)  expr=fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area))))
// fp_to_fx2_23_2   -> fp_to_fx2_23_2    out=fp_to_fx2_23_2_res  start= 85  end= 87  valid=(pipe_en)  expr=fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area))))
// fp_to_fx2_23_3   -> fp_to_fx2_23_3    out=fp_to_fx2_23_3_res  start= 85  end= 87  valid=(pipe_en)  expr=fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v2_w * (e2 * inv_area))))
// fx_color_mul_1   -> fx_color_mul_1    out=fx_color_mul_1_res  start= 87  end= 88  valid=(pipe_en)  expr=(v0_color_r * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area)))))
// fx_color_mul_2   -> fx_color_mul_2    out=fx_color_mul_2_res  start= 87  end= 88  valid=(pipe_en)  expr=(v0_color_g * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area)))))
// fx_color_mul_3   -> fx_color_mul_3    out=fx_color_mul_3_res  start= 87  end= 88  valid=(pipe_en)  expr=(v0_color_b * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area)))))
// fx_color_mul_4   -> fx_color_mul_4    out=fx_color_mul_4_res  start= 87  end= 88  valid=(pipe_en)  expr=(v0_color_a * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area)))))
// fx_texture_mul_1 -> fx_texture_mul_1  out=fx_texture_mul_1_res  start= 87  end= 88  valid=(pipe_en)  expr=(v0_texture_u * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area)))))
// fx_texture_mul_2 -> fx_texture_mul_2  out=fx_texture_mul_2_res  start= 87  end= 88  valid=(pipe_en)  expr=(v0_texture_v * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area)))))
// fx_color_fma_1   -> fx_color_fma_1    out=fx_color_fma_1_res  start= 88  end= 90  valid=(pipe_en)  expr=fma(v1_color_r, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area)))), (v0_color_r * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area))))))
// fx_color_fma_3   -> fx_color_fma_2    out=fx_color_fma_2_res  start= 88  end= 90  valid=(pipe_en)  expr=fma(v1_color_g, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area)))), (v0_color_g * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area))))))
// fx_color_fma_5   -> fx_color_fma_3    out=fx_color_fma_3_res  start= 88  end= 90  valid=(pipe_en)  expr=fma(v1_color_b, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area)))), (v0_color_b * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area))))))
// fx_color_fma_7   -> fx_color_fma_4    out=fx_color_fma_4_res  start= 88  end= 90  valid=(pipe_en)  expr=fma(v1_color_a, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area)))), (v0_color_a * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area))))))
// fx_texture_fma_1 -> fx_texture_fma_1  out=fx_texture_fma_1_res  start= 88  end= 90  valid=(pipe_en)  expr=fma(v1_texture_u, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area)))), (v0_texture_u * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area))))))
// fx_texture_fma_3 -> fx_texture_fma_2  out=fx_texture_fma_2_res  start= 88  end= 90  valid=(pipe_en)  expr=fma(v1_texture_v, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area)))), (v0_texture_v * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area))))))
// fx_color_fma_2   -> fx_color_fma_5    out=fx_color_fma_5_res  start= 90  end= 92  valid=(pipe_en)  expr=fma(v2_color_r, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v2_w * (e2 * inv_area)))), fma(v1_color_r, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area)))), (v0_color_r * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area)))))))
// fx_color_fma_4   -> fx_color_fma_6    out=fx_color_fma_6_res  start= 90  end= 92  valid=(pipe_en)  expr=fma(v2_color_g, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v2_w * (e2 * inv_area)))), fma(v1_color_g, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area)))), (v0_color_g * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area)))))))
// fx_color_fma_6   -> fx_color_fma_7    out=fx_color_fma_7_res  start= 90  end= 92  valid=(pipe_en)  expr=fma(v2_color_b, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v2_w * (e2 * inv_area)))), fma(v1_color_b, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area)))), (v0_color_b * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area)))))))
// fx_color_fma_8   -> fx_color_fma_8    out=fx_color_fma_8_res  start= 90  end= 92  valid=(pipe_en)  expr=fma(v2_color_a, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v2_w * (e2 * inv_area)))), fma(v1_color_a, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area)))), (v0_color_a * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area)))))))
// fx_texture_fma_2 -> fx_texture_fma_3  out=fx_texture_fma_3_res  start= 90  end= 92  valid=(pipe_en)  expr=fma(v2_texture_u, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v2_w * (e2 * inv_area)))), fma(v1_texture_u, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area)))), (v0_texture_u * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area)))))))
// fx_texture_fma_4 -> fx_texture_fma_4  out=fx_texture_fma_4_res  start= 90  end= 92  valid=(pipe_en)  expr=fma(v2_texture_v, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v2_w * (e2 * inv_area)))), fma(v1_texture_v, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area)))), (v0_texture_v * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area)))))))
// fx_color_to_u8_1 -> fx_color_to_u8_1  out=fx_color_to_u8_1_res  start= 92  end= 93  valid=(pipe_en)  expr=fx_color_to_u8(fma(v2_color_r, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v2_w * (e2 * inv_area)))), fma(v1_color_r, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area)))), (v0_color_r * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area))))))))
// fx_color_to_u8_2 -> fx_color_to_u8_2  out=fx_color_to_u8_2_res  start= 92  end= 93  valid=(pipe_en)  expr=fx_color_to_u8(fma(v2_color_g, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v2_w * (e2 * inv_area)))), fma(v1_color_g, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area)))), (v0_color_g * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area))))))))
// fx_color_to_u8_3 -> fx_color_to_u8_3  out=fx_color_to_u8_3_res  start= 92  end= 93  valid=(pipe_en)  expr=fx_color_to_u8(fma(v2_color_b, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v2_w * (e2 * inv_area)))), fma(v1_color_b, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area)))), (v0_color_b * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area))))))))
// fx_color_to_u8_4 -> fx_color_to_u8_4  out=fx_color_to_u8_4_res  start= 92  end= 93  valid=(pipe_en)  expr=fx_color_to_u8(fma(v2_color_a, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v2_w * (e2 * inv_area)))), fma(v1_color_a, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area)))), (v0_color_a * fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area))))))))

// ---- Non-AXIS consumer fire wiring ----
logic mem_read_1_fire;
logic fp_cmp_1_fire;
assign mem_read_1_fire = valid_pipe[47];
assign fp_cmp_1_fire   = valid_pipe[50];

// ---- Delay alignment for late-consumed inputs ----
logic [31:0] align_v0_z_to_fp_mul_10_i0_d8;
logic [31:0] align_v0_w_to_fp_mul_4_i0_d8;
logic [31:0] align_v1_w_to_fp_mul_6_i0_d8;
logic [31:0] align_v2_w_to_fp_mul_8_i0_d8;
logic [31:0] align_v1_w_to_fp_fma_1_i0_d16;
logic [31:0] align_fp_mul_2_to_fp_fma_1_i1_d8;
logic [31:0] align_v1_z_to_fp_fma_3_i0_d16;
logic [31:0] align_fp_mul_2_to_fp_fma_3_i1_d8;
logic [31:0] align_v2_w_to_fp_fma_2_i0_d32;
logic [31:0] align_fp_mul_3_to_fp_fma_2_i1_d24;
logic [31:0] align_v2_z_to_fp_fma_4_i0_d32;
logic [31:0] align_fp_mul_3_to_fp_fma_4_i1_d24;
logic [THREAD_ADDR_W-1:0] align_addr_to_mem_read_1_i0_d47;
logic [31:0] align_fp_fma_4_to_fp_cmp_1_i0_d1;
logic [THREAD_ADDR_W-1:0] align_addr_to_mem_write_1_i0_d50;
logic [31:0] align_fp_fma_4_to_mem_write_1_i1_d2;
logic [31:0] align_fp_mul_4_to_fp_mul_5_i1_d61;
logic [31:0] align_fp_mul_6_to_fp_mul_7_i1_d61;
logic [31:0] align_fp_mul_8_to_fp_mul_9_i1_d61;
logic [7:0] align_v0_color_r_to_fx_color_mul_1_i0_d87;
logic [7:0] align_v0_color_g_to_fx_color_mul_2_i0_d87;
logic [7:0] align_v0_color_b_to_fx_color_mul_3_i0_d87;
logic [7:0] align_v0_color_a_to_fx_color_mul_4_i0_d87;
logic [17:0] align_v0_texture_u_to_fx_texture_mul_1_i1_d87;
logic [17:0] align_v0_texture_v_to_fx_texture_mul_2_i1_d87;
logic [7:0] align_v1_color_r_to_fx_color_fma_1_i0_d88;
logic [24:0] align_fp_to_fx2_23_2_to_fx_color_fma_1_i1_d1;
logic [7:0] align_v1_color_g_to_fx_color_fma_3_i0_d88;
logic [24:0] align_fp_to_fx2_23_2_to_fx_color_fma_3_i1_d1;
logic [7:0] align_v1_color_b_to_fx_color_fma_5_i0_d88;
logic [24:0] align_fp_to_fx2_23_2_to_fx_color_fma_5_i1_d1;
logic [7:0] align_v1_color_a_to_fx_color_fma_7_i0_d88;
logic [24:0] align_fp_to_fx2_23_2_to_fx_color_fma_7_i1_d1;
logic [24:0] align_fp_to_fx2_23_2_to_fx_texture_fma_1_i0_d1;
logic [17:0] align_v1_texture_u_to_fx_texture_fma_1_i1_d88;
logic [24:0] align_fp_to_fx2_23_2_to_fx_texture_fma_3_i0_d1;
logic [17:0] align_v1_texture_v_to_fx_texture_fma_3_i1_d88;
logic [7:0] align_v2_color_r_to_fx_color_fma_2_i0_d90;
logic [24:0] align_fp_to_fx2_23_3_to_fx_color_fma_2_i1_d3;
logic [7:0] align_v2_color_g_to_fx_color_fma_4_i0_d90;
logic [24:0] align_fp_to_fx2_23_3_to_fx_color_fma_4_i1_d3;
logic [7:0] align_v2_color_b_to_fx_color_fma_6_i0_d90;
logic [24:0] align_fp_to_fx2_23_3_to_fx_color_fma_6_i1_d3;
logic [7:0] align_v2_color_a_to_fx_color_fma_8_i0_d90;
logic [24:0] align_fp_to_fx2_23_3_to_fx_color_fma_8_i1_d3;
logic [24:0] align_fp_to_fx2_23_3_to_fx_texture_fma_2_i0_d3;
logic [17:0] align_v2_texture_u_to_fx_texture_fma_2_i1_d90;
logic [24:0] align_fp_to_fx2_23_3_to_fx_texture_fma_4_i0_d3;
logic [17:0] align_v2_texture_v_to_fx_texture_fma_4_i1_d90;

delay_pipe #(
    .WIDTH (32),
    .STAGES(8)
) u_align_v0_z_to_fp_mul_10_i0_d8_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v0_z),
    .data_out(align_v0_z_to_fp_mul_10_i0_d8)
);
delay_pipe #(
    .WIDTH (32),
    .STAGES(8)
) u_align_v0_w_to_fp_mul_4_i0_d8_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v0_w),
    .data_out(align_v0_w_to_fp_mul_4_i0_d8)
);
delay_pipe #(
    .WIDTH (32),
    .STAGES(8)
) u_align_v1_w_to_fp_mul_6_i0_d8_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v1_w),
    .data_out(align_v1_w_to_fp_mul_6_i0_d8)
);
delay_pipe #(
    .WIDTH (32),
    .STAGES(8)
) u_align_v2_w_to_fp_mul_8_i0_d8_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v2_w),
    .data_out(align_v2_w_to_fp_mul_8_i0_d8)
);
delay_pipe #(
    .WIDTH (32),
    .STAGES(8)
) u_align_v1_w_to_fp_fma_1_i0_d16_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(align_v1_w_to_fp_mul_6_i0_d8),
    .data_out(align_v1_w_to_fp_fma_1_i0_d16)
);
delay_pipe #(
    .WIDTH (32),
    .STAGES(8)
) u_align_fp_mul_2_to_fp_fma_1_i1_d8_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(fp_mul_2_res),
    .data_out(align_fp_mul_2_to_fp_fma_1_i1_d8)
);
delay_pipe #(
    .WIDTH (32),
    .STAGES(16)
) u_align_v1_z_to_fp_fma_3_i0_d16_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v1_z),
    .data_out(align_v1_z_to_fp_fma_3_i0_d16)
);
delay_pipe #(
    .WIDTH (32),
    .STAGES(8)
) u_align_fp_mul_2_to_fp_fma_3_i1_d8_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(fp_mul_2_res),
    .data_out(align_fp_mul_2_to_fp_fma_3_i1_d8)
);
delay_pipe #(
    .WIDTH (32),
    .STAGES(24)
) u_align_v2_w_to_fp_fma_2_i0_d32_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(align_v2_w_to_fp_mul_8_i0_d8),
    .data_out(align_v2_w_to_fp_fma_2_i0_d32)
);
delay_pipe #(
    .WIDTH (32),
    .STAGES(24)
) u_align_fp_mul_3_to_fp_fma_2_i1_d24_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(fp_mul_3_res),
    .data_out(align_fp_mul_3_to_fp_fma_2_i1_d24)
);
delay_pipe #(
    .WIDTH (32),
    .STAGES(32)
) u_align_v2_z_to_fp_fma_4_i0_d32_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v2_z),
    .data_out(align_v2_z_to_fp_fma_4_i0_d32)
);
delay_pipe #(
    .WIDTH (32),
    .STAGES(24)
) u_align_fp_mul_3_to_fp_fma_4_i1_d24_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(fp_mul_3_res),
    .data_out(align_fp_mul_3_to_fp_fma_4_i1_d24)
);
delay_pipe #(
    .WIDTH (THREAD_ADDR_W),
    .STAGES(47)
) u_align_addr_to_mem_read_1_i0_d47_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.addr[THREAD_ADDR_W-1:0]),
    .data_out(align_addr_to_mem_read_1_i0_d47)
);
delay_pipe #(
    .WIDTH (32),
    .STAGES(1)
) u_align_fp_fma_4_to_fp_cmp_1_i0_d1_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(fp_fma_4_res),
    .data_out(align_fp_fma_4_to_fp_cmp_1_i0_d1)
);
delay_pipe #(
    .WIDTH (THREAD_ADDR_W),
    .STAGES(3)
) u_align_addr_to_mem_write_1_i0_d50_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(align_addr_to_mem_read_1_i0_d47),
    .data_out(align_addr_to_mem_write_1_i0_d50)
);
delay_pipe #(
    .WIDTH (32),
    .STAGES(2)
) u_align_fp_fma_4_to_mem_write_1_i1_d2_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(fp_fma_4_res),
    .data_out(align_fp_fma_4_to_mem_write_1_i1_d2)
);
delay_pipe #(
    .WIDTH (32),
    .STAGES(61)
) u_align_fp_mul_4_to_fp_mul_5_i1_d61_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(fp_mul_5_res),
    .data_out(align_fp_mul_4_to_fp_mul_5_i1_d61)
);
delay_pipe #(
    .WIDTH (32),
    .STAGES(61)
) u_align_fp_mul_6_to_fp_mul_7_i1_d61_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(fp_mul_6_res),
    .data_out(align_fp_mul_6_to_fp_mul_7_i1_d61)
);
delay_pipe #(
    .WIDTH (32),
    .STAGES(61)
) u_align_fp_mul_8_to_fp_mul_9_i1_d61_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(fp_mul_7_res),
    .data_out(align_fp_mul_8_to_fp_mul_9_i1_d61)
);
delay_pipe #(
    .WIDTH (8),
    .STAGES(87)
) u_align_v0_color_r_to_fx_color_mul_1_i0_d87_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v0_color_r),
    .data_out(align_v0_color_r_to_fx_color_mul_1_i0_d87)
);
delay_pipe #(
    .WIDTH (8),
    .STAGES(87)
) u_align_v0_color_g_to_fx_color_mul_2_i0_d87_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v0_color_g),
    .data_out(align_v0_color_g_to_fx_color_mul_2_i0_d87)
);
delay_pipe #(
    .WIDTH (8),
    .STAGES(87)
) u_align_v0_color_b_to_fx_color_mul_3_i0_d87_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v0_color_b),
    .data_out(align_v0_color_b_to_fx_color_mul_3_i0_d87)
);
delay_pipe #(
    .WIDTH (8),
    .STAGES(87)
) u_align_v0_color_a_to_fx_color_mul_4_i0_d87_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v0_color_a),
    .data_out(align_v0_color_a_to_fx_color_mul_4_i0_d87)
);
delay_pipe #(
    .WIDTH (18),
    .STAGES(87)
) u_align_v0_texture_u_to_fx_texture_mul_1_i1_d87_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v0_u),
    .data_out(align_v0_texture_u_to_fx_texture_mul_1_i1_d87)
);
delay_pipe #(
    .WIDTH (18),
    .STAGES(87)
) u_align_v0_texture_v_to_fx_texture_mul_2_i1_d87_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v0_v),
    .data_out(align_v0_texture_v_to_fx_texture_mul_2_i1_d87)
);
delay_pipe #(
    .WIDTH (8),
    .STAGES(88)
) u_align_v1_color_r_to_fx_color_fma_1_i0_d88_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v1_color_r),
    .data_out(align_v1_color_r_to_fx_color_fma_1_i0_d88)
);
delay_pipe #(
    .WIDTH (25),
    .STAGES(1)
) u_align_fp_to_fx2_23_2_to_fx_color_fma_1_i1_d1_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(fp_to_fx2_23_2_res),
    .data_out(align_fp_to_fx2_23_2_to_fx_color_fma_1_i1_d1)
);
delay_pipe #(
    .WIDTH (8),
    .STAGES(88)
) u_align_v1_color_g_to_fx_color_fma_3_i0_d88_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v1_color_g),
    .data_out(align_v1_color_g_to_fx_color_fma_3_i0_d88)
);
delay_pipe #(
    .WIDTH (25),
    .STAGES(1)
) u_align_fp_to_fx2_23_2_to_fx_color_fma_3_i1_d1_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(fp_to_fx2_23_2_res),
    .data_out(align_fp_to_fx2_23_2_to_fx_color_fma_3_i1_d1)
);
delay_pipe #(
    .WIDTH (8),
    .STAGES(88)
) u_align_v1_color_b_to_fx_color_fma_5_i0_d88_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v1_color_b),
    .data_out(align_v1_color_b_to_fx_color_fma_5_i0_d88)
);
delay_pipe #(
    .WIDTH (25),
    .STAGES(1)
) u_align_fp_to_fx2_23_2_to_fx_color_fma_5_i1_d1_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(fp_to_fx2_23_2_res),
    .data_out(align_fp_to_fx2_23_2_to_fx_color_fma_5_i1_d1)
);
delay_pipe #(
    .WIDTH (8),
    .STAGES(88)
) u_align_v1_color_a_to_fx_color_fma_7_i0_d88_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v1_color_a),
    .data_out(align_v1_color_a_to_fx_color_fma_7_i0_d88)
);
delay_pipe #(
    .WIDTH (25),
    .STAGES(1)
) u_align_fp_to_fx2_23_2_to_fx_color_fma_7_i1_d1_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(fp_to_fx2_23_2_res),
    .data_out(align_fp_to_fx2_23_2_to_fx_color_fma_7_i1_d1)
);
delay_pipe #(
    .WIDTH (25),
    .STAGES(1)
) u_align_fp_to_fx2_23_2_to_fx_texture_fma_1_i0_d1_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(fp_to_fx2_23_2_res),
    .data_out(align_fp_to_fx2_23_2_to_fx_texture_fma_1_i0_d1)
);
delay_pipe #(
    .WIDTH (18),
    .STAGES(88)
) u_align_v1_texture_u_to_fx_texture_fma_1_i1_d88_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v1_u),
    .data_out(align_v1_texture_u_to_fx_texture_fma_1_i1_d88)
);
delay_pipe #(
    .WIDTH (25),
    .STAGES(1)
) u_align_fp_to_fx2_23_2_to_fx_texture_fma_3_i0_d1_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(fp_to_fx2_23_2_res),
    .data_out(align_fp_to_fx2_23_2_to_fx_texture_fma_3_i0_d1)
);
delay_pipe #(
    .WIDTH (18),
    .STAGES(88)
) u_align_v1_texture_v_to_fx_texture_fma_3_i1_d88_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v1_v),
    .data_out(align_v1_texture_v_to_fx_texture_fma_3_i1_d88)
);
delay_pipe #(
    .WIDTH (8),
    .STAGES(90)
) u_align_v2_color_r_to_fx_color_fma_2_i0_d90_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v2_color_r),
    .data_out(align_v2_color_r_to_fx_color_fma_2_i0_d90)
);
delay_pipe #(
    .WIDTH (25),
    .STAGES(3)
) u_align_fp_to_fx2_23_3_to_fx_color_fma_2_i1_d3_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(fp_to_fx2_23_3_res),
    .data_out(align_fp_to_fx2_23_3_to_fx_color_fma_2_i1_d3)
);
delay_pipe #(
    .WIDTH (8),
    .STAGES(90)
) u_align_v2_color_g_to_fx_color_fma_4_i0_d90_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v2_color_g),
    .data_out(align_v2_color_g_to_fx_color_fma_4_i0_d90)
);
delay_pipe #(
    .WIDTH (25),
    .STAGES(3)
) u_align_fp_to_fx2_23_3_to_fx_color_fma_4_i1_d3_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(fp_to_fx2_23_3_res),
    .data_out(align_fp_to_fx2_23_3_to_fx_color_fma_4_i1_d3)
);
delay_pipe #(
    .WIDTH (8),
    .STAGES(90)
) u_align_v2_color_b_to_fx_color_fma_6_i0_d90_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v2_color_b),
    .data_out(align_v2_color_b_to_fx_color_fma_6_i0_d90)
);
delay_pipe #(
    .WIDTH (25),
    .STAGES(3)
) u_align_fp_to_fx2_23_3_to_fx_color_fma_6_i1_d3_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(fp_to_fx2_23_3_res),
    .data_out(align_fp_to_fx2_23_3_to_fx_color_fma_6_i1_d3)
);
delay_pipe #(
    .WIDTH (8),
    .STAGES(90)
) u_align_v2_color_a_to_fx_color_fma_8_i0_d90_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v2_color_a),
    .data_out(align_v2_color_a_to_fx_color_fma_8_i0_d90)
);
delay_pipe #(
    .WIDTH (25),
    .STAGES(3)
) u_align_fp_to_fx2_23_3_to_fx_color_fma_8_i1_d3_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(fp_to_fx2_23_3_res),
    .data_out(align_fp_to_fx2_23_3_to_fx_color_fma_8_i1_d3)
);
delay_pipe #(
    .WIDTH (25),
    .STAGES(3)
) u_align_fp_to_fx2_23_3_to_fx_texture_fma_2_i0_d3_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(fp_to_fx2_23_3_res),
    .data_out(align_fp_to_fx2_23_3_to_fx_texture_fma_2_i0_d3)
);
delay_pipe #(
    .WIDTH (18),
    .STAGES(90)
) u_align_v2_texture_u_to_fx_texture_fma_2_i1_d90_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v2_u),
    .data_out(align_v2_texture_u_to_fx_texture_fma_2_i1_d90)
);
delay_pipe #(
    .WIDTH (25),
    .STAGES(3)
) u_align_fp_to_fx2_23_3_to_fx_texture_fma_4_i0_d3_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(fp_to_fx2_23_3_res),
    .data_out(align_fp_to_fx2_23_3_to_fx_texture_fma_4_i0_d3)
);
delay_pipe #(
    .WIDTH (18),
    .STAGES(90)
) u_align_v2_texture_v_to_fx_texture_fma_4_i1_d90_data_delay (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(thread_data_buf.v2_v),
    .data_out(align_v2_texture_v_to_fx_texture_fma_4_i1_d90)
);

// Leaf ready signals not used (internal distribution only)

// ---- Unit output ready wiring ----
// None (non-blocking FP modules have no AXIS output ready)

// ---- Unit instantiation skeletons ----
// NOTE: Non-blocking FP modules with aclken(pipe_en_internal)
// NOTE: Valid is propagated explicitly via valid_pipe
fp_mul #(
    .LATENCY(8)
) u_fp_mul_1 (
    .aclk(clk),
    .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[1]),
    .valid_in(),
    .a(thread_data_buf.e0),
    .b(thread_data_buf.inv_area),
    .result(fp_mul_1_res)
);
fp_mul #(
    .LATENCY(8)
) u_fp_mul_2 (
    .aclk(clk),
    .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[1]),
    .valid_in(),
    .a(thread_data_buf.e1),
    .b(thread_data_buf.inv_area),
    .result(fp_mul_2_res)
);
fp_mul #(
    .LATENCY(8)
) u_fp_mul_3 (
    .aclk(clk),
    .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[1]),
    .valid_in(),
    .a(thread_data_buf.e2),
    .b(thread_data_buf.inv_area),
    .result(fp_mul_3_res)
);
fp_mul #(
    .LATENCY(8)
) u_fp_mul_4 (
    .aclk(clk),
    .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[9]),
    .valid_in(),
    .a(align_v0_z_to_fp_mul_10_i0_d8),
    .b(fp_mul_1_res),
    .result(fp_mul_4_res)
);
fp_mul #(
    .LATENCY(8)
) u_fp_mul_5 (
    .aclk(clk),
    .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[9]),
    .valid_in(),
    .a(align_v0_w_to_fp_mul_4_i0_d8),
    .b(fp_mul_1_res),
    .result(fp_mul_5_res)
);
fp_mul #(
    .LATENCY(8)
) u_fp_mul_6 (
    .aclk(clk),
    .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[9]),
    .valid_in(),
    .a(align_v1_w_to_fp_mul_6_i0_d8),
    .b(fp_mul_2_res),
    .result(fp_mul_6_res)
);
fp_mul #(
    .LATENCY(8)
) u_fp_mul_7 (
    .aclk(clk),
    .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[9]),
    .valid_in(),
    .a(align_v2_w_to_fp_mul_8_i0_d8),
    .b(fp_mul_3_res),
    .result(fp_mul_7_res)
);
fp_fma #(
    .LATENCY(16)
) u_fp_fma_1 (
    .aclk(clk),
    .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[17]),
    .valid_in(),
    .a(align_v1_w_to_fp_fma_1_i0_d16),
    .b(align_fp_mul_2_to_fp_fma_1_i1_d8),
    .c(fp_mul_5_res),
    .result(fp_fma_1_res)
);
fp_fma #(
    .LATENCY(16)
) u_fp_fma_2 (
    .aclk(clk),
    .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[17]),
    .valid_in(),
    .a(align_v1_z_to_fp_fma_3_i0_d16),
    .b(align_fp_mul_2_to_fp_fma_3_i1_d8),
    .c(fp_mul_4_res),
    .result(fp_fma_2_res)
);
fp_fma #(
    .LATENCY(16)
) u_fp_fma_3 (
    .aclk(clk),
    .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[33]),
    .valid_in(),
    .a(align_v2_w_to_fp_fma_2_i0_d32),
    .b(align_fp_mul_3_to_fp_fma_2_i1_d24),
    .c(fp_fma_1_res),
    .result(fp_fma_3_res)
);
fp_fma #(
    .LATENCY(16)
) u_fp_fma_4 (
    .aclk(clk),
    .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[33]),
    .valid_in(),
    .a(align_v2_z_to_fp_fma_4_i0_d32),
    .b(align_fp_mul_3_to_fp_fma_4_i1_d24),
    .c(fp_fma_2_res),
    .result(fp_fma_4_res)
);
fp_recip #(
    .LATENCY(29)
) u_fp_recip_1 (
    .aclk(clk),
    .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[49]),
    .valid_in(),
    .a(fp_fma_3_res),
    .result(fp_recip_1_out)
);
assign z_rd_en =  pipe_en_internal;
assign z_rd_addr = align_addr_to_mem_read_1_i0_d47;
assign mem_read_1_rdata = z_rd_data;
fp_cmp_le u_fp_cmp_1 (
    .aclk(clk),
    .aclken(pipe_en_internal),
    .s_axis_a(align_fp_fma_4_to_fp_cmp_1_i0_d1),
    //   .s_axis_a_valid(),
    .s_axis_b(mem_read_1_rdata),
    //   .s_axis_b_valid(),
    .m_axis_res(fp_cmp_1_pred[0])
    //   .m_axis_tvalid()
);
assign mem_write_1_fire = valid_pipe[50];
assign mem_write_1_pred[0] = (fp_cmp_1_pred[0]);
assign z_wr_en = mem_write_1_fire && mem_write_1_pred[0] && pipe_en_internal;
assign z_wr_addr = align_addr_to_mem_write_1_i0_d50;
assign z_wr_data = align_fp_fma_4_to_mem_write_1_i1_d2;
fp_mul #(
    .LATENCY(8)
) u_fp_mul_8 (
    .aclk(clk),
    .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[78]),
    .valid_in(),
    .a(fp_recip_1_out),
    .b(align_fp_mul_4_to_fp_mul_5_i1_d61),
    .result(fp_mul_8_res)
);
fp_mul #(
    .LATENCY(8)
) u_fp_mul_9 (
    .aclk(clk),
    .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[78]),
    .valid_in(),
    .a(fp_recip_1_out),
    .b(align_fp_mul_6_to_fp_mul_7_i1_d61),
    .result(fp_mul_9_res)
);
fp_mul #(
    .LATENCY(8)
) u_fp_mul_10 (
    .aclk(clk),
    .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[78]),
    .valid_in(),
    .a(fp_recip_1_out),
    .b(align_fp_mul_8_to_fp_mul_9_i1_d61),
    .result(fp_mul_10_res)
);
fp_to_fx2_23 u_fp_to_fx2_23_1 (
    .aclk(clk),
    .aclken(pipe_en_internal),
    .s_axis_a_tvalid(valid_pipe[86]),
    .s_axis_a_tdata(fp_mul_8_res),
    .m_axis_result_tvalid(),
    .m_axis_result_tdata(fp_to_fx2_23_1_res)
);
fp_to_fx2_23 u_fp_to_fx2_23_2 (
    .aclk(clk),
    .aclken(pipe_en_internal),
    .s_axis_a_tvalid(valid_pipe[86]),
    .s_axis_a_tdata(fp_mul_9_res),
    .m_axis_result_tvalid(),
    .m_axis_result_tdata(fp_to_fx2_23_2_res)
);
fp_to_fx2_23 u_fp_to_fx2_23_3 (
    .aclk(clk),
    .aclken(pipe_en_internal),
    .s_axis_a_tvalid(valid_pipe[86]),
    .s_axis_a_tdata(fp_mul_10_res),
    .m_axis_result_tvalid(),
    .m_axis_result_tdata(fp_to_fx2_23_3_res)
);
fx_color_mul u_fx_color_mul_1 (
    .clk(clk),
    .clken(pipe_en_internal),
    .a(align_v0_color_r_to_fx_color_mul_1_i0_d87),
    .b(fp_to_fx2_23_1_res),
    .q(fx_color_mul_1_res)
);
fx_color_mul u_fx_color_mul_2 (
    .clk(clk),
    .clken(pipe_en_internal),
    .a(align_v0_color_g_to_fx_color_mul_2_i0_d87),
    .b(fp_to_fx2_23_1_res),
    .q(fx_color_mul_2_res)
);
fx_color_mul u_fx_color_mul_3 (
    .clk(clk),
    .clken(pipe_en_internal),
    .a(align_v0_color_b_to_fx_color_mul_3_i0_d87),
    .b(fp_to_fx2_23_1_res),
    .q(fx_color_mul_3_res)
);
fx_color_mul u_fx_color_mul_4 (
    .clk(clk),
    .clken(pipe_en_internal),
    .a(align_v0_color_a_to_fx_color_mul_4_i0_d87),
    .b(fp_to_fx2_23_1_res),
    .q(fx_color_mul_4_res)
);
fx_texture_mul u_fx_texture_mul_1 (
    .clk(clk),
    .clken(pipe_en_internal),
    .a(fp_to_fx2_23_1_res),
    .b(align_v0_texture_u_to_fx_texture_mul_1_i1_d87),
    .q(fx_texture_mul_1_res)
);
fx_texture_mul u_fx_texture_mul_2 (
    .clk(clk),
    .clken(pipe_en_internal),
    .a(fp_to_fx2_23_1_res),
    .b(align_v0_texture_v_to_fx_texture_mul_2_i1_d87),
    .q(fx_texture_mul_2_res)
);
fx_color_fma u_fx_color_fma_1 (
    .clk(clk),
    .clken(pipe_en_internal),
    .a(align_v1_color_r_to_fx_color_fma_1_i0_d88),
    .b(align_fp_to_fx2_23_2_to_fx_color_fma_1_i1_d1),
    .c(fx_color_mul_1_res),
    .q(fx_color_fma_1_res)
);
fx_color_fma u_fx_color_fma_2 (
    .clk(clk),
    .clken(pipe_en_internal),
    .a(align_v1_color_g_to_fx_color_fma_3_i0_d88),
    .b(align_fp_to_fx2_23_2_to_fx_color_fma_3_i1_d1),
    .c(fx_color_mul_2_res),
    .q(fx_color_fma_2_res)
);
fx_color_fma u_fx_color_fma_3 (
    .clk(clk),
    .clken(pipe_en_internal),
    .a(align_v1_color_b_to_fx_color_fma_5_i0_d88),
    .b(align_fp_to_fx2_23_2_to_fx_color_fma_5_i1_d1),
    .c(fx_color_mul_3_res),
    .q(fx_color_fma_3_res)
);
fx_color_fma u_fx_color_fma_4 (
    .clk(clk),
    .clken(pipe_en_internal),
    .a(align_v1_color_a_to_fx_color_fma_7_i0_d88),
    .b(align_fp_to_fx2_23_2_to_fx_color_fma_7_i1_d1),
    .c(fx_color_mul_4_res),
    .q(fx_color_fma_4_res)
);
fx_texture_fma u_fx_texture_fma_1 (
    .clk(clk),
    .clken(pipe_en_internal),
    .a(align_fp_to_fx2_23_2_to_fx_texture_fma_1_i0_d1),
    .b(align_v1_texture_u_to_fx_texture_fma_1_i1_d88),
    .c(fx_texture_mul_1_res),
    .q(fx_texture_fma_1_res)
);
fx_texture_fma u_fx_texture_fma_2 (
    .clk(clk),
    .clken(pipe_en_internal),
    .a(align_fp_to_fx2_23_2_to_fx_texture_fma_3_i0_d1),
    .b(align_v1_texture_v_to_fx_texture_fma_3_i1_d88),
    .c(fx_texture_mul_2_res),
    .q(fx_texture_fma_2_res)
);
fx_color_fma u_fx_color_fma_5 (
    .clk(clk),
    .clken(pipe_en_internal),
    .a(align_v2_color_r_to_fx_color_fma_2_i0_d90),
    .b(align_fp_to_fx2_23_3_to_fx_color_fma_2_i1_d3),
    .c(fx_color_fma_1_res),
    .q(fx_color_fma_5_res)
);
fx_color_fma u_fx_color_fma_6 (
    .clk(clk),
    .clken(pipe_en_internal),
    .a(align_v2_color_g_to_fx_color_fma_4_i0_d90),
    .b(align_fp_to_fx2_23_3_to_fx_color_fma_4_i1_d3),
    .c(fx_color_fma_2_res),
    .q(fx_color_fma_6_res)
);
fx_color_fma u_fx_color_fma_7 (
    .clk(clk),
    .clken(pipe_en_internal),
    .a(align_v2_color_b_to_fx_color_fma_6_i0_d90),
    .b(align_fp_to_fx2_23_3_to_fx_color_fma_6_i1_d3),
    .c(fx_color_fma_3_res),
    .q(fx_color_fma_7_res)
);
fx_color_fma u_fx_color_fma_8 (
    .clk(clk),
    .clken(pipe_en_internal),
    .a(align_v2_color_a_to_fx_color_fma_8_i0_d90),
    .b(align_fp_to_fx2_23_3_to_fx_color_fma_8_i1_d3),
    .c(fx_color_fma_4_res),
    .q(fx_color_fma_8_res)
);
fx_texture_fma u_fx_texture_fma_3 (
    .clk(clk),
    .clken(pipe_en_internal),
    .a(align_fp_to_fx2_23_3_to_fx_texture_fma_2_i0_d3),
    .b(align_v2_texture_u_to_fx_texture_fma_2_i1_d90),
    .c(fx_texture_fma_1_res),
    .q(fx_texture_fma_3_res)
);
fx_texture_fma u_fx_texture_fma_4 (
    .clk(clk),
    .clken(pipe_en_internal),
    .a(align_fp_to_fx2_23_3_to_fx_texture_fma_4_i0_d3),
    .b(align_v2_texture_v_to_fx_texture_fma_4_i1_d90),
    .c(fx_texture_fma_2_res),
    .q(fx_texture_fma_4_res)
);
fx_color_to_u8 u_fx_color_to_u8_1 (
    .clk(clk),
    .clken(pipe_en_internal),
    .in_fx_color(fx_color_fma_5_res),
    .out_u8(fx_color_to_u8_1_res)
);
fx_color_to_u8 u_fx_color_to_u8_2 (
    .clk(clk),
    .clken(pipe_en_internal),
    .in_fx_color(fx_color_fma_6_res),
    .out_u8(fx_color_to_u8_2_res)
);
fx_color_to_u8 u_fx_color_to_u8_3 (
    .clk(clk),
    .clken(pipe_en_internal),
    .in_fx_color(fx_color_fma_7_res),
    .out_u8(fx_color_to_u8_3_res)
);
fx_color_to_u8 u_fx_color_to_u8_4 (
    .clk(clk),
    .clken(pipe_en_internal),
    .in_fx_color(fx_color_fma_8_res),
    .out_u8(fx_color_to_u8_4_res)
);

// ---- Output skid buffer ----
localparam int OUTBUNDLEWIDTH = $bits(
    texcoord_u_tdata
) + $bits(
    texcoord_v_tdata
) + $bits(
    addr_tdata
) + $bits(
    tex_id_tdata
) + $bits(
    texture_mode_u_tdata
) + $bits(
    texture_mode_v_tdata
) + $bits(
    texture_function_tdata
) + $bits(
    color_r_tdata
) + $bits(
    color_g_tdata
) + $bits(
    color_b_tdata
) + $bits(
    color_a_tdata
) + $bits(
    comp_z_tdata
);
logic [OUTBUNDLEWIDTH-1:0] output_bundle_tdata;
logic output_bundle_tvalid;
logic output_bundle_s_axis_tready;
logic [OUTBUNDLEWIDTH-1:0] output_bundle_buf_tdata;
logic output_bundle_buf_tvalid;
logic output_bundle_buf_tready;

logic [47:0] texcoord_u_bundle_tdata;
delay_pipe #(
    .WIDTH (48),
    .STAGES(1)
) u_align_texcoord_u_to_output_bundle_d1 (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(texcoord_u_tdata),
    .data_out(texcoord_u_bundle_tdata)
);
logic [47:0] texcoord_v_bundle_tdata;
delay_pipe #(
    .WIDTH (48),
    .STAGES(1)
) u_align_texcoord_v_to_output_bundle_d1 (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(texcoord_v_tdata),
    .data_out(texcoord_v_bundle_tdata)
);
logic [THREAD_ADDR_W-1:0] addr_bundle_tdata;
delay_pipe #(
    .WIDTH (THREAD_ADDR_W),
    .STAGES(93)
) u_align_addr_to_output_bundle_d93 (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(addr_tdata),
    .data_out(addr_bundle_tdata)
);
logic [7:0] tex_id_bundle_tdata;
delay_pipe #(
    .WIDTH (8),
    .STAGES(93)
) u_align_tex_id_to_output_bundle_d93 (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(tex_id_tdata),
    .data_out(tex_id_bundle_tdata)
);
logic texture_mode_u_bundle_tdata;
delay_pipe #(
    .WIDTH (1),
    .STAGES(93)
) u_align_texture_mode_u_to_output_bundle_d93 (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(texture_mode_u_tdata),
    .data_out(texture_mode_u_bundle_tdata)
);
logic texture_mode_v_bundle_tdata;
delay_pipe #(
    .WIDTH (1),
    .STAGES(93)
) u_align_texture_mode_v_to_output_bundle_d93 (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(texture_mode_v_tdata),
    .data_out(texture_mode_v_bundle_tdata)
);
logic [2:0] texture_function_bundle_tdata;
delay_pipe #(
    .WIDTH (3),
    .STAGES(93)
) u_align_texture_function_to_output_bundle_d93 (
    .clk(clk),
    .rst_n(1'b1),
    .clken(pipe_en_internal),
    .data_in(texture_function_tdata),
    .data_out(texture_function_bundle_tdata)
);
logic comp_z_bundle_tdata;
delay_pipe #(
    .WIDTH (1),
    .STAGES(43)
) u_align_comp_z_to_output_bundle_d43 (
    .clk(clk),
    .rst_n(rst_n),
    .clken(pipe_en_internal),
    .data_in(comp_z_tdata),
    .data_out(comp_z_bundle_tdata)
);

assign output_bundle_tdata = {
  texcoord_u_bundle_tdata,
  texcoord_v_bundle_tdata,
  addr_bundle_tdata,
  tex_id_bundle_tdata,
  texture_mode_u_bundle_tdata,
  texture_mode_v_bundle_tdata,
  texture_function_bundle_tdata,
  color_r_tdata,
  color_g_tdata,
  color_b_tdata,
  color_a_tdata,
  comp_z_bundle_tdata
};
assign output_bundle_tvalid = valid_pipe[93];

axis_skid_buffer #(
    .WIDTH(OUTBUNDLEWIDTH)
) u_output_bundle_skid (
    .aclk(clk),
    .aresetn(rst_n),
    .s_axis_tdata(output_bundle_tdata),
    .s_axis_tvalid(output_bundle_tvalid),
    .s_axis_tready(output_bundle_s_axis_tready),
    .m_axis_tdata(output_bundle_buf_tdata),
    .m_axis_tvalid(output_bundle_buf_tvalid),
    .m_axis_tready(output_bundle_buf_tready)
);

// Pipeline control: clken = output skid can accept
assign pipe_en_internal = output_bundle_s_axis_tready;
assign input_bundle_m_axis_tready = pipe_en_internal;
assign ready_out = input_bundle_s_axis_tready;




  // ************************************* //
  // * Start of Fragment Pipeline logic  * //
  // ************************************* //



    localparam int FRAGMENT_SHADER_LATENCY_STAGES = 5;
    localparam int L1_TEXTURE_HIT_LATENCY_STAGES  = 3;

  typedef struct packed {
    logic [47:0] texcoord_u;
    logic [47:0] texcoord_v;
    logic [THREAD_ADDR_W-1:0] addr;
    logic [7:0] tex_id;
    texture_address_mode_t texture_mode_u;
    texture_address_mode_t texture_mode_v;
    fragment_op_t texture_function;
    color_argb_t color;
  } fragment_token_t;

    typedef struct packed {
        logic valid;
        logic comp_z;
    } fragment_control_t;

  typedef struct packed {
    fragment_token_t token;
    logic [31:0] texture_addr;
    logic no_texture;
  } address_token_t;

  typedef struct packed {
    logic [47:0] texcoord_u;
    logic [47:0] texcoord_v;
    logic [THREAD_ADDR_W-1:0] addr;
    logic [7:0] tex_id;
    texture_address_mode_t texture_mode_u;
    texture_address_mode_t texture_mode_v;
    fragment_op_t texture_function;
    logic [7:0] color_r;
    logic [7:0] color_g;
    logic [7:0] color_b;
    logic [7:0] color_a;
    logic comp_z;
  } fragment_bundle_t;

  typedef struct packed {
    logic [31:0] texture_addr;
    color_argb_t pixel_color;
    fragment_op_t op;
    logic [THREAD_ADDR_W-1:0] addr;
    logic comp_z;
    logic use_texture;
  } fragment_request_token_t;

    typedef struct packed {
        logic [31:0] texture_addr;
        color_argb_t pixel_color;
        fragment_op_t op;
        logic [THREAD_ADDR_W-1:0] addr;
        logic use_texture;
    } fragment_request_payload_t;

  fragment_token_t post_skid_token;
  fragment_bundle_t post_skid_bundle;
  address_token_t address_token_s3;
    fragment_control_t address_control_input;
    fragment_control_t address_control_s3;
  fragment_request_token_t fragment_request_input;
  fragment_request_token_t fragment_request_output;
    fragment_request_payload_t fragment_request_delay_input;
    fragment_request_payload_t fragment_request_delay_output;
    fragment_control_t fragment_request_control_input;
    fragment_control_t fragment_request_control_output;
  logic address_step;
  logic address_use_texture;
    logic texture_response_ready;
  logic fragment_request_input_valid;
  logic fragment_request_input_ready;
  logic fragment_request_output_valid;
  logic fragment_request_output_ready;
    logic fragment_request_fire;
    logic delayed_texture_wait;
  logic address_pipe_valid;
  logic texture_wait_valid;
  logic fragment_join_output_valid;
  logic fragment_join_input_ready;

  logic [31:0] texture_addr;
  logic texture_no_texture;
  logic l1_req_valid;
  logic l1_cache_req_ready;
  logic l1_resp_valid;
  logic [31:0] l1_resp_data;
  logic [31:0] l1_perf_total_req;
  logic [31:0] l1_perf_hit_req;
  logic [31:0] l1_perf_miss_req;
  color_argb_t fragment_color_tdata;
  logic fragment_valid_tdata;
  logic [THREAD_ADDR_W-1:0] fb_addr_tdata;
  logic cmp_pass_fragment_out_tdata;

    assign address_pipe_valid = address_control_s3.valid;
    assign texture_wait_valid = delayed_texture_wait || !l1_cache_req_ready;
  assign fragment_join_output_valid = fragment_request_output_valid;
  assign fragment_join_input_ready = fragment_request_input_ready;

  assign post_skid_bundle = fragment_bundle_t'(output_bundle_buf_tdata);

  always_comb begin
    post_skid_token = '0;
    post_skid_token.texcoord_u = post_skid_bundle.texcoord_u;
    post_skid_token.texcoord_v = post_skid_bundle.texcoord_v;
    post_skid_token.addr = post_skid_bundle.addr;
    post_skid_token.tex_id = post_skid_bundle.tex_id;
    post_skid_token.texture_mode_u = post_skid_bundle.texture_mode_u;
    post_skid_token.texture_mode_v = post_skid_bundle.texture_mode_v;
    post_skid_token.texture_function = post_skid_bundle.texture_function;
    post_skid_token.color.a = post_skid_bundle.color_a;
    post_skid_token.color.r = post_skid_bundle.color_r;
    post_skid_token.color.g = post_skid_bundle.color_g;
    post_skid_token.color.b = post_skid_bundle.color_b;
  end

    assign address_control_input.valid = output_bundle_buf_tvalid;
    assign address_control_input.comp_z = post_skid_bundle.comp_z;

  assign texture_response_ready =
            fragment_request_control_output.valid
            && fragment_request_delay_output.use_texture
      && l1_resp_valid;
    // Backpressure from the fragment request skid is the holding point for the
    // address stage; delayed accepted requests continue toward cache responses.
  assign address_step = fragment_request_input_ready;
  assign output_bundle_buf_tready = address_step;

  delay_pipe #(
      .WIDTH ($bits(fragment_token_t)),
      .STAGES(3)
  ) u_fragment_token_to_address_stage (
      .clk(clk),
      .rst_n(1'b1),
      .clken(address_step),
      .data_in(post_skid_token),
      .data_out(address_token_s3.token)
  );

  delay_pipe #(
      .WIDTH ($bits(fragment_control_t)),
      .STAGES(3)
  ) u_fragment_control_to_address_stage (
      .clk(clk),
      .rst_n(rst_n),
      .clken(address_step),
      .data_in(address_control_input),
      .data_out(address_control_s3)
  );

  texture_address_generator u_texture_address_generator (
      .clk(clk),
      .clken(address_step),
      .tex_idx(post_skid_token.tex_id),
      .u_in(post_skid_token.texcoord_u),
      .v_in(post_skid_token.texcoord_v),
      .texture_mode_u(post_skid_token.texture_mode_u),
      .texture_mode_v(post_skid_token.texture_mode_v),
      .addr_out(texture_addr),
      .no_texture(texture_no_texture),
      .lut_addr_wr_en(lut_addr_wr_en),
      .lut_size_wr_en(lut_size_wr_en),
      .lut_wr_addr(lut_wr_addr),
      .lut_wr_data(lut_wr_data)
  );

  // The address generator is itself a three-stage registered pipeline. Its
  // outputs are therefore already aligned with the delayed fragment token.
  assign address_token_s3.texture_addr = texture_addr;
  assign address_token_s3.no_texture = texture_no_texture;

  assign address_use_texture =
      address_control_s3.valid
      && address_control_s3.comp_z
      && address_token_s3.token.texture_function != COLOR
      && !address_token_s3.no_texture;

  texture_cache #(
      .ADDR_WIDTH(27),
      .PIXEL_BITS(32),
      .CACHE_LINES(32),
      .LINE_PIXELS_X(8),
      .LINE_PIXELS_Y(8),
      .AXI_DATA_WIDTH(128),
      .ENABLE_PERF_COUNTERS(1'b0)
  ) u_l1_texture_cache (
      .clk(clk),
      .rst_n(rst_n),
      .flush(1'b0),
      .req_valid(l1_req_valid),
      .req_ready(l1_cache_req_ready),
      .req_addr(fragment_request_output.texture_addr[26:0]),
      .resp_valid(l1_resp_valid),
      .resp_data(l1_resp_data),
      .m_axi_araddr(tex_m_axi_araddr),
      .m_axi_arlen(tex_m_axi_arlen),
      .m_axi_arsize(tex_m_axi_arsize),
      .m_axi_arburst(tex_m_axi_arburst),
      .m_axi_arvalid(tex_m_axi_arvalid),
      .m_axi_arready(tex_m_axi_arready),
      .m_axi_rdata(tex_m_axi_rdata),
      .m_axi_rresp(tex_m_axi_rresp),
      .m_axi_rvalid(tex_m_axi_rvalid),
      .m_axi_rready(tex_m_axi_rready),
      .m_axi_rlast(tex_m_axi_rlast),
      .perf_total_req(l1_perf_total_req),
      .perf_hit_req(l1_perf_hit_req),
      .perf_miss_req(l1_perf_miss_req),
      .perf_re(1'b0),
      .perf_we(1'b0),
      .perf_addr('0),
      .perf_wdata('0),
      .perf_rdata(),
      .perf_rvalid()
  );

    assign fragment_request_input_valid = address_control_s3.valid;

  always_comb begin
    fragment_request_input = '0;
    fragment_request_input.texture_addr = address_token_s3.texture_addr;
    fragment_request_input.pixel_color = address_token_s3.token.color;
    fragment_request_input.op = fragment_op_t'(address_use_texture
                ? address_token_s3.token.texture_function
                : COLOR);
    fragment_request_input.addr = address_token_s3.token.addr;
    fragment_request_input.comp_z = address_control_s3.comp_z;
    fragment_request_input.use_texture = address_use_texture;
  end

    // Skid buffer sits right at the address/delay merge point. Cache backpressure
    // releases the held token only when a textured request is accepted, while the
    // delayed metadata pipe aligns accepted tokens to in-order cache responses.
  axis_skid_buffer #(
      .WIDTH($bits(fragment_request_token_t))
  ) u_fragment_request_skid_buffer (
      .aclk(clk),
      .aresetn(rst_n),
      .s_axis_tdata(fragment_request_input),
      .s_axis_tvalid(fragment_request_input_valid),
      .s_axis_tready(fragment_request_input_ready),
      .m_axis_tdata(fragment_request_output),
      .m_axis_tvalid(fragment_request_output_valid),
      .m_axis_tready(fragment_request_output_ready)
  );

  assign delayed_texture_wait =
      fragment_request_control_output.valid
      && fragment_request_delay_output.use_texture
      && !l1_resp_valid;

  assign fragment_request_output_ready =
      !delayed_texture_wait
      && l1_cache_req_ready;

  assign fragment_request_fire = fragment_request_output_valid && fragment_request_output_ready;

  always_comb begin
    fragment_request_delay_input = '0;
    fragment_request_delay_input.texture_addr = fragment_request_output.texture_addr;
    fragment_request_delay_input.pixel_color = fragment_request_output.pixel_color;
    fragment_request_delay_input.op = fragment_request_output.op;
    fragment_request_delay_input.addr = fragment_request_output.addr;
    fragment_request_delay_input.use_texture = fragment_request_output.use_texture;
    fragment_request_control_input.valid = fragment_request_fire;
    fragment_request_control_input.comp_z = fragment_request_output.comp_z;
  end

  delay_pipe #(
      .WIDTH ($bits(fragment_request_payload_t)),
      .STAGES(L1_TEXTURE_HIT_LATENCY_STAGES)
  ) u_fragment_request_to_l1_response_stage (
      .clk(clk),
      .rst_n(1'b1),
      .clken(!delayed_texture_wait),
      .data_in(fragment_request_delay_input),
      .data_out(fragment_request_delay_output)
  );

  delay_pipe #(
      .WIDTH ($bits(fragment_control_t)),
      .STAGES(L1_TEXTURE_HIT_LATENCY_STAGES)
  ) u_fragment_control_to_l1_response_stage (
      .clk(clk),
      .rst_n(rst_n),
      .clken(!delayed_texture_wait),
      .data_in(fragment_request_control_input),
      .data_out(fragment_request_control_output)
  );

  // L1 requests fire from the skid's held output. Hit streams can issue one
  // request per cycle; misses deassert cache ready and stall new issues.
  assign l1_req_valid =
      fragment_request_output_valid
      && fragment_request_output.use_texture
      && !delayed_texture_wait;

  logic fragment_shader_input_valid;
  assign fragment_shader_input_valid =
            fragment_request_control_output.valid
            && (!fragment_request_delay_output.use_texture || texture_response_ready);

  fragment_shader u_fragment_shader (
      .clk(clk),
      .rst_n(rst_n),
    .pixel_color(fragment_request_delay_output.pixel_color),
      .texture_color(color_argb_t'(l1_resp_data)),
      .env_color('0),
    .op(fragment_request_delay_output.op),
      .valid_in(fragment_shader_input_valid),
      .fragment_color(fragment_color_tdata),
      .valid_out(fragment_valid_tdata)
  );

  delay_pipe #(
      .WIDTH (THREAD_ADDR_W),
      .STAGES(FRAGMENT_SHADER_LATENCY_STAGES)
  ) u_align_fb_addr_to_fragment_output (
      .clk(clk),
      .rst_n(1'b1),
      .clken(1'b1),
    .data_in(fragment_request_delay_output.addr),
      .data_out(fb_addr_tdata)
  );

  delay_pipe #(
      .WIDTH (1),
      .STAGES(FRAGMENT_SHADER_LATENCY_STAGES)
  ) u_align_compare_to_fragment_output (
      .clk(clk),
      .rst_n(rst_n),
      .clken(1'b1),
    .data_in(fragment_request_control_output.comp_z),
      .data_out(cmp_pass_fragment_out_tdata)
  );

  assign out_fb_color = fragment_color_tdata;
  assign out_fb_addr = fb_addr_tdata;
  assign out_fb_valid = fragment_valid_tdata;
  assign out_fb_we = out_fb_valid && cmp_pass_fragment_out_tdata;


  // Thread emptiness counter: incremented once per token actually accepted
  // into the main pipeline (not merely presented-but-stalled at the ingress
  // skid), decremented once per fragment completing the shader pipeline.
  reg [7:0] emptiness_counter;
  logic input_bundle_fire;
  assign input_bundle_fire = skid_valid_in && ready_out;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      emptiness_counter <= 0;
    end else begin

      unique case ({
        input_bundle_fire, fragment_valid_tdata
      })
        2'b00: emptiness_counter <= emptiness_counter;
        2'b01: emptiness_counter <= emptiness_counter - 1;
        2'b10: emptiness_counter <= emptiness_counter + 1;
        2'b11: emptiness_counter <= emptiness_counter;
      endcase
    end

    empty <= (emptiness_counter == 0) && !input_bundle_fire;
  end

endmodule
