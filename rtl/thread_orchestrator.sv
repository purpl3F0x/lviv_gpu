// Thread Orchestrator Module
// Copyright (c) 2026 Stavros Avramidis
//
// Performs a snake-like traversal of 2x2 pixel quads across the bounding box of a triangle,
// updating edge functions incrementally and distributing them to 4 parallel thread execution units.


`timescale 1ns / 1ns

import gpu_types_pkg::*;


module thread_orchestrator (
    input logic clk,
    input logic rst_n,

    // Frontend Handshake
    input  logic valid_in,
    output logic ready_out,

    // Backend Handshake (one per thread)
    input  logic ready_in [4],
    output logic valid_out[4],

    // Initial inputs from Frontend (floats)
    input logic [31:0] init_e0[4],
    input logic [31:0] init_e1[4],
    input logic [31:0] init_e2[4],

    input logic [31:0] e0_dx_2x,
    input logic [31:0] e0_dy_2x,
    input logic [31:0] e1_dx_2x,
    input logic [31:0] e1_dy_2x,
    input logic [31:0] e2_dx_2x,
    input logic [31:0] e2_dy_2x,

    input logic [7:0] minX_local,
    input logic [7:0] minY_local,
    input logic [7:0] width,
    input logic [7:0] height,

    input logic    [31:0] invArea,
    input vertex_t        v0,
    input vertex_t        v1,
    input vertex_t        v2,

    // Outputs to Threads (one per thread)
    output logic [31:0] out_e0[4],
    output logic [31:0] out_e1[4],
    output logic [31:0] out_e2[4],
    output logic [PIXEL_ADDR_W-1:0] out_pixel_id[4],

    output logic    [31:0] out_invArea,
    output vertex_t        out_v0,
    output vertex_t        out_v1,
    output vertex_t        out_v2
);

  localparam int ADD_SUB_LATENCY = 8;

  // States
  typedef enum logic {
    ST_IDLE,
    ST_TRAVERSE
  } state_t;

  state_t        state;

  // Traversal coordinates & limits
  logic   [ 7:0] num_quads_x;
  logic   [ 7:0] num_quads_y;
  logic   [ 7:0] curr_qx;  // Horizontal quad index
  logic   [ 7:0] curr_qy;  // Vertical quad index
  logic          dir_right;  // 1: Right, 0: Left

  // Pixel coordinates tracking
  logic   [ 7:0] qx_coord;
  logic   [ 7:0] qy_coord;

  // Local bounding box registers
  logic   [ 7:0] r_minX;
  logic   [ 7:0] r_minY;
  logic   [ 7:0] r_width;
  logic   [ 7:0] r_height;

  // Edge function registers
  logic   [31:0] e0_reg                            [4];
  logic   [31:0] e1_reg                            [4];
  logic   [31:0] e2_reg                            [4];

  // Pass-through registers
  logic   [31:0] r_invArea;
  vertex_t r_v0, r_v1, r_v2;

  // Handshake stalling logic
  // Stall if any thread is supposed to receive valid data but is not ready
  logic stall;
  logic thread_ready;
  assign thread_ready = ~ready_in[0] || ~ready_in[1] || ~ready_in[2] || ~ready_in[3];
  assign stall = (state == ST_TRAVERSE) && !thread_ready;

  // Ready out to frontend
  assign ready_out = (state == ST_IDLE);

  // Snake traversal movement controls
  logic move_down;
  logic move_horizontal;
  logic step_done;

  always_comb begin
    move_down = 1'b0;
    move_horizontal = 1'b0;
    step_done = 1'b0;

    if (state == ST_TRAVERSE && !stall) begin
      if (dir_right) begin
        if (curr_qx < num_quads_x) begin
          move_horizontal = 1'b1;
        end else if (curr_qy < num_quads_y) begin
          move_down = 1'b1;
        end else begin
          step_done = 1'b1;
        end
      end else begin
        if (curr_qx > 0) begin
          move_horizontal = 1'b1;
        end else if (curr_qy < num_quads_y) begin
          move_down = 1'b1;
        end else begin
          step_done = 1'b1;
        end
      end
    end
  end

  // Floating-point adder control signals
  logic        fp_op_sub;
  logic [31:0] fp_e0_b;
  logic [31:0] fp_e1_b;
  logic [31:0] fp_e2_b;
  logic        fp_valid_in;

  assign fp_op_sub = (state == ST_TRAVERSE) && !dir_right && move_horizontal; // Subtract if moving left
  assign fp_e0_b = move_down ? e0_dy_2x : e0_dx_2x;
  assign fp_e1_b = move_down ? e1_dy_2x : e1_dx_2x;
  assign fp_e2_b = move_down ? e2_dy_2x : e2_dx_2x;
  assign fp_valid_in = (state == ST_TRAVERSE) && !stall && (move_horizontal || move_down);

  // Registered adder inputs for timing closure/fmax
  logic        fp_op_sub_reg;
  logic        fp_valid_in_reg;
  logic [31:0] fp_e0_b_reg;
  logic [31:0] fp_e1_b_reg;
  logic [31:0] fp_e2_b_reg;
  logic [31:0] e0_reg_reg      [4];
  logic [31:0] e1_reg_reg      [4];
  logic [31:0] e2_reg_reg      [4];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      fp_op_sub_reg   <= 1'b0;
      fp_valid_in_reg <= 1'b0;
      fp_e0_b_reg     <= 32'b0;
      fp_e1_b_reg     <= 32'b0;
      fp_e2_b_reg     <= 32'b0;
      for (int i = 0; i < 4; i++) begin
        e0_reg_reg[i] <= 32'b0;
        e1_reg_reg[i] <= 32'b0;
        e2_reg_reg[i] <= 32'b0;
      end
    end else if (!stall) begin
      fp_op_sub_reg   <= fp_op_sub;
      fp_valid_in_reg <= fp_valid_in;
      fp_e0_b_reg     <= fp_e0_b;
      fp_e1_b_reg     <= fp_e1_b;
      fp_e2_b_reg     <= fp_e2_b;
      for (int i = 0; i < 4; i++) begin
        e0_reg_reg[i] <= e0_reg[i];
        e1_reg_reg[i] <= e1_reg[i];
        e2_reg_reg[i] <= e2_reg[i];
      end
    end
  end

  // Floating-point adders outputs
  logic [31:0] e0_next[4];
  logic [31:0] e1_next[4];
  logic [31:0] e2_next[4];
  logic fp_valid_out_e0[4];

  // Instantiate 12 floating-point add_sub units (4 threads x 3 edge functions)
  generate
    for (genvar i = 0; i < 4; i++) begin : g_fp_adders
      fp_add_sub #(
          .LATENCY(ADD_SUB_LATENCY)
      ) u_fp_add_sub_e0 (
          .aclk     (clk),
          .aresetn  (rst_n),
          .aclken   (!stall),
          .op_sub   (fp_op_sub_reg),
          .valid_in (fp_valid_in_reg),
          .a        (e0_reg_reg[i]),
          .b        (fp_e0_b_reg),
          .valid_out(fp_valid_out_e0[i]),
          .result   (e0_next[i])
      );

      fp_add_sub #(
          .LATENCY(ADD_SUB_LATENCY)
      ) u_fp_add_sub_e1 (
          .aclk     (clk),
          .aresetn  (rst_n),
          .aclken   (!stall),
          .op_sub   (fp_op_sub_reg),
          .valid_in (fp_valid_in_reg),
          .a        (e1_reg_reg[i]),
          .b        (fp_e1_b_reg),
          .valid_out(),
          .result   (e1_next[i])
      );

      fp_add_sub #(
          .LATENCY(ADD_SUB_LATENCY)
      ) u_fp_add_sub_e2 (
          .aclk     (clk),
          .aresetn  (rst_n),
          .aclken   (!stall),
          .op_sub   (fp_op_sub_reg),
          .valid_in (fp_valid_in_reg),
          .a        (e2_reg_reg[i]),
          .b        (fp_e2_b_reg),
          .valid_out(),
          .result   (e2_next[i])
      );
    end
  endgenerate

  // State Machine and Traversal Logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state       <= ST_IDLE;
      curr_qx     <= '0;
      curr_qy     <= '0;
      dir_right   <= 1'b1;
      qx_coord    <= '0;
      qy_coord    <= '0;
      num_quads_x <= '0;
      num_quads_y <= '0;
      r_minX      <= '0;
      r_minY      <= '0;
      r_width     <= '0;
      r_height    <= '0;
      r_invArea   <= '0;
      r_v0        <= '0;
      r_v1        <= '0;
      r_v2        <= '0;

      for (int i = 0; i < 4; i++) begin
        e0_reg[i] <= '0;
        e1_reg[i] <= '0;
        e2_reg[i] <= '0;
      end
    end else begin
      unique case (state)
        ST_IDLE: begin
          if (valid_in) begin
            state       <= ST_TRAVERSE;
            curr_qx     <= '0;
            curr_qy     <= '0;
            dir_right   <= 1'b1;

            // Bounding box start coordinates
            qx_coord    <= minX_local;
            qy_coord    <= minY_local;

            r_minX      <= minX_local;
            r_minY      <= minY_local;
            r_width     <= width;
            r_height    <= height;

            // Calculate number of quads covering the bounding box
            num_quads_x <= (width >> 1) - 1;
            num_quads_y <= (height >> 1) - 1;

            // Pass-through parameters
            r_invArea   <= invArea;
            r_v0        <= v0;
            r_v1        <= v1;
            r_v2        <= v2;

            // Load initial edge functions
            for (int i = 0; i < 4; i++) begin
              e0_reg[i] <= init_e0[i];
              e1_reg[i] <= init_e1[i];
              e2_reg[i] <= init_e2[i];
            end
          end
        end

        ST_TRAVERSE: begin
          if (!stall) begin
            if (move_horizontal) begin
              if (dir_right) begin
                curr_qx  <= curr_qx + 1;
                qx_coord <= qx_coord + 2;
              end else begin
                curr_qx  <= curr_qx - 1;
                qx_coord <= qx_coord - 2;
              end
              for (int i = 0; i < 4; i++) begin
                e0_reg[i] <= e0_next[i];
                e1_reg[i] <= e1_next[i];
                e2_reg[i] <= e2_next[i];
              end
            end else if (move_down) begin
              curr_qy   <= curr_qy + 1;
              qy_coord  <= qy_coord + 2;
              dir_right <= ~dir_right;
              for (int i = 0; i < 4; i++) begin
                e0_reg[i] <= e0_next[i];
                e1_reg[i] <= e1_next[i];
                e2_reg[i] <= e2_next[i];
              end
            end else if (step_done) begin
              state <= ST_IDLE;
            end
          end
        end
      endcase
    end
  end

  // logic [3:0] in_bb_mask;

  // Bounding box pixel validity checking & masking
  // always_comb begin
  //   for (int i = 0; i < 4; i++) begin
  //     in_bb_mask[i] = (state == ST_TRAVERSE);
  //   end
  // end

  // Delay pipelines for valid mask and pass-through metadata
  // Latency is ADD_SUB_LATENCY + 1 (for input registration)
  localparam int TOTAL_LATENCY = ADD_SUB_LATENCY + 1;

  logic    [ 7:0] qx_coord_pipe[TOTAL_LATENCY];
  logic    [ 7:0] qy_coord_pipe[TOTAL_LATENCY];
  // logic    [ 3:0] in_bb_mask_pipe[TOTAL_LATENCY];
  logic    [31:0] invArea_pipe [TOTAL_LATENCY];
  vertex_t        v0_pipe      [TOTAL_LATENCY];
  vertex_t        v1_pipe      [TOTAL_LATENCY];
  vertex_t        v2_pipe      [TOTAL_LATENCY];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < TOTAL_LATENCY; i++) begin
        // in_bb_mask_pipe[i] <= '0;
        qx_coord_pipe[i] <= '0;
        qy_coord_pipe[i] <= '0;
        invArea_pipe[i]  <= '0;
        v0_pipe[i]       <= '0;
        v1_pipe[i]       <= '0;
        v2_pipe[i]       <= '0;
      end
    end else if (!stall) begin
      // in_bb_mask_pipe[0] <= in_bb_mask;
      qx_coord_pipe[0] <= qx_coord;
      qy_coord_pipe[0] <= qy_coord;
      invArea_pipe[0]  <= r_invArea;
      v0_pipe[0]       <= r_v0;
      v1_pipe[0]       <= r_v1;
      v2_pipe[0]       <= r_v2;
      for (int i = 1; i < TOTAL_LATENCY; i++) begin
        // in_bb_mask_pipe[i] <= in_bb_mask_pipe[i-1];
        qx_coord_pipe[i] <= qx_coord_pipe[i-1];
        qy_coord_pipe[i] <= qy_coord_pipe[i-1];
        invArea_pipe[i]  <= invArea_pipe[i-1];
        v0_pipe[i]       <= v0_pipe[i-1];
        v1_pipe[i]       <= v1_pipe[i-1];
        v2_pipe[i]       <= v2_pipe[i-1];
      end
    end
  end

  always_comb begin
    for (int i = 0; i < 4; i++) begin
      // valid_out[i] = fp_valid_out_e0[0] && in_bb_mask_pipe[TOTAL_LATENCY-1][i];
      valid_out[i] = fp_valid_out_e0[0];
    end
  end

  // Assignments to output ports
  assign out_e0 = e0_reg;
  assign out_e1 = e1_reg;
  assign out_e2 = e2_reg;
  assign out_pixel_id[0] =
      (qy_coord_pipe[TOTAL_LATENCY-1] * TILE_SIZE_X) +
      qx_coord_pipe[TOTAL_LATENCY-1];
  assign out_pixel_id[1] =
      (qy_coord_pipe[TOTAL_LATENCY-1] * TILE_SIZE_X) +
      qx_coord_pipe[TOTAL_LATENCY-1] + 1;
  assign out_pixel_id[2] =
      ((qy_coord_pipe[TOTAL_LATENCY-1] + 1) * TILE_SIZE_X) +
      qx_coord_pipe[TOTAL_LATENCY-1];
  assign out_pixel_id[3] =
      ((qy_coord_pipe[TOTAL_LATENCY-1] + 1) * TILE_SIZE_X) +
      qx_coord_pipe[TOTAL_LATENCY-1] + 1;
  assign out_invArea = invArea_pipe[TOTAL_LATENCY-1];
  assign out_v0 = v0_pipe[TOTAL_LATENCY-1];
  assign out_v1 = v1_pipe[TOTAL_LATENCY-1];
  assign out_v2 = v2_pipe[TOTAL_LATENCY-1];

endmodule
