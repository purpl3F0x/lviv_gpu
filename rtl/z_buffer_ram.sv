module z_buffer_ram #(
    parameter int ADDR_WIDTH = 12,
    parameter bit USE_XPM = 1'b1
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

  localparam int DEPTH = 2 ** ADDR_WIDTH;
`ifdef XILINX
  localparam bit UseXpmImpl = 1'b1;
`else
  localparam bit UseXpmImpl = USE_XPM;
`endif

  logic [2*ADDR_WIDTH-1:0] rst_counter;
  logic                    ram_wr_en;
  logic [  ADDR_WIDTH-1:0] ram_wr_addr;
  logic [            31:0] ram_din;

  // If TB does not pulse reset, start in ready state without scrub.
  initial begin
    rst_counter = DEPTH;
    ready = 1'b1;
  end

  assign ram_wr_en   = (!ready) || (wr_en && rst_n);
  assign ram_wr_addr = (!ready) ? rst_counter[ADDR_WIDTH-1:0] : wr_addr;
  assign ram_din     = (!ready) ? 32'hFFFFFFFF : din;

  // reset logic
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rst_counter <= 0;
      ready <= 0;
    end else if (rst_counter != DEPTH) begin
      rst_counter <= rst_counter + 1;
      ready <= 0;
    end else begin
      ready <= 1;
    end
  end

  generate
    if (UseXpmImpl) begin : gen_xpm_ram
      logic [31:0] xpm_dout;
      logic        bypass_d;
      logic [31:0] bypass_data_d;

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
          .enb           (1'b1),
          .regceb        (1'b1),
          .addrb         (rd_addr),
          .doutb         (xpm_dout),
          .sbiterrb      (),
          .dbiterrb      ()
      );

      always_ff @(posedge clk) begin
        if (!rst_n) begin
          bypass_d      <= 1'b0;
          bypass_data_d <= 32'b0;
        end else begin
          bypass_d      <= wr_en && (rd_addr == wr_addr);
          bypass_data_d <= din;
        end
      end

      always_comb begin
        if (bypass_d) dout = bypass_data_d;
        else dout = xpm_dout;
      end
    end else begin : gen_behav_ram
      (* ram_style = "block" *)
      logic [31:0] mem[DEPTH];

      always_ff @(posedge clk) begin
        if (ram_wr_en) begin
          mem[ram_wr_addr] <= ram_din;
        end
      end

      always_comb begin
        if ((rd_addr == wr_addr) && wr_en) dout = din;
        else dout = mem[rd_addr];
      end
    end
  endgenerate
endmodule
