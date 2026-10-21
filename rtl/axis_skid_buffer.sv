`timescale 1ns / 1ps

// Taken from: https://github.com/nelsoncsc/verilaxi/blob/main/rtl/common/snix_register_slice.sv


module axis_skid_buffer #(
    parameter int WIDTH  = 32
) (
    input  logic             aclk,
    input  logic             aresetn,
    // AXIS Slave interface
    input  logic [WIDTH-1:0] s_axis_tdata,
    input  logic             s_axis_tvalid,
    output logic             s_axis_tready,
    // AXIS Master interface
    output logic [WIDTH-1:0] m_axis_tdata,
    output logic             m_axis_tvalid,
    input  logic             m_axis_tready
);

  logic [WIDTH-1:0] skid_data;
  // Replicated: it is the stall enable of the stage that feeds the skid.
  (* max_fanout = 256 *) logic s_axis_tready_reg;
  logic             skid_valid;

  assign s_axis_tready = s_axis_tready_reg;
  assign skid_valid = !s_axis_tready_reg;

  logic s_hsk;
  logic m_stall;
  assign s_hsk   = s_axis_tvalid && s_axis_tready;
  assign m_stall = m_axis_tvalid && !m_axis_tready;

  // Fully-registered slice
  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      s_axis_tready_reg <= 1'b1;
    end else if (s_hsk && m_stall) begin
      s_axis_tready_reg <= 1'b0;
    end else if (m_axis_tready) begin
      s_axis_tready_reg <= 1'b1;
    end
  end

  // No reset on the data: skid_valid (from the reset tready register) qualifies it.
  always_ff @(posedge aclk) begin
    if (s_hsk) begin
      skid_data <= s_axis_tdata;
    end
  end

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      m_axis_tvalid <= 1'b0;
    end else if (!m_axis_tvalid || m_axis_tready) begin
      m_axis_tvalid <= s_axis_tvalid || skid_valid;
    end
  end

  // Output data — skid has priority when draining a held beat.
  always_ff @(posedge aclk) begin
    if (!m_axis_tvalid || m_axis_tready) begin
      if (skid_valid) m_axis_tdata <= skid_data;
      else if (s_axis_tvalid) m_axis_tdata <= s_axis_tdata;
    end
  end

endmodule
