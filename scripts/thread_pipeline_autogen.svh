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
// mem_read_1       -> mem_read_1        out=mem_read_1_rdata    start= 48  end= 50  valid=(pipe_en)  expr=mem_read(addr)
// fp_cmp_1         -> fp_cmp_1          out=fp_cmp_1_pred       start= 50  end= 51  valid=(pipe_en)  expr=(fma(v2_z, (e2 * inv_area), fma(v1_z, (e1 * inv_area), (v0_z * (e0 * inv_area)))) <= mem_read(addr))
// mem_write_1      -> mem_write_1       out=mem_write_1_pred    start= 51  end= 52  valid=(pipe_en)  expr=mem_write(addr, fma(v2_z, (e2 * inv_area), fma(v1_z, (e1 * inv_area), (v0_z * (e0 * inv_area)))))
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
assign mem_read_1_fire = valid_pipe[48];
assign fp_cmp_1_fire = valid_pipe[51];

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
logic [THREAD_ADDR_W-1:0] align_addr_to_mem_read_1_i0_d48;
logic [31:0] align_fp_fma_4_to_fp_cmp_1_i0_d2;
logic [THREAD_ADDR_W-1:0] align_addr_to_mem_write_1_i0_d51;
logic [31:0] align_fp_fma_4_to_mem_write_1_i1_d3;
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

