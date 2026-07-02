`timescale 1ns / 1ps

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
  logic             skid_valid;

  // One-stage skid buffer:
  // - fall-through in the no-stall case
  // - capture one beat on a downstream stall
  // - support drain+refill in a single cycle
  assign s_axis_tready = m_axis_tready || !skid_valid;
  assign m_axis_tvalid = skid_valid || s_axis_tvalid;
  assign m_axis_tdata  = skid_valid ? skid_data : s_axis_tdata;

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      skid_valid <= 1'b0;
      skid_data  <= '0;
    end else begin
      if (skid_valid) begin
        if (m_axis_tready) begin
          // Draining buffered beat; refill immediately if a new beat arrives.
          if (s_axis_tvalid) begin
            skid_valid <= 1'b1;
            skid_data  <= s_axis_tdata;
          end else begin
            skid_valid <= 1'b0;
          end
        end
      end else if (s_axis_tvalid && !m_axis_tready) begin
        // Capture one beat when downstream stalls.
        skid_valid <= 1'b1;
        skid_data  <= s_axis_tdata;
      end
    end
  end

endmodule
