// Triangle DMA
// Copyright (c) 2026 Stavros Avramidis
//
// The AXI DataMover of gpu_top (xil_triangle_datamover: MM2S only, 512-bit memory and stream, no
// DRE), or a behavioural model of it under Verilator, Icarus or SIMULATION, which cannot run the IP.
//
// The model behaves as gpu_top uses the IP: one command at a time; INCR bursts of up to 16 beats
// that do not cross 4 KiB; the stream beat by beat, TKEEP marking the bytes of a partial last beat,
// TLAST on the last beat of a command whose EOF bit is set; then one status byte (OKAY, SLVERR,
// INTERR, TAG). Commands must start 64-byte aligned (triangle_stream_adapter aligns them).

`timescale 1ns / 1ps

`ifdef VERILATOR
`define TRIANGLE_DATAMOVER_MODEL
`endif
`ifdef SIMULATION
`define TRIANGLE_DATAMOVER_MODEL
`endif
`ifdef __ICARUS__
`define TRIANGLE_DATAMOVER_MODEL
`endif

module triangle_datamover (
    input logic aclk,
    input logic aresetn,

    // Command and status, DataMover formats with 32-bit addresses
    input  logic        s_cmd_tvalid,
    output logic        s_cmd_tready,
    input  logic [71:0] s_cmd_tdata,
    output logic        m_sts_tvalid,
    input  logic        m_sts_tready,
    output logic [ 7:0] m_sts_tdata,

    // AXI4 read master
    output logic [  3:0] m_axi_arid,
    output logic [ 31:0] m_axi_araddr,
    output logic [  7:0] m_axi_arlen,
    output logic [  2:0] m_axi_arsize,
    output logic [  1:0] m_axi_arburst,
    output logic [  2:0] m_axi_arprot,
    output logic [  3:0] m_axi_arcache,
    output logic [  3:0] m_axi_aruser,
    output logic         m_axi_arvalid,
    input  logic         m_axi_arready,
    input  logic [511:0] m_axi_rdata,
    input  logic [  1:0] m_axi_rresp,
    input  logic         m_axi_rlast,
    input  logic         m_axi_rvalid,
    output logic         m_axi_rready,

    // Stream
    output logic [511:0] m_axis_tdata,
    output logic [ 63:0] m_axis_tkeep,
    output logic         m_axis_tlast,
    output logic         m_axis_tvalid,
    input  logic         m_axis_tready,

    output logic mm2s_err
);

