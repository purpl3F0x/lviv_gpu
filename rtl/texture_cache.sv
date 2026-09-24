`timescale 1ns / 1ps


module texture_bram_asym #(
    parameter int WIDTHA     = 128,
    parameter int SIZEA      = 256,
    parameter int ADDRWIDTHA = 8,
    parameter int WIDTHB     = 32,
    parameter int SIZEB      = 1024,
    parameter int ADDRWIDTHB = 10
) (
    input logic                  clka,
    input logic                  weA,
    input logic                  enaA,
    input logic [ADDRWIDTHA-1:0] addrA,
    input logic [    WIDTHA-1:0] diA,

    input  logic                  clkb,
    input  logic                  enaB,
    input  logic [ADDRWIDTHB-1:0] addrB,
    output logic [    WIDTHB-1:0] doB
);
  // -----------------------------------------------------------------------------
  // Asymmetric BRAM: wide write port (AXI beat) + narrow read port (pixel word)
  // -----------------------------------------------------------------------------

  localparam int MaxSize = (SIZEA > SIZEB) ? SIZEA : SIZEB;
  localparam int MaxWidth = (WIDTHA > WIDTHB) ? WIDTHA : WIDTHB;
  localparam int MinWidth = (WIDTHA < WIDTHB) ? WIDTHA : WIDTHB;
  localparam int Ratio = MaxWidth / MinWidth;
  localparam int Log2Ratio = (Ratio > 1) ? $clog2(Ratio) : 1;

  (* ram_style = "block" *) logic [MinWidth-1:0] ram[MaxSize];

  logic [WIDTHB-1:0] readB;

  always_ff @(posedge clkb) begin
    if (enaB) begin
      readB <= ram[addrB];
    end

    doB <= readB;
  end

  always_ff @(posedge clka) begin : ramwrite
    int i;

    if (enaA && weA) begin
      for (i = 0; i < Ratio; i++) begin
        ram[{addrA, i[Log2Ratio-1:0]}] <= diA[(i+1)*MinWidth-1-:MinWidth];
      end
    end
  end

endmodule

module texture_cache_tags #(
    parameter int TAG_WIDTH = 48,
    parameter int NUM_LINES = 16,
    parameter int WAY_WIDTH = (NUM_LINES > 1) ? $clog2(NUM_LINES) : 1
) (
    input logic clk,
    input logic rst_n,
    input logic flush,

    input  logic                 lookup_en,
    input  logic [TAG_WIDTH-1:0] lookup_tag,
    output logic                 lookup_hit_found,
    output logic [WAY_WIDTH-1:0] lookup_hit_way,

    input logic                 clear_en,
    input logic [WAY_WIDTH-1:0] clear_way,

    input logic                 fill_en,
    input logic [WAY_WIDTH-1:0] fill_way,
    input logic [TAG_WIDTH-1:0] fill_tag
);
  // -----------------------------------------------------------------------------
  // Tag array for fully-associative lookup (parallel compare over all ways)
  // -----------------------------------------------------------------------------

  logic [TAG_WIDTH-1:0] tag_mem  [NUM_LINES];
  logic                 valid_mem[NUM_LINES];
  logic [NUM_LINES-1:0] hit_oh;

  generate
    for (genvar way = 0; way < NUM_LINES; way++) begin : gen_tag_hit
      assign hit_oh[way] = lookup_en && valid_mem[way] && (tag_mem[way] == lookup_tag);
    end
  endgenerate

  always_comb begin
    lookup_hit_found = |hit_oh;
    lookup_hit_way   = '0;

    for (int way = 0; way < NUM_LINES; way++) begin
      if (hit_oh[way]) begin
        lookup_hit_way = way[WAY_WIDTH-1:0];
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int way = 0; way < NUM_LINES; way++) begin
        tag_mem[way]   <= '0;
        valid_mem[way] <= 1'b0;
      end
    end else if (flush) begin
      for (int way = 0; way < NUM_LINES; way++) begin
        valid_mem[way] <= 1'b0;
      end
    end else begin
      if (clear_en) begin
        valid_mem[clear_way] <= 1'b0;
      end

      if (fill_en) begin
        tag_mem[fill_way]   <= fill_tag;
        valid_mem[fill_way] <= 1'b1;
      end
    end
  end

endmodule

module texture_cache #(
    parameter int ADDR_WIDTH           = 32,
  parameter int AXI_ADDR_WIDTH       = ((ADDR_WIDTH + 7) / 8) * 8,
    parameter int PIXEL_BITS           = 32,
    parameter int CACHE_LINES          = 32,
    parameter int LINE_PIXELS_X        = 8,
    parameter int LINE_PIXELS_Y        = 8,
    parameter int AXI_DATA_WIDTH       = 128,
    parameter bit ENABLE_PERF_COUNTERS = 1'b1
) (
    input logic clk,
    input logic rst_n,
    input logic flush,

    input  logic                  req_valid,
    output logic                  req_ready,
    input  logic [ADDR_WIDTH-1:0] req_addr,

    output logic                  resp_valid,
    output logic [PIXEL_BITS-1:0] resp_data,

    output logic [AXI_ADDR_WIDTH-1:0] m_axi_araddr,
    output logic [           7:0] m_axi_arlen,
    output logic [           2:0] m_axi_arsize,
    output logic [           1:0] m_axi_arburst,
    output logic                  m_axi_arvalid,
    input  logic                  m_axi_arready,

    input  logic [AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input  logic [               1:0] m_axi_rresp,
    input  logic                      m_axi_rvalid,
    output logic                      m_axi_rready,
    input  logic                      m_axi_rlast,

    output logic [31:0] perf_total_req,
    output logic [31:0] perf_hit_req,
    output logic [31:0] perf_miss_req,

    input  logic        perf_re,
    input  logic        perf_we,
    input  logic [ 2:0] perf_addr,
    input  logic [31:0] perf_wdata,
    output logic [31:0] perf_rdata,
    output logic        perf_rvalid
);
  // -----------------------------------------------------------------------------
  // Texture cache top
  // - Fully associative tags + shared asymmetric BRAM payload store
  // - 4-stage hit path: consume request -> compare tags -> BRAM read -> data out
  // - Miss path stalls new accepts and refills one line over AXI
  // -----------------------------------------------------------------------------

  localparam int PixelBytes = PIXEL_BITS / 8;
  localparam int LinePixels = LINE_PIXELS_X * LINE_PIXELS_Y;
  localparam int LineBytes = LinePixels * PixelBytes;
  localparam int LineOffsetBits = (LineBytes > 1) ? $clog2(LineBytes) : 1;
  localparam int PixelOffsetBits = (PixelBytes > 1) ? $clog2(PixelBytes) : 1;
  localparam int PixelIndexBits = LineOffsetBits - PixelOffsetBits;
  localparam int TagBits = ADDR_WIDTH - LineOffsetBits;
  localparam int WayBits = (CACHE_LINES > 1) ? $clog2(CACHE_LINES) : 1;
  localparam int AxiBytes = AXI_DATA_WIDTH / 8;
  localparam int BeatsPerLine = LineBytes / AxiBytes;
  localparam int BeatBits = (BeatsPerLine > 1) ? $clog2(BeatsPerLine) : 1;
  localparam int BramWriteBits = WayBits + BeatBits;
  localparam int BramReadBits = WayBits + PixelIndexBits;
  localparam int PlruBits = CACHE_LINES - 1;
  localparam int TotalWords = CACHE_LINES * LinePixels;
  localparam int TotalBeats = TotalWords / (AXI_DATA_WIDTH / PIXEL_BITS);
  localparam int AxiAddrPadBits = AXI_ADDR_WIDTH - ADDR_WIDTH;

  initial begin
    if (AXI_ADDR_WIDTH < ADDR_WIDTH || (AXI_ADDR_WIDTH % 8) != 0) begin
      $fatal(1, "AXI_ADDR_WIDTH must be an 8-bit multiple >= ADDR_WIDTH");
    end
  end

  typedef enum logic [1:0] {
    REFILL_IDLE,
    REFILL_AR,
    REFILL_R,
    REFILL_RESP
  } refill_state_t;

  logic          [      PlruBits-1:0] plru_tree;

  logic                               request_stage_valid;
  logic          [       TagBits-1:0] request_stage_tag;
  logic          [PixelIndexBits-1:0] request_stage_pixel_index;
  logic          [    ADDR_WIDTH-1:0] request_stage_line_base_addr;
  logic                               stage0_valid;
  logic          [       TagBits-1:0] stage0_tag;
  logic          [PixelIndexBits-1:0] stage0_pixel_index;
  logic          [    ADDR_WIDTH-1:0] stage0_line_base_addr;
  logic                               stage0_hit_found;
  logic          [       WayBits-1:0] stage0_hit_way;
  logic                               stage1_valid;
  logic                               stage2_valid;

  refill_state_t                      refill_state;
  logic          [       WayBits-1:0] refill_way;
  logic          [    ADDR_WIDTH-1:0] refill_base_addr;
  logic          [       TagBits-1:0] refill_tag;
  logic          [PixelIndexBits-1:0] refill_pixel_index;
  logic          [      BeatBits-1:0] refill_beat;

  logic                               tag_lookup_hit_found;
  logic          [       WayBits-1:0] tag_lookup_hit_way;
  logic          [  BramReadBits-1:0] cache_read_addr;
  logic                               cache_read_en;
  logic                               tag_clear_en;
  logic          [       WayBits-1:0] tag_clear_way;
  logic                               tag_fill_en;
  logic          [       WayBits-1:0] tag_fill_way;
  logic          [    ADDR_WIDTH-1:0] req_byte_addr;
  logic                               axi_rresp_error;
  logic                               req_accepted;
  logic                               lookup_fire;
  logic                               stage0_miss_active;
  logic          [              31:0] perf_total_req_q;
  logic          [              31:0] perf_hit_req_q;
  logic          [              31:0] perf_miss_req_q;
  logic          [              31:0] perf_rdata_q;
  logic                               perf_rvalid_q;

  localparam logic [2:0] PerfAddrTotal = 3'd0;
  localparam logic [2:0] PerfAddrHit   = 3'd1;
  localparam logic [2:0] PerfAddrMiss  = 3'd2;

  // Requests use one address per pixel word. AXI uses byte addresses.
  assign req_byte_addr = req_addr << PixelOffsetBits;
  assign req_accepted  = req_valid && req_ready;

  function automatic [TagBits-1:0] addr_tag(input logic [ADDR_WIDTH-1:0] addr);
    begin
      addr_tag = addr[ADDR_WIDTH-1-:TagBits];
    end
  endfunction

  function automatic [PixelIndexBits-1:0] addr_pixel_index(input logic [ADDR_WIDTH-1:0] addr);
    begin
      addr_pixel_index = addr[PixelOffsetBits+:PixelIndexBits];
    end
  endfunction

  function automatic [WayBits-1:0] select_victim(input logic [PlruBits-1:0] tree);
    int node;
    logic [WayBits-1:0] victim;
    begin
      node   = 0;
      victim = '0;
      for (int level = 0; level < WayBits; level++) begin
        victim[WayBits-1-level] = tree[node];
        if (tree[node] == 1'b0) begin
          node = (node << 1) + 1;
        end else begin
          node = (node << 1) + 2;
        end
      end
      select_victim = victim;
    end
  endfunction

  function automatic [PlruBits-1:0] update_plru(input logic [PlruBits-1:0] tree,
                                                input logic [WayBits-1:0] way);
    int node;
    logic [PlruBits-1:0] next_tree;
    begin
      next_tree = tree;
      node = 0;
      for (int level = 0; level < WayBits; level++) begin
        if (way[WayBits-1-level] == 1'b0) begin
          next_tree[node] = 1'b1;
          node = (node << 1) + 1;
        end else begin
          next_tree[node] = 1'b0;
          node = (node << 1) + 2;
        end
      end
      update_plru = next_tree;
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Combinational datapath:
  // - Drive BRAM read controls from registered stage0 hit info
  // - Track refill word for requested pixel index during AXI refill
  // ---------------------------------------------------------------------------
  always_comb begin
    cache_read_addr = {stage0_hit_way, stage0_pixel_index};
    cache_read_en   = 1'b0;

    if (stage0_valid && stage0_hit_found) begin
      cache_read_en = 1'b1;
    end

    if (refill_state == REFILL_RESP) begin
      cache_read_en   = !axi_rresp_error;
      cache_read_addr = {refill_way, refill_pixel_index};
    end
  end

  // External interface wiring and top-level flow-control.
  assign stage0_miss_active = stage0_valid && !stage0_hit_found;
  assign req_ready = !flush && (refill_state == REFILL_IDLE) && !stage0_miss_active;
  assign lookup_fire = request_stage_valid && (refill_state == REFILL_IDLE) && !stage0_miss_active;
  assign m_axi_araddr = {{AxiAddrPadBits{1'b0}}, refill_base_addr};
  assign m_axi_arlen = 8'(BeatsPerLine - 1);
  assign m_axi_arsize = 3'($clog2(AxiBytes));
  assign m_axi_arburst = 2'b01;
  assign m_axi_arvalid = (refill_state == REFILL_AR);
  assign m_axi_rready = (refill_state == REFILL_R);
  assign resp_valid = stage2_valid;
  assign perf_total_req = ENABLE_PERF_COUNTERS ? perf_total_req_q : '0;
  assign perf_hit_req = ENABLE_PERF_COUNTERS ? perf_hit_req_q : '0;
  assign perf_miss_req = ENABLE_PERF_COUNTERS ? perf_miss_req_q : '0;
  assign perf_rdata = ENABLE_PERF_COUNTERS ? perf_rdata_q : '0;
  assign perf_rvalid = ENABLE_PERF_COUNTERS ? perf_rvalid_q : 1'b0;

  // Tag store and lookup.
  texture_cache_tags #(
      .TAG_WIDTH(TagBits),
      .NUM_LINES(CACHE_LINES),
      .WAY_WIDTH(WayBits)
  ) u_cache_tags (
      .clk(clk),
      .rst_n(rst_n),
      .flush(flush),
      .lookup_en(request_stage_valid),
      .lookup_tag(request_stage_tag),
      .lookup_hit_found(tag_lookup_hit_found),
      .lookup_hit_way(tag_lookup_hit_way),
      .clear_en(tag_clear_en),
      .clear_way(tag_clear_way),
      .fill_en(tag_fill_en),
      .fill_way(tag_fill_way),
      .fill_tag(refill_tag)
  );

  // Shared payload store for all ways/lines.
  texture_bram_asym #(
      .WIDTHA(AXI_DATA_WIDTH),
      .SIZEA(TotalBeats),
      .ADDRWIDTHA(BramWriteBits),
      .WIDTHB(PIXEL_BITS),
      .SIZEB(TotalWords),
      .ADDRWIDTHB(BramReadBits)
  ) u_texture_bram (
      .clka (clk),
      .weA  ((refill_state == REFILL_R) && m_axi_rvalid && (m_axi_rresp == 2'b00)),
      .enaA ((refill_state == REFILL_R) && m_axi_rvalid && (m_axi_rresp == 2'b00)),
      .addrA({refill_way, refill_beat}),
      .diA  (m_axi_rdata),
      .clkb (clk),
      .enaB (cache_read_en),
      .addrB(cache_read_addr),
      .doB  (resp_data)
  );

  // ---------------------------------------------------------------------------
  // Sequential control:
  // - Stage registers for hit pipeline
  // - PLRU updates
  // - Miss/refill FSM
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      request_stage_valid <= 1'b0;
      request_stage_tag   <= '0;
      request_stage_pixel_index <= '0;
      request_stage_line_base_addr <= '0;
      stage0_valid       <= 1'b0;
      stage0_tag         <= '0;
      stage0_pixel_index <= '0;
      stage0_line_base_addr <= '0;
      stage0_hit_found   <= 1'b0;
      stage0_hit_way     <= '0;
      stage1_valid       <= 1'b0;
      stage2_valid       <= 1'b0;
      refill_state       <= REFILL_IDLE;
      refill_way         <= '0;
      refill_base_addr   <= '0;
      refill_tag         <= '0;
      refill_pixel_index <= '0;
      refill_beat        <= '0;
      axi_rresp_error    <= 1'b0;
      plru_tree          <= '0;
      perf_total_req_q   <= '0;
      perf_hit_req_q     <= '0;
      perf_miss_req_q    <= '0;
      perf_rdata_q       <= '0;
      perf_rvalid_q      <= 1'b0;

      tag_clear_en       <= 1'b0;
      tag_clear_way      <= '0;
      tag_fill_en        <= 1'b0;
      tag_fill_way       <= '0;
    end else begin
      stage1_valid    <= cache_read_en;
      stage2_valid    <= stage1_valid;
      tag_clear_en    <= 1'b0;
      tag_clear_way   <= '0;
      tag_fill_en     <= 1'b0;
      tag_fill_way    <= '0;
      perf_rvalid_q   <= 1'b0;

      if (flush) begin
        request_stage_valid <= 1'b0;
        request_stage_tag   <= '0;
        request_stage_pixel_index <= '0;
        request_stage_line_base_addr <= '0;
        stage0_valid       <= 1'b0;
        stage0_tag         <= '0;
        stage0_pixel_index <= '0;
        stage0_line_base_addr <= '0;
        stage0_hit_found   <= 1'b0;
        stage0_hit_way     <= '0;
        stage1_valid       <= 1'b0;
        stage2_valid       <= 1'b0;
        refill_state       <= REFILL_IDLE;
        refill_way         <= '0;
        refill_base_addr   <= '0;
        refill_tag         <= '0;
        refill_pixel_index <= '0;
        refill_beat        <= '0;
        axi_rresp_error    <= 1'b0;
        plru_tree          <= '0;
      end else begin
        if (ENABLE_PERF_COUNTERS) begin
          if (lookup_fire) begin
            perf_total_req_q <= perf_total_req_q + 1'b1;
            if (tag_lookup_hit_found) begin
              perf_hit_req_q <= perf_hit_req_q + 1'b1;
            end else begin
              perf_miss_req_q <= perf_miss_req_q + 1'b1;
            end
          end

          if (perf_re) begin
            perf_rvalid_q <= 1'b1;
            case (perf_addr)
              PerfAddrTotal: perf_rdata_q <= perf_total_req_q;
              PerfAddrHit:   perf_rdata_q <= perf_hit_req_q;
              PerfAddrMiss:  perf_rdata_q <= perf_miss_req_q;
              default:       perf_rdata_q <= 32'd0;
            endcase
          end

          if (perf_we) begin
            case (perf_addr)
              PerfAddrTotal: perf_total_req_q <= perf_wdata;
              PerfAddrHit:   perf_hit_req_q <= perf_wdata;
              PerfAddrMiss:  perf_miss_req_q <= perf_wdata;
              default: begin
              end
            endcase
          end
        end

        if (req_accepted) begin
          request_stage_valid <= 1'b1;
          request_stage_tag   <= addr_tag(req_byte_addr);
          request_stage_pixel_index <= addr_pixel_index(req_byte_addr);
          request_stage_line_base_addr <= {req_byte_addr[ADDR_WIDTH-1:LineOffsetBits], {LineOffsetBits{1'b0}}};
        end else if (lookup_fire) begin
          request_stage_valid <= 1'b0;
        end

        if (lookup_fire) begin
          // Stage0 captures lookup result; BRAM read happens in the next stage.
          stage0_valid     <= 1'b1;
          stage0_tag       <= request_stage_tag;
          stage0_pixel_index <= request_stage_pixel_index;
          stage0_line_base_addr <= request_stage_line_base_addr;
          stage0_hit_found <= tag_lookup_hit_found;
          stage0_hit_way   <= tag_lookup_hit_way;
        end else begin
          stage0_valid     <= 1'b0;
        end

        if (stage0_valid && stage0_hit_found) begin
          // Update PLRU on hit when stage0 request is consumed.
          plru_tree <= update_plru(plru_tree, stage0_hit_way);
        end

        if (stage0_valid && !stage0_hit_found && (refill_state == REFILL_IDLE)) begin
          // Start miss refill using captured stage0 address/tag context.
          refill_state <= REFILL_AR;
          refill_way <= select_victim(plru_tree);
          refill_base_addr <= stage0_line_base_addr;
          refill_tag <= stage0_tag;
          refill_pixel_index <= stage0_pixel_index;
          refill_beat <= '0;
          axi_rresp_error <= 1'b0;
          tag_clear_en <= 1'b1;
          tag_clear_way <= select_victim(plru_tree);
        end

        unique case (refill_state)
          REFILL_IDLE: begin
          end

          REFILL_AR: begin
            if (m_axi_arready) begin
              refill_state <= REFILL_R;
            end
          end

          REFILL_R: begin
            if (m_axi_rvalid) begin
              if (m_axi_rresp != 2'b00) begin
                axi_rresp_error <= 1'b1;
              end

              if (m_axi_rlast) begin
                if (!axi_rresp_error && (m_axi_rresp == 2'b00)) begin
                  tag_fill_en <= 1'b1;
                  tag_fill_way <= refill_way;
                  plru_tree <= update_plru(plru_tree, refill_way);
                end
                refill_state <= REFILL_RESP;
              end else begin
                refill_beat <= refill_beat + 1'b1;
              end
            end
          end

          REFILL_RESP: begin
            refill_state <= REFILL_IDLE;
          end
        endcase
      end
    end
  end

  // ! Sanity Checks
  initial begin
    if (CACHE_LINES < 2 || ((CACHE_LINES & (CACHE_LINES - 1)) != 0)) begin
      $fatal(1, "CACHE_LINES must be a power of two and at least 2 for tree PLRU");
    end

    if (PIXEL_BITS % 8 != 0) begin
      $fatal(1, "PIXEL_BITS must be byte aligned");
    end

    if (AXI_DATA_WIDTH % PIXEL_BITS != 0) begin
      $fatal(1, "AXI_DATA_WIDTH must be a multiple of PIXEL_BITS");
    end

    if (LineBytes % AxiBytes != 0) begin
      $fatal(1, "Cache line size must be an integer number of AXI beats");
    end
  end

endmodule

