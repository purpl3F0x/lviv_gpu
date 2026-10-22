// Generator : SpinalHDL v1.12.3    git head : 591e64062329e5e2e2b81f4d52422948053edb97
// Component : AxiTileDma
// Git hash  : d8b2fd7242cf24f2e3e1e9b9a50c54c449ebfc76

`timescale 1ns/1ps

module AxiTileDma (
  input  wire [6:0]    s_apb_PADDR,
  input  wire [0:0]    s_apb_PSEL,
  input  wire          s_apb_PENABLE,
  output wire          s_apb_PREADY,
  input  wire          s_apb_PWRITE,
  input  wire [31:0]   s_apb_PWDATA,
  output wire [31:0]   s_apb_PRDATA,
  output wire          s_apb_PSLVERROR,
  output wire          m_axi_awvalid,
  input  wire          m_axi_awready,
  output wire [31:0]   m_axi_awaddr,
  output wire [3:0]    m_axi_awid,
  output wire [3:0]    m_axi_awregion,
  output wire [7:0]    m_axi_awlen,
  output wire [2:0]    m_axi_awsize,
  output wire [1:0]    m_axi_awburst,
  output wire [0:0]    m_axi_awlock,
  output wire [3:0]    m_axi_awcache,
  output wire [3:0]    m_axi_awqos,
  output wire [2:0]    m_axi_awprot,
  output wire          m_axi_wvalid,
  input  wire          m_axi_wready,
  output wire [127:0]  m_axi_wdata,
  output wire [15:0]   m_axi_wstrb,
  output wire          m_axi_wlast,
  input  wire          m_axi_bvalid,
  output wire          m_axi_bready,
  input  wire [3:0]    m_axi_bid,
  input  wire [1:0]    m_axi_bresp,
  output wire          tile_ram_0_clk,
  output wire          tile_ram_0_rst,
  output wire          tile_ram_0_en,
  output wire [13:0]   tile_ram_0_addr,
  input  wire [63:0]   tile_ram_0_dout,
  output wire          tile_ram_1_clk,
  output wire          tile_ram_1_rst,
  output wire          tile_ram_1_en,
  output wire [13:0]   tile_ram_1_addr,
  input  wire [63:0]   tile_ram_1_dout,
  output wire          tile_ram_2_clk,
  output wire          tile_ram_2_rst,
  output wire          tile_ram_2_en,
  output wire [13:0]   tile_ram_2_addr,
  input  wire [63:0]   tile_ram_2_dout,
  output wire          tile_ram_3_clk,
  output wire          tile_ram_3_rst,
  output wire          tile_ram_3_en,
  output wire [13:0]   tile_ram_3_addr,
  input  wire [63:0]   tile_ram_3_dout,
  (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 irq INTERRUPT" , X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *) output wire          irq,
  (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 irq_done INTERRUPT" , X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *) output wire          irq_done,
  (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 irq_error INTERRUPT" , X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *) output wire          irq_error,
  (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 irq_frame_done INTERRUPT" , X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *) output wire          irq_frame_done,
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ram_clk CLK" , X_INTERFACE_PARAMETER = "ASSOCIATED_RESET ram_resetn" *) input  wire          ram_clk,
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 ram_resetn RST" , X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *) input  wire          ram_resetn,
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" , X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF m_axi, ASSOCIATED_RESET aresetn" *) input  wire          aclk,
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" , X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *) input  wire          aresetn
);
  localparam DmaState_IDLE = 2'd0;
  localparam DmaState_TRANSFER = 2'd1;
  localparam DmaState_ADVANCE_CALC_1 = 2'd2;
  localparam DmaState_ADVANCE_CALC_2 = 2'd3;

  wire                cdcFifo_io_pop_ready;
  wire                cdcFifo_io_push_ready;
  wire                cdcFifo_io_pop_valid;
  wire       [127:0]  cdcFifo_io_pop_payload;
  wire       [4:0]    cdcFifo_io_pushOccupancy;
  wire       [4:0]    cdcFifo_io_popOccupancy;
  wire                startTilePulseAxi_pulseCCByToggle_io_pulseOut;
  wire       [4:0]    _zz_wBeatIdx;
  wire       [38:0]   _zz_advTileHeightStride;
  wire       [15:0]   _zz_advIsLastInRow;
  wire       [15:0]   _zz_advIsLastInFrame;
  wire       [15:0]   _zz_advIsLastInFrame_1;
  wire       [31:0]   busif_bus_rdata;
  reg                 busif_reg_rderr;
  reg        [31:0]   busif_reg_rdata;
  wire                busif_askWrite;
  wire                busif_askRead;
  wire                busif_doWrite;
  wire                busif_doRead;
  reg                 dmaBusy;
  reg                 softResetPending;
  reg        [1:0]    brespVal;
  reg        [7:0]    curLineIdx;
  reg        [31:0]   cycleCounter;
  wire                read_hit_0x0000;
  wire                write_hit_0x0000;
  reg                 START;
  wire                when_RegBase_l328;
  reg                 RESET_POS;
  wire                when_RegBase_l328_1;
  reg                 SOFT_RESET;
  wire                when_RegBase_l328_2;
  wire                read_hit_0x0004;
  wire                write_hit_0x0004;
  wire                BUSY;
  wire       [1:0]    LAST_BRESP;
  wire                SOFT_RESET_PENDING;
  wire                read_hit_0x0008;
  wire                write_hit_0x0008;
  reg        [31:0]   BASE_ADDR_LOW;
  wire                read_hit_0x000c;
  wire                write_hit_0x000c;
  reg        [31:0]   BASE_ADDR_HIGH;
  wire                read_hit_0x0010;
  wire                write_hit_0x0010;
  reg        [31:0]   STRIDE;
  wire                read_hit_0x0014;
  wire                write_hit_0x0014;
  reg        [15:0]   TILES_X;
  wire                read_hit_0x0018;
  wire                write_hit_0x0018;
  reg        [15:0]   TILES_Y;
  wire                read_hit_0x001c;
  wire                write_hit_0x001c;
  reg        [15:0]   CUR_TILE_X;
  reg        [15:0]   CUR_TILE_Y;
  wire                read_hit_0x0020;
  wire                write_hit_0x0020;
  wire       [7:0]    CURRENT_LINE;
  wire                read_hit_0x0024;
  wire                write_hit_0x0024;
  wire       [31:0]   PERF_CYCLES;
  reg                 intrDone;
  reg                 intrError;
  reg                 intrFrameDone;
  wire                read_hit_0x0040;
  wire                write_hit_0x0040;
  wire                read_hit_0x0044;
  wire                write_hit_0x0044;
  wire                read_hit_0x0048;
  wire                write_hit_0x0048;
  wire                read_hit_0x004c;
  wire                write_hit_0x004c;
  reg                 done_raw;
  wire                when_RegBase_l229;
  wire                when_RegBase_l230;
  reg                 done_mask;
  wire                irqDoneStat;
  reg                 error_raw;
  wire                when_RegBase_l229_1;
  wire                when_RegBase_l230_1;
  reg                 error_mask;
  wire                irqErrorStat;
  reg                 frame_done_raw;
  wire                when_RegBase_l229_2;
  wire                when_RegBase_l230_2;
  reg                 frame_done_mask;
  wire                irqFrameDoneStat;
  wire                irqMerged;
  wire       [28:0]   _zz_busif_reg_rdata;
  wire       [31:0]   fullBaseAddr;
  reg        [31:0]   tileOriginAddr;
  reg        [31:0]   rowStartTileAddr;
  reg        [31:0]   shadowStride;
  reg        [15:0]   shadowTilesX;
  reg        [15:0]   shadowTilesY;
  reg                 startTilePulseAxi;
  reg        [12:0]   ramArea_ramReadsLeft;
  reg        [12:0]   ramArea_ramPushesLeft;
  reg        [10:0]   ramArea_ramAddrReg;
  reg        [10:0]   ramArea_ramRowBase;
  reg        [4:0]    ramArea_ramBeatX;
  reg                 ramArea_ramOddLine;
  reg                 ramArea_ramEnReg;
  reg                 ramArea_active;
  reg        [4:0]    ramArea_pushOccupancyReg;
  reg        [4:0]    ramArea_inFlight;
  reg                 ramArea_ramEnReg_delay_1;
  reg                 ramArea_ramEnReg_delay_2;
  reg                 ramArea_ramEnReg_delay_3;
  reg                 ramArea_ramEnReg_delay_4;
  reg                 ramArea_ramEnReg_delay_5;
  reg                 ramArea_ramEnReg_delay_6;
  reg                 ramArea_inFlightRetire;
  wire       [4:0]    ramArea_totalCommitted;
  wire                ramArea_hasRoom;
  wire                ramArea_nextCanRead;
  reg                 ramArea_ramEnReg_delay_1_1;
  reg                 ramArea_ramEnReg_delay_2_1;
  reg                 ramArea_ramEnReg_delay_3_1;
  reg                 ramArea_readValid;
  reg                 ramArea_ramOddLine_delay_1;
  reg                 ramArea_ramOddLine_delay_2;
  reg                 ramArea_ramOddLine_delay_3;
  reg                 ramArea_readOddLine;
  wire       [63:0]   ramArea_leftWord;
  wire       [63:0]   ramArea_rightWord;
  reg        [127:0]  ramArea_mergedWord;
  reg                 ramArea_mergedValid;
  reg        [127:0]  ramArea_mergedData;
  wire                when_AxiTileDma_l480;
  wire                when_AxiTileDma_l503;
  wire                when_AxiTileDma_l507;
  wire                when_AxiTileDma_l519;
  reg        [1:0]    state;
  reg        [31:0]   advTileHeightStride;
  reg        [31:0]   advStepRightAddr;
  reg                 advIsLastInRow;
  reg                 advIsLastInFrame;
  reg                 planActive;
  reg        [31:0]   planLineStart;
  reg        [31:0]   planAddr;
  reg        [0:0]    planBurstIdx;
  reg        [3:0]    outstandingBursts;
  wire                planLastBurstInLine;
  wire                planLastLine;
  reg                 awValidReg;
  reg        [31:0]   awAddrReg;
  wire                planLoad;
  wire       [31:0]   _zz_planLineStart;
  wire                awFire;
  reg        [3:0]    wCredits;
  reg        [4:0]    wBeatIdx;
  wire                wLast;
  wire                wFire;
  wire                wBurstDone;
  wire                when_AxiTileDma_l640;
  wire                when_AxiTileDma_l642;
  wire                bFire;
  wire                when_AxiTileDma_l653;
  wire                when_AxiTileDma_l655;
  wire                when_AxiTileDma_l660;
  wire                when_AxiTileDma_l677;
  wire       [31:0]   _zz_tileOriginAddr;
  wire                when_AxiTileDma_l685;
  wire                when_AxiTileDma_l720;
  wire       [31:0]   _zz_tileOriginAddr_1;
  wire       [31:0]   rawBits;
  `ifndef SYNTHESIS
  reg [111:0] state_string;
  `endif


  assign _zz_wBeatIdx = (wBeatIdx + 5'h01);
  assign _zz_advTileHeightStride = ({7'd0,shadowStride} <<< 3'd7);
  assign _zz_advIsLastInRow = (shadowTilesX - 16'h0001);
  assign _zz_advIsLastInFrame = (shadowTilesX - 16'h0001);
  assign _zz_advIsLastInFrame_1 = (shadowTilesY - 16'h0001);
  AxiTileDma_StreamFifoCC cdcFifo (
    .io_push_valid    (ramArea_mergedValid          ), //i
    .io_push_ready    (cdcFifo_io_push_ready        ), //o
    .io_push_payload  (ramArea_mergedData[127:0]    ), //i
    .io_pop_valid     (cdcFifo_io_pop_valid         ), //o
    .io_pop_ready     (cdcFifo_io_pop_ready         ), //i
    .io_pop_payload   (cdcFifo_io_pop_payload[127:0]), //o
    .io_pushOccupancy (cdcFifo_io_pushOccupancy[4:0]), //o
    .io_popOccupancy  (cdcFifo_io_popOccupancy[4:0] ), //o
    .ram_clk          (ram_clk                      ), //i
    .ram_resetn       (ram_resetn                   ), //i
    .aclk             (aclk                         )  //i
  );
  AxiTileDma_PulseCCByToggle startTilePulseAxi_pulseCCByToggle (
    .io_pulseIn  (startTilePulseAxi                            ), //i
    .io_pulseOut (startTilePulseAxi_pulseCCByToggle_io_pulseOut), //o
    .aclk        (aclk                                         ), //i
    .aresetn     (aresetn                                      ), //i
    .ram_clk     (ram_clk                                      )  //i
  );
  `ifndef SYNTHESIS
  always @(*) begin
    case(state)
      DmaState_IDLE : state_string = "IDLE          ";
      DmaState_TRANSFER : state_string = "TRANSFER      ";
      DmaState_ADVANCE_CALC_1 : state_string = "ADVANCE_CALC_1";
      DmaState_ADVANCE_CALC_2 : state_string = "ADVANCE_CALC_2";
      default : state_string = "??????????????";
    endcase
  end
  `endif

  assign tile_ram_0_clk = ram_clk;
  assign tile_ram_0_rst = (! ram_resetn);
  assign tile_ram_1_clk = ram_clk;
  assign tile_ram_1_rst = (! ram_resetn);
  assign tile_ram_2_clk = ram_clk;
  assign tile_ram_2_rst = (! ram_resetn);
  assign tile_ram_3_clk = ram_clk;
  assign tile_ram_3_rst = (! ram_resetn);
  assign s_apb_PREADY = 1'b1;
  assign s_apb_PRDATA = busif_bus_rdata;
  assign busif_askWrite = (s_apb_PSEL[0] && s_apb_PWRITE);
  assign busif_askRead = ((s_apb_PSEL[0] && (! s_apb_PWRITE)) && (! s_apb_PENABLE));
  assign busif_doWrite = ((busif_askWrite && s_apb_PENABLE) && s_apb_PREADY);
  assign busif_doRead = (((s_apb_PSEL[0] && (! s_apb_PWRITE)) && s_apb_PENABLE) && s_apb_PREADY);
  assign s_apb_PSLVERROR = busif_reg_rderr;
  assign read_hit_0x0000 = ((s_apb_PADDR == 7'h0) && busif_doRead);
  assign write_hit_0x0000 = ((s_apb_PADDR == 7'h0) && busif_doWrite);
  assign when_RegBase_l328 = (write_hit_0x0000 && s_apb_PWDATA[0]);
  assign when_RegBase_l328_1 = (write_hit_0x0000 && s_apb_PWDATA[1]);
  assign when_RegBase_l328_2 = (write_hit_0x0000 && s_apb_PWDATA[2]);
  assign read_hit_0x0004 = ((s_apb_PADDR == 7'h04) && busif_doRead);
  assign write_hit_0x0004 = ((s_apb_PADDR == 7'h04) && busif_doWrite);
  assign BUSY = dmaBusy;
  assign LAST_BRESP = brespVal;
  assign SOFT_RESET_PENDING = softResetPending;
  assign read_hit_0x0008 = ((s_apb_PADDR == 7'h08) && busif_doRead);
  assign write_hit_0x0008 = ((s_apb_PADDR == 7'h08) && busif_doWrite);
  assign read_hit_0x000c = ((s_apb_PADDR == 7'h0c) && busif_doRead);
  assign write_hit_0x000c = ((s_apb_PADDR == 7'h0c) && busif_doWrite);
  assign read_hit_0x0010 = ((s_apb_PADDR == 7'h10) && busif_doRead);
  assign write_hit_0x0010 = ((s_apb_PADDR == 7'h10) && busif_doWrite);
  assign read_hit_0x0014 = ((s_apb_PADDR == 7'h14) && busif_doRead);
  assign write_hit_0x0014 = ((s_apb_PADDR == 7'h14) && busif_doWrite);
  assign read_hit_0x0018 = ((s_apb_PADDR == 7'h18) && busif_doRead);
  assign write_hit_0x0018 = ((s_apb_PADDR == 7'h18) && busif_doWrite);
  assign read_hit_0x001c = ((s_apb_PADDR == 7'h1c) && busif_doRead);
  assign write_hit_0x001c = ((s_apb_PADDR == 7'h1c) && busif_doWrite);
  assign read_hit_0x0020 = ((s_apb_PADDR == 7'h20) && busif_doRead);
  assign write_hit_0x0020 = ((s_apb_PADDR == 7'h20) && busif_doWrite);
  assign CURRENT_LINE = curLineIdx;
  assign read_hit_0x0024 = ((s_apb_PADDR == 7'h24) && busif_doRead);
  assign write_hit_0x0024 = ((s_apb_PADDR == 7'h24) && busif_doWrite);
  assign PERF_CYCLES = cycleCounter;
  always @(*) begin
    intrDone = 1'b0;
    case(state)
      DmaState_IDLE : begin
      end
      DmaState_TRANSFER : begin
      end
      DmaState_ADVANCE_CALC_1 : begin
      end
      default : begin
        intrDone = 1'b1;
      end
    endcase
  end

  always @(*) begin
    intrError = 1'b0;
    if(bFire) begin
      if(when_AxiTileDma_l660) begin
        intrError = 1'b1;
      end
    end
  end

  always @(*) begin
    intrFrameDone = 1'b0;
    case(state)
      DmaState_IDLE : begin
      end
      DmaState_TRANSFER : begin
      end
      DmaState_ADVANCE_CALC_1 : begin
      end
      default : begin
        if(advIsLastInFrame) begin
          intrFrameDone = 1'b1;
        end
      end
    endcase
  end

  assign read_hit_0x0040 = ((s_apb_PADDR == 7'h40) && busif_doRead);
  assign write_hit_0x0040 = ((s_apb_PADDR == 7'h40) && busif_doWrite);
  assign read_hit_0x0044 = ((s_apb_PADDR == 7'h44) && busif_doRead);
  assign write_hit_0x0044 = ((s_apb_PADDR == 7'h44) && busif_doWrite);
  assign read_hit_0x0048 = ((s_apb_PADDR == 7'h48) && busif_doRead);
  assign write_hit_0x0048 = ((s_apb_PADDR == 7'h48) && busif_doWrite);
  assign read_hit_0x004c = ((s_apb_PADDR == 7'h4c) && busif_doRead);
  assign write_hit_0x004c = ((s_apb_PADDR == 7'h4c) && busif_doWrite);
  assign when_RegBase_l229 = s_apb_PWDATA[0];
  assign when_RegBase_l230 = s_apb_PWDATA[0];
  assign irqDoneStat = (done_raw && (! done_mask));
  assign when_RegBase_l229_1 = s_apb_PWDATA[1];
  assign when_RegBase_l230_1 = s_apb_PWDATA[1];
  assign irqErrorStat = (error_raw && (! error_mask));
  assign when_RegBase_l229_2 = s_apb_PWDATA[2];
  assign when_RegBase_l230_2 = s_apb_PWDATA[2];
  assign irqFrameDoneStat = (frame_done_raw && (! frame_done_mask));
  assign irqMerged = ((irqDoneStat || irqErrorStat) || irqFrameDoneStat);
  assign _zz_busif_reg_rdata = 29'h0;
  assign fullBaseAddr = {BASE_ADDR_LOW[31 : 12],12'h0};
  always @(*) begin
    startTilePulseAxi = 1'b0;
    case(state)
      DmaState_IDLE : begin
        if(!when_AxiTileDma_l677) begin
          if(when_AxiTileDma_l685) begin
            startTilePulseAxi = 1'b1;
          end
        end
      end
      DmaState_TRANSFER : begin
      end
      DmaState_ADVANCE_CALC_1 : begin
      end
      default : begin
      end
    endcase
  end

  assign ramArea_totalCommitted = (ramArea_pushOccupancyReg + ramArea_inFlight);
  assign ramArea_hasRoom = (ramArea_totalCommitted < 5'h08);
  assign ramArea_nextCanRead = ((ramArea_active && (13'h0 < ramArea_ramReadsLeft)) && ramArea_hasRoom);
  assign tile_ram_0_en = ramArea_active;
  assign tile_ram_0_addr = {ramArea_ramAddrReg,3'b000};
  assign tile_ram_1_en = ramArea_active;
  assign tile_ram_1_addr = {ramArea_ramAddrReg,3'b000};
  assign tile_ram_2_en = ramArea_active;
  assign tile_ram_2_addr = {ramArea_ramAddrReg,3'b000};
  assign tile_ram_3_en = ramArea_active;
  assign tile_ram_3_addr = {ramArea_ramAddrReg,3'b000};
  assign ramArea_leftWord = (ramArea_readOddLine ? tile_ram_2_dout : tile_ram_0_dout);
  assign ramArea_rightWord = (ramArea_readOddLine ? tile_ram_3_dout : tile_ram_1_dout);
  always @(*) begin
    ramArea_mergedWord[31 : 0] = ramArea_leftWord[31 : 0];
    ramArea_mergedWord[63 : 32] = ramArea_rightWord[31 : 0];
    ramArea_mergedWord[95 : 64] = ramArea_leftWord[63 : 32];
    ramArea_mergedWord[127 : 96] = ramArea_rightWord[63 : 32];
  end

  assign when_AxiTileDma_l480 = (ramArea_ramBeatX == 5'h1f);
  assign when_AxiTileDma_l503 = (ramArea_nextCanRead != ramArea_inFlightRetire);
  assign when_AxiTileDma_l507 = (5'h0 < ramArea_inFlight);
  assign when_AxiTileDma_l519 = (ramArea_active && (ramArea_ramPushesLeft == 13'h0));
  assign planLastBurstInLine = 1'b1;
  assign planLastLine = (curLineIdx == 8'h7f);
  assign planLoad = ((((state == DmaState_TRANSFER) && planActive) && (outstandingBursts < 4'b1000)) && ((! awValidReg) || m_axi_awready));
  assign _zz_planLineStart = (planLineStart + shadowStride);
  assign m_axi_awvalid = awValidReg;
  assign m_axi_awaddr = awAddrReg;
  assign m_axi_awlen = 8'h1f;
  assign m_axi_awsize = 3'b100;
  assign m_axi_awburst = 2'b01;
  assign m_axi_awid = 4'b0000;
  assign m_axi_awregion = 4'b0000;
  assign m_axi_awlock = 1'b0;
  assign m_axi_awcache = 4'b0011;
  assign m_axi_awprot = 3'b000;
  assign m_axi_awqos = 4'b0000;
  assign awFire = (m_axi_awvalid && m_axi_awready);
  assign wLast = (wBeatIdx == 5'h1f);
  assign wFire = (m_axi_wvalid && m_axi_wready);
  assign wBurstDone = (wFire && wLast);
  assign m_axi_wvalid = ((wCredits != 4'b0000) && cdcFifo_io_pop_valid);
  assign m_axi_wdata = cdcFifo_io_pop_payload;
  assign m_axi_wstrb = 16'hffff;
  assign m_axi_wlast = wLast;
  assign cdcFifo_io_pop_ready = ((wCredits != 4'b0000) && m_axi_wready);
  assign when_AxiTileDma_l640 = (awFire && (! wBurstDone));
  assign when_AxiTileDma_l642 = ((! awFire) && wBurstDone);
  assign m_axi_bready = 1'b1;
  assign bFire = (m_axi_bvalid && m_axi_bready);
  assign when_AxiTileDma_l653 = (planLoad && (! bFire));
  assign when_AxiTileDma_l655 = ((! planLoad) && bFire);
  assign when_AxiTileDma_l660 = ((m_axi_bresp == 2'b10) || (m_axi_bresp == 2'b11));
  assign when_AxiTileDma_l677 = (SOFT_RESET || softResetPending);
  assign _zz_tileOriginAddr = ((((CUR_TILE_X == 16'h0) && (CUR_TILE_Y == 16'h0)) || (tileOriginAddr == 32'h0)) ? fullBaseAddr : tileOriginAddr);
  assign when_AxiTileDma_l685 = (START && (! dmaBusy));
  assign when_AxiTileDma_l720 = ((! planActive) && (outstandingBursts == 4'b0000));
  assign _zz_tileOriginAddr_1 = (rowStartTileAddr + advTileHeightStride);
  assign rawBits = {_zz_busif_reg_rdata,{frame_done_raw,{error_raw,done_raw}}};
  assign irq = irqMerged;
  assign irq_done = rawBits[0];
  assign irq_error = rawBits[1];
  assign irq_frame_done = rawBits[2];
  assign busif_bus_rdata = busif_reg_rdata;
  always @(posedge aclk or negedge aresetn) begin
    if(!aresetn) begin
      busif_reg_rderr <= 1'b0;
      busif_reg_rdata <= 32'h0;
      dmaBusy <= 1'b0;
      softResetPending <= 1'b0;
      brespVal <= 2'b00;
      curLineIdx <= 8'h0;
      cycleCounter <= 32'h0;
      START <= 1'b0;
      RESET_POS <= 1'b0;
      SOFT_RESET <= 1'b0;
      BASE_ADDR_LOW <= 32'h0;
      BASE_ADDR_HIGH <= 32'h0;
      STRIDE <= 32'h0;
      TILES_X <= 16'h0001;
      TILES_Y <= 16'h0001;
      CUR_TILE_X <= 16'h0;
      CUR_TILE_Y <= 16'h0;
      done_raw <= 1'b0;
      done_mask <= 1'b0;
      error_raw <= 1'b0;
      error_mask <= 1'b0;
      frame_done_raw <= 1'b0;
      frame_done_mask <= 1'b0;
      tileOriginAddr <= 32'h0;
      rowStartTileAddr <= 32'h0;
      shadowStride <= 32'h0;
      shadowTilesX <= 16'h0001;
      shadowTilesY <= 16'h0001;
      state <= DmaState_IDLE;
      advTileHeightStride <= 32'h0;
      advStepRightAddr <= 32'h0;
      advIsLastInRow <= 1'b0;
      advIsLastInFrame <= 1'b0;
      planActive <= 1'b0;
      planLineStart <= 32'h0;
      planAddr <= 32'h0;
      planBurstIdx <= 1'b0;
      outstandingBursts <= 4'b0000;
      awValidReg <= 1'b0;
      awAddrReg <= 32'h0;
      wCredits <= 4'b0000;
      wBeatIdx <= 5'h0;
    end else begin
      if(when_RegBase_l328) begin
        START <= (! START);
      end else begin
        START <= 1'b0;
      end
      if(when_RegBase_l328_1) begin
        RESET_POS <= (! RESET_POS);
      end else begin
        RESET_POS <= 1'b0;
      end
      if(when_RegBase_l328_2) begin
        SOFT_RESET <= (! SOFT_RESET);
      end else begin
        SOFT_RESET <= 1'b0;
      end
      if(write_hit_0x0008) begin
        BASE_ADDR_LOW <= s_apb_PWDATA[31 : 0];
      end
      if(write_hit_0x000c) begin
        BASE_ADDR_HIGH <= s_apb_PWDATA[31 : 0];
      end
      if(write_hit_0x0010) begin
        STRIDE <= s_apb_PWDATA[31 : 0];
      end
      if(write_hit_0x0014) begin
        TILES_X <= s_apb_PWDATA[15 : 0];
      end
      if(write_hit_0x0018) begin
        TILES_Y <= s_apb_PWDATA[15 : 0];
      end
      if(write_hit_0x001c) begin
        CUR_TILE_X <= s_apb_PWDATA[15 : 0];
      end
      if(write_hit_0x001c) begin
        CUR_TILE_Y <= s_apb_PWDATA[31 : 16];
      end
      if(write_hit_0x0040) begin
        if(when_RegBase_l229) begin
          done_raw <= 1'b0;
        end
      end
      if(write_hit_0x0044) begin
        if(when_RegBase_l230) begin
          done_raw <= 1'b1;
        end
      end
      if(write_hit_0x0048) begin
        done_mask <= s_apb_PWDATA[0];
      end
      if(intrDone) begin
        done_raw <= 1'b1;
      end
      if(write_hit_0x0040) begin
        if(when_RegBase_l229_1) begin
          error_raw <= 1'b0;
        end
      end
      if(write_hit_0x0044) begin
        if(when_RegBase_l230_1) begin
          error_raw <= 1'b1;
        end
      end
      if(write_hit_0x0048) begin
        error_mask <= s_apb_PWDATA[1];
      end
      if(intrError) begin
        error_raw <= 1'b1;
      end
      if(write_hit_0x0040) begin
        if(when_RegBase_l229_2) begin
          frame_done_raw <= 1'b0;
        end
      end
      if(write_hit_0x0044) begin
        if(when_RegBase_l230_2) begin
          frame_done_raw <= 1'b1;
        end
      end
      if(write_hit_0x0048) begin
        frame_done_mask <= s_apb_PWDATA[2];
      end
      if(intrFrameDone) begin
        frame_done_raw <= 1'b1;
      end
      if(RESET_POS) begin
        CUR_TILE_X <= 16'h0;
        CUR_TILE_Y <= 16'h0;
        tileOriginAddr <= fullBaseAddr;
        rowStartTileAddr <= fullBaseAddr;
      end
      if(dmaBusy) begin
        cycleCounter <= (cycleCounter + 32'h00000001);
      end
      if(planLoad) begin
        awValidReg <= 1'b1;
        awAddrReg <= planAddr;
        if(planLastBurstInLine) begin
          planBurstIdx <= 1'b0;
          if(planLastLine) begin
            planActive <= 1'b0;
          end else begin
            planLineStart <= _zz_planLineStart;
            planAddr <= _zz_planLineStart;
            curLineIdx <= (curLineIdx + 8'h01);
          end
        end else begin
          planBurstIdx <= (planBurstIdx + 1'b1);
          planAddr <= (planAddr + 32'h00000200);
        end
      end else begin
        if(m_axi_awready) begin
          awValidReg <= 1'b0;
        end
      end
      if(wFire) begin
        wBeatIdx <= (wLast ? 5'h0 : _zz_wBeatIdx);
      end
      if(when_AxiTileDma_l640) begin
        wCredits <= (wCredits + 4'b0001);
      end else begin
        if(when_AxiTileDma_l642) begin
          wCredits <= (wCredits - 4'b0001);
        end
      end
      if(when_AxiTileDma_l653) begin
        outstandingBursts <= (outstandingBursts + 4'b0001);
      end else begin
        if(when_AxiTileDma_l655) begin
          outstandingBursts <= (outstandingBursts - 4'b0001);
        end
      end
      if(bFire) begin
        if(when_AxiTileDma_l660) begin
          brespVal <= m_axi_bresp;
        end
      end
      if(SOFT_RESET) begin
        softResetPending <= 1'b1;
      end
      case(state)
        DmaState_IDLE : begin
          if(when_AxiTileDma_l677) begin
            softResetPending <= 1'b0;
            tileOriginAddr <= 32'h0;
            rowStartTileAddr <= 32'h0;
            CUR_TILE_X <= 16'h0;
            CUR_TILE_Y <= 16'h0;
          end else begin
            if(when_AxiTileDma_l685) begin
              dmaBusy <= 1'b1;
              cycleCounter <= 32'h0;
              shadowStride <= {STRIDE[31 : 9],9'h0};
              shadowTilesX <= ((TILES_X == 16'h0) ? 16'h0001 : TILES_X);
              shadowTilesY <= ((TILES_Y == 16'h0) ? 16'h0001 : TILES_Y);
              tileOriginAddr <= _zz_tileOriginAddr;
              rowStartTileAddr <= ((CUR_TILE_X == 16'h0) ? _zz_tileOriginAddr : rowStartTileAddr);
              planLineStart <= _zz_tileOriginAddr;
              planAddr <= _zz_tileOriginAddr;
              curLineIdx <= 8'h0;
              planBurstIdx <= 1'b0;
              planActive <= 1'b1;
              state <= DmaState_TRANSFER;
            end
          end
        end
        DmaState_TRANSFER : begin
          if(when_AxiTileDma_l720) begin
            state <= DmaState_ADVANCE_CALC_1;
          end
        end
        DmaState_ADVANCE_CALC_1 : begin
          advTileHeightStride <= _zz_advTileHeightStride[31:0];
          advStepRightAddr <= (tileOriginAddr + 32'h00000200);
          advIsLastInRow <= (CUR_TILE_X == _zz_advIsLastInRow);
          advIsLastInFrame <= ((CUR_TILE_X == _zz_advIsLastInFrame) && (CUR_TILE_Y == _zz_advIsLastInFrame_1));
          state <= DmaState_ADVANCE_CALC_2;
        end
        default : begin
          if(advIsLastInFrame) begin
            CUR_TILE_X <= 16'h0;
            CUR_TILE_Y <= 16'h0;
            tileOriginAddr <= fullBaseAddr;
            rowStartTileAddr <= fullBaseAddr;
          end else begin
            if(advIsLastInRow) begin
              CUR_TILE_X <= 16'h0;
              CUR_TILE_Y <= (CUR_TILE_Y + 16'h0001);
              rowStartTileAddr <= _zz_tileOriginAddr_1;
              tileOriginAddr <= _zz_tileOriginAddr_1;
            end else begin
              CUR_TILE_X <= (CUR_TILE_X + 16'h0001);
              tileOriginAddr <= advStepRightAddr;
            end
          end
          dmaBusy <= 1'b0;
          state <= DmaState_IDLE;
        end
      endcase
      if(busif_askRead) begin
        case(s_apb_PADDR)
          7'h0 : begin
            busif_reg_rdata <= {29'h0,{SOFT_RESET,{RESET_POS,START}}};
            busif_reg_rderr <= 1'b0;
          end
          7'h04 : begin
            busif_reg_rdata <= {28'h0,{SOFT_RESET_PENDING,{LAST_BRESP,BUSY}}};
            busif_reg_rderr <= 1'b0;
          end
          7'h08 : begin
            busif_reg_rdata <= BASE_ADDR_LOW;
            busif_reg_rderr <= 1'b0;
          end
          7'h0c : begin
            busif_reg_rdata <= BASE_ADDR_HIGH;
            busif_reg_rderr <= 1'b0;
          end
          7'h10 : begin
            busif_reg_rdata <= STRIDE;
            busif_reg_rderr <= 1'b0;
          end
          7'h14 : begin
            busif_reg_rdata <= {16'h0,TILES_X};
            busif_reg_rderr <= 1'b0;
          end
          7'h18 : begin
            busif_reg_rdata <= {16'h0,TILES_Y};
            busif_reg_rderr <= 1'b0;
          end
          7'h1c : begin
            busif_reg_rdata <= {CUR_TILE_Y,CUR_TILE_X};
            busif_reg_rderr <= 1'b0;
          end
          7'h20 : begin
            busif_reg_rdata <= {24'h0,CURRENT_LINE};
            busif_reg_rderr <= 1'b0;
          end
          7'h24 : begin
            busif_reg_rdata <= PERF_CYCLES;
            busif_reg_rderr <= 1'b0;
          end
          7'h40 : begin
            busif_reg_rdata <= {_zz_busif_reg_rdata,{frame_done_raw,{error_raw,done_raw}}};
            busif_reg_rderr <= 1'b0;
          end
          7'h44 : begin
            busif_reg_rdata <= {29'h0,{frame_done_raw,{error_raw,done_raw}}};
            busif_reg_rderr <= 1'b0;
          end
          7'h48 : begin
            busif_reg_rdata <= {29'h0,{frame_done_mask,{error_mask,done_mask}}};
            busif_reg_rderr <= 1'b0;
          end
          7'h4c : begin
            busif_reg_rdata <= {29'h0,{irqFrameDoneStat,{irqErrorStat,irqDoneStat}}};
            busif_reg_rderr <= 1'b0;
          end
          default : begin
            busif_reg_rdata <= 32'h0;
            busif_reg_rderr <= ((|s_apb_PADDR[1 : 0]) ? 1'b1 : 1'b0);
          end
        endcase
      end else begin
        busif_reg_rdata <= 32'h0;
        busif_reg_rderr <= 1'b0;
      end
    end
  end

  always @(posedge ram_clk or negedge ram_resetn) begin
    if(!ram_resetn) begin
      ramArea_ramReadsLeft <= 13'h0;
      ramArea_ramPushesLeft <= 13'h0;
      ramArea_ramAddrReg <= 11'h0;
      ramArea_ramRowBase <= 11'h0;
      ramArea_ramBeatX <= 5'h0;
      ramArea_ramOddLine <= 1'b0;
      ramArea_ramEnReg <= 1'b0;
      ramArea_active <= 1'b0;
      ramArea_pushOccupancyReg <= 5'h0;
      ramArea_inFlight <= 5'h0;
      ramArea_ramEnReg_delay_1 <= 1'b0;
      ramArea_ramEnReg_delay_2 <= 1'b0;
      ramArea_ramEnReg_delay_3 <= 1'b0;
      ramArea_ramEnReg_delay_4 <= 1'b0;
      ramArea_ramEnReg_delay_5 <= 1'b0;
      ramArea_ramEnReg_delay_6 <= 1'b0;
      ramArea_inFlightRetire <= 1'b0;
      ramArea_ramEnReg_delay_1_1 <= 1'b0;
      ramArea_ramEnReg_delay_2_1 <= 1'b0;
      ramArea_ramEnReg_delay_3_1 <= 1'b0;
      ramArea_readValid <= 1'b0;
      ramArea_ramOddLine_delay_1 <= 1'b0;
      ramArea_ramOddLine_delay_2 <= 1'b0;
      ramArea_ramOddLine_delay_3 <= 1'b0;
      ramArea_readOddLine <= 1'b0;
      ramArea_mergedValid <= 1'b0;
    end else begin
      ramArea_pushOccupancyReg <= cdcFifo_io_pushOccupancy;
      ramArea_ramEnReg_delay_1 <= ramArea_ramEnReg;
      ramArea_ramEnReg_delay_2 <= ramArea_ramEnReg_delay_1;
      ramArea_ramEnReg_delay_3 <= ramArea_ramEnReg_delay_2;
      ramArea_ramEnReg_delay_4 <= ramArea_ramEnReg_delay_3;
      ramArea_ramEnReg_delay_5 <= ramArea_ramEnReg_delay_4;
      ramArea_ramEnReg_delay_6 <= ramArea_ramEnReg_delay_5;
      ramArea_inFlightRetire <= ramArea_ramEnReg_delay_6;
      ramArea_ramEnReg_delay_1_1 <= ramArea_ramEnReg;
      ramArea_ramEnReg_delay_2_1 <= ramArea_ramEnReg_delay_1_1;
      ramArea_ramEnReg_delay_3_1 <= ramArea_ramEnReg_delay_2_1;
      ramArea_readValid <= ramArea_ramEnReg_delay_3_1;
      ramArea_ramOddLine_delay_1 <= ramArea_ramOddLine;
      ramArea_ramOddLine_delay_2 <= ramArea_ramOddLine_delay_1;
      ramArea_ramOddLine_delay_3 <= ramArea_ramOddLine_delay_2;
      ramArea_readOddLine <= ramArea_ramOddLine_delay_3;
      ramArea_mergedValid <= ramArea_readValid;
      if(startTilePulseAxi_pulseCCByToggle_io_pulseOut) begin
        ramArea_ramReadsLeft <= 13'h1000;
        ramArea_ramPushesLeft <= 13'h1000;
        ramArea_ramAddrReg <= 11'h0;
        ramArea_ramRowBase <= 11'h0;
        ramArea_ramBeatX <= 5'h0;
        ramArea_ramOddLine <= 1'b0;
        ramArea_ramEnReg <= 1'b0;
        ramArea_inFlight <= 5'h0;
        ramArea_active <= 1'b1;
      end else begin
        ramArea_ramEnReg <= ramArea_nextCanRead;
        if(ramArea_ramEnReg) begin
          if(when_AxiTileDma_l480) begin
            ramArea_ramBeatX <= 5'h0;
            ramArea_ramOddLine <= (! ramArea_ramOddLine);
            if(ramArea_ramOddLine) begin
              ramArea_ramAddrReg <= (ramArea_ramAddrReg + 11'h001);
              ramArea_ramRowBase <= (ramArea_ramAddrReg + 11'h001);
            end else begin
              ramArea_ramAddrReg <= ramArea_ramRowBase;
            end
          end else begin
            ramArea_ramBeatX <= (ramArea_ramBeatX + 5'h01);
            ramArea_ramAddrReg <= (ramArea_ramAddrReg + 11'h001);
          end
        end
        if(ramArea_nextCanRead) begin
          ramArea_ramReadsLeft <= (ramArea_ramReadsLeft - 13'h0001);
        end
        if(when_AxiTileDma_l503) begin
          if(ramArea_nextCanRead) begin
            ramArea_inFlight <= (ramArea_inFlight + 5'h01);
          end else begin
            if(when_AxiTileDma_l507) begin
              ramArea_inFlight <= (ramArea_inFlight - 5'h01);
            end
          end
        end
        if(ramArea_mergedValid) begin
          ramArea_ramPushesLeft <= (ramArea_ramPushesLeft - 13'h0001);
        end
        if(when_AxiTileDma_l519) begin
          ramArea_active <= 1'b0;
        end
      end
    end
  end

  always @(posedge ram_clk) begin
    ramArea_mergedData <= ramArea_mergedWord;
  end


endmodule

module AxiTileDma_PulseCCByToggle (
  input  wire          io_pulseIn,
  output wire          io_pulseOut,
  input  wire          aclk,
  input  wire          aresetn,
  input  wire          ram_clk
);

  wire                aresetn_asyncAssertSyncDeassert_buffercc_io_dataOut;
  wire                inArea_target_buffercc_io_dataOut;
  (* altera_attribute = "-name ADV_NETLIST_OPT_ALLOWED NEVER_ALLOW" *) reg                 inArea_target;
  wire                aresetn_asyncAssertSyncDeassert;
  wire                aresetn_synchronized;
  wire                outArea_target;
  reg                 outArea_target_regNext;

  (* keep_hierarchy = "TRUE" *) AxiTileDma_BufferCC_3 aresetn_asyncAssertSyncDeassert_buffercc (
    .io_dataIn  (aresetn_asyncAssertSyncDeassert                    ), //i
    .io_dataOut (aresetn_asyncAssertSyncDeassert_buffercc_io_dataOut), //o
    .ram_clk    (ram_clk                                            ), //i
    .aresetn    (aresetn                                            )  //i
  );
  (* keep_hierarchy = "TRUE" *) AxiTileDma_BufferCC_4 inArea_target_buffercc (
    .io_dataIn            (inArea_target                    ), //i
    .io_dataOut           (inArea_target_buffercc_io_dataOut), //o
    .ram_clk              (ram_clk                          ), //i
    .aresetn_synchronized (aresetn_synchronized             )  //i
  );
  assign aresetn_asyncAssertSyncDeassert = (1'b1 ^ 1'b0);
  assign aresetn_synchronized = aresetn_asyncAssertSyncDeassert_buffercc_io_dataOut;
  assign outArea_target = inArea_target_buffercc_io_dataOut;
  assign io_pulseOut = (outArea_target ^ outArea_target_regNext);
  always @(posedge aclk or negedge aresetn) begin
    if(!aresetn) begin
      inArea_target <= 1'b0;
    end else begin
      if(io_pulseIn) begin
        inArea_target <= (! inArea_target);
      end
    end
  end

  always @(posedge ram_clk or negedge aresetn_synchronized) begin
    if(!aresetn_synchronized) begin
      outArea_target_regNext <= 1'b0;
    end else begin
      outArea_target_regNext <= outArea_target;
    end
  end


endmodule

module AxiTileDma_StreamFifoCC (
  input  wire          io_push_valid,
  output wire          io_push_ready,
  input  wire [127:0]  io_push_payload,
  output wire          io_pop_valid,
  input  wire          io_pop_ready,
  output wire [127:0]  io_pop_payload,
  output wire [4:0]    io_pushOccupancy,
  output wire [4:0]    io_popOccupancy,
  input  wire          ram_clk,
  input  wire          ram_resetn,
  input  wire          aclk
);

  reg        [127:0]  ram_spinal_port1;
  wire       [4:0]    popToPushGray_buffercc_io_dataOut;
  wire                ram_resetn_asyncAssertSyncDeassert_buffercc_io_dataOut;
  wire       [4:0]    pushToPopGray_buffercc_io_dataOut;
  wire       [4:0]    _zz_pushCC_pushPtrGray;
  wire       [3:0]    _zz_ram_port;
  wire       [4:0]    _zz_popCC_popPtrGray;
  reg                 _zz_1;
  wire       [4:0]    popToPushGray;
  wire       [4:0]    pushToPopGray;
  reg        [4:0]    pushCC_pushPtr;
  wire       [4:0]    pushCC_pushPtrPlus;
  wire                io_push_fire;
  (* altera_attribute = "-name ADV_NETLIST_OPT_ALLOWED NEVER_ALLOW" *) reg        [4:0]    pushCC_pushPtrGray;
  wire       [4:0]    pushCC_popPtrGray;
  wire                pushCC_full;
  wire                _zz_io_pushOccupancy;
  wire                _zz_io_pushOccupancy_1;
  wire                _zz_io_pushOccupancy_2;
  wire                _zz_io_pushOccupancy_3;
  wire                ram_resetn_asyncAssertSyncDeassert;
  wire                ram_resetn_synchronized;
  reg        [4:0]    popCC_popPtr;
  (* keep , syn_keep *) wire       [4:0]    popCC_popPtrPlus /* synthesis syn_keep = 1 */ ;
  wire       [4:0]    popCC_popPtrGray;
  wire       [4:0]    popCC_pushPtrGray;
  wire                popCC_addressGen_valid;
  reg                 popCC_addressGen_ready;
  wire       [3:0]    popCC_addressGen_payload;
  wire                popCC_empty;
  wire                popCC_addressGen_fire;
  wire                popCC_readArbitation_valid;
  wire                popCC_readArbitation_ready;
  wire       [3:0]    popCC_readArbitation_payload;
  reg                 popCC_addressGen_rValid;
  reg        [3:0]    popCC_addressGen_rData;
  wire                when_Stream_l477;
  wire                popCC_readPort_cmd_valid;
  wire       [3:0]    popCC_readPort_cmd_payload;
  wire       [127:0]  popCC_readPort_rsp;
  wire                popCC_addressGen_toFlowFire_valid;
  wire       [3:0]    popCC_addressGen_toFlowFire_payload;
  wire                popCC_readArbitation_translated_valid;
  wire                popCC_readArbitation_translated_ready;
  wire       [127:0]  popCC_readArbitation_translated_payload;
  wire                popCC_readArbitation_fire;
  (* altera_attribute = "-name ADV_NETLIST_OPT_ALLOWED NEVER_ALLOW" *) reg        [4:0]    popCC_ptrToPush;
  reg        [4:0]    popCC_ptrToOccupancy;
  wire                _zz_io_popOccupancy;
  wire                _zz_io_popOccupancy_1;
  wire                _zz_io_popOccupancy_2;
  wire                _zz_io_popOccupancy_3;
  (* ram_style = "distributed" *) reg [127:0] ram [0:15];

  assign _zz_pushCC_pushPtrGray = (pushCC_pushPtrPlus >>> 1'b1);
  assign _zz_ram_port = pushCC_pushPtr[3:0];
  assign _zz_popCC_popPtrGray = (popCC_popPtr >>> 1'b1);
  always @(posedge ram_clk) begin
    if(_zz_1) begin
      ram[_zz_ram_port] <= io_push_payload;
    end
  end

  always @(posedge aclk) begin
    if(popCC_readPort_cmd_valid) begin
      ram_spinal_port1 <= ram[popCC_readPort_cmd_payload];
    end
  end

  (* keep_hierarchy = "TRUE" *) AxiTileDma_BufferCC popToPushGray_buffercc (
    .io_dataIn  (popToPushGray[4:0]                    ), //i
    .io_dataOut (popToPushGray_buffercc_io_dataOut[4:0]), //o
    .ram_clk    (ram_clk                               ), //i
    .ram_resetn (ram_resetn                            )  //i
  );
  (* keep_hierarchy = "TRUE" *) AxiTileDma_BufferCC_1 ram_resetn_asyncAssertSyncDeassert_buffercc (
    .io_dataIn  (ram_resetn_asyncAssertSyncDeassert                    ), //i
    .io_dataOut (ram_resetn_asyncAssertSyncDeassert_buffercc_io_dataOut), //o
    .aclk       (aclk                                                  ), //i
    .ram_resetn (ram_resetn                                            )  //i
  );
  (* keep_hierarchy = "TRUE" *) AxiTileDma_BufferCC_2 pushToPopGray_buffercc (
    .io_dataIn               (pushToPopGray[4:0]                    ), //i
    .io_dataOut              (pushToPopGray_buffercc_io_dataOut[4:0]), //o
    .aclk                    (aclk                                  ), //i
    .ram_resetn_synchronized (ram_resetn_synchronized               )  //i
  );
  always @(*) begin
    _zz_1 = 1'b0;
    if(io_push_fire) begin
      _zz_1 = 1'b1;
    end
  end

  assign pushCC_pushPtrPlus = (pushCC_pushPtr + 5'h01);
  assign io_push_fire = (io_push_valid && io_push_ready);
  assign pushCC_popPtrGray = popToPushGray_buffercc_io_dataOut;
  assign pushCC_full = ((pushCC_pushPtrGray[4 : 3] == (~ pushCC_popPtrGray[4 : 3])) && (pushCC_pushPtrGray[2 : 0] == pushCC_popPtrGray[2 : 0]));
  assign io_push_ready = (! pushCC_full);
  assign _zz_io_pushOccupancy = (pushCC_popPtrGray[1] ^ _zz_io_pushOccupancy_1);
  assign _zz_io_pushOccupancy_1 = (pushCC_popPtrGray[2] ^ _zz_io_pushOccupancy_2);
  assign _zz_io_pushOccupancy_2 = (pushCC_popPtrGray[3] ^ _zz_io_pushOccupancy_3);
  assign _zz_io_pushOccupancy_3 = pushCC_popPtrGray[4];
  assign io_pushOccupancy = (pushCC_pushPtr - {_zz_io_pushOccupancy_3,{_zz_io_pushOccupancy_2,{_zz_io_pushOccupancy_1,{_zz_io_pushOccupancy,(pushCC_popPtrGray[0] ^ _zz_io_pushOccupancy)}}}});
  assign ram_resetn_asyncAssertSyncDeassert = (1'b1 ^ 1'b0);
  assign ram_resetn_synchronized = ram_resetn_asyncAssertSyncDeassert_buffercc_io_dataOut;
  assign popCC_popPtrPlus = (popCC_popPtr + 5'h01);
  assign popCC_popPtrGray = (_zz_popCC_popPtrGray ^ popCC_popPtr);
  assign popCC_pushPtrGray = pushToPopGray_buffercc_io_dataOut;
  assign popCC_empty = (popCC_popPtrGray == popCC_pushPtrGray);
  assign popCC_addressGen_valid = (! popCC_empty);
  assign popCC_addressGen_payload = popCC_popPtr[3:0];
  assign popCC_addressGen_fire = (popCC_addressGen_valid && popCC_addressGen_ready);
  always @(*) begin
    popCC_addressGen_ready = popCC_readArbitation_ready;
    if(when_Stream_l477) begin
      popCC_addressGen_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! popCC_readArbitation_valid);
  assign popCC_readArbitation_valid = popCC_addressGen_rValid;
  assign popCC_readArbitation_payload = popCC_addressGen_rData;
  assign popCC_readPort_rsp = ram_spinal_port1;
  assign popCC_addressGen_toFlowFire_valid = popCC_addressGen_fire;
  assign popCC_addressGen_toFlowFire_payload = popCC_addressGen_payload;
  assign popCC_readPort_cmd_valid = popCC_addressGen_toFlowFire_valid;
  assign popCC_readPort_cmd_payload = popCC_addressGen_toFlowFire_payload;
  assign popCC_readArbitation_translated_valid = popCC_readArbitation_valid;
  assign popCC_readArbitation_ready = popCC_readArbitation_translated_ready;
  assign popCC_readArbitation_translated_payload = popCC_readPort_rsp;
  assign io_pop_valid = popCC_readArbitation_translated_valid;
  assign popCC_readArbitation_translated_ready = io_pop_ready;
  assign io_pop_payload = popCC_readArbitation_translated_payload;
  assign popCC_readArbitation_fire = (popCC_readArbitation_valid && popCC_readArbitation_ready);
  assign _zz_io_popOccupancy = (popCC_pushPtrGray[1] ^ _zz_io_popOccupancy_1);
  assign _zz_io_popOccupancy_1 = (popCC_pushPtrGray[2] ^ _zz_io_popOccupancy_2);
  assign _zz_io_popOccupancy_2 = (popCC_pushPtrGray[3] ^ _zz_io_popOccupancy_3);
  assign _zz_io_popOccupancy_3 = popCC_pushPtrGray[4];
  assign io_popOccupancy = ({_zz_io_popOccupancy_3,{_zz_io_popOccupancy_2,{_zz_io_popOccupancy_1,{_zz_io_popOccupancy,(popCC_pushPtrGray[0] ^ _zz_io_popOccupancy)}}}} - popCC_ptrToOccupancy);
  assign pushToPopGray = pushCC_pushPtrGray;
  assign popToPushGray = popCC_ptrToPush;
  always @(posedge ram_clk or negedge ram_resetn) begin
    if(!ram_resetn) begin
      pushCC_pushPtr <= 5'h0;
      pushCC_pushPtrGray <= 5'h0;
    end else begin
      if(io_push_fire) begin
        pushCC_pushPtrGray <= (_zz_pushCC_pushPtrGray ^ pushCC_pushPtrPlus);
      end
      if(io_push_fire) begin
        pushCC_pushPtr <= pushCC_pushPtrPlus;
      end
    end
  end

  always @(posedge aclk or negedge ram_resetn_synchronized) begin
    if(!ram_resetn_synchronized) begin
      popCC_popPtr <= 5'h0;
      popCC_addressGen_rValid <= 1'b0;
      popCC_ptrToPush <= 5'h0;
      popCC_ptrToOccupancy <= 5'h0;
    end else begin
      if(popCC_addressGen_fire) begin
        popCC_popPtr <= popCC_popPtrPlus;
      end
      if(popCC_addressGen_ready) begin
        popCC_addressGen_rValid <= popCC_addressGen_valid;
      end
      if(popCC_readArbitation_fire) begin
        popCC_ptrToPush <= popCC_popPtrGray;
      end
      if(popCC_readArbitation_fire) begin
        popCC_ptrToOccupancy <= popCC_popPtr;
      end
    end
  end

  always @(posedge aclk) begin
    if(popCC_addressGen_ready) begin
      popCC_addressGen_rData <= popCC_addressGen_payload;
    end
  end


endmodule

module AxiTileDma_BufferCC_4 (
  input  wire          io_dataIn,
  output wire          io_dataOut,
  input  wire          ram_clk,
  input  wire          aresetn_synchronized
);

  (* async_reg = "true" , altera_attribute = "-name ADV_NETLIST_OPT_ALLOWED NEVER_ALLOW" *) reg                 buffers_0;
  (* async_reg = "true" *) reg                 buffers_1;

  assign io_dataOut = buffers_1;
  always @(posedge ram_clk or negedge aresetn_synchronized) begin
    if(!aresetn_synchronized) begin
      buffers_0 <= 1'b0;
      buffers_1 <= 1'b0;
    end else begin
      buffers_0 <= io_dataIn;
      buffers_1 <= buffers_0;
    end
  end


endmodule

module AxiTileDma_BufferCC_3 (
  input  wire          io_dataIn,
  output wire          io_dataOut,
  input  wire          ram_clk,
  input  wire          aresetn
);

  (* async_reg = "true" *) reg                 buffers_0;
  (* async_reg = "true" *) reg                 buffers_1;

  assign io_dataOut = buffers_1;
  always @(posedge ram_clk or negedge aresetn) begin
    if(!aresetn) begin
      buffers_0 <= 1'b0;
      buffers_1 <= 1'b0;
    end else begin
      buffers_0 <= io_dataIn;
      buffers_1 <= buffers_0;
    end
  end


endmodule

module AxiTileDma_BufferCC_2 (
  input  wire [4:0]    io_dataIn,
  output wire [4:0]    io_dataOut,
  input  wire          aclk,
  input  wire          ram_resetn_synchronized
);

  (* async_reg = "true" , altera_attribute = "-name ADV_NETLIST_OPT_ALLOWED NEVER_ALLOW" *) reg        [4:0]    buffers_0;
  (* async_reg = "true" *) reg        [4:0]    buffers_1;

  assign io_dataOut = buffers_1;
  always @(posedge aclk or negedge ram_resetn_synchronized) begin
    if(!ram_resetn_synchronized) begin
      buffers_0 <= 5'h0;
      buffers_1 <= 5'h0;
    end else begin
      buffers_0 <= io_dataIn;
      buffers_1 <= buffers_0;
    end
  end


endmodule

module AxiTileDma_BufferCC_1 (
  input  wire          io_dataIn,
  output wire          io_dataOut,
  input  wire          aclk,
  input  wire          ram_resetn
);

  (* async_reg = "true" *) reg                 buffers_0;
  (* async_reg = "true" *) reg                 buffers_1;

  assign io_dataOut = buffers_1;
  always @(posedge aclk or negedge ram_resetn) begin
    if(!ram_resetn) begin
      buffers_0 <= 1'b0;
      buffers_1 <= 1'b0;
    end else begin
      buffers_0 <= io_dataIn;
      buffers_1 <= buffers_0;
    end
  end


endmodule

module AxiTileDma_BufferCC (
  input  wire [4:0]    io_dataIn,
  output wire [4:0]    io_dataOut,
  input  wire          ram_clk,
  input  wire          ram_resetn
);

  (* async_reg = "true" , altera_attribute = "-name ADV_NETLIST_OPT_ALLOWED NEVER_ALLOW" *) reg        [4:0]    buffers_0;
  (* async_reg = "true" *) reg        [4:0]    buffers_1;

  assign io_dataOut = buffers_1;
  always @(posedge ram_clk or negedge ram_resetn) begin
    if(!ram_resetn) begin
      buffers_0 <= 5'h0;
      buffers_1 <= 5'h0;
    end else begin
      buffers_0 <= io_dataIn;
      buffers_1 <= buffers_0;
    end
  end


endmodule
