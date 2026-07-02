// AUTO-GENERATED FROM scripts/create_pipeline.py
// Paste sections into raster_frontend.sv (instantiations + CALC FSMs).

// ---- Unit input registers (one DFF per port) ----
logic [31:0] fp_add_1_a_reg;
logic [31:0] fp_add_1_b_reg;
logic [0:0] fp_add_1_valid_in_reg;
logic [31:0] fp_mul_1_a_reg;
logic [31:0] fp_mul_1_b_reg;
logic [0:0] fp_mul_1_valid_in_reg;

// ---- Pipeline output/intermediate registers ----
logic [31:0] fp_add_1_a_src_reg;
logic [31:0] iw0_reg;
logic [31:0] iw1___iw2_reg;
logic [31:0] tmp0;
logic [31:0] z_reg;

// ---------------- Unit Instantiations (ports tied to input regs) ----------------
logic [31:0] fp_add_1_res;
fp_add #(.LATENCY(8)) u_fp_add_1 (
    .aclk    (clk),
    .aresetn (rst_n),
    .aclken  (1'b1),
    .valid_in(fp_add_1_valid_in_reg),
    .a       (fp_add_1_a_reg),
    .b       (fp_add_1_b_reg),
    .result  (fp_add_1_res)
);

logic [31:0] fp_mul_1_res;
fp_mul #(.LATENCY(5)) u_fp_mul_1 (
    .aclk    (clk),
    .aresetn (rst_n),
    .aclken  (1'b1),
    .valid_in(fp_mul_1_valid_in_reg),
    .a       (fp_mul_1_a_reg),
    .b       (fp_mul_1_b_reg),
    .result  (fp_mul_1_res)
);

// ---------------- Sequential FSM (input setup @ N-1, output latch @ N+L) ----------------
always_ff @(posedge clk) begin
  if (!rst_n) begin
    fp_add_1_a_reg <= 32'b0;
    fp_add_1_b_reg <= 32'b0;
    fp_add_1_valid_in_reg <= 1'b0;
    fp_mul_1_a_reg <= 32'b0;
    fp_mul_1_b_reg <= 32'b0;
    fp_mul_1_valid_in_reg <= 1'b0;
    fp_add_1_a_src_reg <= 32'b0;
    iw0_reg <= 32'b0;
    iw1___iw2_reg <= 32'b0;
    tmp0 <= 32'b0;
    z_reg <= 32'b0;
  end else if (next_state == ST_CALC) begin
    // PRE-CALC: load input regs for operations firing at cycle 0
    fp_mul_1_a_reg <= Node_None;
    fp_mul_1_b_reg <= Node_None;
    fp_mul_1_valid_in_reg <= 1'b1;
  end else if (state == ST_CALC) begin
    case (cycle_cnt)
      8'd0: begin
        fp_mul_1_valid_in_reg <= 1'b0;
      end
      8'd5: begin
        fp_mul_1_a_reg <= iw0_reg;
        fp_mul_1_b_reg <= Node_None;
        fp_mul_1_valid_in_reg <= 1'b1;
        iw0_reg <= fp_mul_1_res;
      end
      8'd6: begin
        fp_mul_1_valid_in_reg <= 1'b0;
      end
      8'd11: begin
        fp_add_1_a_reg <= tmp0;
        fp_add_1_b_reg <= tmp0;
        fp_add_1_valid_in_reg <= 1'b1;
        tmp0 <= fp_mul_1_res;
      end
      8'd12: begin
        fp_add_1_valid_in_reg <= 1'b0;
      end
      8'd20: begin
        fp_add_1_a_reg <= fp_add_1_a_src_reg;
        fp_add_1_b_reg <= tmp0;
        fp_add_1_valid_in_reg <= 1'b1;
        fp_add_1_a_src_reg <= fp_add_1_res;
      end
      8'd21: begin
        fp_add_1_valid_in_reg <= 1'b0;
      end
      8'd29: begin
        z_reg <= fp_add_1_res;
      end
      default: ;
    endcase
  end
end