`ifndef TRIANGLE_DATAMOVER_MODEL

  logic       sts_tkeep_unused;
  logic       sts_tlast_unused;

  xil_triangle_datamover u_datamover (
      .m_axi_mm2s_aclk(aclk),
      .m_axi_mm2s_aresetn(aresetn),
      .mm2s_err(mm2s_err),
      .m_axis_mm2s_cmdsts_aclk(aclk),
      .m_axis_mm2s_cmdsts_aresetn(aresetn),
      .s_axis_mm2s_cmd_tvalid(s_cmd_tvalid),
      .s_axis_mm2s_cmd_tready(s_cmd_tready),
      .s_axis_mm2s_cmd_tdata(s_cmd_tdata),
      .m_axis_mm2s_sts_tvalid(m_sts_tvalid),
      .m_axis_mm2s_sts_tready(m_sts_tready),
      .m_axis_mm2s_sts_tdata(m_sts_tdata),
      .m_axis_mm2s_sts_tkeep(sts_tkeep_unused),
      .m_axis_mm2s_sts_tlast(sts_tlast_unused),
      .m_axi_mm2s_arid(m_axi_arid),
      .m_axi_mm2s_araddr(m_axi_araddr),
      .m_axi_mm2s_arlen(m_axi_arlen),
      .m_axi_mm2s_arsize(m_axi_arsize),
      .m_axi_mm2s_arburst(m_axi_arburst),
      .m_axi_mm2s_arprot(m_axi_arprot),
      .m_axi_mm2s_arcache(m_axi_arcache),
      .m_axi_mm2s_aruser(m_axi_aruser),
      .m_axi_mm2s_arvalid(m_axi_arvalid),
      .m_axi_mm2s_arready(m_axi_arready),
      .m_axi_mm2s_rdata(m_axi_rdata),
      .m_axi_mm2s_rresp(m_axi_rresp),
      .m_axi_mm2s_rlast(m_axi_rlast),
      .m_axi_mm2s_rvalid(m_axi_rvalid),
      .m_axi_mm2s_rready(m_axi_rready),
      .m_axis_mm2s_tdata(m_axis_tdata),
      .m_axis_mm2s_tkeep(m_axis_tkeep),
      .m_axis_mm2s_tlast(m_axis_tlast),
      .m_axis_mm2s_tvalid(m_axis_tvalid),
      .m_axis_mm2s_tready(m_axis_tready)
  );

`else

  localparam int BeatBytes = 64;
  localparam int MaxBurstBeats = 16;

  typedef enum logic [1:0] {
    Idle,
    Address,
    Data,
    Status
  } state_t;

  state_t state;
  logic [31:0] addr;  // next burst
  logic [22:0] bytes_left;  // of the command
  logic eof, error, interr;
  logic [3:0] tag;
  logic [8:0] burst_beats;

  // Beats left in the command, and beats to the next 4 KiB boundary (a burst must not cross it).
  logic [17:0] beats_left;
  logic [6:0] beats_to_4k;
  assign beats_left  = 18'((bytes_left + BeatBytes - 1) / BeatBytes);
  assign beats_to_4k = 7'((4096 - addr[11:0]) / BeatBytes);

  always_comb begin
    burst_beats = MaxBurstBeats;
    if (beats_left < burst_beats) burst_beats = 9'(beats_left);
    if (beats_to_4k < burst_beats) burst_beats = 9'(beats_to_4k);
  end

  assign s_cmd_tready  = state == Idle;
  assign m_axi_arid    = '0;
  assign m_axi_araddr  = addr;
  assign m_axi_arlen   = 8'(burst_beats - 1);
  assign m_axi_arsize  = 3'b110;  // 64 bytes
  assign m_axi_arburst = 2'b01;  // INCR
  assign m_axi_arprot  = '0;
  assign m_axi_arcache = 4'b0011;
  assign m_axi_aruser  = '0;
  assign m_axi_arvalid = state == Address;

  // R passes straight to the stream.
  assign m_axis_tdata  = m_axi_rdata;
  assign m_axis_tvalid = state == Data && m_axi_rvalid;
  assign m_axi_rready  = state == Data && m_axis_tready;
  assign m_axis_tkeep  = bytes_left >= BeatBytes ? '1 : (64'd1 << bytes_left) - 64'd1;
  assign m_axis_tlast  = eof && bytes_left <= BeatBytes;

  // OKAY, SLVERR, DECERR, INTERR, TAG
  assign m_sts_tvalid  = state == Status;
  assign m_sts_tdata   = {!error && !interr, error, 1'b0, interr, tag};

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      state <= Idle;
      mm2s_err <= 1'b0;
    end else begin
      case (state)
        Idle:
        if (s_cmd_tvalid) begin
          addr <= s_cmd_tdata[63:32];
          bytes_left <= s_cmd_tdata[22:0];
          eof <= s_cmd_tdata[30];
          tag <= s_cmd_tdata[67:64];
          error <= 1'b0;
          // The IP reports a zero BTT as an internal error.
          interr <= s_cmd_tdata[22:0] == '0;
          state <= s_cmd_tdata[22:0] == '0 ? Status : Address;
          if (s_cmd_tdata[37:32] != '0)
            $error("triangle_datamover model: command address %h is not 64-byte aligned",
                   s_cmd_tdata[63:32]);
        end
        Address: if (m_axi_arready) state <= Data;
        Data:
        if (m_axi_rvalid && m_axis_tready) begin
          addr <= addr + BeatBytes;
          bytes_left <= bytes_left > BeatBytes ? bytes_left - BeatBytes : '0;
          if (m_axi_rresp != 2'b00) error <= 1'b1;
          if (m_axi_rlast) state <= bytes_left > BeatBytes ? Address : Status;
        end
        Status:
        if (m_sts_tready) begin
          if (error || interr) mm2s_err <= 1'b1;
          state <= Idle;
        end
        default: state <= Idle;
      endcase
    end
  end

`endif

endmodule

`undef TRIANGLE_DATAMOVER_MODEL
