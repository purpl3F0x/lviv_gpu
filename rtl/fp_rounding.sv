`timescale 1ns / 1ps


// Smallest odd integer >= x for IEEE-754 binary32.  Latency: 3 clocks.
//
//   exp <= 126 (|x| < 1, incl. +-0, denormals) : +1.0
//   exp == 127 (1 <= |x| < 2)                  : x<0 -> -1.0 ; x==1.0 -> 1.0 ; else 3.0
//   128 <= exp <= 150 (units bit in mantissa)  : see cases below
//   exp >= 151, Inf, NaN                       : pass through (no odd value exists in
//                                                this range; every finite value is even)
//
// With k = position of the units bit, I = integer part, U = units bit, f = any fraction:
//   x >= 0 :  U=0            -> I+1            (set the units bit)
//             U=1, f=0       -> I              (already odd)
//             U=1, f=1       -> I+2            (add 2^(k+1); if the integer part was all
//                                               ones the result is 2^(e+1)+1)
//   x <  0 :  U=1            -> -I             (already odd)
//             U=0            -> -(I-1)         (subtract 2^(k+1) from {exp,mant}; if the
//                                               integer part was a pure power of two the
//                                               borrow ripples into the exponent)
//
// Pipeline split (adder owns stage 3):
//   S1: mask decode, integer bits, units bit, partial reductions (3 bits per group)
//   S2: finish reductions, pick case, build the adder operands (base, b)
//   S3: one 31-bit add {exp,base} + b   (carry/borrow ripples into the exponent)
module fp_ceil_n_clamp_to_odd (
    input  logic        clk,
    input  logic        clken,
    input  logic        rst_n,  // unused: pure datapath, no reset needed
    input  logic [31:0] f_in,
    output logic [31:0] f_out
);

  // ---------------------------------------------------------------------------
  // Stage 1
  //   mid : 128 <= exp <= 150, e5 = exp[4:0] = exp-128, units bit k = 22-e5
  //   mu  : units bit + fraction   (bits [k:0])
  //   a_int: integer bits above the units bit (for exp >= 128 this is mant & ~mu;
  //          for exp >= 151 mu = 0, so it is the whole mantissa -> pass-through)
  //   pf  : partial "any fraction bit"      (fraction = mu >> 1)
  //   pz  : partial "a_int != 0"
  //   pa  : partial "all integer bits above the units bit are 1" (mant | mu all ones)
  //   exp == 127 is folded in: units bit is the implicit 1, so U=1, a_int=0,
  //   f = (mant != 0), and "all ones" is trivially true.
  // ---------------------------------------------------------------------------
  logic sign, hi, lt127, eq127, mid, u_bit;
  logic [4:0] e5;
  logic [22:0] mant, mu, mu_ao, fm, a_int, msh;
  logic [23:0] t_f, t_a, t_o;
  logic [7:0] pf, pz, pa;

  assign sign  = f_in[31];
  assign mant  = f_in[22:0];
  assign hi    = f_in[30];  // exp >= 128
  assign lt127 = ~f_in[30] & ~(&f_in[29:23]);  // exp <= 126
  assign eq127 = ~f_in[30] & (&f_in[29:23]);  // exp == 127
  assign mid   = f_in[30] & (f_in[29:23] <= 7'd22);
  assign e5    = f_in[27:23];

  assign mu    = mid ? (23'h7FFFFF >> e5) : 23'h0;
  assign mu_ao = eq127 ? 23'h7FFFFF : mu;
  assign fm    = eq127 ? 23'h7FFFFF : (mu >> 1);
  assign a_int = hi ? (mant & ~mu) : 23'h0;
  assign msh   = mant << e5;  // units bit lands on msh[22]
  assign u_bit = mid ? msh[22] : eq127;

  assign t_f   = {1'b0, mant & fm};
  assign t_a   = {1'b0, a_int};
  assign t_o   = {1'b1, mant | mu_ao};

  for (genvar g = 0; g < 8; g++) begin : g_red
    assign pf[g] = |t_f[3*g+:3];
    assign pz[g] = |t_a[3*g+:3];
    assign pa[g] = &t_o[3*g+:3];
  end

  logic s1_sign, s1_mid, s1_eq127, s1_u;
  logic [4:0] s1_e5;
  logic [7:0] s1_exp, s1_pf, s1_pz, s1_pa;
  logic [22:0] s1_a;

  always_ff @(posedge clk) begin
    if (clken) begin
      s1_sign  <= sign & ~lt127;  // |x| < 1 -> +1.0 for either sign
      s1_exp   <= lt127 ? 8'd127 : f_in[30:23];  // 1.0 = {127, 0}
      s1_e5    <= e5;
      s1_mid   <= mid;
      s1_eq127 <= eq127;
      s1_u     <= u_bit;
      s1_a     <= a_int;
      s1_pf    <= pf;
      s1_pz    <= pz;
      s1_pa    <= pa;
    end
  end

  // ---------------------------------------------------------------------------
  // Stage 2: case select -> adder operands
  //   co   : x>=0, U=1, f=1, integer part all ones  -> {exp+1, unit>>1}
  //   padd : x>=0, U=1, f=1, otherwise              -> add 2^(k+1)
  //   nb   : x<0,  U=0                              -> subtract 2^(k+1)
  //          (-2^(k+1) == ~mu in two's complement, so no negation needed)
  //   ug   : gate the units bit off for x<0, U=0, a_int==0 (borrow takes it all)
  // ---------------------------------------------------------------------------
  logic f_any, a_zero, all_ones, co, padd, nb, ug;
  logic [22:0] unit, uhalf, nmu, base, b22;
  logic [23:0] u2_24;

  assign f_any    = |s1_pf;
  assign a_zero   = ~|s1_pz;
  assign all_ones = &s1_pa;

  assign co       = ~s1_sign & s1_u & f_any & all_ones;
  assign padd     = ~s1_sign & s1_u & f_any & ~all_ones;
  assign nb       = s1_mid & s1_sign & ~s1_u;
  assign ug       = ~(nb & a_zero);

  assign unit     = s1_mid ? (23'h400000 >> s1_e5) : 23'h0;  // bit k
  assign uhalf    = s1_mid ? (23'h200000 >> s1_e5) : (s1_eq127 ? 23'h400000 : 23'h0);
  assign u2_24    = s1_mid ? (24'h800000 >> s1_e5) : 24'h0;  // bit k+1
  assign nmu      = s1_mid ? ~(23'h7FFFFF >> s1_e5) : 23'h0;

  assign base     = co ? uhalf : (s1_a | (ug ? unit : 23'h0));
  assign b22      = padd ? u2_24[22:0] : (nb ? nmu : 23'h0);  // padd never has bit 23 set

  logic s2_sign, s2_neg, s2_b23;
  logic [7:0] s2_exp;
  logic [22:0] s2_base, s2_b;

  always_ff @(posedge clk) begin
    if (clken) begin
      s2_sign <= s1_sign;
      s2_exp  <= s1_exp;
      s2_base <= base;
      s2_b    <= b22;
      s2_neg  <= nb;  // b[30:23] = all ones  (subtract)
      s2_b23  <= nb | co;  // b[23]: exponent +1 (co) or part of the subtract
    end
  end

  // ---------------------------------------------------------------------------
  // Stage 3: single add; carry/borrow from the mantissa ripples into the exponent
  // ---------------------------------------------------------------------------
  logic [30:0] b31;
  assign b31 = {{7{s2_neg}}, s2_b23, s2_b};

  always_ff @(posedge clk) begin
    if (clken) begin
      f_out <= {s2_sign, {s2_exp, s2_base} + b31};
    end
  end

endmodule

// 2*floor(x/2) for IEEE-754 binary32.  Latency: 3 clocks.
//
//   exp <= 127            : +x -> +0.0, -x -> -2.0   (-0.0 is treated as +0.0 -> +0.0)
//   128 <= exp <= 150     : clear units bit + fraction; if x < 0 and any of those
//                           bits were set, add 2 to the truncated magnitude
//   exp >= 151, Inf, NaN  : pass through unchanged
//
// Pipeline split (each stage is a few LUT levels; the adder owns stage 3):
//   S1: mask decode, truncate, partial sticky, fold the "small" case into exp/mant
//   S2: finish sticky -> round-up, decode one-hot increment, gate it with round-up
//   S3: one 31-bit add {exp,mant} + inc  (mantissa carry ripples into exponent)
module fp_floor_n_clamp_to_even (
    input  logic        clk,
    input  logic        clken,
    input  logic        rst_n,  // unused: pure datapath, no reset needed
    input  logic [31:0] f_in,
    output logic [31:0] f_out
);

  // ---------------------------------------------------------------------------
  // Stage 1
  //   low : exp <= 127           -> forced to {sign, 7'b0, 23'b0} => +0.0 / -2.0
  //   mid : 128 <= exp <= 150    -> units bit inside mantissa; exp[4:0] == exp-128
  //   Sticky (OR of the bits being discarded) is only half-reduced here:
  //   8 partial ORs of 3 bits each, finished in stage 2.
  // ---------------------------------------------------------------------------
  logic sign, low, mid;
  logic [22:0] mant, mask, trunc;
  logic [23:0] t;
  logic [7:0] ps, exp_f;

  assign sign  = f_in[31] & (|f_in[30:0]);  // -0.0 is treated as +0.0
  assign mant  = f_in[22:0];
  assign low   = ~f_in[30];
  assign mid   = f_in[30] && (f_in[29:23] <= 7'd22);
  assign mask  = mid ? (23'h7FFFFF >> f_in[27:23]) : 23'h0;  // units bit + fraction
  assign t     = {1'b0, mant & mask};  // bits that get discarded
  assign trunc = low ? 23'h0 : (mant & ~mask);

  always_comb begin
    for (int g = 0; g < 8; g++) begin
      ps[g] = |t[3*g+:3];
    end
  end

  // low case: exponent field becomes {sign, 0000000}; mantissa 0; no increment follows
  assign exp_f = low ? {sign, 7'd0} : f_in[30:23];

  logic s1_sign, s1_mid;
  logic [4:0] s1_e5;
  logic [7:0] s1_exp, s1_ps;
  logic [22:0] s1_trunc;

  always_ff @(posedge clk) begin
    if (clken) begin
      s1_sign  <= sign;
      s1_mid   <= mid;
      s1_e5    <= f_in[27:23];
      s1_exp   <= exp_f;
      s1_trunc <= trunc;
      s1_ps    <= ps;
    end
  end

  // ---------------------------------------------------------------------------
  // Stage 2
  //   round_up = negative & something was discarded (value was not already even)
  //   inc      = one-hot at the "2" bit just above the cleared region
  //              (== mask + 1; bit 23 lands on the exponent LSB)
  // ---------------------------------------------------------------------------
  logic round_up;
  logic [23:0] inc, inc_ru;

  assign round_up = s1_sign & (|s1_ps);
  assign inc      = s1_mid ? (24'h800000 >> s1_e5) : 24'h0;
  assign inc_ru   = round_up ? inc : 24'h0;

  logic        s2_sign;
  logic [ 7:0] s2_exp;
  logic [22:0] s2_trunc;
  logic [23:0] s2_inc;

  always_ff @(posedge clk) begin
    if (clken) begin
      s2_sign  <= s1_sign;
      s2_exp   <= s1_exp;
      s2_trunc <= s1_trunc;
      s2_inc   <= inc_ru;
    end
  end

  // ---------------------------------------------------------------------------
  // Stage 3: single add; truncated bits below inc are zero so this is just a
  //          carry chain starting at the "2" bit. Carry into exp is automatic.
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (clken) begin
      f_out <= {s2_sign, {s2_exp, s2_trunc} + 31'(s2_inc)};
    end
  end

endmodule
