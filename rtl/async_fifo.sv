//  modified from: https://github.com/nelsoncsc/verilaxi/blob/main/rtl/common/snix_async_fifo.sv


`timescale 1ns / 1ns

module async_fifo #(
    parameter int DATA_WIDTH = 8,
    parameter int FIFO_DEPTH = 4
) (
    input  logic                        clk,
    input  logic                        rst_n,
    input  logic                        wr_en,
    input  logic [      DATA_WIDTH-1:0] data_i,
    output logic                        fifo_full,
    output logic                        fifo_almost_full,
    output logic [$clog2(FIFO_DEPTH):0] fill_cnt,

    input  logic                        rd_clk,
    input  logic                        rd_rst_n,
    input  logic                        rd_en,
    output logic [      DATA_WIDTH-1:0] data_o,
    output logic [$clog2(FIFO_DEPTH):0] rd_fill_cnt,
    output logic                        fifo_empty
);

  localparam int ADDR_W = $clog2(FIFO_DEPTH);
  localparam int NFF = 2;

  logic [ADDR_W:0] rd_addr, next_rd_addr;
  logic [ADDR_W:0] wr_addr, next_wr_addr;
  logic [ADDR_W:0] rgray, wgray;
  logic [ADDR_W:0] rd_wbin, wr_rbin;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) logic [ADDR_W:0] rd_wgray, wr_rgray;

  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  logic [(ADDR_W+1)*(NFF-1)-1:0] rgray_cross, wgray_cross;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  logic [1:0] write_reset_pipe, read_reset_pipe;
  logic write_reset_n, read_reset_n, write_fire;

  (* ram_style = "distributed" *) logic [DATA_WIDTH-1:0] mem[FIFO_DEPTH];

  logic [DATA_WIDTH-1:0] lcl_rd_data;
  logic lcl_read, lcl_rd_empty;

  initial begin
    if (FIFO_DEPTH < 4 || (FIFO_DEPTH & (FIFO_DEPTH - 1)) != 0)
      $fatal(1, "fifo requires a power-of-two depth of at least 4");
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) write_reset_pipe <= '0;
    else write_reset_pipe <= {write_reset_pipe[0], 1'b1};
  end

  always_ff @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) read_reset_pipe <= '0;
    else read_reset_pipe <= {read_reset_pipe[0], 1'b1};
  end

  assign write_reset_n = write_reset_pipe[1];
  assign read_reset_n = read_reset_pipe[1];
  assign write_fire = wr_en && !fifo_full;
  assign fill_cnt = wr_addr - wr_rbin;
  assign next_wr_addr = wr_addr + 1'b1;

  always_ff @(posedge clk or negedge write_reset_n)
    if (!write_reset_n) begin
      wr_addr <= (ADDR_W + 1)'(0);
      wgray   <= (ADDR_W + 1)'(0);
    end else if (write_fire) begin
      wr_addr <= next_wr_addr;
      wgray   <= next_wr_addr ^ (next_wr_addr >> 1);
    end

  always_ff @(posedge clk) if (write_fire) mem[wr_addr[ADDR_W-1:0]] <= data_i;

  assign next_rd_addr = rd_addr + 1'b1;
  assign lcl_rd_data  = mem[rd_addr[ADDR_W-1:0]];

  always_ff @(posedge clk or negedge write_reset_n)
    if (!write_reset_n) begin
      wr_rgray    <= (ADDR_W + 1)'(0);
      rgray_cross <= (ADDR_W + 1)'(0);
    end else begin
      {wr_rgray, rgray_cross} <= {rgray_cross, rgray};
    end

  always_ff @(posedge rd_clk or negedge read_reset_n)
    if (!read_reset_n) begin
      rd_wgray    <= (ADDR_W + 1)'(0);
      wgray_cross <= (ADDR_W + 1)'(0);
      rd_fill_cnt  <= (ADDR_W + 1)'(0);
    end else begin
      {rd_wgray, wgray_cross} <= {wgray_cross, wgray};
      rd_fill_cnt <= (rd_wbin - rd_addr) & ((1 << (ADDR_W + 1)) - 1);
    end

  always_comb begin
    rd_wbin[ADDR_W] = rd_wgray[ADDR_W];
    for (int i = ADDR_W - 1; i >= 0; i--) begin
      rd_wbin[i] = rd_wbin[i+1] ^ rd_wgray[i];
    end
  end

  assign fifo_full = !write_reset_n || wr_rgray == {~wgray[ADDR_W:ADDR_W-1], wgray[ADDR_W-2:0]};

  always_comb begin
    wr_rbin[ADDR_W] = wr_rgray[ADDR_W];
    for (int i = ADDR_W - 1; i >= 0; i--) begin
      wr_rbin[i] = wr_rbin[i+1] ^ wr_rgray[i];
    end
  end

  always_ff @(posedge clk or negedge write_reset_n) begin
    if (!write_reset_n) fifo_almost_full <= 1'b1;
    else
      fifo_almost_full <= (wr_addr + (ADDR_W + 1)'(write_fire) - wr_rbin)
          >= (ADDR_W + 1)'(FIFO_DEPTH - 1);
  end

  assign lcl_rd_empty = rd_wgray == rgray;
  assign lcl_read = fifo_empty || rd_en;

  // Single block: all rclk state sampled simultaneously so Verilator reads
  // lcl_rd_empty (depends on rgray) before any NBA update of rgray is applied.
  always_ff @(posedge rd_clk or negedge read_reset_n)
    if (!read_reset_n) begin
      rd_addr <= (ADDR_W + 1)'(0);
      rgray   <= (ADDR_W + 1)'(0);
      fifo_empty  <= 1'b1;
    end else if (lcl_read) begin
      if (!lcl_rd_empty) begin
        rd_addr <= next_rd_addr;
        rgray   <= next_rd_addr ^ (next_rd_addr >> 1);
      end
      fifo_empty <= lcl_rd_empty;
      data_o  <= lcl_rd_data;
    end

endmodule : async_fifo
