`timescale 1ns / 1ps

`ifdef VERILATOR
  `define SIM_MODE
`endif
`ifdef SIMULATION
  `define SIM_MODE
`endif
`ifdef __ICARUS__
  `define SIM_MODE
`endif

//`define SIM_MODE


`ifdef VERILATOR
import "DPI-C" function shortreal dpi_bits_to_float(input int unsigned bits);
import "DPI-C" function int unsigned dpi_float_to_bits(input shortreal val);
`define BITSTOSHORTREAL(x) dpi_bits_to_float(x)
`define SHORTREALTOBITS(x) dpi_float_to_bits(x)
`else
  `define BITSTOSHORTREAL(x) $bitstoshortreal(x)
  `define SHORTREALTOBITS(x) $shortrealtobits(x)
`endif


module fp_mul_blocking #(
  parameter int LATENCY = 9
) (
    input  logic        aclk,
    input  logic        aresetn,
    input  logic [31:0] s_axis_a_tdata,
    input  logic        s_axis_a_tvalid,
    output logic        s_axis_a_tready,
    input  logic [31:0] s_axis_b_tdata,
    input  logic        s_axis_b_tvalid,
    output logic        s_axis_b_tready,
    output logic [31:0] m_axis_result_tdata,
    output logic        m_axis_result_tvalid,
    input  logic        m_axis_result_tready
);

`ifdef SIM_MODE
  logic [31:0] a_buf_tdata;
  logic        a_buf_full;
  logic [31:0] b_buf_tdata;
  logic        b_buf_full;

  logic [31:0] out_src_tdata;
  logic        out_src_tvalid;
  logic        out_src_tready;

  logic [31:0] lat_data_pipe [LATENCY];
  logic        lat_valid_pipe[LATENCY];

  shortreal a_real, b_real, res_real;
  logic consume;
  logic a_accept;
  logic b_accept;

  assign consume = a_buf_full && b_buf_full && out_src_tready;
  assign a_accept = s_axis_a_tvalid && (!a_buf_full || consume);
  assign b_accept = s_axis_b_tvalid && (!b_buf_full || consume);

  assign s_axis_a_tready = !a_buf_full || consume;
  assign s_axis_b_tready = !b_buf_full || consume;

  assign a_real = `BITSTOSHORTREAL(a_buf_tdata);
  assign b_real = `BITSTOSHORTREAL(b_buf_tdata);
  assign res_real = a_real * b_real;

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      a_buf_tdata <= '0;
      a_buf_full <= 1'b0;
      b_buf_tdata <= '0;
      b_buf_full <= 1'b0;
      for (int i = 0; i < LATENCY; i++) begin
        lat_data_pipe[i] <= '0;
        lat_valid_pipe[i] <= 1'b0;
      end
    end else begin
      if (a_accept) begin
        a_buf_tdata <= s_axis_a_tdata;
        a_buf_full <= 1'b1;
      end else if (consume) begin
        a_buf_full <= 1'b0;
      end

      if (b_accept) begin
        b_buf_tdata <= s_axis_b_tdata;
        b_buf_full <= 1'b1;
      end else if (consume) begin
        b_buf_full <= 1'b0;
      end

      if (out_src_tready && consume) begin
        lat_data_pipe[0] <= `SHORTREALTOBITS(res_real);
        lat_valid_pipe[0] <= 1'b1;
      end else if (out_src_tready) begin
        lat_valid_pipe[0] <= 1'b0;
      end
      for (int i = 1; i < LATENCY; i++) begin
        lat_data_pipe[i] <= lat_data_pipe[i-1];
        lat_valid_pipe[i] <= lat_valid_pipe[i-1];
      end
    end
  end

  assign out_src_tdata = lat_data_pipe[LATENCY-1];
  assign out_src_tvalid = lat_valid_pipe[LATENCY-1];

  axis_skid_buffer #(.WIDTH(32)) u_out_buf (
      .aclk(aclk),
      .aresetn(aresetn),
      .s_axis_tdata(out_src_tdata),
      .s_axis_tvalid(out_src_tvalid),
      .s_axis_tready(out_src_tready),
      .m_axis_tdata(m_axis_result_tdata),
      .m_axis_tvalid(m_axis_result_tvalid),
      .m_axis_tready(m_axis_result_tready)
  );

`else

  xil_fp_mul_blocking u_fp_mul_blocking (
      .aclk(aclk),
      .aresetn(aresetn),
      .s_axis_a_tvalid(s_axis_a_tvalid),
      .s_axis_a_tdata(s_axis_a_tdata),
      .s_axis_a_tready(s_axis_a_tready),
      .s_axis_b_tvalid(s_axis_b_tvalid),
      .s_axis_b_tdata(s_axis_b_tdata),
      .s_axis_b_tready(s_axis_b_tready),
      .m_axis_result_tvalid(m_axis_result_tvalid),
      .m_axis_result_tdata(m_axis_result_tdata),
      .m_axis_result_tready(m_axis_result_tready)
  );

