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


// ============================================================================
// Floating-Point Adder
// ============================================================================
module fp_add #(
    parameter int LATENCY = 11  // Default latency for Xilinx FP Add
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
  assign res_real = a_real + b_real;
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
  // Ensure IP is configured as AXI4-Stream, non-blocking, with aclken.
  xil_fp_add xil_fp_add_inst (
      .aclk                (aclk),
      .aclken              (aclken),
      .s_axis_a_tvalid     (valid_in),
      .s_axis_a_tdata      (a),
      .s_axis_b_tvalid     (valid_in),
      .s_axis_b_tdata      (b),
      .m_axis_result_tvalid(),          // Non-blocking, so valid output is ignored
      .m_axis_result_tdata (result)
  );
`endif

endmodule

// ============================================================================
// Floating-Point Subtractor
// ============================================================================
module fp_sub #(
    parameter int LATENCY = 11  // Default latency for Xilinx FP Sub
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
  assign res_real = a_real - b_real;
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
  xil_fp_sub xil_fp_sub_inst (
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

// ============================================================================
// Floating-Point Adder/Subtractor
// ============================================================================
module fp_add_sub #(
    parameter int LATENCY = 11
) (
    input  logic        aclk,
    input  logic        aclken,
    input  logic        op_sub, // 0 for add, 1 for sub
    input  logic        valid_in,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic        valid_out,
    output logic [31:0] result
);

`ifdef SIM_MODE
  shortreal a_real, b_real, res_real;
  logic [31:0] res_bits;
  logic [31:0] pipeline [LATENCY];
  logic        valid_pipe [LATENCY];

  assign a_real   = `BITSTOSHORTREAL(a);
  assign b_real   = `BITSTOSHORTREAL(b);
  assign res_real = op_sub ? (a_real - b_real) : (a_real + b_real);
  assign res_bits = `SHORTREALTOBITS(res_real);

  always_ff @(posedge aclk) begin
    if (aclken) begin
      pipeline[0]   <= res_bits;
      valid_pipe[0] <= valid_in;
      for (int i = 1; i < LATENCY; i++) begin
        pipeline[i]   <= pipeline[i-1];
        valid_pipe[i] <= valid_pipe[i-1];
      end
    end
  end

  assign result    = pipeline[LATENCY-1];
  assign valid_out = valid_pipe[LATENCY-1];

`else
  // Xilinx IP instantiation for Synthesis
  xil_fp_add_sub xil_fp_add_sub_inst (
      .aclk                (aclk),
      .aclken              (aclken),
      .s_axis_a_tvalid     (valid_in),
      .s_axis_a_tdata      (a),
      .s_axis_b_tvalid     (valid_in),
      .s_axis_b_tdata      (b),
      .s_axis_operation_tvalid(valid_in),
      .s_axis_operation_tdata({7'b0, op_sub}),
      .m_axis_result_tvalid(valid_out),
      .m_axis_result_tdata (result)
  );
`endif

endmodule

// ============================================================================
// Floating-Point to 16-bit Signed Integer (2-cycle latency)
// ============================================================================
module fp32_to_int16 #(
    parameter int LATENCY = 2
) (
    input  logic        aclk,
    input  logic        aclken,
    input  logic        valid_in,
    input  logic [31:0] a,
    output logic [15:0] result
);

`ifdef SIM_MODE
  shortreal a_real;
  logic [15:0] res_bits;
  logic [15:0] pipeline [LATENCY];

  assign a_real   = `BITSTOSHORTREAL(a);
  assign res_bits = 16'(int'(a_real));

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
  xil_fp32_to_int16 xil_fp32_to_int16_inst (
      .aclk                (aclk),
      .aclken              (aclken),
      .s_axis_a_tvalid     (valid_in),
      .s_axis_a_tdata      (a),
      .m_axis_result_tvalid(),
      .m_axis_result_tdata (result)
  );
`endif

endmodule

// ============================================================================
// Floating-Point to Fixed-Point Q2.23 (2-cycle latency)
// Wrapper name is fp_to_fx2_23, synthesis backend is xil_fp_to_fx2_23
// ============================================================================
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
  shortreal a_real;
  logic [24:0] res_bits;
  logic [24:0] pipeline [LATENCY];
  logic        valid_pipe [LATENCY];
  integer scaled;

  always_comb begin
    a_real = `BITSTOSHORTREAL(s_axis_a_tdata);
    // Round to nearest instead of truncating toward zero.
    if (a_real >= 0.0) begin
      scaled = $rtoi((a_real * 8388608.0) + 0.5);  // 2^23
    end else begin
      scaled = $rtoi((a_real * 8388608.0) - 0.5);  // 2^23
    end
    res_bits = scaled[24:0];
  end

  always_ff @(posedge aclk) begin
    if (aclken) begin
      pipeline[0] <= res_bits;
      valid_pipe[0] <= s_axis_a_tvalid;
      for (int i = 1; i < LATENCY; i++) begin
        pipeline[i] <= pipeline[i-1];
        valid_pipe[i] <= valid_pipe[i-1];
      end
    end
  end

  assign m_axis_result_tdata = pipeline[LATENCY-1];
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

// ============================================================================
// Floating-Point to Fixed-Point Q2.8 (2-cycle latency)
// Wrapper name is fp_to_fx2_8, synthesis backend is xil_fp_to_fx2_8
// ============================================================================
module fp_to_fx2_8 #(
    parameter int LATENCY = 2
) (
    input  logic        aclk,
    input  logic        aclken,
    input  logic        s_axis_a_tvalid,
    input  logic [31:0] s_axis_a_tdata,
    output logic        m_axis_result_tvalid,
    output logic [15:0] m_axis_result_tdata
);

`ifdef SIM_MODE
  shortreal a_real;
  logic [15:0] res_bits;
  logic [15:0] pipeline [LATENCY];
  logic        valid_pipe [LATENCY];
  integer scaled;

  always_comb begin
    a_real = `BITSTOSHORTREAL(s_axis_a_tdata);
    scaled = $rtoi(a_real * 256.0);  // 2^8
    res_bits = scaled[15:0];
  end

  always_ff @(posedge aclk) begin
    if (aclken) begin
      pipeline[0] <= res_bits;
      valid_pipe[0] <= s_axis_a_tvalid;
      for (int i = 1; i < LATENCY; i++) begin
        pipeline[i] <= pipeline[i-1];
        valid_pipe[i] <= valid_pipe[i-1];
      end
    end
  end

  assign m_axis_result_tdata = pipeline[LATENCY-1];
  assign m_axis_result_tvalid = valid_pipe[LATENCY-1];

`else
  xil_fp_to_fx2_8 xil_fp_to_fx2_8_inst (
      .aclk                (aclk),
      .aclken              (aclken),
      .s_axis_a_tvalid     (s_axis_a_tvalid),
      .s_axis_a_tdata      (s_axis_a_tdata),
      .m_axis_result_tvalid(m_axis_result_tvalid),
      .m_axis_result_tdata (m_axis_result_tdata)
  );
`endif

endmodule
