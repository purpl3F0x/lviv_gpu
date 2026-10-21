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
logic [31:0] mem_read_1_rdata;
logic [31:0] fp_recip_1_out;
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
logic [31:0] fx_color_interpolate_1_res;
logic [47:0] fx_texture_interpolate_1_res;
logic [47:0] fx_texture_interpolate_2_res;

// ---- Selected outputs ----
logic [47:0] texcoord_u_tdata;
assign texcoord_u_tdata = fx_texture_interpolate_1_res;
logic [47:0] texcoord_v_tdata;
assign texcoord_v_tdata = fx_texture_interpolate_2_res;
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
logic [$bits(blend_op_t)-1:0] sfactor_op_tdata;
assign sfactor_op_tdata = thread_data_buf.sfactor_op;
logic [$bits(blend_op_t)-1:0] dfactor_op_tdata;
assign dfactor_op_tdata = thread_data_buf.dfactor_op;
logic [31:0] color_tdata;
assign color_tdata = fx_color_interpolate_1_res;
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
// mem_read_1       -> mem_read_1        out=mem_read_1_rdata    start= 47  end= 50  valid=(pipe_en)  expr=mem_read(addr)
// fp_recip_1       -> fp_recip_1        out=fp_recip_1_out      start= 48  end= 77  valid=(pipe_en)  expr=(1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area)))))
// fp_cmp_1         -> fp_cmp_1          out=fp_cmp_1_pred       start= 50  end= 53  valid=(pipe_en)  expr=depth_compare(fma(v2_z, (e2 * inv_area), fma(v1_z, (e1 * inv_area), (v0_z * (e0 * inv_area)))), mem_read(addr), depth_func)
// mem_write_1      -> mem_write_1       out=mem_write_1_pred    start= 53  end= 54  valid=(pipe_en)  expr=mem_write(addr, fma(v2_z, (e2 * inv_area), fma(v1_z, (e1 * inv_area), (v0_z * (e0 * inv_area)))))
// fp_mul_5         -> fp_mul_8          out=fp_mul_8_res        start= 77  end= 85  valid=(pipe_en)  expr=((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area)))
// fp_mul_7         -> fp_mul_9          out=fp_mul_9_res        start= 77  end= 85  valid=(pipe_en)  expr=((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area)))
// fp_mul_9         -> fp_mul_10         out=fp_mul_10_res       start= 77  end= 85  valid=(pipe_en)  expr=((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v2_w * (e2 * inv_area)))
// fp_to_fx2_23_1   -> fp_to_fx2_23_1    out=fp_to_fx2_23_1_res  start= 85  end= 88  valid=(pipe_en)  expr=fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area))))
// fp_to_fx2_23_2   -> fp_to_fx2_23_2    out=fp_to_fx2_23_2_res  start= 85  end= 88  valid=(pipe_en)  expr=fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area))))
// fp_to_fx2_23_3   -> fp_to_fx2_23_3    out=fp_to_fx2_23_3_res  start= 85  end= 88  valid=(pipe_en)  expr=fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v2_w * (e2 * inv_area))))
// fx_color_interpolate_1 -> fx_color_interpolate_1  out=fx_color_interpolate_1_res  start= 88  end= 94  valid=(pipe_en)  expr=color_interpolate(v0_color, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area)))), v1_color, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area)))), v2_color, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v2_w * (e2 * inv_area)))))
// fx_texture_interpolate_1 -> fx_texture_interpolate_1  out=fx_texture_interpolate_1_res  start= 88  end= 94  valid=(pipe_en)  expr=texture_interpolate(v0_texture_u, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area)))), v1_texture_u, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area)))), v2_texture_u, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v2_w * (e2 * inv_area)))))
// fx_texture_interpolate_2 -> fx_texture_interpolate_2  out=fx_texture_interpolate_2_res  start= 88  end= 94  valid=(pipe_en)  expr=texture_interpolate(v0_texture_v, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v0_w * (e0 * inv_area)))), v1_texture_v, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v1_w * (e1 * inv_area)))), v2_texture_v, fp_to_fx2_23(((1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))) * (v2_w * (e2 * inv_area)))))

