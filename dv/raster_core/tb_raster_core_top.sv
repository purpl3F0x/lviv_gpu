// SystemVerilog Testbench for raster_core (Frontend + Thread Orchestrator)
// Suitable for Vivado Simulator (xsim) and Verilator
// Copyright (c) 2026 Stavros Avramidis

`timescale 1ns / 1ns

import gpu_types_pkg::*;

module tb_raster_core_top;

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
  logic [31:0] out_e0 [4];
  logic [31:0] out_e1 [4];
  logic [31:0] out_e2 [4];
  logic [31:0] out_invArea;
  vertex_t out_v0;
  vertex_t out_v1;
  vertex_t out_v2;
  logic [6:0] out_minX_local;
  logic [6:0] out_minY_local;
  logic [7:0] out_width;
  logic [7:0] out_height;

  // Derivatives
  logic [31:0] out_e0_dx;
  logic [31:0] out_e0_dy;
  logic [31:0] out_e1_dx;
  logic [31:0] out_e1_dy;
  logic [31:0] out_e2_dx;
  logic [31:0] out_e2_dy;

  // Instantiate the top-level DUT
  raster_core dut (
      .clk        (clk),
      .rst_n      (rst_n),
      .vertex_in  (vertex_in),
      .tile_x_id  (tile_x_id),
      .tile_y_id  (tile_y_id),
      .valid_in   (valid_in),
      .ready_out  (ready_out),
      .ready_in   ('{ready_in, ready_in, ready_in, ready_in}),
      .valid_out  (valid_out),
      .out_e0     (out_e0),
      .out_e1     (out_e1),
      .out_e2     (out_e2),
      .out_invArea(out_invArea),
      .out_v0     (out_v0),
      .out_v1     (out_v1),
      .out_v2     (out_v2),
      .out_minX_local(out_minX_local),
      .out_minY_local(out_minY_local),
      .out_width(out_width),
      .out_height(out_height),
      .out_e0_dx_2x(out_e0_dx),
      .out_e0_dy_2x(out_e0_dy),
      .out_e1_dx_2x(out_e1_dx),
      .out_e1_dy_2x(out_e1_dy),
      .out_e2_dx_2x(out_e2_dx),
      .out_e2_dy_2x(out_e2_dy)
  );

  // Clock generation (100MHz)
  always #5 clk = ~clk;

  // Helper function to convert float to bits
  function automatic logic [31:0] float(shortreal val);
    return $shortrealtobits(val);
  endfunction

  // Helper function to convert bits to shortreal
  function automatic shortreal bits_to_float(logic [31:0] val);
    return $bitstoshortreal(val);
  endfunction

  // Send vertex task
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

  // Watchdog timer (5ms)
  initial begin
    #5000000;
    $display("[TB] ERROR: Simulation watchdog timeout!");
    $finish;
  end

  // Monitor outputs
  int pixel_count;
  always @(posedge clk) begin
    if (valid_out && ready_in) begin
      $display("[MON] Time=%0d ns | Step %0d:", $time, pixel_count);
      for (int i = 0; i < 4; i++) begin
        $display("  Thread %0d: e0=%f, e1=%f, e2=%f", 
                 i, 
                 bits_to_float(out_e0[i]), 
                 bits_to_float(out_e1[i]), 
                 bits_to_float(out_e2[i]));
      end
      pixel_count <= pixel_count + 1;
    end
  end

  // Test stimulus
  initial begin
    pixel_count = 0;
    $display("[TB] Starting Raster Core Top Testbench...");
    clk = 0;
    rst_n = 0;
    vertex_in = '0;
    tile_x_id = 0;
    tile_y_id = 0;
    valid_in = 0;
    ready_in = 0;

    #100;
    rst_n = 1;
    #20;

    // Test Case 1: Triangle intersecting Tile (1, 1)
    // Tile bounds: x in [128.5, 256.5], y in [128.5, 256.5]
    tile_x_id = 1;
    tile_y_id = 1;

    $display("[TB] Sending Triangle 1 Vertices...");
    // v0: (100.0, 100.0)
    send_vertex(float(100.0), float(100.0));
    // v1: (200.0, 100.0)
    send_vertex(float(200.0), float(100.0));
    // v2: (150.0, 200.0)
    send_vertex(float(150.0), float(200.0));
    $display("[TB] Triangle 1 sent. Waiting for outputs...");

    // Wait and print FSM states
    for (int cycle = 0; cycle < 100; cycle++) begin
      $display("[DEBUG] Cycle %0d | Time=%0d ns | front_state=%s, front_cycle=%0d, orch_state=%s, f_valid_out=%b, f_ready_in=%b", 
               cycle, $time, dut.u_frontend.state.name(), dut.u_frontend.cycle_cnt, dut.u_orchestrator.state.name(), dut.u_frontend.valid_out, dut.u_orchestrator.ready_out);
      @(posedge clk);
    end

    // Assert ready_in to start consuming traversed pixels
    $display("[TB] Consuming pixels...");
    ready_in = 1;

    // Let simulation run for traversal
    while (dut.u_orchestrator.state == dut.u_orchestrator.ST_TRAVERSE || 
           dut.u_frontend.state == dut.u_frontend.ST_CALC || 
           dut.u_frontend.state == dut.u_frontend.ST_STALL) begin
      $display("[TB_LOOP] Time=%0d ns | orch_state=%s, front_state=%s",
               $time, dut.u_orchestrator.state.name(), dut.u_frontend.state.name());
      @(posedge clk);
      
      // Inject random stalling (30% chance) to verify thread blocking
      if ($urandom_range(0, 9) < 3) begin
        ready_in = 0;
        $display("[TB] Downstream Stalled at Time=%0d ns", $time);
        repeat ($urandom_range(1, 4)) @(posedge clk);
        ready_in = 1;
        $display("[TB] Downstream Stall Released at Time=%0d ns", $time);
      end
    end

    $display("[TB] Traversal finished. Total blocks consumed = %0d", pixel_count);
    ready_in = 0;

    for (int cycle = 0; cycle < 100; cycle++) begin
      $display("[DEBUG] Cycle %0d | Time=%0d ns | front_state=%s, front_cycle=%0d, orch_state=%s, f_valid_out=%b, f_ready_in=%b", 
               cycle, $time, dut.u_frontend.state.name(), dut.u_frontend.cycle_cnt, dut.u_orchestrator.state.name(), dut.u_frontend.valid_out, dut.u_orchestrator.ready_out);
      @(posedge clk);
    end
    $display("[TB] Simulation successful!");
    $finish;
  end

endmodule
