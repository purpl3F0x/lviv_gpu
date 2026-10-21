`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Frame buffer RAM: two write ports share the BRAM's write port, two read ports
// share its read port, all on one clock.
//
// Port 0 (W0/R0) is 32 bits wide. Port 1 (W1/R1) is 64 bits wide with one
// address bit less: port-1 word a holds port-0 words {a, 0} (low half) and
// {a, 1} (high half). The RAM is 64 bits wide with a write enable per 32-bit
// half; W0 writes the half picked by w0_addr[0], W1 writes both, and R0 reads
// the half picked by r0_addr[0].
//
// Usage assumption: W0 and W1 never write in the same cycle, and R0 and R1 never
// read in the same cycle. This is not checked; on a collision port 0 wins, the
// port 1 write is dropped and R1 returns the row R0 addressed.
//
// Latency: a write lands 2 cycles after w*_en; read data appears 4 cycles after
// r*_en (input register, BRAM array register, DO_REG, per-port output register).
// -----------------------------------------------------------------------------
module frame_buffer_ram #(
    parameter unsigned ADDR_WIDTH = 12  // Port 0 word address width; port 1 has one bit less
) (
    // -------------------------------------------------------------------------
    // Clock & Reset (shared by all ports)
    // -------------------------------------------------------------------------
    input wire clk,
    input wire rst_n,

    // WRITE PORT 0 (BRAM_W0)
    input wire                  w0_en,
    input wire [ADDR_WIDTH-1:0] w0_addr,
    input wire [          31:0] w0_din,

    // WRITE PORT 1 (BRAM_W1)
    input wire                  w1_en,
    input wire [ADDR_WIDTH-2:0] w1_addr,
    input wire [          63:0] w1_din,

    // READ PORT 0 (BRAM_R0)
    input  wire                  r0_en,
    input  wire [ADDR_WIDTH-1:0] r0_addr,
    output wire [          31:0] r0_dout,

    // READ PORT 1 (BRAM_R1)
    input  wire                  r1_en,
    input  wire [ADDR_WIDTH-2:0] r1_addr,
    output wire [          63:0] r1_dout
);

  localparam unsigned BankAw = ADDR_WIDTH - 1;
  localparam unsigned BankDepth = 1 << BankAw;

  // -------------------------------------------------------------------------
  // 1. Port Select + Input Register Stage
  // -------------------------------------------------------------------------
  // The port selects sit in front of the input registers, so the BRAM pins are
  // driven straight from flip-flops. W0 presents its word to both halves and
  // writes only the one picked by its address LSB; W1 writes both halves.
  reg [       1:0] ram_wea;
  reg [BankAw-1:0] ram_addra;
  reg [      63:0] ram_dia;

  reg              ram_enb;
  reg [BankAw-1:0] ram_addrb;
  reg              r0_lsb;  // r0_addr[0], for R0's half select

  always @(posedge clk) begin
    if (!rst_n) begin
      ram_wea <= 2'b00;
      ram_enb <= 1'b0;
    end else begin
      ram_wea <= w0_en ? (w0_addr[0] ? 2'b10 : 2'b01) : {2{w1_en}};
      ram_enb <= r0_en | r1_en;
    end
  end

  always @(posedge clk) begin
    ram_addra <= w0_en ? w0_addr[ADDR_WIDTH-1:1] : w1_addr;
    ram_dia   <= w0_en ? {2{w0_din}} : w1_din;
    ram_addrb <= r0_en ? r0_addr[ADDR_WIDTH-1:1] : r1_addr;
    r0_lsb    <= r0_addr[0];
  end

  // -------------------------------------------------------------------------
  // 2. BRAM Storage & Output Stages
  // -------------------------------------------------------------------------
  (* ram_style = "block", cascade_height = 1 *) reg [63:0] mem[BankDepth];

  reg [63:0] ram_core_data;
  reg [63:0] bram_dout_reg;

  // Synchronous write process, one write enable per 32-bit half
  always @(posedge clk) begin
    if (ram_wea[0]) mem[ram_addra][31:0] <= ram_dia[31:0];
    if (ram_wea[1]) mem[ram_addra][63:32] <= ram_dia[63:32];
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

  // R0's half select, registered with the same enables as the array read and
  // DO_REG so it always matches bram_dout_reg.
  reg r0_sel_core, r0_sel_dout;
  always @(posedge clk) begin
    if (ram_enb) r0_sel_core <= r0_lsb;
    if (ram_enb_d1) r0_sel_dout <= r0_sel_core;
  end

  wire [31:0] r0_word = r0_sel_dout ? bram_dout_reg[63:32] : bram_dout_reg[31:0];

  // -------------------------------------------------------------------------
  // 3. Per-Port Output Registers
  // -------------------------------------------------------------------------
  // One fabric register per port after DO_REG. Each loads only on its own
  // port's reads, so it holds that port's last read data.

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

  reg [31:0] r0_dout_reg;
  reg [63:0] r1_dout_reg;
  always @(posedge clk) begin
    if (rd_valid_0[2]) r0_dout_reg <= r0_word;
    if (rd_valid_1[2]) r1_dout_reg <= bram_dout_reg;
  end

  assign r0_dout = r0_dout_reg;
  assign r1_dout = r1_dout_reg;

endmodule
