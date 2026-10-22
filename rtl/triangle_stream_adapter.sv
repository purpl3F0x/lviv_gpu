// Triangle Stream Adapter
// Copyright (c) 2026 Stavros Avramidis
//
// Turns the triangle DMA's 512-bit stream into frontend_data_in_t triangles.
//
// A triangle is a 96-byte gpu_triangle_t (sdk/include/gpu_triangle.h), stored every TRIANGLE_STRIDE
// bytes from a 32-byte aligned base. A beat is two 32-byte halves and a record three, so at a
// 96-byte stride a triangle arrives as a full beat and a half, or a half and a full beat. At a
// 128-byte stride each record is followed by a 32-byte gap, which is dropped.
//
// Commands from the visibility DMA pass through on their way to the DataMover. Each is aligned down
// to 64 bytes, its BTT lengthened by the half it now starts early, so the DataMover (no DRE) only
// sees aligned commands. A side FIFO keeps, per command, whether its first half is that extra half
// and how many halves the command holds; the gearbox drops the first and stops at the second, so it
// does not depend on TKEEP or TLAST. A command's data always starts on a new beat.
//
// Up to one triangle per beat: at a 96-byte stride the stream is 1.5 beats per triangle.

`timescale 1ns / 1ps

import gpu_types_pkg::*;

module triangle_stream_adapter #(
    // Bytes from one triangle to the next; 96 (packed) or 128. A multiple of 32, at least 96.
    parameter int TRIANGLE_STRIDE = 96
) (
    input logic aclk,
    input logic aresetn,

    // Commands from the visibility DMA, and the same commands aligned for the DataMover
    input  logic        s_cmd_tvalid,
    output logic        s_cmd_tready,
    input  logic [71:0] s_cmd_tdata,
    output logic        m_cmd_tvalid,
    input  logic        m_cmd_tready,
    output logic [71:0] m_cmd_tdata,

    // DataMover stream
    input  logic [511:0] s_axis_tdata,
    input  logic         s_axis_tvalid,
    output logic         s_axis_tready,

    // Triangles
    output logic              m_tri_valid,
    input  logic              m_tri_ready,
    output frontend_data_in_t m_tri_data
);
  localparam int HalfBits = 256;
  localparam int RecordHalves = 3;  // 96 bytes
  localparam int StrideHalves = TRIANGLE_STRIDE / 32;
  localparam int HalvesW = 19;  // a 23-bit BTT in 32-byte halves
  localparam int SideFifoDepth = 16;  // commands the DataMover can hold, with margin

  initial begin
    if (TRIANGLE_STRIDE % 32 != 0 || StrideHalves < RecordHalves || StrideHalves > 4)
      $fatal(1, "triangle_stream_adapter: TRIANGLE_STRIDE must be 96 or 128");
  end

  //
  // Command alignment
  //

  logic lead_half;
  logic [22:0] aligned_btt;
  logic side_full, side_empty, side_pop;
  logic [HalvesW:0] side_in, side_out;
  logic side_lead;
  logic [HalvesW-1:0] side_halves;

  assign lead_half = s_cmd_tdata[37];  // the command starts on the upper half of a beat
  assign aligned_btt = s_cmd_tdata[22:0] + (lead_half ? 23'd32 : 23'd0);

  always_comb begin
    m_cmd_tdata = s_cmd_tdata;
    m_cmd_tdata[63:32] = {s_cmd_tdata[63:38], 6'b0};
    m_cmd_tdata[22:0] = aligned_btt;
  end

  assign m_cmd_tvalid = s_cmd_tvalid && !side_full;
  assign s_cmd_tready = m_cmd_tready && !side_full;
  assign side_in = {lead_half, HalvesW'(aligned_btt >> 5)};

  sync_fifo #(
      .DATA_WIDTH(HalvesW + 1),
      .FIFO_DEPTH(SideFifoDepth)
  ) u_side_fifo (
      .clk(aclk),
      .rst_n(aresetn),
      .wr_en(s_cmd_tvalid && s_cmd_tready),
      .data_i(side_in),
      .rd_en(side_pop),
      .data_o(side_out),
      .fill_cnt(),
      .fifo_full(side_full),
      .fifo_almost_full(),
      .fifo_empty(side_empty)
  );

  assign {side_lead, side_halves} = side_out;

  //
  // Gearbox
  //

  logic [HalvesW-1:0] halves_seen;  // of the current command, including its lead half
  logic [1:0] rec_pos;  // half of the current record the next data half is
  logic [HalfBits-1:0] rec_half[2];  // the record's first two halves
  logic out_valid;
  logic [RecordHalves*HalfBits-1:0] out_record;

  logic beat_fire;
  logic [HalvesW-1:0] halves_seen_next;
  logic [1:0] rec_pos_next;
  logic [HalfBits-1:0] rec_half_next[2];
  logic emit;
  logic [RecordHalves*HalfBits-1:0] emit_record;
  logic command_done;

  // The output register is free next cycle, and the command the beat belongs to is known.
  assign s_axis_tready = !side_empty && (!out_valid || m_tri_ready);
  assign beat_fire = s_axis_tvalid && s_axis_tready;

  // Walks the beat's two halves in address order. Record halves 0 and 1 are kept, half 2 completes
  // the triangle, and half 3 (a 128-byte stride) is the gap.
  always_comb begin
    logic [HalvesW-1:0] position;
    logic [HalfBits-1:0] half;
    rec_pos_next = rec_pos;
    rec_half_next = rec_half;
    emit = 1'b0;
    emit_record = '0;
    for (int slot = 0; slot < 2; slot++) begin
      position = halves_seen + HalvesW'(slot);
      half = s_axis_tdata[slot*HalfBits+:HalfBits];
      // Inside the command, and not the extra half its alignment added in front.
      if (position < side_halves && !(position == '0 && side_lead)) begin
        if (rec_pos_next < 2'(RecordHalves - 1)) begin
          rec_half_next[rec_pos_next[0]] = half;
        end else if (rec_pos_next == 2'(RecordHalves - 1)) begin
          emit = 1'b1;
          emit_record = {half, rec_half_next[1], rec_half_next[0]};
        end
        rec_pos_next = rec_pos_next == 2'(StrideHalves - 1) ? 2'd0 : rec_pos_next + 2'd1;
      end
    end
    halves_seen_next = halves_seen + HalvesW'(2);
    command_done = halves_seen_next >= side_halves;
  end

  assign side_pop = beat_fire && command_done;

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      halves_seen <= '0;
      rec_pos <= '0;
      out_valid <= 1'b0;
    end else begin
      if (m_tri_ready) out_valid <= 1'b0;
      if (beat_fire) begin
        rec_half <= rec_half_next;
        if (emit) begin
          out_valid  <= 1'b1;
          out_record <= emit_record;
        end
        if (command_done) begin
          halves_seen <= '0;
          rec_pos <= '0;
`ifndef SYNTHESIS
          if (rec_pos_next != '0)
            $error("triangle_stream_adapter: command of %0d halves ends inside a triangle",
                   side_halves);
`endif
        end else begin
          halves_seen <= halves_seen_next;
          rec_pos <= rec_pos_next;
        end
      end
    end
  end

  assign m_tri_valid = out_valid;

  triangle_unpack u_unpack (
      .packed_triangle(out_record),
      .triangle(m_tri_data)
  );

endmodule
