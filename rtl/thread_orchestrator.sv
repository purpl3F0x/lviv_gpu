`timescale 1ns / 1ns

import gpu_types_pkg::*;

module thread_orchestrator #(
) (
    // Frontend side
    input logic in_clk,
    input logic in_rst_n,
    input logic valid_in,
    output logic ready_out,
    input orchestrator_data_in_t in_data,

    // Orchestrator and thread side
    input logic clk,
    input logic rst_n,
    input logic ready_in[4],
    output logic valid_out[4],
    output thread_data_in_t out_data[4]
);

  localparam int AccumulatorLatency = 2;
  localparam int ConverterLatency = 7;
  localparam int PipeLatency = AccumulatorLatency + ConverterLatency;
  localparam int InFifoDepth = 16;
  localparam int ThreadFifoDepth = 32;
  localparam int DelayDepth = 2 ** $clog2(PipeLatency);
  localparam int DelayAddrW = $clog2(DelayDepth);

  // DSP instructions, in the order configured in dsp_macro_0.
  localparam logic [1:0] Load = 2'd0,  // CONCAT + C
                         Add = 2'd1,   // P + CONCAT
                         Sub = 2'd2;   // P - CONCAT

  // Thread token fields that do not come from the DSPs; they travel beside the DSP pipeline.
  typedef struct packed {
    logic [PIXEL_ADDR_W_THREAD-1:0] addr;
    logic [7:0] tex_id;
    texture_address_mode_t texture_mode_u;
    texture_address_mode_t texture_mode_v;
    fragment_op_t texture_function;
    blend_op_t sfactor_op;
    blend_op_t dfactor_op;
    float_t inv_area;
    fx_5_13_t v0_u, v0_v, v1_u, v1_v, v2_u, v2_v;
    float_t v0_w, v0_z, v1_w, v1_z, v2_w, v2_z;
    color_argb_t v0_color, v1_color, v2_color;
  } passthrough_t;

  // 14.10 edge deltas aligned to the 28.20 edge format.
  function automatic fx_28_20_t align_delta(input fx_14_10_t delta);
    return fx_28_20_t'(delta) <<< 10;
  endfunction

  //
  // Input FIFO (frontend clock to orchestrator clock)
  //

  logic [$bits(orchestrator_data_in_t)-1:0] triangle_bits;
  orchestrator_data_in_t triangle;
  logic in_empty, triangle_valid, triangle_pop, in_full;

  // data_o holds the head triangle until its last group issues, then the next one follows.
  async_fifo #(
      .DATA_WIDTH($bits(orchestrator_data_in_t)),
      .FIFO_DEPTH(InFifoDepth)
  ) u_in_fifo (
      .clk(in_clk),
      .rst_n(in_rst_n),
      .wr_en(valid_in),
      .data_i(in_data),
      .fifo_full(in_full),
      .fifo_almost_full(),
      .fill_cnt(),
      .rd_clk(clk),
      .rd_rst_n(rst_n),
      .rd_en(triangle_pop),
      .data_o(triangle_bits),
      .rd_fill_cnt(),
      .fifo_empty(in_empty)
  );

  assign ready_out = !in_full;
  assign triangle = orchestrator_data_in_t'(triangle_bits);
  assign triangle_valid = !in_empty;

  //
  // Snake traversal
  //

  logic advance, issue, issue_last, issue_down;
  logic [1:0] issue_op;
  logic busy, dir_right, dir_right_q, step_down_q, last_q;
  logic [1:0] step_op_q;
  logic [TILE_ADDR_X-1:0] issue_x, pixel_x, cols_left, cols_left_q;
  logic [TILE_ADDR_Y-1:0] issue_y, pixel_y, rows_left, rows_left_q;

  // busy: the head triangle's first group has issued; the registers describe its next group.
  // Otherwise the group this cycle is the head triangle's first one, loaded straight from data_o.
  always_comb begin
    if (busy) begin
      issue_x = pixel_x;
      issue_y = pixel_y;
      issue_op = step_op_q;
      issue_down = step_down_q;
      issue_last = last_q;
      cols_left = cols_left_q;
      rows_left = rows_left_q;
      dir_right = dir_right_q;
    end else begin
      issue_x = triangle.minX_local;
      issue_y = triangle.minY_local;
      issue_op = Load;
      issue_down = 1'b0;
      issue_last = triangle.width == 0 && triangle.height == 0;
      cols_left = triangle.width;
      rows_left = triangle.height;
      dir_right = 1'b1;
    end
  end

  assign issue = advance && triangle_valid;
  assign triangle_pop = issue && issue_last;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      busy <= 1'b0;
      pixel_x <= '0;
      pixel_y <= '0;
      cols_left_q <= '0;
      rows_left_q <= '0;
      dir_right_q <= 1'b1;
      step_op_q <= Add;
      step_down_q <= 1'b0;
      last_q <= 1'b0;
    end else if (issue) begin
      busy <= !issue_last;
      if (cols_left != 0) begin
        pixel_x <= dir_right ? issue_x + TILE_ADDR_X'(1) : issue_x - TILE_ADDR_X'(1);
        pixel_y <= issue_y;
        cols_left_q <= cols_left - TILE_ADDR_X'(1);
        rows_left_q <= rows_left;
        dir_right_q <= dir_right;
        step_op_q <= dir_right ? Add : Sub;
        step_down_q <= 1'b0;
        last_q <= cols_left == TILE_ADDR_X'(1) && rows_left == 0;
      end else begin
        pixel_x <= issue_x;
        pixel_y <= issue_y + TILE_ADDR_Y'(1);
        cols_left_q <= triangle.width;
        rows_left_q <= rows_left - TILE_ADDR_Y'(1);
        dir_right_q <= !dir_right;
        step_op_q <= Add;
        step_down_q <= 1'b1;
        last_q <= triangle.width == 0 && rows_left == TILE_ADDR_Y'(1);
      end
    end
  end

  //
  // Edge accumulators
  //

  fx_28_20_t init[3], dx[3], dy[3], dxdy[3];
  fx_28_20_t concat_operand[3], c_operand[4][3], edges[4][3];
  logic [3:0][2:0][31:0] results;

  assign init = '{triangle.init_e0, triangle.init_e1, triangle.init_e2};
  assign dx = '{
          align_delta(triangle.e0_dx), align_delta(triangle.e1_dx), align_delta(triangle.e2_dx)
      };
  assign dy = '{
          align_delta(triangle.e0_dy), align_delta(triangle.e1_dy), align_delta(triangle.e2_dy)
      };
  assign dxdy = '{
          align_delta(triangle.e0_dx_plus_dy),
          align_delta(triangle.e1_dx_plus_dy),
          align_delta(triangle.e2_dx_plus_dy)
      };

  // CONCAT is shared by all lanes: the edge value on load, then the 2x2 group step.
  // C is a fixed per-lane offset to the lane's pixel inside the group, used only on load.
  for (genvar edge_idx = 0; edge_idx < 3; edge_idx++) begin : g_operand
    always_comb begin
      if (issue_op == Load) concat_operand[edge_idx] = init[edge_idx];
      else if (issue_down) concat_operand[edge_idx] = dy[edge_idx] <<< 1;
      else concat_operand[edge_idx] = dx[edge_idx] <<< 1;
    end

    assign c_operand[0][edge_idx] = '0;
    assign c_operand[1][edge_idx] = dx[edge_idx];
    assign c_operand[2][edge_idx] = dy[edge_idx];
    assign c_operand[3][edge_idx] = dxdy[edge_idx];
  end

  logic [PipeLatency-1:0] valid_pipe;

  always_ff @(posedge clk) begin
    if (!rst_n) valid_pipe <= '0;
    else if (advance) valid_pipe <= {valid_pipe[PipeLatency-2:0], issue};
  end

  for (genvar lane = 0; lane < 4; lane++) begin : g_lane
    for (genvar edge_idx = 0; edge_idx < 3; edge_idx++) begin : g_edge
      orchestrator_alu u_alu (
          .clk(clk),
          .clken(advance),
          .op(issue_op),
          .concat_operand(concat_operand[edge_idx]),
          .c_operand(c_operand[lane][edge_idx]),
          .result(edges[lane][edge_idx])
      );

      fx28_20_to_fp32 #(
          .LATENCY(ConverterLatency)
      ) u_converter (
          .aclk(clk),
          .aclken(advance),
          .s_axis_a_tvalid(valid_pipe[AccumulatorLatency-1]),
          .s_axis_a_tdata(edges[lane][edge_idx]),
          .m_axis_result_tvalid(),
          .m_axis_result_tdata(results[lane][edge_idx])
      );
    end
  end

  //
  // Passthrough delay line
  //

  // Written every advancing cycle so it stays aligned with the DSP and converter pipeline;
  // the read pointer trails the write pointer by PipeLatency - 1, plus the output register.
  (* ram_style = "distributed" *) passthrough_t delay_mem[DelayDepth];
  logic [DelayAddrW-1:0] delay_wr_ptr, delay_rd_ptr;
  passthrough_t delay_in, delay_out;

  always_comb begin
    delay_in.addr = {issue_y, issue_x};
    delay_in.tex_id = triangle.tex_id;
    delay_in.texture_mode_u = triangle.texture_mode_u;
    delay_in.texture_mode_v = triangle.texture_mode_v;
    delay_in.texture_function = triangle.texture_function;
    delay_in.sfactor_op = triangle.sfactor_op;
    delay_in.dfactor_op = triangle.dfactor_op;
    delay_in.inv_area = triangle.inv_area;
    delay_in.v0_u = triangle.v0_u;
    delay_in.v0_v = triangle.v0_v;
    delay_in.v1_u = triangle.v1_u;
    delay_in.v1_v = triangle.v1_v;
    delay_in.v2_u = triangle.v2_u;
    delay_in.v2_v = triangle.v2_v;
    delay_in.v0_w = triangle.v0_w;
    delay_in.v0_z = triangle.v0_z;
    delay_in.v1_w = triangle.v1_w;
    delay_in.v1_z = triangle.v1_z;
    delay_in.v2_w = triangle.v2_w;
    delay_in.v2_z = triangle.v2_z;
    delay_in.v0_color = triangle.v0_color;
    delay_in.v1_color = triangle.v1_color;
    delay_in.v2_color = triangle.v2_color;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      delay_wr_ptr <= '0;
      delay_rd_ptr <= DelayAddrW'(DelayDepth - (PipeLatency - 1));
    end else if (advance) begin
      delay_wr_ptr <= delay_wr_ptr + 1'b1;
      delay_rd_ptr <= delay_rd_ptr + 1'b1;
    end
  end

  always_ff @(posedge clk) begin
    if (advance) begin
      delay_mem[delay_wr_ptr] <= delay_in;
      delay_out <= delay_mem[delay_rd_ptr];
    end
  end

  //
  // Thread FIFOs
  //

  logic [3:0] fifo_almost_full;
  logic out_fire;
  thread_data_in_t fifo_wdata[4];

  assign out_fire = valid_pipe[PipeLatency-1] && advance;

  // Registered one cycle early off almost-full, so the write in the next cycle always has room.
  always_ff @(posedge clk) begin
    if (!rst_n) advance <= 1'b0;
    else advance <= !(|fifo_almost_full);
  end

  for (genvar lane = 0; lane < 4; lane++) begin : g_thread_fifo
    logic fifo_empty;
    logic [$bits(thread_data_in_t)-1:0] rdata;

    always_comb begin
      fifo_wdata[lane].addr = delay_out.addr;
      fifo_wdata[lane].tex_id = delay_out.tex_id;
      fifo_wdata[lane].texture_mode_u = delay_out.texture_mode_u;
      fifo_wdata[lane].texture_mode_v = delay_out.texture_mode_v;
      fifo_wdata[lane].texture_function = delay_out.texture_function;
      fifo_wdata[lane].sfactor_op = delay_out.sfactor_op;
      fifo_wdata[lane].dfactor_op = delay_out.dfactor_op;
      fifo_wdata[lane].inv_area = delay_out.inv_area;
      fifo_wdata[lane].e0 = results[lane][0];
      fifo_wdata[lane].e1 = results[lane][1];
      fifo_wdata[lane].e2 = results[lane][2];
      fifo_wdata[lane].v0_u = delay_out.v0_u;
      fifo_wdata[lane].v0_v = delay_out.v0_v;
      fifo_wdata[lane].v1_u = delay_out.v1_u;
      fifo_wdata[lane].v1_v = delay_out.v1_v;
      fifo_wdata[lane].v2_u = delay_out.v2_u;
      fifo_wdata[lane].v2_v = delay_out.v2_v;
      fifo_wdata[lane].v0_w = delay_out.v0_w;
      fifo_wdata[lane].v0_z = delay_out.v0_z;
      fifo_wdata[lane].v1_w = delay_out.v1_w;
      fifo_wdata[lane].v1_z = delay_out.v1_z;
      fifo_wdata[lane].v2_w = delay_out.v2_w;
      fifo_wdata[lane].v2_z = delay_out.v2_z;
      fifo_wdata[lane].v0_color = delay_out.v0_color;
      fifo_wdata[lane].v1_color = delay_out.v1_color;
      fifo_wdata[lane].v2_color = delay_out.v2_color;
    end

    sync_fifo #(
        .DATA_WIDTH($bits(thread_data_in_t)),
        .FIFO_DEPTH(ThreadFifoDepth)
    ) u_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .data_i(fifo_wdata[lane]),
        .wr_en(out_fire),
        .rd_en(ready_in[lane]),
        .data_o(rdata),
        .fill_cnt(),
        .fifo_full(),
        .fifo_almost_full(fifo_almost_full[lane]),
        .fifo_empty(fifo_empty)
    );

    assign valid_out[lane] = !fifo_empty;
    assign out_data[lane]  = thread_data_in_t'(rdata);
  end

endmodule