// ---- Non-AXIS consumer fire wiring ----
logic mem_read_1_fire;
logic fp_cmp_1_fire;
assign mem_read_1_fire = valid_pipe[47];
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
logic [THREAD_ADDR_W-1:0] align_addr_to_mem_read_1_i0_d47;
logic [31:0] align_fp_fma_4_to_fp_cmp_1_i0_d2;
logic [2:0] align_depth_func_to_fp_cmp_1_i2_d50;
logic [THREAD_ADDR_W-1:0] align_addr_to_mem_write_1_i0_d53;
logic [31:0] align_fp_fma_4_to_mem_write_1_i1_d5;
logic [31:0] align_fp_mul_4_to_fp_mul_5_i1_d61;
logic [31:0] align_fp_mul_6_to_fp_mul_7_i1_d61;
logic [31:0] align_fp_mul_8_to_fp_mul_9_i1_d61;
logic [31:0] align_v0_color_to_fx_color_interpolate_1_i0_d88;
logic [31:0] align_v1_color_to_fx_color_interpolate_1_i2_d88;
logic [31:0] align_v2_color_to_fx_color_interpolate_1_i4_d88;
logic [17:0] align_v0_texture_u_to_fx_texture_interpolate_1_i0_d88;
logic [17:0] align_v1_texture_u_to_fx_texture_interpolate_1_i2_d88;
logic [17:0] align_v2_texture_u_to_fx_texture_interpolate_1_i4_d88;
logic [17:0] align_v0_texture_v_to_fx_texture_interpolate_2_i0_d88;
logic [17:0] align_v1_texture_v_to_fx_texture_interpolate_2_i2_d88;
logic [17:0] align_v2_texture_v_to_fx_texture_interpolate_2_i4_d88;

