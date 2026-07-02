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
logic [31:0] fp_fma_5_res;
logic [31:0] fp_fma_6_res;
logic [31:0] fp_fma_7_res;
logic [31:0] fp_fma_8_res;
logic [31:0] fp_recip_1_out;
logic [31:0] mem_read_1_rdata;
logic [0:0] fp_cmp_1_pred;
logic fp_cmp_1_pred_valid;
logic [0:0] mem_write_1_pred;
logic [31:0] fp_mul_8_res;
logic [31:0] fp_mul_9_res;

// ---- Selected outputs ----
logic comp_z_tdata;
logic comp_z_tvalid;
assign comp_z_tdata = fp_cmp_1_pred;
assign comp_z_tvalid = fp_cmp_1_pred_valid;
logic [31:0] texcoord_u_tdata;
logic texcoord_u_tvalid;
assign texcoord_u_tdata = fp_mul_8_res;
assign texcoord_u_tvalid = valid_pipe[64];
logic [31:0] texcoord_v_tdata;
logic texcoord_v_tvalid;
assign texcoord_v_tdata = fp_mul_9_res;
assign texcoord_v_tvalid = valid_pipe[64];

// ---- Unit input ready wires ----
// None (non-blocking FP modules use aclken/valid_in)

// ---- Unit mapping summary ----
// fp_mul_1         -> fp_mul_1          out=fp_mul_1_res        start=  0  end=  5  valid=(pipe_en)  expr=(e0 * inv_area)
// fp_mul_2         -> fp_mul_2          out=fp_mul_2_res        start=  0  end=  5  valid=(pipe_en)  expr=(e1 * inv_area)
// fp_mul_3         -> fp_mul_3          out=fp_mul_3_res        start=  0  end=  5  valid=(pipe_en)  expr=(e2 * inv_area)
// fp_mul_4         -> fp_mul_4          out=fp_mul_4_res        start=  5  end= 10  valid=(pipe_en)  expr=(v0_z * (e0 * inv_area))
// fp_mul_5         -> fp_mul_5          out=fp_mul_5_res        start=  5  end= 10  valid=(pipe_en)  expr=(v0_w * (e0 * inv_area))
// fp_mul_6         -> fp_mul_6          out=fp_mul_6_res        start=  5  end= 10  valid=(pipe_en)  expr=(v0_texture_u_over_w * (e0 * inv_area))
// fp_mul_7         -> fp_mul_7          out=fp_mul_7_res        start=  5  end= 10  valid=(pipe_en)  expr=(v0_texture_v_over_w * (e0 * inv_area))
// fp_fma_1         -> fp_fma_1          out=fp_fma_1_res        start= 10  end= 23  valid=(pipe_en)  expr=fma(v1_z, (e1 * inv_area), (v0_z * (e0 * inv_area)))
// fp_fma_3         -> fp_fma_2          out=fp_fma_2_res        start= 10  end= 23  valid=(pipe_en)  expr=fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area)))
// fp_fma_5         -> fp_fma_3          out=fp_fma_3_res        start= 10  end= 23  valid=(pipe_en)  expr=fma(v1_texture_u_over_w, (e1 * inv_area), (v0_texture_u_over_w * (e0 * inv_area)))
// fp_fma_7         -> fp_fma_4          out=fp_fma_4_res        start= 10  end= 23  valid=(pipe_en)  expr=fma(v1_texture_v_over_w, (e1 * inv_area), (v0_texture_v_over_w * (e0 * inv_area)))
// fp_fma_2         -> fp_fma_5          out=fp_fma_5_res        start= 23  end= 36  valid=(pipe_en)  expr=fma(v2_z, (e2 * inv_area), fma(v1_z, (e1 * inv_area), (v0_z * (e0 * inv_area))))
// fp_fma_4         -> fp_fma_6          out=fp_fma_6_res        start= 23  end= 36  valid=(pipe_en)  expr=fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))
// fp_fma_6         -> fp_fma_7          out=fp_fma_7_res        start= 23  end= 36  valid=(pipe_en)  expr=fma(v2_texture_u_over_w, (e2 * inv_area), fma(v1_texture_u_over_w, (e1 * inv_area), (v0_texture_u_over_w * (e0 * inv_area))))
// fp_fma_8         -> fp_fma_8          out=fp_fma_8_res        start= 23  end= 36  valid=(pipe_en)  expr=fma(v2_texture_v_over_w, (e2 * inv_area), fma(v1_texture_v_over_w, (e1 * inv_area), (v0_texture_v_over_w * (e0 * inv_area))))
// fp_recip_1       -> fp_recip_1        out=fp_recip_1_out      start= 36  end= 58  valid=(pipe_en)  expr=(1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area)))))
// mem_read_1       -> mem_read_1        out=mem_read_1_rdata    start= 36  end= 37  valid=(pipe_en)  expr=mem_read(addr)
// fp_cmp_1         -> fp_cmp_1          out=fp_cmp_1_pred       start= 37  end= 38  valid=(pipe_en)  expr=(fma(v2_z, (e2 * inv_area), fma(v1_z, (e1 * inv_area), (v0_z * (e0 * inv_area)))) <= mem_read(addr))
// mem_write_1      -> mem_write_1       out=mem_write_1_pred    start= 38  end= 39  valid=(pipe_en)  expr=mem_write(addr, fma(v2_z, (e2 * inv_area), fma(v1_z, (e1 * inv_area), (v0_z * (e0 * inv_area)))))
// fp_mul_8         -> fp_mul_8          out=fp_mul_8_res        start= 58  end= 63  valid=(pipe_en)  expr=(fma(v2_texture_u_over_w, (e2 * inv_area), fma(v1_texture_u_over_w, (e1 * inv_area), (v0_texture_u_over_w * (e0 * inv_area)))) * (1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))))
// fp_mul_9         -> fp_mul_9          out=fp_mul_9_res        start= 58  end= 63  valid=(pipe_en)  expr=(fma(v2_texture_v_over_w, (e2 * inv_area), fma(v1_texture_v_over_w, (e1 * inv_area), (v0_texture_v_over_w * (e0 * inv_area)))) * (1 / fma(v2_w, (e2 * inv_area), fma(v1_w, (e1 * inv_area), (v0_w * (e0 * inv_area))))))

