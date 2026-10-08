`timescale 1ns / 1ns

import gpu_types_pkg::*;

module thread_orchestrator #(
) (
    input logic clk,
    input logic rst_n,

    input logic thread_clk,
    input logic thread_rst_n,

    input logic valid_in,
    output logic ready_out,
    input orchestrator_data_in_t in_data,
    input logic ready_in[4],
    output logic valid_out[4],
    output thread_data_in_t out_data[4]
);

  localparam int AccumulatorLatency = 3;
  localparam int Fx48Tof32Latency = 7;
  localparam int PipeLatency = AccumulatorLatency + Fx48Tof32Latency;
  localparam int ThreadFifoDepth = 32;

  // Triangle Stack
  localparam int TriangleSlots = 4;
  localparam int SlotW = $clog2(TriangleSlots);

  // ALU Definitions
  localparam logic [2:0] Hold = 3'd0, Load = 3'd1, AddX = 3'd2, SubX = 3'd3, AddXY = 3'd4,
                         AddY = 3'd5, Clear = 3'd6;

  typedef enum logic [1:0] {
    IDLE,
    LOAD,
    INITIALIZE,
    TRAVERSE
  } state_t;
  state_t state;

  (* ram_style = "distributed" *) orchestrator_data_in_t triangle_slots[TriangleSlots];

  typedef struct packed {
    edge_fixed_t init_e0, init_e1, init_e2;
    edge_fixed_t e0_dx, e0_dy, e1_dx, e1_dy, e2_dx, e2_dy;
    logic [TILE_ADDR_X-1:0] minX_local;
    logic [TILE_ADDR_Y-1:0] minY_local;
    logic [TILE_ADDR_X:0] width;
    logic [TILE_ADDR_Y:0] height;
    logic empty_box;
  } alu_triangle_t;

  orchestrator_data_in_t triangle_read;
  alu_triangle_t triangle, prefetched_triangle;

  logic [SlotW:0] wr_ptr, trav_ptr, rd_ptr;
  logic [SlotW:0] fetch_ptr;
  logic prefetch_valid, prefetch_fill, prefetch_take;
  logic [SlotW:0] triangle_count;
  logic triangle_push, triangle_pop, skip_empty;
  logic dir_right, issue_valid, issue_last;
  logic advance;
  // pixel_x/y hold the group issued this cycle; row_end/issue_last/arrive_down describe it.
  logic [TILE_ADDR_X-1:0] pixel_x;
  logic [TILE_ADDR_Y-1:0] pixel_y;
  logic [TILE_ADDR_X-1:0] columns_left;
  logic [TILE_ADDR_Y-1:0] rows_left;
  logic [TILE_ADDR_X-1:0] columns_per_row;

  logic row_end, arrive_down;
  edge_fixed_t edges[4][3];

  logic [2:0] accumulator_op[4];
  edge_fixed_t concat_operand[4][3], c_operand[4][3];
  logic [3:0][2:0][31:0] results;
  logic [3:0] fifo_almost_full;
  logic out_valid, out_fire;
  thread_data_in_t out_template;
  thread_data_in_t fifo_wdata[4];
  logic [PipeLatency-1:0] valid_pipe, last_pipe;
  logic [PipeLatency-1:0][PIXEL_ADDR_W_THREAD-1:0] addr_pipe;
  logic [PIXEL_ADDR_W_THREAD-1:0] issue_addr;

  always_comb begin
    triangle_read = triangle_slots[fetch_ptr[SlotW-1:0]];
  end

  assign prefetch_take = prefetch_valid
      && ((state == IDLE) || skip_empty || (issue_valid && issue_last));

  always_ff @(posedge clk) begin
    if (!rst_n) prefetch_fill <= 1'b0;
    else if (prefetch_fill) prefetch_fill <= 1'b0;
    else
      prefetch_fill <= ((fetch_ptr != wr_ptr) || triangle_push)
          && (!prefetch_valid || (advance && prefetch_take));
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      fetch_ptr <= '0;
      prefetch_valid <= 1'b0;
    end else begin
      if (prefetch_fill) begin
        fetch_ptr <= fetch_ptr + 1'b1;
        prefetch_valid <= 1'b1;
      end else if (advance && prefetch_take) prefetch_valid <= 1'b0;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      prefetched_triangle <= '0;
    end else if (prefetch_fill) begin
      prefetched_triangle.init_e0 <= triangle_read.init_e0;
      prefetched_triangle.init_e1 <= triangle_read.init_e1;
      prefetched_triangle.init_e2 <= triangle_read.init_e2;
      prefetched_triangle.e0_dx <= triangle_read.e0_dx;
      prefetched_triangle.e0_dy <= triangle_read.e0_dy;
      prefetched_triangle.e1_dx <= triangle_read.e1_dx;
      prefetched_triangle.e1_dy <= triangle_read.e1_dy;
      prefetched_triangle.e2_dx <= triangle_read.e2_dx;
      prefetched_triangle.e2_dy <= triangle_read.e2_dy;
      prefetched_triangle.minX_local <= triangle_read.minX_local;
      prefetched_triangle.minY_local <= triangle_read.minY_local;
      prefetched_triangle.width <= triangle_read.width;
      prefetched_triangle.height <= triangle_read.height;
      prefetched_triangle.empty_box <= (triangle_read.width == 0) || (triangle_read.height == 0);
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) triangle <= '0;
    else if (advance) begin
      if (prefetch_take) triangle <= prefetched_triangle;
    end
  end

  assign triangle_push = valid_in && ready_out;

  assign triangle_pop = advance && last_pipe[PipeLatency-2];
  assign skip_empty = (state == LOAD) && triangle.empty_box;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      triangle_count <= '0;
    end else begin
      case ({
        triangle_push, triangle_pop
      })
        2'b10:   triangle_count <= triangle_count + 1'b1;
        2'b01:   triangle_count <= triangle_count - 1'b1;
        default: ;
      endcase
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) ready_out <= 1'b0;
    // Equivalent to triangle_count < TriangleSlots - 1 for power-of-two TriangleSlots.
    else
      ready_out <= !(triangle_count[SlotW] || (&triangle_count[SlotW-1:0]));
  end

  assign issue_valid = (state == INITIALIZE) || (state == TRAVERSE);


  assign out_valid = valid_pipe[PipeLatency-1];
  assign out_fire = out_valid && advance;

  // Registered one cycle early off almost-full, so the write in the next cycle always has room.
  always_ff @(posedge clk) begin
    if (!rst_n) advance <= 1'b0;
    else advance <= !(|fifo_almost_full);
  end

  assign issue_addr = {pixel_y, pixel_x};


  always_comb begin
    concat_operand = '{default: '{default: '0}};
    c_operand = '{default: '{default: '0}};
    accumulator_op = '{4{Clear}};

    unique case (state)

      IDLE: begin
      end
      LOAD: begin
        if (triangle.empty_box == 1'b0) begin
          accumulator_op = '{4{Load}};
          c_operand = '{default: '{triangle.init_e0, triangle.init_e1, triangle.init_e2}};
          concat_operand[3] = '{triangle.e0_dx, triangle.e1_dx, triangle.e2_dx};
        end
      end
      INITIALIZE: begin
        concat_operand = '{
            default: '{triangle.e0_dx << 1, triangle.e1_dx << 1, triangle.e2_dx << 1}
        };
        c_operand[0] = '{default: '0};
        c_operand[1] = '{triangle.e0_dx, triangle.e1_dx, triangle.e2_dx};
        c_operand[2] = '{triangle.e0_dy, triangle.e1_dy, triangle.e2_dy};
        c_operand[3] = '{triangle.e0_dy, triangle.e1_dy, triangle.e2_dy};
        accumulator_op = '{Hold, AddY, AddY, AddXY};
      end
      TRAVERSE: begin
        concat_operand = '{
            default: '{triangle.e0_dx << 1, triangle.e1_dx << 1, triangle.e2_dx << 1}
        };
        c_operand = '{default: '{triangle.e0_dy << 1, triangle.e1_dy << 1, triangle.e2_dy << 1}};
        if (arrive_down) accumulator_op = '{4{AddY}};
        else begin
          if (dir_right) accumulator_op = '{4{AddX}};
          else accumulator_op = '{4{SubX}};
        end
      end
    endcase
  end

  for (genvar lane = 0; lane < 4; lane++) begin : g_lane
    for (genvar edge_idx = 0; edge_idx < 3; edge_idx++) begin : g_edge
      fx16_32_accumulator u_accumulator (
          .clk(clk),
          .rst_n(rst_n),
          .clken(advance),
          .op(accumulator_op[lane]),
          .concat_operand($signed(concat_operand[lane][edge_idx])),
          .c_operand($signed(c_operand[lane][edge_idx])),
          .result(edges[lane][edge_idx])
      );

      fx16_32_to_fp32 #(
          .LATENCY(Fx48Tof32Latency)
      ) u_converter (
          .aclk(clk),
          .aclken(advance),
          .valid_in(valid_pipe[AccumulatorLatency-1]),
          .a(edges[lane][edge_idx]),
          .result(results[lane][edge_idx])
      );
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wr_ptr <= '0;
    end else if (triangle_push) begin
      triangle_slots[wr_ptr[SlotW-1:0]] <= in_data;
      wr_ptr <= wr_ptr + 1'b1;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) rd_ptr <= '0;
    else if (triangle_pop) rd_ptr <= rd_ptr + 1'b1;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_pipe <= '0;
      last_pipe  <= '0;
      addr_pipe  <= '0;
    end else if (advance) begin
      valid_pipe <= {valid_pipe[PipeLatency-2:0], issue_valid};
      last_pipe  <= {last_pipe[PipeLatency-2:0], (issue_valid && issue_last) || skip_empty};
      addr_pipe  <= {addr_pipe[PipeLatency-2:0], issue_addr};
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= IDLE;
      trav_ptr <= '0;
      dir_right <= 1'b1;
      pixel_x <= '0;
      pixel_y <= '0;
      columns_left <= '0;
      rows_left <= '0;
      columns_per_row <= '0;
      row_end <= 1'b0;
      issue_last <= 1'b0;
      arrive_down <= 1'b0;
    end else begin
      if (advance) begin
        case (state)
          IDLE:
          if (prefetch_valid) begin
            state <= LOAD;
          end
          LOAD:
          if (skip_empty) begin
            trav_ptr <= trav_ptr + 1'b1;
            state <= prefetch_valid ? LOAD : IDLE;
          end else begin
            pixel_x <= triangle.minX_local;
            pixel_y <= triangle.minY_local;
            columns_per_row <= TILE_ADDR_X'(triangle.width - 1'b1);
            columns_left <= TILE_ADDR_X'(triangle.width - 1'b1);
            rows_left <= TILE_ADDR_Y'(triangle.height - 1'b1);
            dir_right <= 1'b1;
            row_end <= triangle.width == 1;
            issue_last <= triangle.width == 1 && triangle.height == 1;
            arrive_down <= 1'b0;
            state <= INITIALIZE;
          end
          INITIALIZE, TRAVERSE: begin
            if (row_end) begin
              pixel_y <= pixel_y + TILE_ADDR_Y'(1);
              dir_right <= !dir_right;
              columns_left <= columns_per_row;
              rows_left <= rows_left - TILE_ADDR_Y'(1);
              arrive_down <= 1'b1;
              row_end <= columns_per_row == 0;
              issue_last <= columns_per_row == 0 && rows_left == TILE_ADDR_Y'(1);
            end else begin
              pixel_x <= dir_right ? pixel_x + TILE_ADDR_X'(1) : pixel_x - TILE_ADDR_X'(1);
              columns_left <= columns_left - TILE_ADDR_X'(1);
              arrive_down <= 1'b0;
              row_end <= columns_left == TILE_ADDR_X'(1);
              issue_last <= columns_left == TILE_ADDR_X'(1) && rows_left == 0;
            end
            if (issue_last) begin
              trav_ptr <= trav_ptr + 1'b1;
              state <= prefetch_valid ? LOAD : IDLE;
            end else state <= TRAVERSE;
          end
          default: state <= IDLE;
        endcase
      end
    end
  end

  //
  // Output FIFOs
  //

  always_ff @(posedge clk) begin
    if (advance) out_template <= triangle_slots[rd_ptr[SlotW-1:0]].thread_data;
  end

  always_comb begin
    fifo_wdata[0] = out_template;
    fifo_wdata[0].e0 = results[0][0];
    fifo_wdata[0].e1 = results[0][1];
    fifo_wdata[0].e2 = results[0][2];
    fifo_wdata[0].addr = addr_pipe[PipeLatency-1];
    fifo_wdata[1] = out_template;
    fifo_wdata[1].e0 = results[1][0];
    fifo_wdata[1].e1 = results[1][1];
    fifo_wdata[1].e2 = results[1][2];
    fifo_wdata[1].addr = addr_pipe[PipeLatency-1];
    fifo_wdata[2] = out_template;
    fifo_wdata[2].e0 = results[2][0];
    fifo_wdata[2].e1 = results[2][1];
    fifo_wdata[2].e2 = results[2][2];
    fifo_wdata[2].addr = addr_pipe[PipeLatency-1];
    fifo_wdata[3] = out_template;
    fifo_wdata[3].e0 = results[3][0];
    fifo_wdata[3].e1 = results[3][1];
    fifo_wdata[3].e2 = results[3][2];
    fifo_wdata[3].addr = addr_pipe[PipeLatency-1];
  end

  for (genvar lane = 0; lane < 4; lane++) begin : g_thread_fifo
    logic fifo_empty;
    logic [$bits(thread_data_in_t)-1:0] rdata;

    async_fifo #(
        .DATA_WIDTH($bits(thread_data_in_t)),
        .FIFO_DEPTH(ThreadFifoDepth)
    ) u_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .data_i(fifo_wdata[lane]),
        .wr_en(out_fire),
        .rd_clk(thread_clk),
        .rd_rst_n(thread_rst_n),
        .rd_en(ready_in[lane]),
        .data_o(rdata),
        .fill_cnt(),
        .rd_fill_cnt(),
        .fifo_full(),
        .fifo_almost_full(fifo_almost_full[lane]),
        .fifo_empty(fifo_empty)
    );

    assign valid_out[lane] = !fifo_empty;
    assign out_data[lane]  = thread_data_in_t'(rdata);
  end

endmodule
