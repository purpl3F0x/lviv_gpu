

module int16_add (
    input clken,
    input logic [15:0] a,
    input logic [15:0] b,
    output logic [15:0] s
);
  always_comb begin
    if (clken) s = a - b;
    else s = 0;
  end
endmodule

module int16_sub (
    input clken,
    input logic [15:0] a,
    input logic [15:0] b,
    output logic [15:0] s
);
  always_comb begin
    if (clken) s = a - b;
    else s = 0;
  end
endmodule