// ---- Master valid pipeline ----
logic [64:0] valid_pipe;
assign valid_pipe[0] = input_bundle_buf_tvalid;
always_ff @(posedge clk) begin
  if (~rst_n)
    valid_pipe[64:1] <= '0;
  else if (pipe_en_internal)
    valid_pipe[64:1] <= valid_pipe[63:0];
end

// ---- Non-AXIS consumer fire wiring ----
logic mem_read_1_fire;
logic fp_cmp_1_fire;
logic mem_write_1_fire;
assign mem_read_1_fire = valid_pipe[37];
assign fp_cmp_1_fire = valid_pipe[38];
assign mem_write_1_fire = valid_pipe[39];

// ---- Delay alignment for late-consumed inputs ----
logic [31:0] align_v0_z_to_fp_mul_4_i0_d5;
logic [31:0] align_v0_w_to_fp_mul_5_i0_d5;
logic [31:0] align_v0_texture_u_over_w_to_fp_mul_6_i0_d5;
logic [31:0] align_v0_texture_v_over_w_to_fp_mul_7_i0_d5;
logic [31:0] align_v1_z_to_fp_fma_1_i0_d10;
logic [31:0] align_fp_mul_2_to_fp_fma_1_i1_d5;
logic [31:0] align_v1_w_to_fp_fma_3_i0_d10;
logic [31:0] align_fp_mul_2_to_fp_fma_3_i1_d5;
logic [31:0] align_v1_texture_u_over_w_to_fp_fma_5_i0_d10;
logic [31:0] align_fp_mul_2_to_fp_fma_5_i1_d5;
logic [31:0] align_v1_texture_v_over_w_to_fp_fma_7_i0_d10;
logic [31:0] align_fp_mul_2_to_fp_fma_7_i1_d5;
logic [31:0] align_v2_z_to_fp_fma_2_i0_d23;
logic [31:0] align_fp_mul_3_to_fp_fma_2_i1_d18;
logic [31:0] align_v2_w_to_fp_fma_4_i0_d23;
logic [31:0] align_fp_mul_3_to_fp_fma_4_i1_d18;
logic [31:0] align_v2_texture_u_over_w_to_fp_fma_6_i0_d23;
logic [31:0] align_fp_mul_3_to_fp_fma_6_i1_d18;
logic [31:0] align_v2_texture_v_over_w_to_fp_fma_8_i0_d23;
logic [31:0] align_fp_mul_3_to_fp_fma_8_i1_d18;
logic [13:0] align_addr_to_mem_read_1_i0_d36;
logic [31:0] align_fp_fma_2_to_fp_cmp_1_i0_d1;
logic [13:0] align_addr_to_mem_write_1_i0_d38;
logic [31:0] align_fp_fma_2_to_mem_write_1_i1_d2;
logic [31:0] align_fp_fma_6_to_fp_mul_8_i0_d22;
logic [31:0] align_fp_fma_8_to_fp_mul_9_i0_d22;

