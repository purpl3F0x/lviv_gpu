// Simple parameterized delay pipeline
// Copyright (c) 2026 Stavros Avramidis

`timescale 1ns / 1ns

module delay_pipe #(
    parameter int WIDTH  = 32,
    parameter int STAGES = 1
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             clken,
    input  logic [WIDTH-1:0] data_in,
    output logic [WIDTH-1:0] data_out
);

  if (STAGES == 0) begin : gen_zero_delay
    assign data_out = data_in;
  end else begin : gen_delay
    logic [WIDTH-1:0] pipe[STAGES];

    always_ff @(posedge clk) begin
      if (clken) begin
        pipe[0] <= data_in;
        for (int i = 1; i < STAGES; i++) begin
          pipe[i] <= pipe[i-1];
        end
      end
    end

    assign data_out = pipe[STAGES-1];
  end

endmodule
