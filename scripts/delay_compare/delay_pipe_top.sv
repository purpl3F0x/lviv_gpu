// Synthesis top for delay_pipe in the delay line comparison: reset tied off, as raster_frontend uses
// it, so Vivado can infer SRLs.

`timescale 1ns / 1ns

module delay_pipe_top #(
    parameter int WIDTH  = 16,
    parameter int STAGES = 16
) (
    input  logic             clk,
    input  logic             clken,
    input  logic [WIDTH-1:0] data_in,
    output logic [WIDTH-1:0] data_out
);

  delay_pipe #(
      .WIDTH (WIDTH),
      .STAGES(STAGES)
  ) u_delay (
      .clk(clk),
      .rst_n(1'b1),
      .clken(clken),
      .data_in(data_in),
      .data_out(data_out)
  );

endmodule