delay_pipe #(.WIDTH(32), .STAGES(5)) u_align_v0_z_to_fp_mul_4_i0_d5_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(s_axis_v0_z_tdata), .data_out(align_v0_z_to_fp_mul_4_i0_d5));
delay_pipe #(.WIDTH(32), .STAGES(5)) u_align_v0_w_to_fp_mul_5_i0_d5_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(s_axis_v0_w_tdata), .data_out(align_v0_w_to_fp_mul_5_i0_d5));
delay_pipe #(.WIDTH(32), .STAGES(5)) u_align_v0_texture_u_over_w_to_fp_mul_6_i0_d5_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(s_axis_v0_texture_u_over_w_tdata), .data_out(align_v0_texture_u_over_w_to_fp_mul_6_i0_d5));
delay_pipe #(.WIDTH(32), .STAGES(5)) u_align_v0_texture_v_over_w_to_fp_mul_7_i0_d5_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(s_axis_v0_texture_v_over_w_tdata), .data_out(align_v0_texture_v_over_w_to_fp_mul_7_i0_d5));
delay_pipe #(.WIDTH(32), .STAGES(10)) u_align_v1_z_to_fp_fma_1_i0_d10_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(s_axis_v1_z_tdata), .data_out(align_v1_z_to_fp_fma_1_i0_d10));
delay_pipe #(.WIDTH(32), .STAGES(5)) u_align_fp_mul_2_to_fp_fma_1_i1_d5_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_mul_2_res), .data_out(align_fp_mul_2_to_fp_fma_1_i1_d5));
delay_pipe #(.WIDTH(32), .STAGES(10)) u_align_v1_w_to_fp_fma_3_i0_d10_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(s_axis_v1_w_tdata), .data_out(align_v1_w_to_fp_fma_3_i0_d10));
delay_pipe #(.WIDTH(32), .STAGES(5)) u_align_fp_mul_2_to_fp_fma_3_i1_d5_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_mul_2_res), .data_out(align_fp_mul_2_to_fp_fma_3_i1_d5));
delay_pipe #(.WIDTH(32), .STAGES(10)) u_align_v1_texture_u_over_w_to_fp_fma_5_i0_d10_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(s_axis_v1_texture_u_over_w_tdata), .data_out(align_v1_texture_u_over_w_to_fp_fma_5_i0_d10));
delay_pipe #(.WIDTH(32), .STAGES(5)) u_align_fp_mul_2_to_fp_fma_5_i1_d5_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_mul_2_res), .data_out(align_fp_mul_2_to_fp_fma_5_i1_d5));
delay_pipe #(.WIDTH(32), .STAGES(10)) u_align_v1_texture_v_over_w_to_fp_fma_7_i0_d10_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(s_axis_v1_texture_v_over_w_tdata), .data_out(align_v1_texture_v_over_w_to_fp_fma_7_i0_d10));
delay_pipe #(.WIDTH(32), .STAGES(5)) u_align_fp_mul_2_to_fp_fma_7_i1_d5_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_mul_2_res), .data_out(align_fp_mul_2_to_fp_fma_7_i1_d5));
delay_pipe #(.WIDTH(32), .STAGES(23)) u_align_v2_z_to_fp_fma_2_i0_d23_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(s_axis_v2_z_tdata), .data_out(align_v2_z_to_fp_fma_2_i0_d23));
delay_pipe #(.WIDTH(32), .STAGES(18)) u_align_fp_mul_3_to_fp_fma_2_i1_d18_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_mul_3_res), .data_out(align_fp_mul_3_to_fp_fma_2_i1_d18));
delay_pipe #(.WIDTH(32), .STAGES(23)) u_align_v2_w_to_fp_fma_4_i0_d23_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(s_axis_v2_w_tdata), .data_out(align_v2_w_to_fp_fma_4_i0_d23));
delay_pipe #(.WIDTH(32), .STAGES(18)) u_align_fp_mul_3_to_fp_fma_4_i1_d18_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_mul_3_res), .data_out(align_fp_mul_3_to_fp_fma_4_i1_d18));
delay_pipe #(.WIDTH(32), .STAGES(23)) u_align_v2_texture_u_over_w_to_fp_fma_6_i0_d23_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(s_axis_v2_texture_u_over_w_tdata), .data_out(align_v2_texture_u_over_w_to_fp_fma_6_i0_d23));
delay_pipe #(.WIDTH(32), .STAGES(18)) u_align_fp_mul_3_to_fp_fma_6_i1_d18_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_mul_3_res), .data_out(align_fp_mul_3_to_fp_fma_6_i1_d18));
delay_pipe #(.WIDTH(32), .STAGES(23)) u_align_v2_texture_v_over_w_to_fp_fma_8_i0_d23_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(s_axis_v2_texture_v_over_w_tdata), .data_out(align_v2_texture_v_over_w_to_fp_fma_8_i0_d23));
delay_pipe #(.WIDTH(32), .STAGES(18)) u_align_fp_mul_3_to_fp_fma_8_i1_d18_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_mul_3_res), .data_out(align_fp_mul_3_to_fp_fma_8_i1_d18));
delay_pipe #(.WIDTH(14), .STAGES(36)) u_align_addr_to_mem_read_1_i0_d36_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(s_axis_addr_tdata), .data_out(align_addr_to_mem_read_1_i0_d36));
delay_pipe #(.WIDTH(32), .STAGES(1)) u_align_fp_fma_2_to_fp_cmp_1_i0_d1_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_fma_5_res), .data_out(align_fp_fma_2_to_fp_cmp_1_i0_d1));
delay_pipe #(.WIDTH(14), .STAGES(38)) u_align_addr_to_mem_write_1_i0_d38_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(s_axis_addr_tdata), .data_out(align_addr_to_mem_write_1_i0_d38));
delay_pipe #(.WIDTH(32), .STAGES(2)) u_align_fp_fma_2_to_mem_write_1_i1_d2_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_fma_5_res), .data_out(align_fp_fma_2_to_mem_write_1_i1_d2));
delay_pipe #(.WIDTH(32), .STAGES(22)) u_align_fp_fma_6_to_fp_mul_8_i0_d22_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_fma_7_res), .data_out(align_fp_fma_6_to_fp_mul_8_i0_d22));
delay_pipe #(.WIDTH(32), .STAGES(22)) u_align_fp_fma_8_to_fp_mul_9_i0_d22_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(fp_fma_8_res), .data_out(align_fp_fma_8_to_fp_mul_9_i0_d22));