delay_pipe #(.WIDTH(32), .STAGES(8)) u_align_v0_z_to_fp_mul_10_i0_d8_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v0_z), .data_out(align_v0_z_to_fp_mul_10_i0_d8));
delay_pipe #(.WIDTH(32), .STAGES(8)) u_align_v0_w_to_fp_mul_4_i0_d8_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v0_w), .data_out(align_v0_w_to_fp_mul_4_i0_d8));
delay_pipe #(.WIDTH(32), .STAGES(8)) u_align_v1_w_to_fp_mul_6_i0_d8_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v1_w), .data_out(align_v1_w_to_fp_mul_6_i0_d8));
delay_pipe #(.WIDTH(32), .STAGES(8)) u_align_v2_w_to_fp_mul_8_i0_d8_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v2_w), .data_out(align_v2_w_to_fp_mul_8_i0_d8));
delay_pipe #(.WIDTH(32), .STAGES(8)) u_align_v1_w_to_fp_fma_1_i0_d16_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(align_v1_w_to_fp_mul_6_i0_d8), .data_out(align_v1_w_to_fp_fma_1_i0_d16));
delay_pipe #(.WIDTH(32), .STAGES(8)) u_align_fp_mul_2_to_fp_fma_1_i1_d8_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_mul_2_res), .data_out(align_fp_mul_2_to_fp_fma_1_i1_d8));
delay_pipe #(.WIDTH(32), .STAGES(16)) u_align_v1_z_to_fp_fma_3_i0_d16_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v1_z), .data_out(align_v1_z_to_fp_fma_3_i0_d16));
delay_pipe #(.WIDTH(32), .STAGES(8)) u_align_fp_mul_2_to_fp_fma_3_i1_d8_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_mul_2_res), .data_out(align_fp_mul_2_to_fp_fma_3_i1_d8));
delay_pipe #(.WIDTH(32), .STAGES(24)) u_align_v2_w_to_fp_fma_2_i0_d32_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(align_v2_w_to_fp_mul_8_i0_d8), .data_out(align_v2_w_to_fp_fma_2_i0_d32));
delay_pipe #(.WIDTH(32), .STAGES(24)) u_align_fp_mul_3_to_fp_fma_2_i1_d24_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_mul_3_res), .data_out(align_fp_mul_3_to_fp_fma_2_i1_d24));
delay_pipe #(.WIDTH(32), .STAGES(32)) u_align_v2_z_to_fp_fma_4_i0_d32_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v2_z), .data_out(align_v2_z_to_fp_fma_4_i0_d32));
delay_pipe #(.WIDTH(32), .STAGES(24)) u_align_fp_mul_3_to_fp_fma_4_i1_d24_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_mul_3_res), .data_out(align_fp_mul_3_to_fp_fma_4_i1_d24));
delay_pipe #(.WIDTH(THREAD_ADDR_W), .STAGES(48)) u_align_addr_to_mem_read_1_i0_d48_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.addr[THREAD_ADDR_W-1:0]), .data_out(align_addr_to_mem_read_1_i0_d48));
delay_pipe #(.WIDTH(32), .STAGES(2)) u_align_fp_fma_4_to_fp_cmp_1_i0_d2_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_fma_4_res), .data_out(align_fp_fma_4_to_fp_cmp_1_i0_d2));
delay_pipe #(.WIDTH(THREAD_ADDR_W), .STAGES(3)) u_align_addr_to_mem_write_1_i0_d51_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(align_addr_to_mem_read_1_i0_d48), .data_out(align_addr_to_mem_write_1_i0_d51));
delay_pipe #(.WIDTH(32), .STAGES(3)) u_align_fp_fma_4_to_mem_write_1_i1_d3_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_fma_4_res), .data_out(align_fp_fma_4_to_mem_write_1_i1_d3));
delay_pipe #(.WIDTH(32), .STAGES(61)) u_align_fp_mul_4_to_fp_mul_5_i1_d61_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_mul_5_res), .data_out(align_fp_mul_4_to_fp_mul_5_i1_d61));
delay_pipe #(.WIDTH(32), .STAGES(61)) u_align_fp_mul_6_to_fp_mul_7_i1_d61_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_mul_6_res), .data_out(align_fp_mul_6_to_fp_mul_7_i1_d61));
delay_pipe #(.WIDTH(32), .STAGES(61)) u_align_fp_mul_8_to_fp_mul_9_i1_d61_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_mul_7_res), .data_out(align_fp_mul_8_to_fp_mul_9_i1_d61));
delay_pipe #(.WIDTH(8), .STAGES(87)) u_align_v0_color_r_to_fx_color_mul_1_i0_d87_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v0_color_r), .data_out(align_v0_color_r_to_fx_color_mul_1_i0_d87));
delay_pipe #(.WIDTH(8), .STAGES(87)) u_align_v0_color_g_to_fx_color_mul_2_i0_d87_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v0_color_g), .data_out(align_v0_color_g_to_fx_color_mul_2_i0_d87));
delay_pipe #(.WIDTH(8), .STAGES(87)) u_align_v0_color_b_to_fx_color_mul_3_i0_d87_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v0_color_b), .data_out(align_v0_color_b_to_fx_color_mul_3_i0_d87));
delay_pipe #(.WIDTH(8), .STAGES(87)) u_align_v0_color_a_to_fx_color_mul_4_i0_d87_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v0_color_a), .data_out(align_v0_color_a_to_fx_color_mul_4_i0_d87));
delay_pipe #(.WIDTH(18), .STAGES(87)) u_align_v0_texture_u_to_fx_texture_mul_1_i1_d87_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v0_u), .data_out(align_v0_texture_u_to_fx_texture_mul_1_i1_d87));
delay_pipe #(.WIDTH(18), .STAGES(87)) u_align_v0_texture_v_to_fx_texture_mul_2_i1_d87_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v0_v), .data_out(align_v0_texture_v_to_fx_texture_mul_2_i1_d87));
delay_pipe #(.WIDTH(8), .STAGES(88)) u_align_v1_color_r_to_fx_color_fma_1_i0_d88_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v1_color_r), .data_out(align_v1_color_r_to_fx_color_fma_1_i0_d88));
delay_pipe #(.WIDTH(25), .STAGES(1)) u_align_fp_to_fx2_23_2_to_fx_color_fma_1_i1_d1_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_to_fx2_23_2_res), .data_out(align_fp_to_fx2_23_2_to_fx_color_fma_1_i1_d1));
delay_pipe #(.WIDTH(8), .STAGES(88)) u_align_v1_color_g_to_fx_color_fma_3_i0_d88_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v1_color_g), .data_out(align_v1_color_g_to_fx_color_fma_3_i0_d88));
delay_pipe #(.WIDTH(25), .STAGES(1)) u_align_fp_to_fx2_23_2_to_fx_color_fma_3_i1_d1_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_to_fx2_23_2_res), .data_out(align_fp_to_fx2_23_2_to_fx_color_fma_3_i1_d1));
delay_pipe #(.WIDTH(8), .STAGES(88)) u_align_v1_color_b_to_fx_color_fma_5_i0_d88_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v1_color_b), .data_out(align_v1_color_b_to_fx_color_fma_5_i0_d88));
delay_pipe #(.WIDTH(25), .STAGES(1)) u_align_fp_to_fx2_23_2_to_fx_color_fma_5_i1_d1_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_to_fx2_23_2_res), .data_out(align_fp_to_fx2_23_2_to_fx_color_fma_5_i1_d1));
delay_pipe #(.WIDTH(8), .STAGES(88)) u_align_v1_color_a_to_fx_color_fma_7_i0_d88_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v1_color_a), .data_out(align_v1_color_a_to_fx_color_fma_7_i0_d88));
delay_pipe #(.WIDTH(25), .STAGES(1)) u_align_fp_to_fx2_23_2_to_fx_color_fma_7_i1_d1_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_to_fx2_23_2_res), .data_out(align_fp_to_fx2_23_2_to_fx_color_fma_7_i1_d1));
delay_pipe #(.WIDTH(25), .STAGES(1)) u_align_fp_to_fx2_23_2_to_fx_texture_fma_1_i0_d1_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_to_fx2_23_2_res), .data_out(align_fp_to_fx2_23_2_to_fx_texture_fma_1_i0_d1));
delay_pipe #(.WIDTH(18), .STAGES(88)) u_align_v1_texture_u_to_fx_texture_fma_1_i1_d88_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v1_u), .data_out(align_v1_texture_u_to_fx_texture_fma_1_i1_d88));
delay_pipe #(.WIDTH(25), .STAGES(1)) u_align_fp_to_fx2_23_2_to_fx_texture_fma_3_i0_d1_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_to_fx2_23_2_res), .data_out(align_fp_to_fx2_23_2_to_fx_texture_fma_3_i0_d1));
delay_pipe #(.WIDTH(18), .STAGES(88)) u_align_v1_texture_v_to_fx_texture_fma_3_i1_d88_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v1_v), .data_out(align_v1_texture_v_to_fx_texture_fma_3_i1_d88));
delay_pipe #(.WIDTH(8), .STAGES(90)) u_align_v2_color_r_to_fx_color_fma_2_i0_d90_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v2_color_r), .data_out(align_v2_color_r_to_fx_color_fma_2_i0_d90));
delay_pipe #(.WIDTH(25), .STAGES(3)) u_align_fp_to_fx2_23_3_to_fx_color_fma_2_i1_d3_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_to_fx2_23_3_res), .data_out(align_fp_to_fx2_23_3_to_fx_color_fma_2_i1_d3));
delay_pipe #(.WIDTH(8), .STAGES(90)) u_align_v2_color_g_to_fx_color_fma_4_i0_d90_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v2_color_g), .data_out(align_v2_color_g_to_fx_color_fma_4_i0_d90));
delay_pipe #(.WIDTH(25), .STAGES(3)) u_align_fp_to_fx2_23_3_to_fx_color_fma_4_i1_d3_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_to_fx2_23_3_res), .data_out(align_fp_to_fx2_23_3_to_fx_color_fma_4_i1_d3));
delay_pipe #(.WIDTH(8), .STAGES(90)) u_align_v2_color_b_to_fx_color_fma_6_i0_d90_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v2_color_b), .data_out(align_v2_color_b_to_fx_color_fma_6_i0_d90));
delay_pipe #(.WIDTH(25), .STAGES(3)) u_align_fp_to_fx2_23_3_to_fx_color_fma_6_i1_d3_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_to_fx2_23_3_res), .data_out(align_fp_to_fx2_23_3_to_fx_color_fma_6_i1_d3));
delay_pipe #(.WIDTH(8), .STAGES(90)) u_align_v2_color_a_to_fx_color_fma_8_i0_d90_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v2_color_a), .data_out(align_v2_color_a_to_fx_color_fma_8_i0_d90));
delay_pipe #(.WIDTH(25), .STAGES(3)) u_align_fp_to_fx2_23_3_to_fx_color_fma_8_i1_d3_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_to_fx2_23_3_res), .data_out(align_fp_to_fx2_23_3_to_fx_color_fma_8_i1_d3));
delay_pipe #(.WIDTH(25), .STAGES(3)) u_align_fp_to_fx2_23_3_to_fx_texture_fma_2_i0_d3_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_to_fx2_23_3_res), .data_out(align_fp_to_fx2_23_3_to_fx_texture_fma_2_i0_d3));
delay_pipe #(.WIDTH(18), .STAGES(90)) u_align_v2_texture_u_to_fx_texture_fma_2_i1_d90_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v2_u), .data_out(align_v2_texture_u_to_fx_texture_fma_2_i1_d90));
delay_pipe #(.WIDTH(25), .STAGES(3)) u_align_fp_to_fx2_23_3_to_fx_texture_fma_4_i0_d3_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_to_fx2_23_3_res), .data_out(align_fp_to_fx2_23_3_to_fx_texture_fma_4_i0_d3));
delay_pipe #(.WIDTH(18), .STAGES(90)) u_align_v2_texture_v_to_fx_texture_fma_4_i1_d90_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(thread_data_buf.v2_v), .data_out(align_v2_texture_v_to_fx_texture_fma_4_i1_d90));