`endif

endmodule

module fp_fma_blocking #(
  parameter int LATENCY = 22
) (
    input  logic        aclk,
    input  logic        aresetn,
    input  logic [31:0] s_axis_a_tdata,
    input  logic        s_axis_a_tvalid,
    output logic        s_axis_a_tready,
    input  logic [31:0] s_axis_b_tdata,
    input  logic        s_axis_b_tvalid,
    output logic        s_axis_b_tready,
    input  logic [31:0] s_axis_c_tdata,
    input  logic        s_axis_c_tvalid,
    output logic        s_axis_c_tready,
    output logic [31:0] m_axis_result_tdata,
    output logic        m_axis_result_tvalid,
    input  logic        m_axis_result_tready
);

`ifdef SIM_MODE
  logic [31:0] a_buf_tdata;
  logic        a_buf_full;
  logic [31:0] b_buf_tdata;
  logic        b_buf_full;
  logic [31:0] c_buf_tdata;
  logic        c_buf_full;

  logic [31:0] out_src_tdata;
  logic        out_src_tvalid;
  logic        out_src_tready;

  logic [31:0] lat_data_pipe [LATENCY];
  logic        lat_valid_pipe[LATENCY];

  shortreal a_real, b_real, c_real, res_real;
  logic consume;
  logic a_accept;
  logic b_accept;
  logic c_accept;

  assign consume = a_buf_full && b_buf_full && c_buf_full && out_src_tready;
  assign a_accept = s_axis_a_tvalid && (!a_buf_full || consume);
  assign b_accept = s_axis_b_tvalid && (!b_buf_full || consume);
  assign c_accept = s_axis_c_tvalid && (!c_buf_full || consume);

  assign s_axis_a_tready = !a_buf_full || consume;
  assign s_axis_b_tready = !b_buf_full || consume;
  assign s_axis_c_tready = !c_buf_full || consume;

  assign a_real = `BITSTOSHORTREAL(a_buf_tdata);
  assign b_real = `BITSTOSHORTREAL(b_buf_tdata);
  assign c_real = `BITSTOSHORTREAL(c_buf_tdata);
  assign res_real = (a_real * b_real) + c_real;

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      a_buf_tdata <= '0;
      a_buf_full <= 1'b0;
      b_buf_tdata <= '0;
      b_buf_full <= 1'b0;
      c_buf_tdata <= '0;
      c_buf_full <= 1'b0;
      for (int i = 0; i < LATENCY; i++) begin
        lat_data_pipe[i] <= '0;
        lat_valid_pipe[i] <= 1'b0;
      end
    end else begin
      if (a_accept) begin
        a_buf_tdata <= s_axis_a_tdata;
        a_buf_full <= 1'b1;
      end else if (consume) begin
        a_buf_full <= 1'b0;
      end

      if (b_accept) begin
        b_buf_tdata <= s_axis_b_tdata;
        b_buf_full <= 1'b1;
      end else if (consume) begin
        b_buf_full <= 1'b0;
      end

      if (c_accept) begin
        c_buf_tdata <= s_axis_c_tdata;
        c_buf_full <= 1'b1;
      end else if (consume) begin
        c_buf_full <= 1'b0;
      end

      if (out_src_tready && consume) begin
        lat_data_pipe[0] <= `SHORTREALTOBITS(res_real);
        lat_valid_pipe[0] <= 1'b1;
      end else if (out_src_tready) begin
        lat_valid_pipe[0] <= 1'b0;
      end
      for (int i = 1; i < LATENCY; i++) begin
        lat_data_pipe[i] <= lat_data_pipe[i-1];
        lat_valid_pipe[i] <= lat_valid_pipe[i-1];
      end
    end
  end

  assign out_src_tdata = lat_data_pipe[LATENCY-1];
  assign out_src_tvalid = lat_valid_pipe[LATENCY-1];

  axis_skid_buffer #(.WIDTH(32)) u_out_buf (
      .aclk(aclk),
      .aresetn(aresetn),
      .s_axis_tdata(out_src_tdata),
      .s_axis_tvalid(out_src_tvalid),
      .s_axis_tready(out_src_tready),
      .m_axis_tdata(m_axis_result_tdata),
      .m_axis_tvalid(m_axis_result_tvalid),
      .m_axis_tready(m_axis_result_tready)
  );