// Leaf ready signals not used (internal distribution only)

// ---- Unit output ready wiring ----
// None (non-blocking FP modules have no AXIS output ready)

// ---- Unit instantiation skeletons ----
// NOTE: Non-blocking FP modules with aclken(pipe_en_internal)
// NOTE: Valid is propagated explicitly via valid_pipe
fp_mul #(.LATENCY(5)) u_fp_mul_1 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    .valid_in(valid_pipe[1]),
    .a(s_axis_e0_tdata), .b(s_axis_inv_area_tdata),
    .result(fp_mul_1_res)
);
fp_mul #(.LATENCY(5)) u_fp_mul_2 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    .valid_in(valid_pipe[1]),
    .a(s_axis_e1_tdata), .b(s_axis_inv_area_tdata),
    .result(fp_mul_2_res)
);
fp_mul #(.LATENCY(5)) u_fp_mul_3 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    .valid_in(valid_pipe[1]),
    .a(s_axis_e2_tdata), .b(s_axis_inv_area_tdata),
    .result(fp_mul_3_res)
);
fp_mul #(.LATENCY(5)) u_fp_mul_4 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    .valid_in(valid_pipe[6]),
    .a(align_v0_z_to_fp_mul_4_i0_d5), .b(fp_mul_1_res),
    .result(fp_mul_4_res)
);
fp_mul #(.LATENCY(5)) u_fp_mul_5 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    .valid_in(valid_pipe[6]),
    .a(align_v0_w_to_fp_mul_5_i0_d5), .b(fp_mul_1_res),
    .result(fp_mul_5_res)
);
fp_mul #(.LATENCY(5)) u_fp_mul_6 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    .valid_in(valid_pipe[6]),
    .a(align_v0_texture_u_over_w_to_fp_mul_6_i0_d5), .b(fp_mul_1_res),
    .result(fp_mul_6_res)
);
fp_mul #(.LATENCY(5)) u_fp_mul_7 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    .valid_in(valid_pipe[6]),
    .a(align_v0_texture_v_over_w_to_fp_mul_7_i0_d5), .b(fp_mul_1_res),
    .result(fp_mul_7_res)
);
fp_fma #(.LATENCY(13)) u_fp_fma_1 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    .valid_in(valid_pipe[11]),
    .a(align_v1_z_to_fp_fma_1_i0_d10), .b(align_fp_mul_2_to_fp_fma_1_i1_d5), .c(fp_mul_4_res),
    .result(fp_fma_1_res)
);
fp_fma #(.LATENCY(13)) u_fp_fma_2 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    .valid_in(valid_pipe[11]),
    .a(align_v1_w_to_fp_fma_3_i0_d10), .b(align_fp_mul_2_to_fp_fma_3_i1_d5), .c(fp_mul_5_res),
    .result(fp_fma_2_res)
);
fp_fma #(.LATENCY(13)) u_fp_fma_3 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    .valid_in(valid_pipe[11]),
    .a(align_v1_texture_u_over_w_to_fp_fma_5_i0_d10), .b(align_fp_mul_2_to_fp_fma_5_i1_d5), .c(fp_mul_6_res),
    .result(fp_fma_3_res)
);
fp_fma #(.LATENCY(13)) u_fp_fma_4 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    .valid_in(valid_pipe[11]),
    .a(align_v1_texture_v_over_w_to_fp_fma_7_i0_d10), .b(align_fp_mul_2_to_fp_fma_7_i1_d5), .c(fp_mul_7_res),
    .result(fp_fma_4_res)
);
fp_fma #(.LATENCY(13)) u_fp_fma_5 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    .valid_in(valid_pipe[24]),
    .a(align_v2_z_to_fp_fma_2_i0_d23), .b(align_fp_mul_3_to_fp_fma_2_i1_d18), .c(fp_fma_1_res),
    .result(fp_fma_5_res)
);
fp_fma #(.LATENCY(13)) u_fp_fma_6 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    .valid_in(valid_pipe[24]),
    .a(align_v2_w_to_fp_fma_4_i0_d23), .b(align_fp_mul_3_to_fp_fma_4_i1_d18), .c(fp_fma_2_res),
    .result(fp_fma_6_res)
);
fp_fma #(.LATENCY(13)) u_fp_fma_7 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    .valid_in(valid_pipe[24]),
    .a(align_v2_texture_u_over_w_to_fp_fma_6_i0_d23), .b(align_fp_mul_3_to_fp_fma_6_i1_d18), .c(fp_fma_3_res),
    .result(fp_fma_7_res)
);
fp_fma #(.LATENCY(13)) u_fp_fma_8 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    .valid_in(valid_pipe[24]),
    .a(align_v2_texture_v_over_w_to_fp_fma_8_i0_d23), .b(align_fp_mul_3_to_fp_fma_8_i1_d18), .c(fp_fma_4_res),
    .result(fp_fma_8_res)
);
fp_recip #(.LATENCY(22)) u_fp_recip_1 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    .valid_in(valid_pipe[37]),
    .a(fp_fma_6_res),
    .result(fp_recip_1_out)
);
assign z_rd_en = mem_read_1_fire;
assign z_rd_addr = align_addr_to_mem_read_1_i0_d36;
always_ff @(posedge clk) begin
    if (!rst_n) begin
        mem_read_1_rdata <= '0;
    end else if (mem_read_1_fire) begin
        mem_read_1_rdata <= z_rd_data;
    end