assign align_fp_mul_2_to_fp_fma_3_i1_d8 = align_fp_mul_2_to_fp_fma_1_i1_d8;
assign align_fp_mul_3_to_fp_fma_4_i1_d24 = align_fp_mul_3_to_fp_fma_2_i1_d24;
logic [128-1:0] align_s0_d8_in, align_s0_d8_out;
assign align_s0_d8_in = {thread_data_buf.v0_z, thread_data_buf.v0_w, thread_data_buf.v1_w, thread_data_buf.v2_w};
delay_pipe #(.WIDTH(128), .STAGES(8)) u_align_s0_d8 (.clk(clk), .rst_n(1'b1), .clken(pipe_en_internal), .data_in(align_s0_d8_in), .data_out(align_s0_d8_out));
assign {align_v0_z_to_fp_mul_10_i0_d8, align_v0_w_to_fp_mul_4_i0_d8, align_v1_w_to_fp_mul_6_i0_d8, align_v2_w_to_fp_mul_8_i0_d8} = align_s0_d8_out;
logic [64-1:0] align_s8_d8_in, align_s8_d8_out;
assign align_s8_d8_in = {align_v1_w_to_fp_mul_6_i0_d8, fp_mul_2_res};
delay_pipe #(.WIDTH(64), .STAGES(8)) u_align_s8_d8 (.clk(clk), .rst_n(1'b1), .clken(pipe_en_internal), .data_in(align_s8_d8_in), .data_out(align_s8_d8_out));
assign {align_v1_w_to_fp_fma_1_i0_d16, align_fp_mul_2_to_fp_fma_1_i1_d8} = align_s8_d8_out;
delay_pipe #(.WIDTH(32), .STAGES(16)) u_align_v1_z_to_fp_fma_3_i0_d16_data_delay (.clk(clk), .rst_n(1'b1), .clken(pipe_en_internal), .data_in(thread_data_buf.v1_z), .data_out(align_v1_z_to_fp_fma_3_i0_d16));
logic [64-1:0] align_s8_d24_in, align_s8_d24_out;
assign align_s8_d24_in = {align_v2_w_to_fp_mul_8_i0_d8, fp_mul_3_res};
delay_pipe #(.WIDTH(64), .STAGES(24)) u_align_s8_d24 (.clk(clk), .rst_n(1'b1), .clken(pipe_en_internal), .data_in(align_s8_d24_in), .data_out(align_s8_d24_out));
assign {align_v2_w_to_fp_fma_2_i0_d32, align_fp_mul_3_to_fp_fma_2_i1_d24} = align_s8_d24_out;
delay_pipe #(.WIDTH(32), .STAGES(32)) u_align_v2_z_to_fp_fma_4_i0_d32_data_delay (.clk(clk), .rst_n(1'b1), .clken(pipe_en_internal), .data_in(thread_data_buf.v2_z), .data_out(align_v2_z_to_fp_fma_4_i0_d32));
delay_pipe #(.WIDTH(THREAD_ADDR_W), .STAGES(47)) u_align_addr_to_mem_read_1_i0_d47_data_delay (.clk(clk), .rst_n(1'b1), .clken(pipe_en_internal), .data_in(thread_data_buf.addr[THREAD_ADDR_W-1:0]), .data_out(align_addr_to_mem_read_1_i0_d47));
delay_pipe #(.WIDTH(32), .STAGES(2)) u_align_fp_fma_4_to_fp_cmp_1_i0_d2_data_delay (.clk(clk), .rst_n(1'b1), .clken(pipe_en_internal), .data_in(fp_fma_4_res), .data_out(align_fp_fma_4_to_fp_cmp_1_i0_d2));
delay_pipe #(.WIDTH(3), .STAGES(50)) u_align_depth_func_to_fp_cmp_1_i2_d50_data_delay (.clk(clk), .rst_n(1'b1), .clken(pipe_en_internal), .data_in(thread_data_buf.depth_func), .data_out(align_depth_func_to_fp_cmp_1_i2_d50));
delay_pipe #(.WIDTH(THREAD_ADDR_W), .STAGES(6)) u_align_addr_to_mem_write_1_i0_d53_data_delay (.clk(clk), .rst_n(1'b1), .clken(pipe_en_internal), .data_in(align_addr_to_mem_read_1_i0_d47), .data_out(align_addr_to_mem_write_1_i0_d53));
delay_pipe #(.WIDTH(32), .STAGES(5)) u_align_fp_fma_4_to_mem_write_1_i1_d5_data_delay (.clk(clk), .rst_n(1'b1), .clken(pipe_en_internal), .data_in(fp_fma_4_res), .data_out(align_fp_fma_4_to_mem_write_1_i1_d5));
logic [96-1:0] align_s16_d61_in, align_s16_d61_out;
assign align_s16_d61_in = {fp_mul_5_res, fp_mul_6_res, fp_mul_7_res};
delay_pipe #(.WIDTH(96), .STAGES(61)) u_align_s16_d61 (.clk(clk), .rst_n(1'b1), .clken(pipe_en_internal), .data_in(align_s16_d61_in), .data_out(align_s16_d61_out));
assign {align_fp_mul_4_to_fp_mul_5_i1_d61, align_fp_mul_6_to_fp_mul_7_i1_d61, align_fp_mul_8_to_fp_mul_9_i1_d61} = align_s16_d61_out;
logic [204-1:0] align_s0_d88_in, align_s0_d88_out;
assign align_s0_d88_in = {thread_data_buf.v0_color, thread_data_buf.v1_color, thread_data_buf.v2_color, thread_data_buf.v0_u, thread_data_buf.v1_u, thread_data_buf.v2_u, thread_data_buf.v0_v, thread_data_buf.v1_v, thread_data_buf.v2_v};
delay_pipe #(.WIDTH(204), .STAGES(88)) u_align_s0_d88 (.clk(clk), .rst_n(1'b1), .clken(pipe_en_internal), .data_in(align_s0_d88_in), .data_out(align_s0_d88_out));
assign {align_v0_color_to_fx_color_interpolate_1_i0_d88, align_v1_color_to_fx_color_interpolate_1_i2_d88, align_v2_color_to_fx_color_interpolate_1_i4_d88, align_v0_texture_u_to_fx_texture_interpolate_1_i0_d88, align_v1_texture_u_to_fx_texture_interpolate_1_i2_d88, align_v2_texture_u_to_fx_texture_interpolate_1_i4_d88, align_v0_texture_v_to_fx_texture_interpolate_2_i0_d88, align_v1_texture_v_to_fx_texture_interpolate_2_i2_d88, align_v2_texture_v_to_fx_texture_interpolate_2_i4_d88} = align_s0_d88_out;

