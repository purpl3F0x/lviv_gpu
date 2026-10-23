// -----------------------------------------------------------------------------
// Floating-Point Unit Wrappers
// Copyright (c) 2026 Stavros Avramidis
//
// Provides Verilator simulation equivalents and bindings for Xilinx Floating-Point IPs.
// IPs are non-blocking with aclk and aclken.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ns
`ifdef VERILATOR
`define SIM_MODE
`endif
`ifdef SIMULATION
`define SIM_MODE
`endif
`ifdef __ICARUS__
`define SIM_MODE
`endif

`ifdef VERILATOR
import "DPI-C" function shortreal dpi_bits_to_float(input int unsigned bits);
import "DPI-C" function int unsigned dpi_float_to_bits(input shortreal val);
`define BITSTOSHORTREAL(x) dpi_bits_to_float(x)
`define SHORTREALTOBITS(x) dpi_float_to_bits(x)
`else
`define BITSTOSHORTREAL(x) $bitstoshortreal(x)
`define SHORTREALTOBITS(x) $shortrealtobits(x)
`endif


module fx28_20_to_fp32 #(
    parameter int LATENCY = 7
) (
    input logic aclk,
    input logic aclken,
    input logic s_axis_a_tvalid,
    input logic signed [47:0] s_axis_a_tdata,
    output logic m_axis_result_tvalid,
    output logic [31:0] m_axis_result_tdata
);
`ifdef SIM_MODE
  shortreal converted;
  logic [31:0] res_bits;
  logic [31:0] pipeline[LATENCY];
  logic valid_pipe[LATENCY];

  assign converted = real'($signed(s_axis_a_tdata)) / 1048576.0;
  assign res_bits  = `SHORTREALTOBITS(converted);

  always_ff @(posedge aclk) begin
    if (aclken) begin
      pipeline[0]   <= res_bits;
      valid_pipe[0] <= s_axis_a_tvalid;
      for (int i = 1; i < LATENCY; i++) begin
        pipeline[i]   <= pipeline[i-1];
        valid_pipe[i] <= valid_pipe[i-1];
      end
    end
  end

  assign m_axis_result_tdata  = pipeline[LATENCY-1];
  assign m_axis_result_tvalid = valid_pipe[LATENCY-1];
`else
  xil_fx28_20_to_fp32 u_convert (
      .aclk(aclk),
      .aclken(aclken),
      .s_axis_a_tvalid(s_axis_a_tvalid),
      .s_axis_a_tdata(s_axis_a_tdata),
      .m_axis_result_tvalid(m_axis_result_tvalid),
      .m_axis_result_tdata(m_axis_result_tdata)
  );
`endif
endmodule

// ============================================================================
// Floating-Point Multiplier
// ============================================================================
module fp_mul #(
    parameter int LATENCY = 8  // Default latency for Xilinx FP Mul
) (
    input  logic        aclk,
    input  logic        aclken,
    input  logic        valid_in,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] result
);

`ifdef SIM_MODE
  shortreal a_real, b_real, res_real;
  logic [31:0] res_bits;
  logic [31:0] pipeline [LATENCY];

  assign a_real   = `BITSTOSHORTREAL(a);
  assign b_real   = `BITSTOSHORTREAL(b);
  assign res_real = a_real * b_real;
  assign res_bits = `SHORTREALTOBITS(res_real);

  always_ff @(posedge aclk) begin
    if (aclken) begin
      pipeline[0] <= res_bits;
      for (int i = 1; i < LATENCY; i++) begin
        pipeline[i] <= pipeline[i-1];
      end
    end
  end

  assign result = pipeline[LATENCY-1];

`else
  // Xilinx IP instantiation for Synthesis
  xil_fp_mul xil_fp_mul_inst (
      .aclk                (aclk),
      .aclken              (aclken),
      .s_axis_a_tvalid     (valid_in),
      .s_axis_a_tdata      (a),
      .s_axis_b_tvalid     (valid_in),
      .s_axis_b_tdata      (b),
      .m_axis_result_tvalid(),
      .m_axis_result_tdata (result)
  );
`endif

endmodule

// ============================================================================
// Floating-Point Fused Multiply-Add: (a * b) + c
// ============================================================================
module fp_fma #(
    parameter int LATENCY = 19  // Default latency for Xilinx FP FMA
) (
    input  logic        aclk,
    input  logic        aclken,
    input  logic        valid_in,
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [31:0] c,
    output logic [31:0] result
);

