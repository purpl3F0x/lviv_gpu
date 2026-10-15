`timescale 1ns / 1ps

import gpu_types_pkg::*;

module tb_raster_frontend_smoke;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic valid_in = 1'b0;
  logic ready_out;
  logic valid_out;
  logic ready_in = 1'b1;
  logic core_empty;
  frontend_data_in_t in_data = '0;
  uint12_t bin_min_x = 384;
  uint12_t bin_min_y = 128;
  uint12_t bin_max_x = 511;
  uint12_t bin_max_y = 255;
  orchestrator_data_in_t out_data;

  raster_frontend dut (
      .clk(clk),
      .rst_n(rst_n),
      .valid_in(valid_in),
      .ready_out(ready_out),
      .in_data(in_data),
      .bin_min_x(bin_min_x),
      .bin_min_y(bin_min_y),
      .bin_max_x(bin_max_x),
      .bin_max_y(bin_max_y),
      .ready_in(ready_in),
      .valid_out(valid_out),
      .core_empty(core_empty),
      .out_data(out_data)
  );

  always #5 clk = ~clk;

  initial begin
    in_data.v0.position.x = $shortrealtobits(512.715149);
    in_data.v0.position.y = $shortrealtobits(260.558655);
    in_data.v0.position.w = $shortrealtobits(1.0);
    in_data.v0.u = $shortrealtobits(-3.98812389);
    in_data.v0.v = $shortrealtobits(5.28462219);
    in_data.v1.position.x = $shortrealtobits(552.308716);
    in_data.v1.position.y = $shortrealtobits(231.386169);
    in_data.v1.position.w = $shortrealtobits(1.0);
    in_data.v1.u = $shortrealtobits(-3.69124985);
    in_data.v1.v = $shortrealtobits(5.53462219);
    in_data.v2.position.x = $shortrealtobits(505.103821);
    in_data.v2.position.y = $shortrealtobits(252.082977);
    in_data.v2.position.w = $shortrealtobits(1.0);
    in_data.v2.u = $shortrealtobits(-4.08187389);
    in_data.v2.v = $shortrealtobits(5.37837219);

    repeat (5) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    while (!ready_out) @(negedge clk);
    valid_in = 1'b1;
    do @(posedge clk); while (!ready_out);
    @(negedge clk);
    valid_in = 1'b0;

    do @(negedge clk); while (!valid_out);
    $display("frontend valid: inv_area=%h e0=%h e1=%h e2=%h bounds=(%0d,%0d)+(%0d,%0d)",
             out_data.inv_area, out_data.init_e0, out_data.init_e1, out_data.init_e2,
             out_data.minX_local, out_data.minY_local, out_data.width, out_data.height);
    $display("PASS: frontend smoke transaction accepted and returned");
    $finish;
  end

  initial begin
    #1000000;
    $fatal(1, "frontend smoke test timed out");
  end
endmodule