// Leaf ready signals not used (internal distribution only)

// ---- Unit output ready wiring ----
// None (non-blocking FP modules have no AXIS output ready)

// ---- Unit instantiation skeletons ----
// NOTE: Non-blocking FP modules with aclken(pipe_en_internal)
// NOTE: Valid is propagated explicitly via valid_pipe
fp_mul #(.LATENCY(8)) u_fp_mul_1 (
    .aclk(clk), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[1]),
    .valid_in(),
    .a(thread_data_buf.e0), .b(thread_data_buf.inv_area),
    .result(fp_mul_1_res)
);
fp_mul #(.LATENCY(8)) u_fp_mul_2 (
    .aclk(clk), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[1]),
    .valid_in(),
    .a(thread_data_buf.e1), .b(thread_data_buf.inv_area),
    .result(fp_mul_2_res)
);
fp_mul #(.LATENCY(8)) u_fp_mul_3 (
    .aclk(clk), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[1]),
    .valid_in(),
    .a(thread_data_buf.e2), .b(thread_data_buf.inv_area),
    .result(fp_mul_3_res)
);
fp_mul #(.LATENCY(8)) u_fp_mul_4 (
    .aclk(clk), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[9]),
    .valid_in(),
    .a(align_v0_z_to_fp_mul_10_i0_d8), .b(fp_mul_1_res),
    .result(fp_mul_4_res)
);
fp_mul #(.LATENCY(8)) u_fp_mul_5 (
    .aclk(clk), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[9]),
    .valid_in(),
    .a(align_v0_w_to_fp_mul_4_i0_d8), .b(fp_mul_1_res),
    .result(fp_mul_5_res)
);
fp_mul #(.LATENCY(8)) u_fp_mul_6 (
    .aclk(clk), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[9]),
    .valid_in(),
    .a(align_v1_w_to_fp_mul_6_i0_d8), .b(fp_mul_2_res),
    .result(fp_mul_6_res)
);
fp_mul #(.LATENCY(8)) u_fp_mul_7 (
    .aclk(clk), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[9]),
    .valid_in(),
    .a(align_v2_w_to_fp_mul_8_i0_d8), .b(fp_mul_3_res),
    .result(fp_mul_7_res)
);
fp_fma #(.LATENCY(16)) u_fp_fma_1 (
    .aclk(clk), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[17]),
    .valid_in(),
    .a(align_v1_w_to_fp_fma_1_i0_d16), .b(align_fp_mul_2_to_fp_fma_1_i1_d8), .c(fp_mul_5_res),
    .result(fp_fma_1_res)
);
fp_fma #(.LATENCY(16)) u_fp_fma_2 (
    .aclk(clk), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[17]),
    .valid_in(),
    .a(align_v1_z_to_fp_fma_3_i0_d16), .b(align_fp_mul_2_to_fp_fma_3_i1_d8), .c(fp_mul_4_res),
    .result(fp_fma_2_res)
);
fp_fma #(.LATENCY(16)) u_fp_fma_3 (
    .aclk(clk), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[33]),
    .valid_in(),
    .a(align_v2_w_to_fp_fma_2_i0_d32), .b(align_fp_mul_3_to_fp_fma_2_i1_d24), .c(fp_fma_1_res),
    .result(fp_fma_3_res)
);
fp_fma #(.LATENCY(16)) u_fp_fma_4 (
    .aclk(clk), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[33]),
    .valid_in(),
    .a(align_v2_z_to_fp_fma_4_i0_d32), .b(align_fp_mul_3_to_fp_fma_4_i1_d24), .c(fp_fma_2_res),
    .result(fp_fma_4_res)
);
assign z_rd_en = pipe_en_internal;
assign z_rd_addr = align_addr_to_mem_read_1_i0_d47;
assign mem_read_1_rdata = z_rd_data;
fp_recip #(.LATENCY(29)) u_fp_recip_1 (
    .aclk(clk), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[49]),
    .valid_in(),
    .a(fp_fma_3_res),
    .result(fp_recip_1_out)
);
fp_cmp_le u_fp_cmp_1 (
    .aclk(clk),
    .aclken(pipe_en_internal),
    .s_axis_a(align_fp_fma_4_to_fp_cmp_1_i0_d2),
    .s_axis_b(mem_read_1_rdata),
    .func(depth_func_t'(align_depth_func_to_fp_cmp_1_i2_d50)),
    .m_axis_res(fp_cmp_1_pred[0])
);
assign mem_write_1_fire = valid_pipe[53];
assign mem_write_1_pred[0] = (fp_cmp_1_pred[0]);
assign z_wr_en = mem_write_1_fire && mem_write_1_pred[0] && pipe_en_internal;
assign z_wr_addr = align_addr_to_mem_write_1_i0_d53;
assign z_wr_data = align_fp_fma_4_to_mem_write_1_i1_d5;
fp_mul #(.LATENCY(8)) u_fp_mul_8 (
    .aclk(clk), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[78]),
    .valid_in(),
    .a(fp_recip_1_out), .b(align_fp_mul_4_to_fp_mul_5_i1_d61),
    .result(fp_mul_8_res)
);
fp_mul #(.LATENCY(8)) u_fp_mul_9 (
    .aclk(clk), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[78]),
    .valid_in(),
    .a(fp_recip_1_out), .b(align_fp_mul_6_to_fp_mul_7_i1_d61),
    .result(fp_mul_9_res)
);
fp_mul #(.LATENCY(8)) u_fp_mul_10 (
    .aclk(clk), .aclken(pipe_en_internal),
    // .valid_in(valid_pipe[78]),
    .valid_in(),
    .a(fp_recip_1_out), .b(align_fp_mul_8_to_fp_mul_9_i1_d61),
    .result(fp_mul_10_res)
);
fp_to_fx2_23 #(.LATENCY(3)) u_fp_to_fx2_23_1 (
    .aclk(clk), .aclken(pipe_en_internal),
    .s_axis_a_tvalid(valid_pipe[86]),
    .s_axis_a_tdata(fp_mul_8_res),
    .m_axis_result_tvalid(),
    .m_axis_result_tdata(fp_to_fx2_23_1_res)
);
fp_to_fx2_23 #(.LATENCY(3)) u_fp_to_fx2_23_2 (
    .aclk(clk), .aclken(pipe_en_internal),
    .s_axis_a_tvalid(valid_pipe[86]),
    .s_axis_a_tdata(fp_mul_9_res),
    .m_axis_result_tvalid(),
    .m_axis_result_tdata(fp_to_fx2_23_2_res)
);
fp_to_fx2_23 #(.LATENCY(3)) u_fp_to_fx2_23_3 (
    .aclk(clk), .aclken(pipe_en_internal),
    .s_axis_a_tvalid(valid_pipe[86]),
    .s_axis_a_tdata(fp_mul_10_res),
    .m_axis_result_tvalid(),
    .m_axis_result_tdata(fp_to_fx2_23_3_res)
);
fx_color_interpolator u_fx_color_interpolate_1 (
    .clk(clk), .clken(pipe_en_internal),
    .color0(align_v0_color_to_fx_color_interpolate_1_i0_d88), .weight0(fp_to_fx2_23_1_res),
    .color1(align_v1_color_to_fx_color_interpolate_1_i2_d88), .weight1(fp_to_fx2_23_2_res),
    .color2(align_v2_color_to_fx_color_interpolate_1_i4_d88), .weight2(fp_to_fx2_23_3_res),
    .result(fx_color_interpolate_1_res)
);
fx_texture_interpolator u_fx_texture_interpolate_1 (
    .clk(clk), .clken(pipe_en_internal),
    .coord0(align_v0_texture_u_to_fx_texture_interpolate_1_i0_d88), .weight0(fp_to_fx2_23_1_res),
    .coord1(align_v1_texture_u_to_fx_texture_interpolate_1_i2_d88), .weight1(fp_to_fx2_23_2_res),
    .coord2(align_v2_texture_u_to_fx_texture_interpolate_1_i4_d88), .weight2(fp_to_fx2_23_3_res),
    .result(fx_texture_interpolate_1_res)
);
fx_texture_interpolator u_fx_texture_interpolate_2 (
    .clk(clk), .clken(pipe_en_internal),
    .coord0(align_v0_texture_v_to_fx_texture_interpolate_2_i0_d88), .weight0(fp_to_fx2_23_1_res),
    .coord1(align_v1_texture_v_to_fx_texture_interpolate_2_i2_d88), .weight1(fp_to_fx2_23_2_res),
    .coord2(align_v2_texture_v_to_fx_texture_interpolate_2_i4_d88), .weight2(fp_to_fx2_23_3_res),
    .result(fx_texture_interpolate_2_res)
);

