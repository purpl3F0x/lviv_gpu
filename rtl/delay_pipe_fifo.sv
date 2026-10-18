`timescale 1ns / 1ns

// Circular buffer in LUTRAM: synchronous write, asynchronous read, no registers of its own.
// dout = din from OFFSET CE ticks ago, so a register (or another delay_pipe_ram) must follow it.
//
// PTR_MODE 2: dual pointers OFFSET apart; dual-port RAM, ~0.6 LUT/bit up to 32 deep.
//          1: one pointer wrapping at OFFSET, read before write; single-port RAM, 1 LUT/bit per 64.
//          0: auto, dual below 32, single from 32 up.
// rst resets the pointers only.
module delay_pipe_ram #(
    parameter unsigned WIDTH    = 16,
    parameter unsigned OFFSET   = 16,   // storage delay in CE ticks, >= 1
    parameter unsigned PTR_MODE = 0     // 0 auto, 1 single pointer, 2 dual pointers
) (
    input  wire             clk,
    input  wire             rst,
    input  wire             ce,
    input  wire [WIDTH-1:0] din,
    output wire [WIDTH-1:0] dout
);

  localparam unsigned AW_RAW = $clog2(OFFSET);
  localparam unsigned AW     = (AW_RAW < 1) ? 1 : AW_RAW;
  localparam unsigned DEPTH  = 1 << AW;

  localparam unsigned SINGLE = (PTR_MODE == 1) ? 1 : (PTR_MODE == 2) ? 0 : (OFFSET >= 32) ? 1 : 0;

  (* ram_style = "distributed" *) reg [WIDTH-1:0] mem[0:DEPTH-1];

  integer i;
  initial begin
    for (i = 0; i < DEPTH; i = i + 1) mem[i] = {WIDTH{1'b0}};
  end

  generate
    if (SINGLE != 0) begin : g_single
      reg [AW-1:0] ptr = {AW{1'b0}};

      always @(posedge clk) begin
        if (rst) ptr <= {AW{1'b0}};
        else if (ce) ptr <= (ptr == OFFSET - 1) ? {AW{1'b0}} : ptr + 1'b1;
      end

      always @(posedge clk) begin
        if (ce) mem[ptr] <= din;
      end

      assign dout = mem[ptr];  // old content, read before the write above
    end else begin : g_dual
      localparam [AW-1:0] RD_INIT = DEPTH - OFFSET;
      reg [AW-1:0] wr_ptr = {AW{1'b0}};
      reg [AW-1:0] rd_ptr = RD_INIT;

      always @(posedge clk) begin
        if (ce) mem[wr_ptr] <= din;
      end

      always @(posedge clk) begin
        if (rst) begin
          wr_ptr <= {AW{1'b0}};
          rd_ptr <= RD_INIT;
        end else if (ce) begin
          wr_ptr <= wr_ptr + 1'b1;  // power-of-two depth, wraps naturally
          rd_ptr <= rd_ptr + 1'b1;
        end
      end

      assign dout = mem[rd_ptr];
    end
  endgenerate

endmodule


// LUTRAM drop-in for delay_pipe: same ports, and STAGES = N delays by exactly N cycles.
// Optional input register, delay_pipe_ram, output register; the RAM holds STAGES - 1 - IN_REG
// entries, so IN_REG moves one cycle from the RAM into a register without changing the latency.
// Requires STAGES >= 2 + IN_REG. clken low freezes everything; rst_n resets the pointers only, so
// data_out is meaningful STAGES cycles after a reset.
module delay_pipe_fifo #(
    parameter unsigned WIDTH    = 16,
    parameter unsigned STAGES   = 16,
    parameter unsigned IN_REG   = 1,    // 1: register data_in before the RAM, 0: write it directly
    parameter unsigned PTR_MODE = 0     // 0 auto, 1 single pointer, 2 dual pointers
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             clken,
    input  wire [WIDTH-1:0] data_in,
    output reg  [WIDTH-1:0] data_out
);

  localparam integer OFFSET_RAW = STAGES - 1 - ((IN_REG != 0) ? 1 : 0);
  localparam unsigned OFFSET    = (OFFSET_RAW < 1) ? 1 : OFFSET_RAW;

  initial begin
    if (OFFSET_RAW < 1) $fatal(1, "delay_pipe_fifo requires STAGES >= 2 + IN_REG");
  end

  wire [WIDTH-1:0] wr_data;
  generate
    if (IN_REG != 0) begin : g_in_reg
      reg [WIDTH-1:0] din_r = {WIDTH{1'b0}};
      always @(posedge clk) begin
        if (clken) din_r <= data_in;
      end
      assign wr_data = din_r;
    end else begin : g_no_in_reg
      assign wr_data = data_in;
    end
  endgenerate

  wire [WIDTH-1:0] rd_data;

  delay_pipe_ram #(
      .WIDTH   (WIDTH),
      .OFFSET  (OFFSET),
      .PTR_MODE(PTR_MODE)
  ) u_ram (
      .clk (clk),
      .rst (!rst_n),
      .ce  (clken),
      .din (wr_data),
      .dout(rd_data)
  );

  initial data_out = {WIDTH{1'b0}};
  always @(posedge clk) begin
    if (clken) data_out <= rd_data;
  end

endmodule
