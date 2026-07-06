module fx_9_8_to_u8 (
    input  logic        clk,
    input  logic        clken,
    input  logic [16:0] in_fx9_8,
    output logic [ 7:0] out_u8
);

  always_ff @(posedge clk) begin
    if (clken) begin
      if (in_fx9_8[16] == 1'b1)  // > 255, clamp
        out_u8 <= 8'd255;
      else out_u8 <= (in_fx9_8 + 8'd128) >> 8;  // round to nearest
    end
  end

endmodule