end
fp_cmp_le u_fp_cmp_1 (
    .clk(clk),
    .s_axis_a(align_fp_fma_2_to_fp_cmp_1_i0_d1), .s_axis_a_valid(valid_pipe[38]),
    .s_axis_b(mem_read_1_rdata), .s_axis_b_valid(valid_pipe[38]),
    .m_axis_res(fp_cmp_1_pred[0]), .m_axis_tvalid(fp_cmp_1_pred_valid)
);
assign z_wr_en = (fp_cmp_1_pred_valid && fp_cmp_1_pred[0]);
assign z_wr_addr = align_addr_to_mem_write_1_i0_d38;
assign z_wr_data = align_fp_fma_2_to_mem_write_1_i1_d2;
fp_mul #(.LATENCY(5)) u_fp_mul_8 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    .valid_in(valid_pipe[59]),
    .a(align_fp_fma_6_to_fp_mul_8_i0_d22), .b(fp_recip_1_out),
    .result(fp_mul_8_res)
);
fp_mul #(.LATENCY(5)) u_fp_mul_9 (
    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),
    .valid_in(valid_pipe[59]),
    .a(align_fp_fma_8_to_fp_mul_9_i0_d22), .b(fp_recip_1_out),
    .result(fp_mul_9_res)
);

// ---- Output skid buffer ----
localparam int OUTBUNDLEWIDTH = 65;
logic [OUTBUNDLEWIDTH-1:0] output_bundle_tdata;
logic output_bundle_tvalid;
logic output_bundle_s_axis_tready;
logic [OUTBUNDLEWIDTH-1:0] output_bundle_buf_tdata;
logic output_bundle_buf_tvalid;
logic output_bundle_buf_tready;

