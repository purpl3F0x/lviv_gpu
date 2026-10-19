`timescale 1ns / 1ps

import gpu_types_pkg::*;

module tb_raster_frontend_smoke;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic [4:0] s_apb_PADDR = '0;
  logic [0:0] s_apb_PSEL = '0;
  logic s_apb_PENABLE = 1'b0;
  logic s_apb_PREADY;
  logic s_apb_PWRITE = 1'b0;
  logic [31:0] s_apb_PWDATA = '0;
  logic [31:0] s_apb_PRDATA;
  logic s_apb_PSLVERROR;
  logic valid_in = 1'b0;
  logic ready_out;
  logic valid_out;
  logic ready_in = 1'b1;
  logic core_empty;
  frontend_data_in_t in_data = '0;
  orchestrator_data_in_t out_data;

  raster_frontend dut (
      .clk(clk),
      .rst_n(rst_n),
      .apb_clk(clk),
      .apb_rst_n(rst_n),
      .s_apb_PADDR(s_apb_PADDR),
      .s_apb_PSEL(s_apb_PSEL),
      .s_apb_PENABLE(s_apb_PENABLE),
      .s_apb_PREADY(s_apb_PREADY),
      .s_apb_PWRITE(s_apb_PWRITE),
      .s_apb_PWDATA(s_apb_PWDATA),
      .s_apb_PRDATA(s_apb_PRDATA),
      .s_apb_PSLVERROR(s_apb_PSLVERROR),
      .valid_in(valid_in),
      .ready_out(ready_out),
      .in_data(in_data),
      .ready_in(ready_in),
      .valid_out(valid_out),
      .orchestrator_empty(1'b1),
      .core_empty(core_empty),
      .out_data(out_data)
  );

  always #5 clk = ~clk;

  task automatic apb_write(input logic [4:0] address, input logic [31:0] data);
    begin
      @(negedge clk);
      s_apb_PADDR = address;
      s_apb_PSEL = 1'b1;
      s_apb_PWRITE = 1'b1;
      s_apb_PWDATA = data;
      @(negedge clk);
      s_apb_PENABLE = 1'b1;
      @(negedge clk);
      s_apb_PSEL = 1'b0;
      s_apb_PENABLE = 1'b0;
      s_apb_PWRITE = 1'b0;
    end
  endtask

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
    apb_write(5'h04, 32'd3);
    apb_write(5'h08, 32'd1);
    repeat (8) @(posedge clk);
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