`else

  xil_fp_fma_blocking u_fp_fma_blocking (
      .aclk(aclk),
      .aresetn(aresetn),
      .s_axis_a_tvalid(s_axis_a_tvalid),
      .s_axis_a_tdata(s_axis_a_tdata),
      .s_axis_a_tready(s_axis_a_tready),
      .s_axis_b_tvalid(s_axis_b_tvalid),
      .s_axis_b_tdata(s_axis_b_tdata),
      .s_axis_b_tready(s_axis_b_tready),
      .s_axis_c_tvalid(s_axis_c_tvalid),
      .s_axis_c_tdata(s_axis_c_tdata),
      .s_axis_c_tready(s_axis_c_tready),
      .m_axis_result_tvalid(m_axis_result_tvalid),
      .m_axis_result_tdata(m_axis_result_tdata),
      .m_axis_result_tready(m_axis_result_tready)
  );

`endif

endmodule

module fp_recip_blocking #(
  parameter int LATENCY = 32
) (
    input  logic        aclk,
    input  logic        aresetn,
    input  logic [31:0] s_axis_a_tdata,
    input  logic        s_axis_a_tvalid,
    output logic        s_axis_a_tready,
    output logic [31:0] m_axis_result_tdata,
    output logic        m_axis_result_tvalid,
    input  logic        m_axis_result_tready
);

`ifdef SIM_MODE
  logic [31:0] a_buf_tdata;
  logic        a_buf_full;

  logic [31:0] out_src_tdata;
  logic        out_src_tvalid;
  logic        out_src_tready;

  logic [31:0] lat_data_pipe [LATENCY];
  logic        lat_valid_pipe[LATENCY];

  shortreal a_real, res_real;
  logic consume;
  logic a_accept;

  assign consume = a_buf_full && out_src_tready;
  assign a_accept = s_axis_a_tvalid && (!a_buf_full || consume);
  assign s_axis_a_tready = !a_buf_full || consume;

  assign a_real = `BITSTOSHORTREAL(a_buf_tdata);
  assign res_real = 1.0 / a_real;

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      a_buf_tdata <= '0;
      a_buf_full <= 1'b0;
      for (int i = 0; i < LATENCY; i++) begin
        lat_data_pipe[i] <= '0;
        lat_valid_pipe[i] <= 1'b0;
      end
    end else begin
      if (a_accept) begin
        a_buf_tdata <= s_axis_a_tdata;
        a_buf_full <= 1'b1;
      end else if (consume) begin
        a_buf_full <= 1'b0;
      end

      if (out_src_tready && consume) begin
        lat_data_pipe[0] <= `SHORTREALTOBITS(res_real);
        lat_valid_pipe[0] <= 1'b1;
      end else if (out_src_tready) begin
        lat_valid_pipe[0] <= 1'b0;
      end
      for (int i = 1; i < LATENCY; i++) begin
        lat_data_pipe[i] <= lat_data_pipe[i-1];
        lat_valid_pipe[i] <= lat_valid_pipe[i-1];
      end
    end
  end

  assign out_src_tdata = lat_data_pipe[LATENCY-1];
  assign out_src_tvalid = lat_valid_pipe[LATENCY-1];

  axis_skid_buffer #(.WIDTH(32)) u_out_buf (
      .aclk(aclk),
      .aresetn(aresetn),
      .s_axis_tdata(out_src_tdata),
      .s_axis_tvalid(out_src_tvalid),
      .s_axis_tready(out_src_tready),
      .m_axis_tdata(m_axis_result_tdata),
      .m_axis_tvalid(m_axis_result_tvalid),
      .m_axis_tready(m_axis_result_tready)
  );

`else

  xil_fp_recip_blocking u_fp_recip_blocking (
      .aclk(aclk),
      .aresetn(aresetn),
      .s_axis_a_tvalid(s_axis_a_tvalid),
      .s_axis_a_tdata(s_axis_a_tdata),
      .s_axis_a_tready(s_axis_a_tready),
      .m_axis_result_tvalid(m_axis_result_tvalid),
      .m_axis_result_tdata(m_axis_result_tdata),
      .m_axis_result_tready(m_axis_result_tready)
  );

`endif

endmodule