logic comp_z_bundle_tdata;
delay_pipe #(.WIDTH(1), .STAGES(26)) u_align_comp_z_to_output_bundle_d26 (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in(comp_z_tdata), .data_out(comp_z_bundle_tdata));

assign output_bundle_tdata = {comp_z_bundle_tdata, texcoord_u_tdata, texcoord_v_tdata};
assign output_bundle_tvalid = valid_pipe[64];

axis_skid_buffer #(
    .WIDTH (OUTBUNDLEWIDTH),
    .STAGES(1)
) u_output_bundle_skid (
    .aclk(clk), .aresetn(rst_n),
    .s_axis_tdata(output_bundle_tdata),
    .s_axis_tvalid(output_bundle_tvalid),
    .s_axis_tready(output_bundle_s_axis_tready),
    .m_axis_tdata(output_bundle_buf_tdata),
    .m_axis_tvalid(output_bundle_buf_tvalid),
    .m_axis_tready(output_bundle_buf_tready)
);

assign {m_axis_comp_z_tdata, m_axis_texcoord_u_tdata, m_axis_texcoord_v_tdata} = output_bundle_buf_tdata;
assign m_axis_comp_z_tvalid = output_bundle_buf_tvalid;
assign m_axis_texcoord_u_tvalid = output_bundle_buf_tvalid;
assign m_axis_texcoord_v_tvalid = output_bundle_buf_tvalid;
assign output_bundle_buf_tready = m_axis_comp_z_tready && m_axis_texcoord_u_tready && m_axis_texcoord_v_tready;

// Pipeline control: clken = output skid can accept
assign pipe_en_internal = output_bundle_s_axis_tready;
assign input_bundle_m_axis_tready = pipe_en_internal;
assign ready_out = input_bundle_s_axis_tready;

