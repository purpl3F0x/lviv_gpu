`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Frame buffer RAM: two write ports share the BRAM's write port, two read ports
// share its read port, all on one clock.
//
// Usage assumption: W0 and W1 never write in the same cycle, and R0 and R1 never
// read in the same cycle. This is not checked; on a collision port 0 wins, the
// port 1 write is dropped and R1 returns R0's data.
//
// Latency: a write lands 2 cycles after w*_en; read data appears
// 1 + READ_OUT_STAGES cycles after r*_en (input register + read registers).
// -----------------------------------------------------------------------------
module frame_buffer_ram #(
    parameter unsigned DATA_WIDTH = 32,
    parameter unsigned ADDR_WIDTH = 12,  // Word address width
    // Read registers: 2 in the BRAM (array, DO_REG) + READ_OUT_STAGES - 2 per
    // port in fabric. Min 2.
    parameter unsigned READ_OUT_STAGES = 2
) (
    // -------------------------------------------------------------------------
    // Clock & Reset (shared by all ports)
    // -------------------------------------------------------------------------
    input wire clk,
    input wire rst_n,

    // WRITE PORT 0 (BRAM_W0)
    input wire                  w0_en,
    input wire [ADDR_WIDTH-1:0] w0_addr,
    input wire [DATA_WIDTH-1:0] w0_din,

    // WRITE PORT 1 (BRAM_W1)
    input wire                  w1_en,
    input wire [ADDR_WIDTH-1:0] w1_addr,
    input wire [DATA_WIDTH-1:0] w1_din,

    // READ PORT 0 (BRAM_R0)
    input  wire                  r0_en,
    input  wire [ADDR_WIDTH-1:0] r0_addr,
    output wire [DATA_WIDTH-1:0] r0_dout,

    // READ PORT 1 (BRAM_R1)
    input  wire                  r1_en,
    input  wire [ADDR_WIDTH-1:0] r1_addr,
    output wire [DATA_WIDTH-1:0] r1_dout
);

  localparam unsigned DEPTH = 1 << ADDR_WIDTH;

  // -------------------------------------------------------------------------
  // 1. Input Register Stage
  // -------------------------------------------------------------------------
  reg r_w0_en, r_w1_en;
  reg [ADDR_WIDTH-1:0] r_w0_addr, r_w1_addr;
  reg [DATA_WIDTH-1:0] r_w0_din, r_w1_din;

  reg r_r0_en, r_r1_en;
  reg [ADDR_WIDTH-1:0] r_r0_addr, r_r1_addr;

  always @(posedge clk) begin
    if (!rst_n) begin
      r_w0_en <= 1'b0;
      r_w1_en <= 1'b0;
      r_r0_en <= 1'b0;
      r_r1_en <= 1'b0;
    end else begin
      r_w0_en <= w0_en;
      r_w1_en <= w1_en;
      r_r0_en <= r0_en;
      r_r1_en <= r1_en;
    end
  end

  always @(posedge clk) begin
    r_w0_addr <= w0_addr;
    r_w1_addr <= w1_addr;
    r_w0_din  <= w0_din;
    r_w1_din  <= w1_din;

    r_r0_addr <= r0_addr;
    r_r1_addr <= r1_addr;
  end

  // -------------------------------------------------------------------------
  // 2. Drive BRAM Pins from Registered Signals
  // -------------------------------------------------------------------------
  wire                  ram_ena = r_w0_en | r_w1_en;
  wire [ADDR_WIDTH-1:0] ram_addra = r_w0_en ? r_w0_addr : r_w1_addr;
  wire [DATA_WIDTH-1:0] ram_dia = r_w0_en ? r_w0_din : r_w1_din;

  wire                  ram_enb = r_r0_en | r_r1_en;
  wire [ADDR_WIDTH-1:0] ram_addrb = r_r0_en ? r_r0_addr : r_r1_addr;

  // -------------------------------------------------------------------------
  // 3. BRAM Storage & Output Stages
  // -------------------------------------------------------------------------
  (* ram_style = "block", cascade_height = 1  *)reg  [DATA_WIDTH-1:0] mem                                         [DEPTH];

  reg  [DATA_WIDTH-1:0] ram_core_data;
  reg  [DATA_WIDTH-1:0] bram_dout_reg;

  // Synchronous full-word write process
  always @(posedge clk) begin
    if (ram_ena) begin
      mem[ram_addra] <= ram_dia;
    end
  end

  // Stage 0: Synchronous Core Read
  always @(posedge clk) begin
    if (ram_enb) begin
      ram_core_data <= mem[ram_addrb];
    end
  end

  // Stage 1 Enable: 1-cycle delayed ram_enb to latch Stage 0 core data
  reg ram_enb_d1;
  always @(posedge clk) begin
    if (!rst_n) begin
      ram_enb_d1 <= 1'b0;
    end else begin
      ram_enb_d1 <= ram_enb;
    end
  end

  // Stage 1: Absorbed into hard primitive DOB_REG
  always @(posedge clk) begin
    if (ram_enb_d1) begin
      bram_dout_reg <= ram_core_data;
    end
  end

  // -------------------------------------------------------------------------
  // 4. Per-Port Output Stages (READ_OUT_STAGES - 2 fabric registers per port)
  // -------------------------------------------------------------------------
  // The first register of each port loads only on that port's reads, so it holds
  // the port's last read data; any further ones are plain pipeline registers.
  // With READ_OUT_STAGES = 2 both ports read DO_REG directly, which holds the
  // data of the last read on either port.
  if (READ_OUT_STAGES < 2) begin : g_read_out_stages_check
    $error("frame_buffer_ram: READ_OUT_STAGES must be at least 2");
  end

  if (READ_OUT_STAGES <= 2) begin : g_no_out_regs
    assign r0_dout = bram_dout_reg;
    assign r1_dout = bram_dout_reg;
  end else begin : g_out_regs
    // Read enables aligned with bram_dout_reg (input register, array, DO_REG)
    reg [2:0] rd_valid_0, rd_valid_1;
    always @(posedge clk) begin
      if (!rst_n) begin
        rd_valid_0 <= 3'b0;
        rd_valid_1 <= 3'b0;
      end else begin
        rd_valid_0 <= {rd_valid_0[1:0], r0_en};
        rd_valid_1 <= {rd_valid_1[1:0], r1_en};
      end
    end

    reg [DATA_WIDTH-1:0] out_r0[READ_OUT_STAGES-2];
    reg [DATA_WIDTH-1:0] out_r1[READ_OUT_STAGES-2];

    integer s;
    always @(posedge clk) begin
      if (rd_valid_0[2]) out_r0[0] <= bram_dout_reg;
      if (rd_valid_1[2]) out_r1[0] <= bram_dout_reg;
      for (s = 1; s < READ_OUT_STAGES - 2; s = s + 1) begin
        out_r0[s] <= out_r0[s-1];
        out_r1[s] <= out_r1[s-1];
      end
    end

    assign r0_dout = out_r0[READ_OUT_STAGES-3];
    assign r1_dout = out_r1[READ_OUT_STAGES-3];
  end

endmodule
