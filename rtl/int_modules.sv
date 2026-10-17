

module int_add #(
    parameter int WIDTH = 16
) (
    input logic clk,
    input logic clken,
    input logic [WIDTH-1:0] a,
    input logic [WIDTH-1:0] b,
    output logic [WIDTH-1:0] s
);
  always_ff @(posedge clk) begin
    if (clken) s <= a + b;
  end
endmodule

module int_sub #(
    parameter int WIDTH = 16
) (
    input logic clk,
    input logic clken,
    input logic [WIDTH-1:0] a,
    input logic [WIDTH-1:0] b,
    output logic [WIDTH-1:0] s
);
  always_ff @(posedge clk) begin
    if (clken) s <= a - b;
  end
endmodule

module int_mul #(
    parameter unsigned WIDTHA = 16,
    parameter unsigned WIDTHB = 16,
    parameter unsigned WIDTHP = WIDTHA + WIDTHB,
    parameter unsigned INPUT_BUFFERS = 1,
    parameter unsigned OUTPUT_BUFFERS = 1,
    parameter unsigned LATENCY = 0
) (
    input logic clk,
    input logic clken,
    input logic signed [WIDTHA-1:0] a,
    input logic signed [WIDTHB-1:0] b,
    output logic signed [WIDTHP-1:0] p
);

  if (LATENCY != 1 + OUTPUT_BUFFERS + INPUT_BUFFERS)
    $error("LATENCY must equal 1 + OUTPUT_BUFFERS + INPUT_BUFFERS");

  logic signed [WIDTHA-1:0] a_reg[INPUT_BUFFERS-1:0];
  logic signed [WIDTHB-1:0] b_reg[INPUT_BUFFERS-1:0];
  logic signed [WIDTHP-1:0] p_reg[ 1+OUTPUT_BUFFERS];

  genvar i;

  // Input buffering for a and b
  generate
    for (i = 0; i < INPUT_BUFFERS; i++) begin : g_in_buffer
      if (i == 0) begin : g_first
        always_ff @(posedge clk) begin
          if (clken) begin
            a_reg[i] <= a;
            b_reg[i] <= b;
          end
        end
      end else begin : g_next
        always_ff @(posedge clk) begin
          if (clken) begin
            a_reg[i] <= a_reg[i-1];
            b_reg[i] <= b_reg[i-1];
          end
        end
      end
    end
  endgenerate

  // Output buffering for the product
  generate
    for (i = 1; i <= OUTPUT_BUFFERS; i++) begin : g_out_buffer
      always_ff @(posedge clk) begin
        if (clken) p_reg[i] <= p_reg[i-1];
      end
    end
  endgenerate
  assign p = p_reg[OUTPUT_BUFFERS];


  always_ff @(posedge clk) begin
    if (clken) begin
      p_reg[0] <= a_reg[INPUT_BUFFERS-1] * b_reg[INPUT_BUFFERS-1];
    end
  end

endmodule


module int_mul_add #(
    parameter unsigned WIDTHA = 16,
    parameter unsigned WIDTHB = 16,
    parameter unsigned WIDTHP = WIDTHA + WIDTHB,
    parameter logic SUBTRACT = 0,
    parameter unsigned INPUT_BUFFERS = 1,
    parameter unsigned OUTPUT_BUFFERS = 1,
    parameter unsigned LATENCY = 0
) (
    input logic clk,
    input logic clken,
    input logic signed [WIDTHA-1:0] a,
    input logic signed [WIDTHB-1:0] b,
    input logic signed [WIDTHP-1:0] c,  // Input non-pipelined
    output logic signed [WIDTHP-1:0] p
);

  if (LATENCY != 2 + OUTPUT_BUFFERS + INPUT_BUFFERS)
    $error("LATENCY must equal 2 + OUTPUT_BUFFERS + INPUT_BUFFERS");

  logic signed [WIDTHA-1:0] a_reg[INPUT_BUFFERS-1:0];
  logic signed [WIDTHB-1:0] b_reg[INPUT_BUFFERS-1:0];
  logic signed [WIDTHP-1:0] p_reg[ 2+OUTPUT_BUFFERS];

  genvar i;

  // Input buffering for a and b
  generate
    for (i = 0; i < INPUT_BUFFERS; i++) begin : g_in_buffer
      if (i == 0) begin : g_first
        always_ff @(posedge clk) begin
          if (clken) begin
            a_reg[i] <= a;
            b_reg[i] <= b;
          end
        end
      end else begin : g_next
        always_ff @(posedge clk) begin
          if (clken) begin
            a_reg[i] <= a_reg[i-1];
            b_reg[i] <= b_reg[i-1];
          end
        end
      end
    end
  endgenerate

  // Output buffering for the product
  generate
    for (i = 1; i <= OUTPUT_BUFFERS; i++) begin : g_out_buffer
      always_ff @(posedge clk) begin
        if (clken) p_reg[i] <= p_reg[i-1];
      end
    end
  endgenerate
  assign p = p_reg[1+OUTPUT_BUFFERS];


  always_ff @(posedge clk) begin
    if (clken) begin
      p_reg[0] <= a_reg[INPUT_BUFFERS-1] * b_reg[INPUT_BUFFERS-1];
      p_reg[1+OUTPUT_BUFFERS] <= p_reg[OUTPUT_BUFFERS] + ((SUBTRACT ? -c : c));
    end
  end

endmodule


module int_min #(
    parameter unsigned WIDTH = 16
) (
    input logic clk,
    input logic clken,
    input logic [WIDTH-1:0] a,
    input logic [WIDTH-1:0] b,
    output logic [WIDTH-1:0] res
);

  always_ff @(posedge clk) begin
    if (clken) begin
      res <= (a < b) ? a : b;
    end
  end

endmodule

module int_max #(
    parameter unsigned WIDTH = 16
) (
    input logic clk,
    input logic clken,
    input logic [WIDTH-1:0] a,
    input logic [WIDTH-1:0] b,
    output logic [WIDTH-1:0] res
);

  always_ff @(posedge clk) begin
    if (clken) begin
      res <= (a > b) ? a : b;
    end
  end

endmodule

module tri_bb_aligned_boundries #(
    parameter unsigned WIDTH = 16,
    parameter unsigned FRACTIONAL = 8
) (
    input logic clk,
    input logic clken,
    input logic signed [WIDTH-1:0] a,
    input logic signed [WIDTH-1:0] b,
    input logic signed [WIDTH-1:0] c,
    output logic signed [WIDTH-FRACTIONAL-1:0] min_val,
    output logic signed [WIDTH-FRACTIONAL-1:0] max_val
);
  // verilator lint_off UNUSEDSIGNAL
  logic signed [WIDTH-1:0] c_reg, min1, max1, min2, max2;
  // verilator lint_on UNUSEDSIGNAL

  always_ff @(posedge clk) begin
    if (clken) begin
      // Stage 1
      c_reg <= c;
      if (a <= b) begin
        min1 <= a;
        max1 <= b;
      end else begin
        min1 <= b;
        max1 <= a;
      end
      // Stage 2
      min2 <= (min1 <= c_reg) ? min1 : c_reg;
      max2 <= (max1 >= c_reg) ? max1 : c_reg;

    end
  end

  assign min_val = {min2[WIDTH-1:FRACTIONAL+1], 1'b0};  // unset LSB, floor + snap to even
  assign max_val = {max2[WIDTH-1:FRACTIONAL+1], 1'b1};  // set LSB, ceil + snap to odd

endmodule