// ---- Output skid buffer ----
localparam int OUTBUNDLEWIDTH = $bits(texcoord_u_tdata) + $bits(texcoord_v_tdata) + $bits(addr_tdata) + $bits(tex_id_tdata) + $bits(texture_mode_u_tdata) + $bits(texture_mode_v_tdata) + $bits(texture_function_tdata) + $bits(sfactor_op_tdata) + $bits(dfactor_op_tdata) + $bits(color_tdata) + $bits(comp_z_tdata);
logic [OUTBUNDLEWIDTH-1:0] output_bundle_tdata;
logic output_bundle_tvalid;
(*max_fanout = 250*) logic output_bundle_s_axis_tready;
logic [OUTBUNDLEWIDTH-1:0] output_bundle_buf_tdata;
logic output_bundle_buf_tvalid;
logic output_bundle_buf_tready;

logic [THREAD_ADDR_W-1:0] addr_bundle_tdata;
logic [7:0] tex_id_bundle_tdata;
logic texture_mode_u_bundle_tdata;
logic texture_mode_v_bundle_tdata;
logic [2:0] texture_function_bundle_tdata;
logic [$bits(blend_op_t)-1:0] sfactor_op_bundle_tdata;
logic [$bits(blend_op_t)-1:0] dfactor_op_bundle_tdata;
logic comp_z_bundle_tdata;
logic [THREAD_ADDR_W + $bits(blend_op_t) + $bits(blend_op_t) + 13-1:0] bundle_s0_d94_in, bundle_s0_d94_out;
assign bundle_s0_d94_in = {addr_tdata, tex_id_tdata, texture_mode_u_tdata, texture_mode_v_tdata, texture_function_tdata, sfactor_op_tdata, dfactor_op_tdata};
delay_pipe #(.WIDTH(THREAD_ADDR_W + $bits(blend_op_t) + $bits(blend_op_t) + 13), .STAGES(94)) u_bundle_s0_d94 (.clk(clk), .rst_n(1'b1), .clken(pipe_en_internal), .data_in(bundle_s0_d94_in), .data_out(bundle_s0_d94_out));
assign {addr_bundle_tdata, tex_id_bundle_tdata, texture_mode_u_bundle_tdata, texture_mode_v_bundle_tdata, texture_function_bundle_tdata, sfactor_op_bundle_tdata, dfactor_op_bundle_tdata} = bundle_s0_d94_out;
delay_pipe #(.WIDTH(1), .STAGES(41)) u_align_comp_z_to_output_bundle_d41 (.clk(clk), .rst_n(rst_reg), .clken(pipe_en_internal), .data_in(comp_z_tdata), .data_out(comp_z_bundle_tdata));

assign output_bundle_tdata = {texcoord_u_tdata, texcoord_v_tdata, addr_bundle_tdata, tex_id_bundle_tdata, texture_mode_u_bundle_tdata, texture_mode_v_bundle_tdata, texture_function_bundle_tdata, sfactor_op_bundle_tdata, dfactor_op_bundle_tdata, color_tdata, comp_z_bundle_tdata};
assign output_bundle_tvalid = valid_pipe[94];

axis_skid_buffer #(
    .WIDTH(OUTBUNDLEWIDTH)
) u_output_bundle_skid (
    .aclk(clk), .aresetn(rst_reg),
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

