//  modified from: https://github.com/nelsoncsc/verilaxi/blob/main/rtl/common/snix_sync_fifo.sv
//
//  Synchronous first-word-fall-through FIFO with a registered output and no empty bypass.
//  - data_o is valid whenever fifo_empty is low; rd_en pops it (valid/ready style).
//  - fill_cnt counts every stored entry, including those in the read pipeline and data_o,
//    so it can be non-zero while fifo_empty is still high.
//  - Writes while full and reads while empty are ignored.
//
//  RAM_STYLE   Vivado ram_style for the storage: "distributed" (LUTRAM), "block" (BRAM),
//              "ultra" (URAM), "registers" or "auto".
//  OUTPUT_REGS Extra output pipeline registers after the RAM read register. For BRAM/URAM the first
//              one is packed into the primitive (DOB_REG / OREG; URAM wants at least 1), the rest
//              are fabric FFs, e.g. to cover routing to a distant consumer. For LUTRAM all are FFs.
//              Read latency is 1 + OUTPUT_REGS, write-to-data_o latency is 2 + OUTPUT_REGS.
//              Entries in flight count against FIFO_DEPTH, so sustained one-per-cycle streaming
//              needs FIFO_DEPTH >= 3 + OUTPUT_REGS.
//
//  The read pipeline moves on one shared enable (output register free or being popped; the RAM read
//  itself only when it holds data), so every stage maps onto the RAM's clock-enabled registers with
//  no fabric skid buffer. The cost is that rd_en drives those enables combinationally.

`timescale 1ns / 1ns

module sync_fifo #(
    parameter int DATA_WIDTH  = 32,
    parameter int FIFO_DEPTH  = 16,
    // Untyped on purpose: Vivado rejects a `string` parameter as an attribute value.
    // verilog_lint: waive explicit-parameter-storage-type
    parameter RAM_STYLE = "distributed",
    parameter int OUTPUT_REGS = 0
) (
    input logic clk,
    input logic rst_n,

    input logic                  wr_en,
    input logic [DATA_WIDTH-1:0] data_i,

    input  logic                  rd_en,
    output logic [DATA_WIDTH-1:0] data_o,

    output logic [$clog2(FIFO_DEPTH):0] fill_cnt,
    output logic                        fifo_full,
    output logic                        fifo_almost_full,
    output logic                        fifo_empty
);

  localparam int AddrW = $clog2(FIFO_DEPTH);
  localparam int ReadLatency = 1 + OUTPUT_REGS;

  initial begin
    if (FIFO_DEPTH < 2 || (FIFO_DEPTH & (FIFO_DEPTH - 1)) != 0)
      $fatal(1, "sync_fifo requires a power-of-two depth of at least 2");
    if (OUTPUT_REGS < 0) $fatal(1, "sync_fifo OUTPUT_REGS must be non-negative");
    if (RAM_STYLE != "distributed" && RAM_STYLE != "block" && RAM_STYLE != "ultra" &&
        RAM_STYLE != "registers" && RAM_STYLE != "auto")
      $fatal(1, "sync_fifo RAM_STYLE must be distributed, block, ultra, registers or auto");
  end

  // A read never targets the slot being written (that would need DEPTH entries in the RAM while a
  // write is accepted, which full prevents), so no read-during-write logic is needed.
  (* ram_style = RAM_STYLE, rw_addr_collision = "no" *) logic [DATA_WIDTH-1:0] mem[FIFO_DEPTH];

  // Emptiness comes from fill_cnt, so the pointers only index the RAM and need no wrap bit.
  logic [AddrW-1:0] wr_addr, rd_addr;
  // Keep the output stages as real FFs; with a shared enable Vivado would otherwise pack them into SRLs.
  (* shreg_extract = "no" *) logic [DATA_WIDTH-1:0] rd_pipe[ReadLatency];
  logic [ReadLatency-1:0] pipe_valid;
  logic write_fire, read_fire, advance, refill;

  assign write_fire = wr_en && !fifo_full;
  assign read_fire = rd_en && pipe_valid[ReadLatency-1];
  // The read pipeline moves whenever the output register is free or being popped.
  assign advance = !pipe_valid[ReadLatency-1] || read_fire;
  // The RAM holds data when not every stored entry is already in the read pipeline.
  assign refill = advance && (fill_cnt != (AddrW + 1)'($countones(pipe_valid)));

  always_ff @(posedge clk) begin
    if (!rst_n) wr_addr <= '0;
    else if (write_fire) wr_addr <= wr_addr + 1'b1;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) rd_addr <= '0;
    else if (refill) rd_addr <= rd_addr + 1'b1;
  end

  // Write
  always_ff @(posedge clk) if (write_fire) mem[wr_addr] <= data_i;

  // Read
  always_ff @(posedge clk) if (refill) rd_pipe[0] <= mem[rd_addr];

  for (genvar i = 1; i < ReadLatency; i++) begin : g_out_reg
    always_ff @(posedge clk) if (advance) rd_pipe[i] <= rd_pipe[i-1];
  end

  assign data_o = rd_pipe[ReadLatency-1];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pipe_valid <= '0;
    end else if (advance) begin
      pipe_valid[0] <= refill;
      for (int i = 1; i < ReadLatency; i++) pipe_valid[i] <= pipe_valid[i-1];
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) fill_cnt <= '0;
    else if (write_fire && !read_fire) fill_cnt <= fill_cnt + 1'b1;
    else if (read_fire && !write_fire) fill_cnt <= fill_cnt - 1'b1;
  end

  assign fifo_full = fill_cnt[AddrW];
  assign fifo_almost_full = fill_cnt >= (AddrW + 1)'(FIFO_DEPTH - 1);
  assign fifo_empty = !pipe_valid[ReadLatency-1];
endmodule : sync_fifo
