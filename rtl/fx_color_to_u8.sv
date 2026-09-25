module fx_color_to_u8 (
    input  logic        clk,
    input  logic        clken,
    input  logic [32:0] in_fx_color,
    output logic [ 7:0] out_u8
);
  logic [32:0] in_fx_color_reg;
  logic [33:0] rounded;

  assign rounded = {1'b0, in_fx_color_reg} + 34'd4194304;

  always_ff @(posedge clk) begin
    if (clken) begin
      // Stage 1: register input.
      in_fx_color_reg <= in_fx_color;

      // Stage 2: round and clamp.
      if (|rounded[33:31])  // > 255 after rounding, clamp
        out_u8 <= 8'd255;
      else out_u8 <= rounded[30:23];  // round UQ10.23 to u8
    end
  end

endmodule
