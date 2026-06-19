// Tile RAM (Dual-Port RAM with Asymmetric Widths)
// Copyright (c) 2026 Stavros Avramidis
//
// Dual-port RAM with asymmetric port widths for tiled pixel and z-buffer storage.
// Total capacity is (TILE_SIZE_X * TILE_SIZE_Y) 32-bit words.
// Port A data width is determined by NUM_THREADS (32 * NUM_THREADS).
// Port B data width is determined by AXI_WIDTH (typically 128 bits).

`timescale 1ns / 1ns

module tile_ram #(
    parameter int TILE_SIZE_X = gpu_types_pkg::TILE_SIZE_X,
    parameter int TILE_SIZE_Y = gpu_types_pkg::TILE_SIZE_Y,
    parameter int NUM_THREADS = 16,   // Number of threads (Port A width = 32 * NUM_THREADS)
    parameter int AXI_WIDTH   = 128, // Port B width (AXI interface size, e.g. 128)
    
    // Derived local parameters for address sizing
    localparam int DEPTH_A = (TILE_SIZE_X * TILE_SIZE_Y) / NUM_THREADS,
    localparam int DEPTH_B = (TILE_SIZE_X * TILE_SIZE_Y * 32) / AXI_WIDTH
) (
    // Port A (Compute side)
    input  logic                                clk_a,
    input  logic                                en_a,
    input  logic                                we_a,   // Write enable (no mask)
    input  logic [        $clog2(DEPTH_A)-1:0]  addr_a,
    input  logic [       (32*NUM_THREADS)-1:0]  din_a,
    output logic [       (32*NUM_THREADS)-1:0]  dout_a,

    // Port B (AXI/Memory side)
    input  logic                                clk_b,
    input  logic                                en_b,
    input  logic                                we_b,   // Write enable (no mask)
    input  logic [        $clog2(DEPTH_B)-1:0]  addr_b,
    input  logic [            AXI_WIDTH-1:0]    din_b,
    output logic [            AXI_WIDTH-1:0]    dout_b
);

  localparam int TOTAL_PIXELS = TILE_SIZE_X * TILE_SIZE_Y;
  localparam int BYTES_A = 4 * NUM_THREADS;
  localparam int BYTES_B = AXI_WIDTH / 8;
  localparam int TOTAL_BYTES = TOTAL_PIXELS * 4;
  localparam int SHIFT_A = $clog2(BYTES_A);
  localparam int SHIFT_B = $clog2(BYTES_B);

  // Elaborate check to ensure RAM configurations division is clean
  initial begin
    if (TOTAL_PIXELS % NUM_THREADS != 0) begin
      $error("Configuration Error: TOTAL_PIXELS must be divisible by NUM_THREADS.");
    end
    if ((TOTAL_PIXELS * 32) % AXI_WIDTH != 0) begin
      $error("Configuration Error: Total RAM size in bits must be divisible by AXI_WIDTH.");
    end
  end

`ifdef SYNTHESIS
  // Xilinx XPM Dual-Port RAM instantiation
  xpm_memory_tdpram #(
      .ADDR_WIDTH_A($clog2(DEPTH_A)),
      .ADDR_WIDTH_B($clog2(DEPTH_B)),
      .AUTO_SLEEP_TIME(0),
      .BYTE_WRITE_WIDTH_A(32*NUM_THREADS),
      .BYTE_WRITE_WIDTH_B(AXI_WIDTH),
      .CLOCKING_MODE("independent_clock"),
      .ECC_MODE("no_ecc"),
      .MEMORY_INIT_FILE("none"),
      .MEMORY_INIT_PARAM("0"),
      .MEMORY_OPTIMIZATION("true"),
      .MEMORY_PRIMITIVE("block"),
      .MEMORY_SIZE(TOTAL_PIXELS * 32),
      .MESSAGE_CONTROL(0),
      .READ_DATA_WIDTH_A(32*NUM_THREADS),
      .READ_DATA_WIDTH_B(AXI_WIDTH),
      .READ_LATENCY_A(1),
      .READ_LATENCY_B(1),
      .READ_RESET_VALUE_A("0"),
      .READ_RESET_VALUE_B("0"),
      .RST_MODE_A("SYNC"),
      .RST_MODE_B("SYNC"),
      .SIM_ASSERT_CHK(0),
      .USE_EMBEDDED_CONSTRAINT(0),
      .USE_MEM_INIT(0),
      .WAKEUP_TIME("disable_sleep"),
      .WRITE_DATA_WIDTH_A(32*NUM_THREADS),
      .WRITE_DATA_WIDTH_B(AXI_WIDTH),
      .WRITE_MODE_A("read_first"),
      .WRITE_MODE_B("read_first")
  ) u_xpm_memory_tdpram (
      .clka           (clk_a),
      .ena            (en_a),
      .wea            (we_a),
      .addra          (addr_a),
      .dina           (din_a),
      .douta          (dout_a),
      .clkb           (clk_b),
      .enb            (en_b),
      .web            (we_b),
      .addrb          (addr_b),
      .dinb           (din_b),
      .doutb          (dout_b),
      .rsta           (1'b0),
      .rstb           (1'b0),
      .sleep          (1'b0),
      .regcea         (1'b1),
      .regceb         (1'b1),
      .injectsbiterra (1'b0),
      .injectsbiterrb (1'b0),
      .injectdbiterra (1'b0),
      .injectdbiterrb (1'b0),
      .sbiterra       (),
      .sbiterrb       (),
      .dbiterra       (),
      .dbiterrb       ()
  );
`else
  /* verilator lint_off MULTIDRIVEN */

  // Internal flat byte-level RAM array
  (* ram_style = "block" *) logic [7:0] mem [TOTAL_BYTES];

  // Port A Read/Write Process (READ_FIRST / Read-before-Write)
  always_ff @(posedge clk_a) begin
    if (en_a) begin
      for (int i = 0; i < BYTES_A; i++) begin
        if (we_a) begin
          mem[{addr_a, i[SHIFT_A-1:0]}] <= din_a[8*i +: 8];
        end
        dout_a[8*i +: 8] <= mem[{addr_a, i[SHIFT_A-1:0]}];
      end
    end
  end

  // Port B Read/Write Process (READ_FIRST / Read-before-Write)
  always_ff @(posedge clk_b) begin
    if (en_b) begin
      for (int j = 0; j < BYTES_B; j++) begin
        if (we_b) begin
          mem[{addr_b, j[SHIFT_B-1:0]}] <= din_b[8*j +: 8];
        end
        dout_b[8*j +: 8] <= mem[{addr_b, j[SHIFT_B-1:0]}];
      end
    end
  end

  /* verilator lint_on MULTIDRIVEN */
`endif

endmodule
