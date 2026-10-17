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

// 48-bit edge accumulator on one DSP slice (dsp_macro_0), latency 2:
// CONCAT, C and SEL registered in the DSP input stage, P registered at the output.
// SEL 0: CONCAT + C
// SEL 1: P + CONCAT
// SEL 2: P - CONCAT
module orchestrator_alu (
    input logic clk,
    input logic clken,
    input logic [1:0] op,
    input logic signed [47:0] concat_operand,
    input logic signed [47:0] c_operand,
    output logic signed [47:0] result
);

`ifndef SIM_MODE
  dsp_macro_0 u_dsp (
      .CLK(clk),
      .CE(clken),
      .SEL(op),
      .CONCAT(concat_operand),
      .C(c_operand),
      .P(result)
  );
`else

  logic [1:0] op_stage;
  logic signed [47:0] concat_stage, c_stage;

  always_ff @(posedge clk) begin
    if (clken) begin
      op_stage <= op;
      concat_stage <= concat_operand;
      c_stage <= c_operand;
      case (op_stage)
        2'd0: result <= concat_stage + c_stage;
        2'd1: result <= result + concat_stage;
        2'd2: result <= result - concat_stage;
        default: result <= result;
      endcase
    end
  end
`endif

endmodule