`ifdef SIM_MODE
  shortreal a_real, b_real, c_real, res_real;
  logic [31:0] res_bits;
  logic [31:0] pipeline [LATENCY];

  assign a_real   = `BITSTOSHORTREAL(a);
  assign b_real   = `BITSTOSHORTREAL(b);
  assign c_real   = `BITSTOSHORTREAL(c);
  assign res_real = (a_real * b_real) + c_real;
  assign res_bits = `SHORTREALTOBITS(res_real);

  always_ff @(posedge aclk) begin
    if (aclken) begin
      pipeline[0] <= res_bits;
      for (int i = 1; i < LATENCY; i++) begin
        pipeline[i] <= pipeline[i-1];
      end
    end
  end

  assign result = pipeline[LATENCY-1];

`else
  // Xilinx IP instantiation for Synthesis
  xil_fp_fma xil_fp_fma_inst (
      .aclk                (aclk),
      .aclken              (aclken),
      .s_axis_a_tvalid     (valid_in),
      .s_axis_a_tdata      (a),
      .s_axis_b_tvalid     (valid_in),
      .s_axis_b_tdata      (b),
      .s_axis_c_tvalid     (valid_in),
      .s_axis_c_tdata      (c),
      .m_axis_result_tvalid(),
      .m_axis_result_tdata (result)
  );
`endif

endmodule

// ============================================================================
// Floating-Point Reciprocal (1/x)
// ============================================================================
module fp_recip #(
    parameter int LATENCY = 29  // Default latency for Xilinx FP Recip
) (
    input  logic        aclk,
    input  logic        aclken,
    input  logic        valid_in,
    input  logic [31:0] a,
    output logic [31:0] result
);

`ifdef SIM_MODE
  shortreal a_real, res_real;
  logic [31:0] res_bits;
  logic [31:0] pipeline [LATENCY];

  assign a_real   = `BITSTOSHORTREAL(a);
  assign res_real = 1.0 / a_real;
  assign res_bits = `SHORTREALTOBITS(res_real);

  always_ff @(posedge aclk) begin
    if (aclken) begin
      pipeline[0] <= res_bits;
      for (int i = 1; i < LATENCY; i++) begin
        pipeline[i] <= pipeline[i-1];
      end
    end
  end

  assign result = pipeline[LATENCY-1];

`else
  // Xilinx IP instantiation for Synthesis
  // Reciprocal typically has only one input stream
  xil_fp_recip xil_fp_recip_inst (
      .aclk                (aclk),
      .aclken              (aclken),
      .s_axis_a_tvalid     (valid_in),
      .s_axis_a_tdata      (a),
      .m_axis_result_tvalid(),
      .m_axis_result_tdata (result)
  );
`endif

endmodule

module fp_to_fx14_10 #(
    parameter int LATENCY = 6
) (
    input logic aclk,
    input logic aclken,
    input logic s_axis_a_tvalid,
    input logic [31:0] s_axis_a_tdata,
    output logic m_axis_result_tvalid,
    output logic signed [23:0] m_axis_result_tdata
);
`ifdef SIM_MODE
  real scaled;
  longint signed converted;
  logic signed [23:0] res_bits;
  logic signed [23:0] pipeline[LATENCY];
  logic valid_pipe[LATENCY];

  function automatic longint signed round_nearest_even(input real value);
    real magnitude;
    real fraction;
    longint signed integral;
    begin
      magnitude = value < 0.0 ? -value : value;
      integral  = longint'($floor(magnitude));
      fraction  = magnitude - real'(integral);
      if ((fraction > 0.5) || ((fraction == 0.5) && integral[0])) integral++;
      return value < 0.0 ? -integral : integral;
    end
  endfunction

  always_comb begin
    scaled = real'(`BITSTOSHORTREAL(s_axis_a_tdata)) * 1024.0;
    converted = round_nearest_even(scaled);
    res_bits = converted[23:0];
  end

  always_ff @(posedge aclk) begin
    if (aclken) begin
      pipeline[0]   <= res_bits;
      valid_pipe[0] <= s_axis_a_tvalid;
      for (int i = 1; i < LATENCY; i++) begin
        pipeline[i]   <= pipeline[i-1];
        valid_pipe[i] <= valid_pipe[i-1];
      end
    end
  end

  assign m_axis_result_tdata  = pipeline[LATENCY-1];
  assign m_axis_result_tvalid = valid_pipe[LATENCY-1];