// Leaf ready signals not used (internal distribution only)

// ---- Unit output ready wiring ----
// None (non-blocking FP modules have no AXIS output ready)

// ---- Unit instantiation skeletons ----
// NOTE: Non-blocking FP modules with aclken(pipe_en_internal)
// NOTE: Valid is propagated explicitly via valid_pipe
fp_mul #(.LATENCY(8)) u_fp_mul_1 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[1]),
    .valid_in(),
    .a(thread_data_buf.e0), .b(thread_data_buf.inv_area),
    .result(fp_mul_1_res)
);
fp_mul #(.LATENCY(8)) u_fp_mul_2 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[1]),
    .valid_in(),
    .a(thread_data_buf.e1), .b(thread_data_buf.inv_area),
    .result(fp_mul_2_res)
);
fp_mul #(.LATENCY(8)) u_fp_mul_3 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[1]),
    .valid_in(),
    .a(thread_data_buf.e2), .b(thread_data_buf.inv_area),
    .result(fp_mul_3_res)
);
fp_mul #(.LATENCY(8)) u_fp_mul_4 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[9]),
    .valid_in(),
    .a(align_v0_z_to_fp_mul_10_i0_d8), .b(fp_mul_1_res),
    .result(fp_mul_4_res)
);
fp_mul #(.LATENCY(8)) u_fp_mul_5 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[9]),
    .valid_in(),
    .a(align_v0_w_to_fp_mul_4_i0_d8), .b(fp_mul_1_res),
    .result(fp_mul_5_res)
);
fp_mul #(.LATENCY(8)) u_fp_mul_6 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[9]),
    .valid_in(),
    .a(align_v1_w_to_fp_mul_6_i0_d8), .b(fp_mul_2_res),
    .result(fp_mul_6_res)
);
fp_mul #(.LATENCY(8)) u_fp_mul_7 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[9]),
    .valid_in(),
    .a(align_v2_w_to_fp_mul_8_i0_d8), .b(fp_mul_3_res),
    .result(fp_mul_7_res)
);
fp_fma #(.LATENCY(16)) u_fp_fma_1 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[17]),
    .valid_in(),
    .a(align_v1_w_to_fp_fma_1_i0_d16), .b(align_fp_mul_2_to_fp_fma_1_i1_d8), .c(fp_mul_5_res),
    .result(fp_fma_1_res)
);
fp_fma #(.LATENCY(16)) u_fp_fma_2 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[17]),
    .valid_in(),
    .a(align_v1_z_to_fp_fma_3_i0_d16), .b(align_fp_mul_2_to_fp_fma_3_i1_d8), .c(fp_mul_4_res),
    .result(fp_fma_2_res)
);
fp_fma #(.LATENCY(16)) u_fp_fma_3 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[33]),
    .valid_in(),
    .a(align_v2_w_to_fp_fma_2_i0_d32), .b(align_fp_mul_3_to_fp_fma_2_i1_d24), .c(fp_fma_1_res),
    .result(fp_fma_3_res)
);
fp_fma #(.LATENCY(16)) u_fp_fma_4 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[33]),
    .valid_in(),
    .a(align_v2_z_to_fp_fma_4_i0_d32), .b(align_fp_mul_3_to_fp_fma_4_i1_d24), .c(fp_fma_2_res),
    .result(fp_fma_4_res)
);
fp_recip #(.LATENCY(29)) u_fp_recip_1 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[49]),
    .valid_in(),
    .a(fp_fma_3_res),
    .result(fp_recip_1_out)
);
assign z_rd_en = mem_read_1_fire && pipe_en_internal;
assign z_rd_addr = align_addr_to_mem_read_1_i0_d48;
assign mem_read_1_rdata = z_rd_data;
fp_cmp_le u_fp_cmp_1 (
    .aclk(clk),
    .aclken(pipe_en_internal),
    .s_axis_a(align_fp_fma_4_to_fp_cmp_1_i0_d2),
    //   .s_axis_a_valid(),
    .s_axis_b(mem_read_1_rdata),
    //   .s_axis_b_valid(),
    .m_axis_res(fp_cmp_1_pred[0])
    //   .m_axis_tvalid()
);
assign mem_write_1_fire = valid_pipe[51];
assign mem_write_1_pred[0] = (fp_cmp_1_pred[0]);
assign z_wr_en = mem_write_1_fire && mem_write_1_pred[0] && pipe_en_internal;
assign z_wr_addr = align_addr_to_mem_write_1_i0_d51;
assign z_wr_data = align_fp_fma_4_to_mem_write_1_i1_d3;
fp_mul #(.LATENCY(8)) u_fp_mul_8 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[78]),
    .valid_in(),
    .a(fp_recip_1_out), .b(align_fp_mul_4_to_fp_mul_5_i1_d61),
    .result(fp_mul_8_res)
);
fp_mul #(.LATENCY(8)) u_fp_mul_9 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[78]),
    .valid_in(),
    .a(fp_recip_1_out), .b(align_fp_mul_6_to_fp_mul_7_i1_d61),
    .result(fp_mul_9_res)
);
fp_mul #(.LATENCY(8)) u_fp_mul_10 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[78]),
    .valid_in(),
    .a(fp_recip_1_out), .b(align_fp_mul_8_to_fp_mul_9_i1_d61),
    .result(fp_mul_10_res)
);
fp_to_fx2_23 u_fp_to_fx2_23_1 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    .s_axis_a_tvalid(valid_pipe[86]),
    .s_axis_a_tdata(fp_mul_8_res),
    .m_axis_result_tvalid(),
    .m_axis_result_tdata(fp_to_fx2_23_1_res)
);
fp_to_fx2_23 u_fp_to_fx2_23_2 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    .s_axis_a_tvalid(valid_pipe[86]),
    .s_axis_a_tdata(fp_mul_9_res),
    .m_axis_result_tvalid(),
    .m_axis_result_tdata(fp_to_fx2_23_2_res)
);
fp_to_fx2_23 u_fp_to_fx2_23_3 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    .s_axis_a_tvalid(valid_pipe[86]),
    .s_axis_a_tdata(fp_mul_10_res),
    .m_axis_result_tvalid(),
    .m_axis_result_tdata(fp_to_fx2_23_3_res)
);
fx_color_mul u_fx_color_mul_1 (
    .clk(clk), .clken(pipe_en_internal),
    .a(align_v0_color_r_to_fx_color_mul_1_i0_d87), .b(fp_to_fx2_23_1_res),
    .q(fx_color_mul_1_res)
);
fx_color_mul u_fx_color_mul_2 (
    .clk(clk), .clken(pipe_en_internal),
    .a(align_v0_color_g_to_fx_color_mul_2_i0_d87), .b(fp_to_fx2_23_1_res),
    .q(fx_color_mul_2_res)
);
fx_color_mul u_fx_color_mul_3 (
    .clk(clk), .clken(pipe_en_internal),
    .a(align_v0_color_b_to_fx_color_mul_3_i0_d87), .b(fp_to_fx2_23_1_res),
    .q(fx_color_mul_3_res)
);
fx_color_mul u_fx_color_mul_4 (
    .clk(clk), .clken(pipe_en_internal),
    .a(align_v0_color_a_to_fx_color_mul_4_i0_d87), .b(fp_to_fx2_23_1_res),
    .q(fx_color_mul_4_res)
);
fx_texture_mul u_fx_texture_mul_1 (
    .clk(clk), .clken(pipe_en_internal),
    .a(fp_to_fx2_23_1_res), .b(align_v0_texture_u_to_fx_texture_mul_1_i1_d87),
    .q(fx_texture_mul_1_res)
);
fx_texture_mul u_fx_texture_mul_2 (
    .clk(clk), .clken(pipe_en_internal),
    .a(fp_to_fx2_23_1_res), .b(align_v0_texture_v_to_fx_texture_mul_2_i1_d87),
    .q(fx_texture_mul_2_res)
);
fx_color_fma u_fx_color_fma_1 (
    .clk(clk), .clken(pipe_en_internal),
    .a(align_v1_color_r_to_fx_color_fma_1_i0_d88), .b(align_fp_to_fx2_23_2_to_fx_color_fma_1_i1_d1), .c(fx_color_mul_1_res),
    .q(fx_color_fma_1_res)
);
fx_color_fma u_fx_color_fma_2 (
    .clk(clk), .clken(pipe_en_internal),
    .a(align_v1_color_g_to_fx_color_fma_3_i0_d88), .b(align_fp_to_fx2_23_2_to_fx_color_fma_3_i1_d1), .c(fx_color_mul_2_res),
    .q(fx_color_fma_2_res)
);
fx_color_fma u_fx_color_fma_3 (
    .clk(clk), .clken(pipe_en_internal),
    .a(align_v1_color_b_to_fx_color_fma_5_i0_d88), .b(align_fp_to_fx2_23_2_to_fx_color_fma_5_i1_d1), .c(fx_color_mul_3_res),
    .q(fx_color_fma_3_res)
);
fx_color_fma u_fx_color_fma_4 (
    .clk(clk), .clken(pipe_en_internal),
    .a(align_v1_color_a_to_fx_color_fma_7_i0_d88), .b(align_fp_to_fx2_23_2_to_fx_color_fma_7_i1_d1), .c(fx_color_mul_4_res),
    .q(fx_color_fma_4_res)
);
fx_texture_fma u_fx_texture_fma_1 (
    .clk(clk), .clken(pipe_en_internal),
    .a(align_fp_to_fx2_23_2_to_fx_texture_fma_1_i0_d1), .b(align_v1_texture_u_to_fx_texture_fma_1_i1_d88), .c(fx_texture_mul_1_res),
    .q(fx_texture_fma_1_res)
);
fx_texture_fma u_fx_texture_fma_2 (
    .clk(clk), .clken(pipe_en_internal),
    .a(align_fp_to_fx2_23_2_to_fx_texture_fma_3_i0_d1), .b(align_v1_texture_v_to_fx_texture_fma_3_i1_d88), .c(fx_texture_mul_2_res),
    .q(fx_texture_fma_2_res)
);
fx_color_fma u_fx_color_fma_5 (
    .clk(clk), .clken(pipe_en_internal),
    .a(align_v2_color_r_to_fx_color_fma_2_i0_d90), .b(align_fp_to_fx2_23_3_to_fx_color_fma_2_i1_d3), .c(fx_color_fma_1_res),
    .q(fx_color_fma_5_res)
);
fx_color_fma u_fx_color_fma_6 (
    .clk(clk), .clken(pipe_en_internal),
    .a(align_v2_color_g_to_fx_color_fma_4_i0_d90), .b(align_fp_to_fx2_23_3_to_fx_color_fma_4_i1_d3), .c(fx_color_fma_2_res),
    .q(fx_color_fma_6_res)
);
fx_color_fma u_fx_color_fma_7 (
    .clk(clk), .clken(pipe_en_internal),
    .a(align_v2_color_b_to_fx_color_fma_6_i0_d90), .b(align_fp_to_fx2_23_3_to_fx_color_fma_6_i1_d3), .c(fx_color_fma_3_res),
    .q(fx_color_fma_7_res)
);
fx_color_fma u_fx_color_fma_8 (
    .clk(clk), .clken(pipe_en_internal),
    .a(align_v2_color_a_to_fx_color_fma_8_i0_d90), .b(align_fp_to_fx2_23_3_to_fx_color_fma_8_i1_d3), .c(fx_color_fma_4_res),
    .q(fx_color_fma_8_res)
);
fx_texture_fma u_fx_texture_fma_3 (
    .clk(clk), .clken(pipe_en_internal),
    .a(align_fp_to_fx2_23_3_to_fx_texture_fma_2_i0_d3), .b(align_v2_texture_u_to_fx_texture_fma_2_i1_d90), .c(fx_texture_fma_1_res),
    .q(fx_texture_fma_3_res)
);
fx_texture_fma u_fx_texture_fma_4 (
    .clk(clk), .clken(pipe_en_internal),
    .a(align_fp_to_fx2_23_3_to_fx_texture_fma_4_i0_d3), .b(align_v2_texture_v_to_fx_texture_fma_4_i1_d90), .c(fx_texture_fma_2_res),
    .q(fx_texture_fma_4_res)
);
fx_color_to_u8 u_fx_color_to_u8_1 (
    .clk(clk), .clken(pipe_en_internal),
    .in_fx_color(fx_color_fma_5_res),
    .out_u8(fx_color_to_u8_1_res)
);
fx_color_to_u8 u_fx_color_to_u8_2 (
    .clk(clk), .clken(pipe_en_internal),
    .in_fx_color(fx_color_fma_6_res),
    .out_u8(fx_color_to_u8_2_res)
);
fx_color_to_u8 u_fx_color_to_u8_3 (
    .clk(clk), .clken(pipe_en_internal),
    .in_fx_color(fx_color_fma_7_res),
    .out_u8(fx_color_to_u8_3_res)
);
fx_color_to_u8 u_fx_color_to_u8_4 (
    .clk(clk), .clken(pipe_en_internal),
    .in_fx_color(fx_color_fma_8_res),
    .out_u8(fx_color_to_u8_4_res)
);

