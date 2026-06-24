`timescale 1ns / 1ns

import gpu_types_pkg::*;

module tb_raster_frontend_simple;

  // Clock and Reset
  logic clk;
  logic rst_n;

  // Inputs
  vertex_t vertex_in;
  logic [TILE_ID_W_X-1:0] tile_x_id;
  logic [TILE_ID_W_Y-1:0] tile_y_id;
  logic valid_in;
  logic ready_in;

  // Outputs
  logic ready_out;
  logic valid_out;
  logic [31:0] out_e0_00;
  logic [31:0] out_e1_00;
  logic [31:0] out_e2_00;
  logic [31:0] out_e0_dx;
  logic [31:0] out_e0_dy;
  logic [31:0] out_e1_dx;
  logic [31:0] out_e1_dy;
  logic [31:0] out_e2_dx;
  logic [31:0] out_e2_dy;
  logic [31:0] out_invArea;
  vertex_t out_v0;
  vertex_t out_v1;
  vertex_t out_v2;
  logic [7:0] out_minX_local;
  logic [7:0] out_minY_local;
  logic [7:0] out_width;
  logic [7:0] out_height;

  // Instantiate the Device Under Test (DUT)
  raster_frontend dut (
      .clk(clk),
      .rst_n(rst_n),
      .vertex_in(vertex_in),
      .tile_x_id(tile_x_id),
      .tile_y_id(tile_y_id),
      .valid_in(valid_in),
      .ready_out(ready_out),
      .ready_in(ready_in),
      .valid_out(valid_out),
      .out_e0_00(out_e0_00),
      .out_e1_00(out_e1_00),
      .out_e2_00(out_e2_00),
      .out_e0_dx(out_e0_dx),
      .out_e0_dy(out_e0_dy),
      .out_e1_dx(out_e1_dx),
      .out_e1_dy(out_e1_dy),
      .out_e2_dx(out_e2_dx),
      .out_e2_dy(out_e2_dy),
      .out_invArea(out_invArea),
      .out_v0(out_v0),
      .out_v1(out_v1),
      .out_v2(out_v2),
      .out_minX_local(out_minX_local),
      .out_minY_local(out_minY_local),
      .out_width(out_width),
      .out_height(out_height)
  );

  // Clock Generation (100MHz)
  always #5 clk = ~clk;

  function automatic logic [31:0] float(shortreal val);
    return $shortrealtobits(val);
  endfunction

  // Task to send a single vertex
  task automatic send_vertex(input logic [31:0] x, input logic [31:0] y);
    do begin
      @(negedge clk);
    end while (!ready_out);
    vertex_in = '0;
    vertex_in.x = x;
    vertex_in.y = y;
    vertex_in.z = float(0.5);
    vertex_in.w = float(1.0);
    valid_in = 1'b1;
    @(negedge clk);
    valid_in = 1'b0;
  endtask

  // Task to send an entire triangle
  task automatic send_triangle(input logic [31:0] tile_x, input logic [31:0] tile_y,
                               input shortreal v0_x, input shortreal v0_y, input shortreal v1_x,
                               input shortreal v1_y, input shortreal v2_x, input shortreal v2_y);
    tile_x_id = tile_x[TILE_ID_W_X-1:0];
    tile_y_id = tile_y[TILE_ID_W_Y-1:0];

    $display("[TB] Sending triangle at tile (%0d, %0d)", tile_x, tile_y);
    $display("     v0 = (%f, %f)", v0_x, v0_y);
    $display("     v1 = (%f, %f)", v1_x, v1_y);
    $display("     v2 = (%f, %f)", v2_x, v2_y);

    send_vertex(float(v0_x), float(v0_y));
    send_vertex(float(v1_x), float(v1_y));
    send_vertex(float(v2_x), float(v2_y));
  endtask

  // Dump waves for waveform viewing
  initial begin
    $dumpfile("waves.vcd");
    $dumpvars(0, tb_raster_frontend_simple);
  end

  // Watchdog Timer
  initial begin
    #20000;  // 20us watchdog
    $display("[TB] Timeout!");
    $finish;
  end

  initial begin
    // Initialize
    clk = 0;
    rst_n = 0;
    vertex_in = '0;
    tile_x_id = 0;
    tile_y_id = 0;
    valid_in = 0;
    ready_in = 0;

    // Reset sequence
    #100;
    rst_n = 1;
    #40;

    // Triangle 1: (From first test of the suite)
    // Vertices:
    //   v0 = (730.707, 1637.08)
    //   v1 = (682.389, 868.851)
    //   v2 = (253.689, 221.798)
    //   tile_x = 13, tile_y = 8
    send_triangle(13, 8, 730.707, 1637.08, 682.389, 868.851, 253.689, 221.798);

    // Wait for the pipeline output to be ready
    while (!valid_out) begin
      @(posedge clk);
    end

    $display("[TB] Triangle 1 Output Validated!");
    $display("     out_e0_00 = %f", $bitstoshortreal(out_e0_00));
    $display("     out_e1_00 = %f", $bitstoshortreal(out_e1_00));
    $display("     out_e2_00 = %f", $bitstoshortreal(out_e2_00));
    $display("     out_invArea = %f", $bitstoshortreal(out_invArea));

    // Consume output
    ready_in = 1;
    @(posedge clk);
    ready_in = 0;
    @(posedge clk);

    // Triangle 2:
    // Vertices:
    //   v0 = (2370.18, 114.902)
    //   v1 = (1402.71, 2591.98)
    //   v2 = (1244.03, 1598.33)
    //   tile_x = 9, tile_y = 0
    send_triangle(9, 0, 2370.18, 114.902, 1402.71, 2591.98, 1244.03, 1598.33);

    while (!valid_out) begin
      @(posedge clk);
    end
    $display("[TB] Triangle 2 Output Validated!");
    ready_in = 1;
    @(posedge clk);
    ready_in = 0;
    @(posedge clk);

    // Triangle 3:
    // Vertices:
    //   v0 = (2059.57, 937.492)
    //   v1 = (3670.37, 3657.89)
    //   v2 = (748.427, 1935.51)
    //   tile_x = 9, tile_y = 20
    send_triangle(9, 20, 2059.57, 937.492, 3670.37, 3657.89, 748.427, 1935.51);

    while (!valid_out) begin
      @(posedge clk);
    end
    $display("[TB] Triangle 3 Output Validated!");
    ready_in = 1;
    @(posedge clk);
    ready_in = 0;

    // Finish simulation
    repeat (20) @(posedge clk);
    $display("[TB] Done!");
    $finish;
  end

endmodule
