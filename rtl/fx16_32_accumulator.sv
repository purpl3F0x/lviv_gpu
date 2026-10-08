`timescale 1ns / 1ns

module fx16_32_accumulator (
    input logic clk,
    input logic rst_n,
    input logic clken,
    input logic [2:0] op,
    input logic signed [47:0] concat_operand,
    input logic signed [47:0] c_operand,
    output logic signed [47:0] result
);


`ifdef SYNTHESIS
  dsp_macro_0 u_dsp (
      .CLK(clk),
      .CE(clken),
      .SCLR(!rst_n),
      .SEL(op),
      .CONCAT(concat_operand),
      .C(c_operand),
      .P(result)
  );
`else

  logic [2:0] op_input, op_stage;
  logic signed [47:0] concat_input, c_input;
  logic signed [47:0] concat_stage1, concat_stage2, c_stage;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      op_input <= '0;
      op_stage <= '0;
      concat_input <= '0;
      concat_stage1 <= '0;
      concat_stage2 <= '0;
      c_input <= '0;
      c_stage <= '0;
      result <= '0;

    end else if (clken) begin
      op_input <= op;
      op_stage <= op_input;

      concat_input <= concat_operand;
      concat_stage1 <= concat_input;
      concat_stage2 <= concat_stage1;

      c_input <= c_operand;
      c_stage <= c_input;
      case (op_stage)
        3'd0: result <= result;
        3'd1: result <= c_stage;
        3'd2: result <= result + concat_stage2;
        3'd3: result <= result - concat_stage2;
        3'd4: result <= result + concat_stage2 + c_stage;
        3'd5: result <= result + c_stage;
        default: result <= 48'd0;
      endcase
    end
  end
`endif

endmodule
