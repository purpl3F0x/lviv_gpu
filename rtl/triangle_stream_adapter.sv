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
// The visibility DMA's commands go to the DataMover as they are. Without DRE the DataMover does not
// realign: a command that starts on the upper half of a beat arrives with TKEEP clear over the lower
// half of its first beat, and one that ends on a lower half with TKEEP clear over the upper half of
// its last (its start and end strobes). So TKEEP alone says which halves are data. Every command
// must hold whole strides, as the visibility DMA's do (BTT = triangles x stride), for the gearbox
// to stay on record boundaries.
//
// Four registered stages, each taking a beat every cycle while the next one can, so the stream runs
// at a beat per cycle (two thirds of a triangle at a 96-byte stride) while the output is ready:
//   input skid buffer   the DataMover's TREADY ends here
//   half filter         the halves TKEEP keeps, packed to the front, and how many (0, 1 or 2)
//   gearbox             three halves to a 768-bit record, at most one per beat
//   output skid buffer  after triangle_unpack; the output's ready ends here

`timescale 1ns / 1ps

import gpu_types_pkg::*;

module triangle_stream_adapter #(
    // Bytes from one triangle to the next; 96 (packed) or 128. A multiple of 32, at least 96.
    parameter int TRIANGLE_STRIDE = 96
) (
    input logic aclk,
    input logic aresetn,

    // DataMover stream
    input  logic [511:0] s_axis_tdata,
    input  logic [ 63:0] s_axis_tkeep,
    input  logic         s_axis_tvalid,
    output logic         s_axis_tready,

    // Triangles
    output logic              m_tri_valid,
    input  logic              m_tri_ready,
    output frontend_data_in_t m_tri_data
);
  localparam int HalfBits = 256;
  localparam int HalfBytes = HalfBits / 8;
  localparam int RecordHalves = 3;  // 96 bytes
  localparam int StrideHalves = TRIANGLE_STRIDE / 32;

  initial begin
    if (TRIANGLE_STRIDE % 32 != 0 || StrideHalves < RecordHalves || StrideHalves > 4)
      $fatal(1, "triangle_stream_adapter: TRIANGLE_STRIDE must be 96 or 128");
  end

  //
  // Input skid buffer: the beat, and per half whether TKEEP keeps it
  //

  logic [511:0] beat_data;
  logic [1:0] beat_keep;
  logic beat_valid, beat_ready;

  axis_skid_buffer #(
      .WIDTH(512 + 2)
  ) u_in_skid (
      .aclk(aclk),
      .aresetn(aresetn),
      .s_axis_tdata({s_axis_tkeep[HalfBytes], s_axis_tkeep[0], s_axis_tdata}),
      .s_axis_tvalid(s_axis_tvalid),
      .s_axis_tready(s_axis_tready),
      .m_axis_tdata({beat_keep, beat_data}),
      .m_axis_tvalid(beat_valid),
      .m_axis_tready(beat_ready)
  );

`ifndef SYNTHESIS
  // 32-byte aligned addresses and lengths: TKEEP keeps each half whole or not at all.
  function automatic bit partial(input logic [HalfBytes-1:0] keep);
    return keep != '0 && keep != '1;
  endfunction

  always_ff @(posedge aclk) begin
    if (aresetn && s_axis_tvalid && s_axis_tready &&
        (partial(s_axis_tkeep[0+:HalfBytes]) || partial(s_axis_tkeep[HalfBytes+:HalfBytes])))
      $error("triangle_stream_adapter: TKEEP %h keeps part of a half", s_axis_tkeep);
  end
`endif

  //
  // Half filter
  //

  logic filt_valid, filt_ready;
  logic [1:0] filt_count;  // halves kept, in filt_half[0] then filt_half[1]
  logic [HalfBits-1:0] filt_half[2];

  assign beat_ready = !filt_valid || filt_ready;

  always_ff @(posedge aclk) begin
    if (!aresetn) filt_valid <= 1'b0;
    else if (beat_ready) filt_valid <= beat_valid && beat_keep != 2'b00;
  end

  // The data loads on every free cycle; filt_valid qualifies it.
  always_ff @(posedge aclk) begin
    if (beat_ready) begin
      filt_count <= 2'(beat_keep[0]) + 2'(beat_keep[1]);
      filt_half[0] <= beat_keep[0] ? beat_data[0+:HalfBits] : beat_data[HalfBits+:HalfBits];
      filt_half[1] <= beat_data[HalfBits+:HalfBits];
    end
  end

  //
  // Gearbox
  //

  logic [1:0] held;  // halves of the current record kept
  logic [HalfBits-1:0] held_half[2];
  logic [1:0] stride_pos;  // of the next half in its stride; RecordHalves and up are the gap
  logic rec_valid, rec_ready;
  logic [RecordHalves*HalfBits-1:0] rec_data;

  logic filt_fire;
  logic [1:0] held_next, stride_pos_next;
  logic [HalfBits-1:0] held_half_next[2];
  logic emit;
  logic [RecordHalves*HalfBits-1:0] emit_record;

  assign filt_ready = !rec_valid || rec_ready;
  assign filt_fire  = filt_valid && filt_ready;

  // The kept halves in address order: two of a record are held, the third completes it. At most
  // four halves (two held, two in), so at most one record per beat.
  always_comb begin
    held_next = held;
    held_half_next = held_half;
    stride_pos_next = stride_pos;
    emit = 1'b0;
    emit_record = '0;
    for (int slot = 0; slot < 2; slot++) begin
      if (2'(slot) < filt_count) begin
        if (stride_pos_next < 2'(RecordHalves)) begin
          if (held_next == 2'(RecordHalves - 1)) begin
            emit = 1'b1;
            emit_record = {filt_half[slot], held_half_next[1], held_half_next[0]};
            held_next = '0;
          end else begin
            held_half_next[held_next[0]] = filt_half[slot];
            held_next = held_next + 2'd1;
          end
        end
        stride_pos_next = stride_pos_next == 2'(StrideHalves - 1) ? '0 : stride_pos_next + 2'd1;
      end
    end
  end

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      held <= '0;
      stride_pos <= '0;
      rec_valid <= 1'b0;
    end else begin
      if (rec_ready) rec_valid <= 1'b0;
      if (filt_fire) begin
        held <= held_next;
        stride_pos <= stride_pos_next;
        if (emit) rec_valid <= 1'b1;
      end
    end
  end

  always_ff @(posedge aclk) begin
    if (filt_fire) begin
      held_half <= held_half_next;
      if (emit) rec_data <= emit_record;
    end
  end

  //
  // Output skid buffer
  //

  frontend_data_in_t rec_tri;
  logic [$bits(frontend_data_in_t)-1:0] out_bits;

  triangle_unpack u_unpack (
      .packed_triangle(rec_data),
      .triangle(rec_tri)
  );

  axis_skid_buffer #(
      .WIDTH($bits(frontend_data_in_t))
  ) u_out_skid (
      .aclk(aclk),
      .aresetn(aresetn),
      .s_axis_tdata(rec_tri),
      .s_axis_tvalid(rec_valid),
      .s_axis_tready(rec_ready),
      .m_axis_tdata(out_bits),
      .m_axis_tvalid(m_tri_valid),
      .m_axis_tready(m_tri_ready)
  );

  assign m_tri_data = frontend_data_in_t'(out_bits);

endmodule
