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

// 48-bit edge accumulator on one DSP48E2, fully pipelined (latency 4):
//   result = (load ? c : result) + AD * b
// where the pre-adder output AD is selected by inmode from a and d:
//   InmodeZero 0, InmodeA a, InmodeNegA -a, InmodeD d, InmodeAD d + a.
//
// a, d, b and inmode are registered with the pre-adder (A/D/B1/INMODE -> AD/B2 -> M -> P),
// c and load enter at the ALU stage, so they must be presented two clken cycles later than the
// operands they combine with. All registers share clken.
module orchestrator_alu (
    input logic clk,
    input logic clken,

    // Multiplier side, cycle t
    input logic signed [23:0] a,
    input logic signed [23:0] d,
    input logic signed [17:0] b,
    input logic        [ 4:0] inmode,

    // ALU side, cycle t + 2
    input logic signed [47:0] c,
    input logic               load,

    // Cycle t + 4
    output logic signed [47:0] result
);

  // OPMODE {W, Z, Y, X}: X = Y = M, W = 0, Z = C on load else P.
  localparam logic [8:0] OpmodeLoad = 9'b00_011_01_01, OpmodeStep = 9'b00_010_01_01;

`ifndef SIM_MODE
  DSP48E2 #(
      .AMULTSEL("AD"),
      .BMULTSEL("B"),
      .PREADDINSEL("A"),
      .USE_MULT("MULTIPLY"),
      .USE_SIMD("ONE48"),
      .USE_PATTERN_DETECT("NO_PATDET"),
      .A_INPUT("DIRECT"),
      .B_INPUT("DIRECT"),
      .AREG(1),
      .ACASCREG(1),
      .BREG(2),
      .BCASCREG(2),
      .DREG(1),
      .ADREG(1),
      .INMODEREG(1),
      .MREG(1),
      .CREG(1),
      .OPMODEREG(1),
      .CARRYINSELREG(1),
      .ALUMODEREG(0),
      .CARRYINREG(0),
      .PREG(1)
  ) u_dsp (
      .CLK(clk),
      .A(30'(a)),
      .B(b),
      .C(c),
      .D(27'(d)),
      .INMODE(inmode),
      .OPMODE(load ? OpmodeLoad : OpmodeStep),
      .ALUMODE(4'b0000),
      .CARRYIN(1'b0),
      .CARRYINSEL(3'b000),
      .CEA1(1'b0),
      .CEA2(clken),
      .CEB1(clken),
      .CEB2(clken),
      .CEC(clken),
      .CED(clken),
      .CEAD(clken),
      .CEM(clken),
      .CEP(clken),
      .CEINMODE(clken),
      .CECTRL(clken),
      .CEALUMODE(1'b0),
      .CECARRYIN(1'b0),
      .RSTA(1'b0),
      .RSTB(1'b0),
      .RSTC(1'b0),
      .RSTD(1'b0),
      .RSTM(1'b0),
      .RSTP(1'b0),
      .RSTINMODE(1'b0),
      .RSTCTRL(1'b0),
      .RSTALUMODE(1'b0),
      .RSTALLCARRYIN(1'b0),
      .ACIN('0),
      .BCIN('0),
      .PCIN('0),
      .CARRYCASCIN(1'b0),
      .MULTSIGNIN(1'b0),
      .ACOUT(),
      .BCOUT(),
      .PCOUT(),
      .CARRYCASCOUT(),
      .MULTSIGNOUT(),
      .CARRYOUT(),
      .OVERFLOW(),
      .UNDERFLOW(),
      .PATTERNDETECT(),
      .PATTERNBDETECT(),
      .XOROUT(),
      .P(result)
  );
`else

  // Cycle-accurate model of the DSP48E2 configuration above.
  logic signed [26:0] a_q, d_q, ad_q, a_eff, d_eff;
  logic signed [17:0] b1_q, b2_q;
  logic [4:0] inmode_q;
  logic signed [44:0] m_q;
  logic signed [47:0] c_q;
  logic load_q;

  // INMODE[1] gates A, INMODE[2] enables D, INMODE[3] selects D - A; [0] and [4] stay 0 (A2, B2).
  assign a_eff = inmode_q[1] ? '0 : a_q;
  assign d_eff = inmode_q[2] ? d_q : '0;

  always_ff @(posedge clk) begin
    if (clken) begin
      a_q <= 27'(a);
      d_q <= 27'(d);
      inmode_q <= inmode;
      b1_q <= b;
      b2_q <= b1_q;
      ad_q <= inmode_q[3] ? d_eff - a_eff : d_eff + a_eff;
      m_q <= ad_q * b2_q;
      c_q <= c;
      load_q <= load;
      result <= (load_q ? c_q : result) + 48'(m_q);
    end
  end
`endif

endmodule
