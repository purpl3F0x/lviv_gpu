`timescale 1ns / 1ns

import gpu_types_pkg::*;

module tb_raster_core;

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
  logic [6:0] out_minX_local;
  logic [6:0] out_minY_local;
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

  // Helper function to convert real numbers (floats) to 32-bit representation
  function automatic logic [31:0] float(shortreal val);
    return $shortrealtobits(val);
  endfunction

  // Send a vertex to the DUT on the falling edge of clock to avoid race conditions
  task automatic send_vertex(input logic [31:0] x, input logic [31:0] y);
    do begin
      @(negedge clk);
    end while (!ready_out);
    vertex_in = '0;
    vertex_in.x = x;
    vertex_in.y = y;
    valid_in = 1'b1;
    @(negedge clk);
    valid_in = 1'b0;
  endtask

  // Watchdog timeout to prevent infinite simulation hangs
  initial begin
    #100000; // 100us timeout
    $display("[TB] ERROR: Simulation timeout!");
    $fflush();
    $finish;
  end

  // Monitor block
  always @(posedge clk) begin
    $display("[MON] time=%0d ns, ready_out=%b, valid_out=%b, state=%s, cycle_cnt=%0d", 
             $time, ready_out, valid_out, dut.state.name(), dut.cycle_cnt);
    $fflush();
  end

  initial begin
    // Initialize signals
    clk = 0;
    rst_n = 0;
    vertex_in = '0;
    tile_x_id = '0;
    tile_y_id = '0;
    valid_in = 0;
    ready_in = 0; // Downstream consumer not ready initially

    // Reset sequence
    #100;
    rst_n = 1;
    #20;

    // Setup Tile ID (e.g. Tile x=1, y=1 -> p_min x=128.0, y=128.0)
    tile_x_id = 1;
    tile_y_id = 1;

    // Send Triangle 1
    $display("[TB] Sending Triangle 1 Vertex 0 (100.0, 100.0)...");
    $fflush();
    send_vertex(float(100.0), float(100.0));

    $display("[TB] Sending Triangle 1 Vertex 1 (200.0, 100.0)...");
    $fflush();
    send_vertex(float(200.0), float(100.0));

    $display("[TB] Sending Triangle 1 Vertex 2 (150.0, 200.0)...");
    $fflush();
    send_vertex(float(150.0), float(200.0));

    $display("[TB] Triangle 1 sent. Waiting for it to buffer at the output...");
    $fflush();

    // Wait for output to become valid (Triangle 1 output buffered)
    while (!valid_out) begin
      @(negedge clk);
    end
    $display("[TB] Triangle 1 outputs buffered! valid_out=%b", valid_out);
    $display("[TB] out_e0_00 (Triangle 1) = %h (%f)", out_e0_00,  $bitstoshortreal(out_e0_00));
    $fflush();

    // Verify that ready_out is 0 while stalling in ST_STALL
    @(negedge clk);
    $display("[TB] Checking stall state: state=%s, valid_out=%b, ready_out=%b", 
             dut.state.name(), valid_out, ready_out);
    $fflush();

    if (dut.state == dut.ST_STALL && valid_out == 1'b1 && ready_out == 1'b0) begin
      $display("[TB] SUCCESS: Pipeline entered ST_STALL as expected!");
    end else begin
      $display("[TB] ERROR: Pipeline did not enter ST_STALL correctly!");
    end
    $fflush();

    // Now consume Triangle 1 data by asserting ready_in
    $display("[TB] Asserting ready_in to consume Triangle 1 data...");
    $fflush();
    ready_in = 1;
    @(negedge clk);
    ready_in = 0;
    
    // Check that we returned to ST_READ_V0 and valid_out went low
    @(negedge clk);
    $display("[TB] After consumption: state=%s, valid_out=%b, ready_out=%b", 
             dut.state.name(), valid_out, ready_out);
    $fflush();
    if (dut.state == dut.ST_READ_V0 && valid_out == 1'b0 && ready_out == 1'b1) begin
      $display("[TB] SUCCESS: Pipeline returned to ST_READ_V0 after consumption!");
    end else begin
      $display("[TB] ERROR: Pipeline did not return to ST_READ_V0 correctly!");
    end
    $fflush();

    // Send Triangle 2
    $display("[TB] Sending Triangle 2 Vertex 0 (300.0, 300.0)...");
    $fflush();
    send_vertex(float(300.0), float(300.0));

    $display("[TB] Sending Triangle 2 Vertex 1 (400.0, 300.0)...");
    $fflush();
    send_vertex(float(400.0), float(300.0));

    $display("[TB] Sending Triangle 2 Vertex 2 (350.0, 400.0)...");
    $fflush();
    send_vertex(float(350.0), float(400.0));

    $display("[TB] Triangle 2 sent. Waiting for it to finish...");
    $fflush();

    // Wait for output to become valid (Triangle 2 output buffered)
    while (!valid_out) begin
      @(negedge clk);
    end
    $display("[TB] Triangle 2 outputs buffered! valid_out=%b", valid_out);
    $display("[TB] out_e0_00 (Triangle 2) = %h (%f)", out_e0_00,  $bitstoshortreal(out_e0_00));
    $fflush();

    // Consume Triangle 2
    $display("[TB] Asserting ready_in to consume Triangle 2 data...");
    $fflush();
    ready_in = 1;
    @(negedge clk);
    ready_in = 0;

    repeat (5) @(negedge clk);
    $finish;
  end

endmodule
