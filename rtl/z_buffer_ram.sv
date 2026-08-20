module z_buffer_ram #(
    parameter int ADDR_WIDTH = 12,
  parameter bit USE_XPM    = 1'b0,
  parameter logic [31:0] RESET_Z_VALUE = 32'h3F80_0000
) (
    input  logic clk,
    input  logic rst_n,
    output logic ready,

    // Port A: Write port
    input logic                  wr_en,
    input logic [ADDR_WIDTH-1:0] wr_addr,
    input logic [          31:0] din,

    // Port B: Read port
    input  logic                  rd_en,
    input  logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [          31:0] dout
);

  localparam int ForwardDepth = 3;

  localparam int DEPTH = 2 ** ADDR_WIDTH;

`ifdef XILINX
  localparam bit UseXpmImpl = 1'b1;
`else
  localparam bit UseXpmImpl = USE_XPM;
`endif

  // =========================================================================
  // 1. Reset / Scrubbing Logic
  // =========================================================================
  typedef enum logic [0:0] {
    ZBUF_SCRUB = 1'b0,
    ZBUF_READY = 1'b1
  } zbuf_state_t;

  zbuf_state_t            zbuf_state;
  logic [ADDR_WIDTH-1:0] scrub_addr;
  logic                  ram_wr_en;
  logic [ADDR_WIDTH-1:0] ram_wr_addr;
  logic [          31:0] ram_din;

  // While scrubbing, ignore functional writes and only clear memory to far depth.
  assign ready       = (zbuf_state == ZBUF_READY);
  assign ram_wr_en   = (zbuf_state == ZBUF_SCRUB) || (wr_en && rst_n && ready);
  assign ram_wr_addr = (zbuf_state == ZBUF_SCRUB) ? scrub_addr : wr_addr;
  assign ram_din     = (zbuf_state == ZBUF_SCRUB) ? RESET_Z_VALUE : din;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      zbuf_state <= ZBUF_SCRUB;
      scrub_addr <= '0;
    end else begin
      case (zbuf_state)
        ZBUF_SCRUB: begin
          if (scrub_addr == ADDR_WIDTH'(DEPTH - 1)) begin
            zbuf_state <= ZBUF_READY;
          end else begin
            scrub_addr <= scrub_addr + 1'b1;
          end
        end
        ZBUF_READY: begin
          // Stay ready until reset.
        end
        default: begin end
      endcase
    end
  end

  // =========================================================================
  // 2. Parameterized In-Flight Write Tracking Shift Register
  // =========================================================================
  // Registered read address aligned with 1-cycle BRAM read latency
  logic [ADDR_WIDTH-1:0] rd_addr_d1;

  // Pipeline history queues (Index 0 = current input, Index 1..N-1 = history)
  logic                  wr_en_q    [ForwardDepth];
  logic [ADDR_WIDTH-1:0] wr_addr_q  [ForwardDepth];
  logic [          31:0] wr_din_q   [ForwardDepth];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_addr_d1 <= '0;
      for (int i = 0; i < ForwardDepth; i++) begin
        wr_en_q[i]   <= 1'b0;
        wr_addr_q[i] <= '0;
        wr_din_q[i]  <= '0;
      end
    end else begin
      // Target read address being evaluated at raw BRAM output
      if (rd_en) rd_addr_d1 <= rd_addr;

      // Shift Register Stage 0: Capture active write input
      wr_en_q[0]   <= wr_en && ready;
      wr_addr_q[0] <= wr_addr;
      wr_din_q[0]  <= din;

      // Shift Register Stages 1 to ForwardDepth-1
      for (int i = 1; i < ForwardDepth; i++) begin
        wr_en_q[i]   <= wr_en_q[i-1];
        wr_addr_q[i] <= wr_addr_q[i-1];
        wr_din_q[i]  <= wr_din_q[i-1];
      end
    end
  end

  // =========================================================================
  // 3. Block RAM Implementation (Synchronous 1-Cycle Read)
  // =========================================================================
  logic [31:0] raw_bram_dout;

  generate
    if (UseXpmImpl) begin : gen_xpm_ram
      xpm_memory_sdpram #(
          .ADDR_WIDTH_A           (ADDR_WIDTH),
          .ADDR_WIDTH_B           (ADDR_WIDTH),
          .AUTO_SLEEP_TIME        (0),
          .BYTE_WRITE_WIDTH_A     (32),
          .CLOCKING_MODE          ("common_clock"),
          .ECC_MODE               ("no_ecc"),
          .MEMORY_INIT_FILE       ("none"),
          .MEMORY_INIT_PARAM      ("0"),
          .MEMORY_OPTIMIZATION    ("true"),
          .MEMORY_PRIMITIVE       ("block"),
          .MEMORY_SIZE            (DEPTH * 32),
          .MESSAGE_CONTROL        (0),
          .READ_DATA_WIDTH_B      (32),
          .READ_LATENCY_B         (1),
          .READ_RESET_VALUE_B     ("0"),
          .RST_MODE_A             ("SYNC"),
          .RST_MODE_B             ("SYNC"),
          .SIM_ASSERT_CHK         (0),
          .USE_EMBEDDED_CONSTRAINT(0),
          .USE_MEM_INIT           (0),
          .WAKEUP_TIME            ("disable_sleep"),
          .WRITE_DATA_WIDTH_A     (32),
          .WRITE_MODE_B           ("read_first")
      ) u_zbuf_xpm (
          .sleep         (1'b0),
          .clka          (clk),
          .ena           (ram_wr_en),
          .wea           (ram_wr_en),
          .addra         (ram_wr_addr),
          .dina          (ram_din),
          .injectsbiterra(1'b0),
          .injectdbiterra(1'b0),
          .clkb          (clk),
          .rstb          (1'b0),
          .enb           (rd_en),
          .regceb        (1'b1),
          .addrb         (rd_addr),
          .doutb         (raw_bram_dout),
          .sbiterrb      (),
          .dbiterrb      ()
      );
    end else begin : gen_behav_ram
      (* ram_style = "block" *)
      logic [31:0] mem[DEPTH];

      always_ff @(posedge clk) begin
        if (ram_wr_en) begin
          mem[ram_wr_addr] <= ram_din;
        end
      end

      // Synchronous BRAM read inference matching XPM 1-cycle latency
      always_ff @(posedge clk) begin
        if (rd_en) begin
          raw_bram_dout <= mem[rd_addr];
        end
      end
    end
  endgenerate

  // =========================================================================
  // 4. Parameterized Priority Forwarding Mux
  // =========================================================================
  // Scans from youngest (index 0) to oldest (index ForwardDepth-1)
  always_comb begin
    dout = raw_bram_dout;  // Default fallback: BRAM output

    // Loop backwards so that lower indices (youngest writes) override higher indices
    for (int i = ForwardDepth - 1; i >= 0; i--) begin
      if (wr_en_q[i] && (wr_addr_q[i] == rd_addr_d1)) begin
        dout = wr_din_q[i];
      end
    end
  end

endmodule
