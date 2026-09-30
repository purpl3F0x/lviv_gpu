module z_buffer_ram #(
    parameter int          ADDR_WIDTH         = 12,
    parameter int          PIPELINE_REGISTERS = 2,
    parameter logic [31:0] RESET_Z_VALUE      = 32'h3F80_0000
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

  localparam int DEPTH = 1 << ADDR_WIDTH;

  // =========================================================================
  // Reset / Scrubbing Logic
  // =========================================================================
  typedef enum logic [1:0] {
    ZBUF_SCRUB,
    ZBUF_DRAIN,
    ZBUF_READY
  } zbuf_state_t;

  zbuf_state_t                  zbuf_state;
  logic        [ADDR_WIDTH-1:0] scrub_addr;
  logic                         ram_wr_en;
  logic        [ADDR_WIDTH-1:0] ram_wr_addr;
  logic        [          31:0] ram_din;

  // While scrubbing, clear all memory locations to RESET_Z_VALUE.
  assign ready = (zbuf_state == ZBUF_READY);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      ram_wr_en   <= 1'b0;
      ram_wr_addr <= '0;
      ram_din     <= '0;
    end else begin
      ram_wr_en   <= (zbuf_state == ZBUF_SCRUB) || (wr_en && ready);
      ram_wr_addr <= (zbuf_state == ZBUF_SCRUB) ? scrub_addr : wr_addr;
      ram_din     <= (zbuf_state == ZBUF_SCRUB) ? RESET_Z_VALUE : din;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      zbuf_state <= ZBUF_SCRUB;
      scrub_addr <= '0;
    end else begin
      case (zbuf_state)
        ZBUF_SCRUB: begin
          if (scrub_addr == ADDR_WIDTH'(DEPTH - 1)) begin
            zbuf_state <= ZBUF_DRAIN;
          end else begin
            scrub_addr <= scrub_addr + 1'b1;
          end
        end
        ZBUF_DRAIN: begin
          zbuf_state <= ZBUF_READY;
        end
        ZBUF_READY: begin
          // Stay ready until reset.
        end
        default: begin
        end
      endcase
    end
  end

  // =========================================================================
  // Block RAM Storage
  // =========================================================================
  (* ram_style = "block", cascade_height = 1  *)
  logic [31:0] mem[DEPTH];
  logic [31:0] ram_dout[PIPELINE_REGISTERS + 1];


  always_ff @(posedge clk) begin
    if (ram_wr_en) begin
      mem[ram_wr_addr] <= ram_din;
    end
  end

  always_ff @(posedge clk) begin
    if (rd_en) begin

      ram_dout[0] <= mem[rd_addr];

      for (int i = 0; i < PIPELINE_REGISTERS; i++) begin
        ram_dout[i+1] <= ram_dout[i];
      end

    end
  end

  assign dout = ram_dout[PIPELINE_REGISTERS];

endmodule