// ---- Output skid buffer ----
localparam int OUTBUNDLEWIDTH = $bits(texcoord_u_tdata) + $bits(texcoord_v_tdata) + $bits(addr_tdata) + $bits(tex_id_tdata) + $bits(texture_mode_u_tdata) + $bits(texture_mode_v_tdata) + $bits(texture_function_tdata) + $bits(color_r_tdata) + $bits(color_g_tdata) + $bits(color_b_tdata) + $bits(color_a_tdata) + $bits(comp_z_tdata);
logic [OUTBUNDLEWIDTH-1:0] output_bundle_tdata;
logic output_bundle_tvalid;
logic output_bundle_s_axis_tready;
logic [OUTBUNDLEWIDTH-1:0] output_bundle_buf_tdata;
logic output_bundle_buf_tvalid;
logic output_bundle_buf_tready;

logic [47:0] texcoord_u_bundle_tdata;
delay_pipe #(.WIDTH(48), .STAGES(1)) u_align_texcoord_u_to_output_bundle_d1 (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(texcoord_u_tdata), .data_out(texcoord_u_bundle_tdata));
logic [47:0] texcoord_v_bundle_tdata;
delay_pipe #(.WIDTH(48), .STAGES(1)) u_align_texcoord_v_to_output_bundle_d1 (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(texcoord_v_tdata), .data_out(texcoord_v_bundle_tdata));
logic [THREAD_ADDR_W-1:0] addr_bundle_tdata;
delay_pipe #(.WIDTH(THREAD_ADDR_W), .STAGES(93)) u_align_addr_to_output_bundle_d93 (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(addr_tdata), .data_out(addr_bundle_tdata));
logic [7:0] tex_id_bundle_tdata;
delay_pipe #(.WIDTH(8), .STAGES(93)) u_align_tex_id_to_output_bundle_d93 (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(tex_id_tdata), .data_out(tex_id_bundle_tdata));
logic texture_mode_u_bundle_tdata;
delay_pipe #(.WIDTH(1), .STAGES(93)) u_align_texture_mode_u_to_output_bundle_d93 (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(texture_mode_u_tdata), .data_out(texture_mode_u_bundle_tdata));
logic texture_mode_v_bundle_tdata;
delay_pipe #(.WIDTH(1), .STAGES(93)) u_align_texture_mode_v_to_output_bundle_d93 (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(texture_mode_v_tdata), .data_out(texture_mode_v_bundle_tdata));
logic [2:0] texture_function_bundle_tdata;
delay_pipe #(.WIDTH(3), .STAGES(93)) u_align_texture_function_to_output_bundle_d93 (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(texture_function_tdata), .data_out(texture_function_bundle_tdata));
logic comp_z_bundle_tdata;
delay_pipe #(.WIDTH(1), .STAGES(42)) u_align_comp_z_to_output_bundle_d42 (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(comp_z_tdata), .data_out(comp_z_bundle_tdata));

assign output_bundle_tdata = {texcoord_u_bundle_tdata, texcoord_v_bundle_tdata, addr_bundle_tdata, tex_id_bundle_tdata, texture_mode_u_bundle_tdata, texture_mode_v_bundle_tdata, texture_function_bundle_tdata, color_r_tdata, color_g_tdata, color_b_tdata, color_a_tdata, comp_z_bundle_tdata};
assign output_bundle_tvalid = valid_pipe[93];

axis_skid_buffer #(
    .WIDTH(OUTBUNDLEWIDTH)
) u_output_bundle_skid (
    .aclk(clk), .aresetn(rst_n),
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