`else
  logic [31:0] result_padded;
  xil_fp_to_fx14_10 u_convert (
      .aclk(aclk),
      .aclken(aclken),
      .s_axis_a_tvalid(s_axis_a_tvalid),
      .s_axis_a_tdata(s_axis_a_tdata),
      .m_axis_result_tvalid(m_axis_result_tvalid),
      .m_axis_result_tdata(result_padded)
  );
  assign m_axis_result_tdata = result_padded[23:0];
`endif
endmodule

module fp_to_fx5_13 #(
    parameter int LATENCY = 6
) (
    input logic aclk,
    input logic aclken,
    input logic s_axis_a_tvalid,
    input logic [31:0] s_axis_a_tdata,
    output logic m_axis_result_tvalid,
    output logic signed [17:0] m_axis_result_tdata
);
`ifdef SIM_MODE
  real scaled;
  longint signed converted;
  logic [17:0] res_bits;

  function automatic longint signed round_nearest_even(input real value);
    real magnitude;
    real fraction;
    longint signed integral;
    begin
      magnitude = value < 0.0 ? -value : value;
      integral  = longint'($floor(magnitude));
      fraction  = magnitude - real'(integral);
      if ((fraction > 0.5) || ((fraction == 0.5) && integral[0])) integral++;
      return value < 0.0 ? -integral : integral;
    end
  endfunction

  assign scaled = real'(`BITSTOSHORTREAL(s_axis_a_tdata)) * 8192.0;
  assign converted = round_nearest_even(scaled);
  assign res_bits = converted[17:0];
  delay_pipe #(
      .WIDTH (19),
      .STAGES(LATENCY)
  ) u_pipeline (
      .clk(aclk),
      .rst_n(1'b1),
      .clken(aclken),
      .data_in({s_axis_a_tvalid, res_bits}),
      .data_out({m_axis_result_tvalid, m_axis_result_tdata})
  );
`else
  logic [23:0] result_padded;
  xil_fp_to_fx5_13 u_convert (
      .aclk(aclk),
      .aclken(aclken),
      .s_axis_a_tvalid(s_axis_a_tvalid),
      .s_axis_a_tdata(s_axis_a_tdata),
      .m_axis_result_tvalid(m_axis_result_tvalid),
      .m_axis_result_tdata(result_padded)
  );
  assign m_axis_result_tdata = result_padded[17:0];
`endif
endmodule

module fp_to_fx2_23 #(
    parameter int LATENCY = 2
) (
    input  logic        aclk,
    input  logic        aclken,
    input  logic        s_axis_a_tvalid,
    input  logic [31:0] s_axis_a_tdata,
    output logic        m_axis_result_tvalid,
    output logic [24:0] m_axis_result_tdata
);

`ifdef SIM_MODE
  shortreal             a_real;
  logic          [24:0] res_bits;
  logic          [24:0] pipeline  [LATENCY];
  logic                 valid_pipe[LATENCY];
  longint signed        scaled;

  function automatic longint signed round_nearest_even(input real value);
    real magnitude;
    real fraction;
    longint signed integral;
    begin
      magnitude = value < 0.0 ? -value : value;
      integral  = longint'($floor(magnitude));
      fraction  = magnitude - real'(integral);
      if ((fraction > 0.5) || ((fraction == 0.5) && integral[0])) integral++;
      return value < 0.0 ? -integral : integral;
    end
  endfunction

  always_comb begin
    a_real   = `BITSTOSHORTREAL(s_axis_a_tdata);
    scaled   = round_nearest_even(real'(a_real) * 8388608.0);
    res_bits = scaled[24:0];
  end

  always_ff @(posedge aclk) begin
    if (aclken) begin
      pipeline[0]   <= res_bits;
      valid_pipe[0] <= s_axis_a_tvalid;
      for (int i = 1; i < LATENCY; i++) begin
        pipeline[i]   <= pipeline[i-1];
        valid_pipe[i] <= valid_pipe[i-1];
      end
    end
  end

  assign m_axis_result_tdata  = pipeline[LATENCY-1];
  assign m_axis_result_tvalid = valid_pipe[LATENCY-1];

`else
  xil_fp_to_fx2_23 xil_fp_to_fx2_23_inst (
      .aclk                (aclk),
      .aclken              (aclken),
      .s_axis_a_tvalid     (s_axis_a_tvalid),
      .s_axis_a_tdata      (s_axis_a_tdata),
      .m_axis_result_tvalid(m_axis_result_tvalid),
      .m_axis_result_tdata (m_axis_result_tdata)
  );
`endif

endmodule

