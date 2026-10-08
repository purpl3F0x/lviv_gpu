
//  modified from: https://github.com/nelsoncsc/verilaxi/blob/main/rtl/common/snix_sync_fifo.sv
//  Synchronous FIFO with a registered output and no empty bypass.

`timescale 1ns / 1ns

module sync_fifo #(
    parameter int DATA_WIDTH = 32,
    parameter int FIFO_DEPTH = 16
) (
    input logic clk,
    input logic rst_n,

    input logic [DATA_WIDTH-1:0] data_i,
    input logic                  wr_en,

    input  logic                  rd_en,
    output logic [DATA_WIDTH-1:0] data_o,

    output logic [$clog2(FIFO_DEPTH):0] fill_cnt,
    output logic                        fifo_full,
    output logic                        fifo_almost_full,
    output logic                        fifo_empty
);

  localparam int AWIDTH = $clog2(FIFO_DEPTH);

  (* ram_style = "distributed",  ramstyle = "no_rw_check"*) logic [DATA_WIDTH-1:0] mem[FIFO_DEPTH];


  logic [AWIDTH:0] wptr, rptr;
  logic output_valid;
  logic do_wr, do_rd, refill;

  assign do_rd = rd_en & output_valid;
  assign do_wr = wr_en & ~fifo_full;
  assign refill = (!output_valid || do_rd) && (fill_cnt > (output_valid ? 1 : 0));

  always_ff @(posedge clk) begin
    if (!rst_n) wptr <= '0;
    else if (do_wr) wptr <= wptr + 1'b1;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) rptr <= '0;
    else if (refill) rptr <= rptr + 1'b1;
  end

  always_ff @(posedge clk) if (do_wr) mem[wptr[AWIDTH-1:0]] <= data_i;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      output_valid <= 1'b0;
    end else if (refill) begin
      data_o <= mem[rptr[AWIDTH-1:0]];
      output_valid <= 1'b1;
    end else if (do_rd) begin
      output_valid <= 1'b0;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      fill_cnt   <= '0;
    end else begin
      case ({
        do_wr, do_rd
      })
        2'b10: begin
          fill_cnt <= fill_cnt + 1'b1;
        end
        2'b01: begin
          fill_cnt <= fill_cnt - 1'b1;
        end
        default: ;
      endcase
    end
  end

  assign fifo_full = fill_cnt[AWIDTH];
  assign fifo_almost_full = fill_cnt >= (AWIDTH + 1)'(FIFO_DEPTH - 1);

  assign fifo_empty = !output_valid;

endmodule
