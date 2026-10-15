`timescale 1ns / 1ps

import gpu_types_pkg::*;

module tb_raster_frontend_csv;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic valid_in = 1'b0;
  logic ready_out;
  logic ready_in = 1'b1;
  logic valid_out;
  logic core_empty;
  frontend_data_in_t in_data = '0;
  uint12_t bin_min_x = '0;
  uint12_t bin_min_y = '0;
  uint12_t bin_max_x = '0;
  uint12_t bin_max_y = '0;
  orchestrator_data_in_t out_data;

  integer input_file;
  integer expected_file;
  integer input_scan;
  integer expected_scan;
  integer transaction_id;
  integer expected_id;
  integer bin_min_x_value;
  integer bin_min_y_value;
  integer bin_max_x_value;
  integer bin_max_y_value;
  integer expected_width;
  integer expected_height;
  integer expected_min_x_local;
  integer expected_min_y_local;
  integer rows_checked = 0;
  string input_path;
  string expected_path;

  real v0_x, v0_y, v1_x, v1_y, v2_x, v2_y;
  real v0_u, v0_v, v1_u, v1_v, v2_u, v2_v;
  real exp_inv_area, exp_w0, exp_w1, exp_w2;
  real exp_dx0, exp_dx1, exp_dx2;
  real exp_dy0, exp_dy1, exp_dy2;
  real exp_v0_u, exp_v0_v, exp_v1_u, exp_v1_v, exp_v2_u, exp_v2_v;

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

  function automatic logic [31:0] to_fp32(input real value);
    shortreal single_value;
    begin
      single_value = value;
      to_fp32 = $shortrealtobits(single_value);
    end
  endfunction

  function automatic real fp32_to_real(input logic [31:0] value);
    shortreal single_value;
    begin
      single_value = $bitstoshortreal(value);
      fp32_to_real = single_value;
    end
  endfunction

  function automatic real fx14_10_to_real(input logic signed [23:0] value);
    fx14_10_to_real = $itor($signed(value)) / 1024.0;
  endfunction

  // $itor() takes a 32-bit integer and would truncate the 48-bit value; use an implicit real conversion instead.
  function automatic real fx28_20_to_real(input logic signed [47:0] value);
    real value_real;
    value_real = value;
    fx28_20_to_real = value_real / 1048576.0;
  endfunction

  function automatic real fx5_13_to_real(input logic signed [17:0] value);
    fx5_13_to_real = $itor($signed(value)) / 8192.0;
  endfunction

  task automatic check_close(input string field_name, input real actual, input real expected);
    real difference;
    real percentage_difference;
    begin
      const real TOLERANCE = 2.5 ;  // 1%

      // Portable abs: $abs is an iverilog extension that xsim rejects.
      difference = (actual > expected) ? (actual - expected) : (expected - actual);
      percentage_difference = (difference / (((actual + expected) < 0.0 ? -(actual + expected) : (actual + expected)) / 2)) * 100.0;
      if (percentage_difference > TOLERANCE)
        $warning(
            "row %0d %s mismatch: got %.10f expected %.10f (tol %.10f, %% diff %.10f)",
            transaction_id,
            field_name,
            actual,
            expected,
            TOLERANCE,
            percentage_difference
        );
    end
  endtask

  task automatic skip_csv_header(input integer file_handle);
    integer character_code;
    begin
      character_code = $fgetc(file_handle);
      while ((character_code != -1) && (character_code != 10)) character_code = $fgetc(file_handle);
    end
  endtask

  initial begin : run_csv
    input_path = "frontend_inputs_float.csv";
    expected_path = "frontend_expected.csv";
    if ($value$plusargs("INPUTS=%s", input_path) == 0) begin
    end
    if ($value$plusargs("EXPECTED=%s", expected_path) == 0) begin
    end

    input_file = $fopen(input_path, "r");
    expected_file = $fopen(expected_path, "r");
    if (input_file == 0) $fatal(1, "cannot open input CSV: %s", input_path);
    if (expected_file == 0) $fatal(1, "cannot open expected CSV: %s", expected_path);

    skip_csv_header(input_file);
    skip_csv_header(expected_file);

    repeat (5) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    begin : read_rows
      while (1) begin
        input_scan = $fscanf(
            input_file,
            "%d,%f,%f,%f,%f,%f,%f,%d,%d,%d,%d,%f,%f,%f,%f,%f,%f",
            transaction_id,
            v0_x,
            v0_y,
            v1_x,
            v1_y,
            v2_x,
            v2_y,
            bin_min_x_value,
            bin_min_y_value,
            bin_max_x_value,
            bin_max_y_value,
            v0_u,
            v0_v,
            v1_u,
            v1_v,
            v2_u,
            v2_v
        );
        if ((input_scan == -1) || ((input_scan == 0) && $feof(input_file))) disable read_rows;
        if (input_scan != 17)
          $fatal(
              1,
              "malformed input CSV row after transaction %0d (read %0d fields)",
              rows_checked,
              input_scan
          );

        expected_scan = $fscanf(
            expected_file,
            "%d,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%d,%d,%d,%d,%f,%f,%f,%f,%f,%f",
            expected_id,
            exp_inv_area,
            exp_w0,
            exp_w1,
            exp_w2,
            exp_dx0,
            exp_dx1,
            exp_dx2,
            exp_dy0,
            exp_dy1,
            exp_dy2,
            expected_width,
            expected_height,
            expected_min_x_local,
            expected_min_y_local,
            exp_v0_u,
            exp_v0_v,
            exp_v1_u,
            exp_v1_v,
            exp_v2_u,
            exp_v2_v
        );
        if (expected_scan != 21)
          $fatal(
              1,
              "expected CSV row missing/malformed for transaction %0d (read %0d fields)",
              transaction_id,
              expected_scan
          );
        if (expected_id != transaction_id)
          $fatal(
              1, "CSV transaction mismatch: input %0d expected %0d", transaction_id, expected_id
          );

        in_data = '0;
        in_data.v0.position.x = to_fp32(v0_x);
        in_data.v0.position.y = to_fp32(v0_y);
        in_data.v0.position.w = to_fp32(1.0);
        in_data.v1.position.x = to_fp32(v1_x);
        in_data.v1.position.y = to_fp32(v1_y);
        in_data.v1.position.w = to_fp32(1.0);
        in_data.v2.position.x = to_fp32(v2_x);
        in_data.v2.position.y = to_fp32(v2_y);
        in_data.v2.position.w = to_fp32(1.0);
        in_data.v0.u = to_fp32(v0_u);
        in_data.v0.v = to_fp32(v0_v);
        in_data.v1.u = to_fp32(v1_u);
        in_data.v1.v = to_fp32(v1_v);
        in_data.v2.u = to_fp32(v2_u);
        in_data.v2.v = to_fp32(v2_v);
        bin_min_x = bin_min_x_value;
        bin_min_y = bin_min_y_value;
        bin_max_x = bin_max_x_value;
        bin_max_y = bin_max_y_value;

        @(negedge clk);
        while (!ready_out) @(negedge clk);
        valid_in = 1'b1;
        do @(posedge clk); while (!ready_out);
        @(negedge clk);
        valid_in = 1'b0;

        do @(posedge clk); while (!valid_out);

        check_close("invArea", fp32_to_real(out_data.inv_area), exp_inv_area);
        check_close("w0", fx28_20_to_real(out_data.init_e0), exp_w0);
        check_close("w1", fx28_20_to_real(out_data.init_e1), exp_w1);
        check_close("w2", fx28_20_to_real(out_data.init_e2), exp_w2);
        check_close("dx0", fx14_10_to_real(out_data.e0_dx), exp_dx0);
        check_close("dx1", fx14_10_to_real(out_data.e1_dx), exp_dx1);
        check_close("dx2", fx14_10_to_real(out_data.e2_dx), exp_dx2);
        check_close("dy0", fx14_10_to_real(out_data.e0_dy), exp_dy0);
        check_close("dy1", fx14_10_to_real(out_data.e1_dy), exp_dy1);
        check_close("dy2", fx14_10_to_real(out_data.e2_dy), exp_dy2);

        if (out_data.width !== expected_width[5:0])
          $fatal(
              1,
              "row %0d width mismatch: got %0d expected %0d",
              transaction_id,
              out_data.width,
              expected_width
          );
        if (out_data.height !== expected_height[5:0])
          $fatal(
              1,
              "row %0d height mismatch: got %0d expected %0d",
              transaction_id,
              out_data.height,
              expected_height
          );
        if (out_data.minX_local !== expected_min_x_local[5:0])
          $fatal(
              1,
              "row %0d minX_local mismatch: got %0d expected %0d",
              transaction_id,
              out_data.minX_local,
              expected_min_x_local
          );
        if (out_data.minY_local !== expected_min_y_local[5:0])
          $fatal(
              1,
              "row %0d minY_local mismatch: got %0d expected %0d",
              transaction_id,
              out_data.minY_local,
              expected_min_y_local
          );

        check_close("v0_u", fx5_13_to_real(out_data.v0_u), exp_v0_u);
        check_close("v0_v", fx5_13_to_real(out_data.v0_v), exp_v0_v);
        check_close("v1_u", fx5_13_to_real(out_data.v1_u), exp_v1_u);
        check_close("v1_v", fx5_13_to_real(out_data.v1_v), exp_v1_v);
        check_close("v2_u", fx5_13_to_real(out_data.v2_u), exp_v2_u);
        check_close("v2_v", fx5_13_to_real(out_data.v2_v), exp_v2_v);

        rows_checked = rows_checked + 1;
        if ((rows_checked % 100) == 0) $display("checked %0d CSV transactions", rows_checked);
      end
    end

    $fclose(input_file);
    $fclose(expected_file);
    $display("PASS: checked %0d frontend CSV transactions", rows_checked);
    $finish;
  end

  initial begin
    #10000000;
    $fatal(1, "testbench timeout");
  end
endmodule
