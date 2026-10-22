// Generator : SpinalHDL v1.12.3    git head : 591e64062329e5e2e2b81f4d52422948053edb97
// Component : AxiVisibilityDma
// Git hash  : 0867eb45c9a7627edf7c710aa90817a6ac31f5e6

`timescale 1ns/1ps

module AxiVisibilityDma (
  input  wire [6:0]    s_apb_PADDR,
  input  wire [0:0]    s_apb_PSEL,
  input  wire          s_apb_PENABLE,
  output wire          s_apb_PREADY,
  input  wire          s_apb_PWRITE,
  input  wire [31:0]   s_apb_PWDATA,
  output wire [31:0]   s_apb_PRDATA,
  output wire          s_apb_PSLVERROR,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_vb ARVALID" , X_INTERFACE_PARAMETER = "NUM_READ_OUTSTANDING 8, READ_WRITE_MODE READ_ONLY" *) output wire          m_axi_vb_arvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_vb ARREADY" *) input  wire          m_axi_vb_arready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_vb ARADDR" *) output wire [31:0]   m_axi_vb_araddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_vb ARID" *) output wire [3:0]    m_axi_vb_arid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_vb ARREGION" *) output wire [3:0]    m_axi_vb_arregion,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_vb ARLEN" *) output wire [7:0]    m_axi_vb_arlen,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_vb ARSIZE" *) output wire [2:0]    m_axi_vb_arsize,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_vb ARBURST" *) output wire [1:0]    m_axi_vb_arburst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_vb ARLOCK" *) output wire [0:0]    m_axi_vb_arlock,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_vb ARCACHE" *) output wire [3:0]    m_axi_vb_arcache,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_vb ARQOS" *) output wire [3:0]    m_axi_vb_arqos,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_vb ARPROT" *) output wire [2:0]    m_axi_vb_arprot,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_vb RVALID" *) input  wire          m_axi_vb_rvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_vb RREADY" *) output reg           m_axi_vb_rready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_vb RDATA" *) input  wire [127:0]  m_axi_vb_rdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_vb RID" *) input  wire [3:0]    m_axi_vb_rid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_vb RRESP" *) input  wire [1:0]    m_axi_vb_rresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_vb RLAST" *) input  wire          m_axi_vb_rlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis_datamover_cmd TVALID" *) output wire          m_axis_datamover_cmd_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis_datamover_cmd TREADY" *) input  wire          m_axis_datamover_cmd_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis_datamover_cmd TDATA" *) output wire [71:0]   m_axis_datamover_cmd_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis_datamover_sts TVALID" *) input  wire          s_axis_datamover_sts_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis_datamover_sts TREADY" *) output wire          s_axis_datamover_sts_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis_datamover_sts TDATA" *) input  wire [7:0]    s_axis_datamover_sts_tdata,
  output wire          ready,
  (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 irq INTERRUPT" , X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *) output wire          irq,
  (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 irq_done INTERRUPT" , X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *) output wire          irq_done,
  (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 irq_error INTERRUPT" , X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *) output wire          irq_error,
  (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 irq_frame_done INTERRUPT" , X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *) output wire          irq_frame_done,
  input  wire          aclk,
  input  wire          aresetn
);
  localparam FilterState_IDLE = 3'd0;
  localparam FilterState_FILTER_STREAM = 3'd1;
  localparam FilterState_FLUSH_STALL = 3'd2;
  localparam FilterState_WAIT_RETIRE = 3'd3;
  localparam FilterState_ADVANCE_TILE = 3'd4;

  reg                 vbFifo_io_pop_ready;
  wire                streamFifo_1_io_pop_ready;
  wire                vbFifo_io_push_ready;
  wire                vbFifo_io_pop_valid;
  wire       [1:0]    vbFifo_io_pop_payload;
  wire       [9:0]    vbFifo_io_occupancy;
  wire       [9:0]    vbFifo_io_availability;
  wire                streamFifo_io_push_ready;
  wire                streamFifo_io_pop_valid;
  wire       [26:0]   streamFifo_io_pop_payload_triWordAddr;
  wire       [16:0]   streamFifo_io_pop_payload_triCount;
  wire       [3:0]    streamFifo_io_pop_payload_tag;
  wire       [6:0]    streamFifo_io_occupancy;
  wire       [6:0]    streamFifo_io_availability;
  wire                streamFifo_1_io_push_ready;
  wire                streamFifo_1_io_pop_valid;
  wire       [7:0]    streamFifo_1_io_pop_payload;
  wire       [2:0]    streamFifo_1_io_occupancy;
  wire       [2:0]    streamFifo_1_io_availability;
  wire       [5:0]    _zz_visBitsIn;
  wire       [6:0]    _zz_visBitsIn_1;
  wire       [6:0]    _zz_visBitsIn_2;
  wire       [12:0]   _zz_bytesTo4KbBoundary;
  wire       [11:0]   _zz_bytesTo4KbBoundary_1;
  wire       [8:0]    _zz_beatsTo4KbBoundary;
  wire       [31:0]   _zz__zz_currentBurstLen_1;
  wire       [31:0]   _zz__zz_currentBurstLen_1_1;
  wire       [31:0]   _zz_currentBurstLen_3;
  wire       [31:0]   _zz_currentBurstLen_4;
  wire       [31:0]   _zz_currentBurstLen_5;
  wire       [15:0]   _zz_m_axi_vb_arlen;
  wire       [31:0]   _zz_arAddrReg;
  wire       [19:0]   _zz_arAddrReg_1;
  wire       [31:0]   _zz_arBeatsRemaining_1;
  wire       [18:0]   _zz_dmArea_bttUnits;
  wire       [18:0]   _zz_dmArea_bttUnits_1;
  wire       [19:0]   _zz_dmArea_bttUnits_2;
  wire       [18:0]   _zz_dmArea_bttUnits_3;
  wire       [23:0]   _zz_dmArea_bttBytes;
  wire       [31:0]   _zz_isLastBeat;
  wire       [31:0]   _zz_isLastTri1;
  wire       [31:0]   _zz_isLastTri;
  wire       [30:0]   _zz__zz_arBeatsRemaining;
  wire       [31:0]   _zz__zz_arBeatsRemaining_1;
  wire       [16:0]   _zz_when_AxiVisibilityDma_l885;
  wire       [31:0]   busif_bus_rdata;
  reg                 busif_reg_rderr;
  reg        [31:0]   busif_reg_rdata;
  wire                busif_askWrite;
  wire                busif_askRead;
  wire                busif_doWrite;
  wire                busif_doRead;
  reg                 dmaBusy;
  reg                 axiReadError;
  reg                 dmErrorFlag;
  reg        [7:0]    dmLastStsReg;
  reg        [31:0]   cycleCounter;
  reg        [31:0]   statVisCount;
  reg        [31:0]   statCmdCount;
  reg        [31:0]   statStsCount;
  wire                read_hit_0x0000;
  wire                write_hit_0x0000;
  reg                 START;
  wire                when_RegBase_l328;
  reg                 SOFT_RESET;
  wire                when_RegBase_l328_1;
  reg                 IRQ_ENABLE;
  reg                 AUTO_ADV_EN;
  wire                read_hit_0x0004;
  wire                write_hit_0x0004;
  wire                BUSY;
  reg                 DONE;
  wire                when_RegBase_l229;
  reg                 ERROR;
  wire                when_RegBase_l229_1;
  reg                 IRQ_STATUS;
  wire                when_RegBase_l229_2;
  reg                 FRAME_DONE;
  wire                when_RegBase_l229_3;
  wire                AXI_ERR_FLAG;
  wire                DM_ERR_FLAG;
  wire                read_hit_0x0008;
  wire                write_hit_0x0008;
  reg        [27:0]   VB_BASE_LOW;
  wire                read_hit_0x000c;
  wire                write_hit_0x000c;
  reg        [31:0]   VB_BASE_HIGH;
  wire                read_hit_0x0010;
  wire                write_hit_0x0010;
  reg        [26:0]   TRI_BASE_LOW;
  wire                read_hit_0x0014;
  wire                write_hit_0x0014;
  reg        [31:0]   TRI_BASE_HIGH;
  wire                read_hit_0x0018;
  wire                write_hit_0x0018;
  reg        [31:0]   TRI_COUNT;
  wire                read_hit_0x001c;
  wire                write_hit_0x001c;
  reg        [5:0]    TILE_INDEX;
  wire                read_hit_0x0020;
  wire                write_hit_0x0020;
  reg        [16:0]   BTT_LIMIT_TRI;
  wire                read_hit_0x0024;
  wire                write_hit_0x0024;
  wire       [31:0]   STAT_VIS;
  wire                read_hit_0x0028;
  wire                write_hit_0x0028;
  wire       [31:0]   STAT_CMD;
  wire                read_hit_0x002c;
  wire                write_hit_0x002c;
  wire       [31:0]   STAT_STS;
  wire                read_hit_0x0030;
  wire                write_hit_0x0030;
  wire       [7:0]    DM_LAST_STS;
  wire                read_hit_0x0034;
  wire                write_hit_0x0034;
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
  wire                when_RegBase_l229_4;
  wire                when_RegBase_l230;
  reg                 done_mask;
  wire                irqDoneStat;
  reg                 error_raw;
  wire                when_RegBase_l229_5;
  wire                when_RegBase_l230_1;
  reg                 error_mask;
  wire                irqErrorStat;
  reg                 frame_done_raw;
  wire                when_RegBase_l229_6;
  wire                when_RegBase_l230_2;
  reg                 frame_done_mask;
  wire                irqFrameDoneStat;
  wire                irqMerged;
  wire       [28:0]   _zz_busif_reg_rdata;
  wire       [27:0]   fullVbWordAddr;
  wire       [31:0]   fullVbBaseAddr;
  wire       [26:0]   fullTriWordAddr;
  wire       [31:0]   rawBits;
  wire                when_AxiVisibilityDma_l399;
  reg        [5:0]    activeTileIdx;
  wire                rBuffered_valid;
  wire                rBuffered_ready;
  wire       [127:0]  rBuffered_payload_data;
  wire       [3:0]    rBuffered_payload_id;
  wire       [1:0]    rBuffered_payload_resp;
  wire                rBuffered_payload_last;
  reg                 m_axi_vb_r_rValid;
  reg        [127:0]  m_axi_vb_r_rData_data;
  reg        [3:0]    m_axi_vb_r_rData_id;
  reg        [1:0]    m_axi_vb_r_rData_resp;
  reg                 m_axi_vb_r_rData_last;
  wire                when_Stream_l477;
  reg        [1:0]    visBitsIn;
  reg        [31:0]   arAddrReg;
  reg        [31:0]   arBeatsRemaining;
  reg        [31:0]   rBeatsRemaining;
  reg        [3:0]    outstandingReads;
  wire       [12:0]   bytesTo4KbBoundary;
  wire       [15:0]   beatsTo4KbBoundary;
  wire       [15:0]   maxBurstBeats;
  wire       [15:0]   currentBurstLen;
  wire       [15:0]   _zz_currentBurstLen;
  wire       [31:0]   _zz_currentBurstLen_1;
  wire       [15:0]   _zz_currentBurstLen_2;
  wire                canIssueAr;
  wire                arFire;
  wire                rFire;
  wire                when_AxiVisibilityDma_l473;
  wire                when_AxiVisibilityDma_l475;
  wire                when_AxiVisibilityDma_l481;
  reg                 cmdStreamInternal_valid;
  wire                cmdStreamInternal_ready;
  reg        [26:0]   cmdStreamInternal_payload_triWordAddr;
  reg        [16:0]   cmdStreamInternal_payload_triCount;
  reg        [3:0]    cmdStreamInternal_payload_tag;
  reg        [71:0]   dmArea_cmdPayload;
  wire       [18:0]   dmArea_bttUnits;
  wire       [22:0]   dmArea_bttBytes;
  wire       [31:0]   dmArea_startByteAddr;
  wire                io_pop_fire;
  wire       [7:0]    _zz_dmLastStsReg;
  wire                when_AxiVisibilityDma_l595;
  reg        [31:0]   triCounter;
  reg        [31:0]   shadowTriCount;
  reg        [26:0]   triAddr0;
  reg        [26:0]   triAddr1;
  reg        [16:0]   shadowMaxTriangles;
  reg        [3:0]    tagCounter;
  reg                 runActive;
  reg        [26:0]   runStartWord;
  reg        [16:0]   runLength;
  wire       [31:0]   triIdx1;
  wire                isValid0;
  wire                isValid1;
  wire                rawV0;
  wire                rawV1;
  wire                v0;
  wire                v1;
  wire                isLastBeat;
  wire                isLastTri1;
  wire       [31:0]   stepCount;
  wire       [26:0]   stepUnits;
  reg        [0:0]    sliceIdx;
  wire                isVisible;
  wire                isLastTri;
  wire                triStep;
  reg        [2:0]    filterState_1;
  wire                when_AxiVisibilityDma_l709;
  wire       [31:0]   _zz_arBeatsRemaining;
  wire                when_AxiVisibilityDma_l750;
  wire       [1:0]    switch_AxiVisibilityDma_l761;
  wire                when_AxiVisibilityDma_l839;
  wire                when_AxiVisibilityDma_l885;
  wire                when_AxiVisibilityDma_l1012;
  wire                when_AxiVisibilityDma_l1029;
  `ifndef SYNTHESIS
  reg [103:0] filterState_1_string;
  `endif


  assign _zz_visBitsIn = (6'h0 + activeTileIdx);
  assign _zz_visBitsIn_1 = (7'h40 + _zz_visBitsIn_2);
  assign _zz_visBitsIn_2 = {1'd0, activeTileIdx};
  assign _zz_bytesTo4KbBoundary_1 = arAddrReg[11 : 0];
  assign _zz_bytesTo4KbBoundary = {1'd0, _zz_bytesTo4KbBoundary_1};
  assign _zz_beatsTo4KbBoundary = (bytesTo4KbBoundary >>> 3'd4);
  assign _zz__zz_currentBurstLen_1 = {16'd0, _zz_currentBurstLen};
  assign _zz__zz_currentBurstLen_1_1 = {16'd0, _zz_currentBurstLen};
  assign _zz_currentBurstLen_3 = ((_zz_currentBurstLen_1 < _zz_currentBurstLen_4) ? _zz_currentBurstLen_1 : _zz_currentBurstLen_5);
  assign _zz_currentBurstLen_4 = {16'd0, _zz_currentBurstLen_2};
  assign _zz_currentBurstLen_5 = {16'd0, _zz_currentBurstLen_2};
  assign _zz_m_axi_vb_arlen = (currentBurstLen - 16'h0001);
  assign _zz_arAddrReg_1 = ({4'd0,currentBurstLen} <<< 3'd4);
  assign _zz_arAddrReg = {12'd0, _zz_arAddrReg_1};
  assign _zz_arBeatsRemaining_1 = {16'd0, currentBurstLen};
  assign _zz_dmArea_bttUnits = {2'd0, streamFifo_io_pop_payload_triCount};
  assign _zz_dmArea_bttUnits_2 = ({1'd0,_zz_dmArea_bttUnits_3} <<< 1'd1);
  assign _zz_dmArea_bttUnits_1 = _zz_dmArea_bttUnits_2[18:0];
  assign _zz_dmArea_bttUnits_3 = {2'd0, streamFifo_io_pop_payload_triCount};
  assign _zz_dmArea_bttBytes = {dmArea_bttUnits,5'h0};
  assign _zz_isLastBeat = (triCounter + 32'h00000002);
  assign _zz_isLastTri1 = (shadowTriCount - 32'h00000001);
  assign _zz_isLastTri = (shadowTriCount - 32'h00000001);
  assign _zz__zz_arBeatsRemaining = (_zz__zz_arBeatsRemaining_1 >>> 1'd1);
  assign _zz__zz_arBeatsRemaining_1 = (TRI_COUNT + 32'h00000001);
  assign _zz_when_AxiVisibilityDma_l885 = (runLength + 17'h00002);
  AxiVisibilityDma_StreamFifo vbFifo (
    .io_push_valid   (rBuffered_valid            ), //i
    .io_push_ready   (vbFifo_io_push_ready       ), //o
    .io_push_payload (visBitsIn[1:0]             ), //i
    .io_pop_valid    (vbFifo_io_pop_valid        ), //o
    .io_pop_ready    (vbFifo_io_pop_ready        ), //i
    .io_pop_payload  (vbFifo_io_pop_payload[1:0] ), //o
    .io_flush        (1'b0                       ), //i
    .io_occupancy    (vbFifo_io_occupancy[9:0]   ), //o
    .io_availability (vbFifo_io_availability[9:0]), //o
    .aclk            (aclk                       ), //i
    .aresetn         (aresetn                    )  //i
  );
  AxiVisibilityDma_StreamFifo_1 streamFifo (
    .io_push_valid               (cmdStreamInternal_valid                    ), //i
    .io_push_ready               (streamFifo_io_push_ready                   ), //o
    .io_push_payload_triWordAddr (cmdStreamInternal_payload_triWordAddr[26:0]), //i
    .io_push_payload_triCount    (cmdStreamInternal_payload_triCount[16:0]   ), //i
    .io_push_payload_tag         (cmdStreamInternal_payload_tag[3:0]         ), //i
    .io_pop_valid                (streamFifo_io_pop_valid                    ), //o
    .io_pop_ready                (m_axis_datamover_cmd_tready                ), //i
    .io_pop_payload_triWordAddr  (streamFifo_io_pop_payload_triWordAddr[26:0]), //o
    .io_pop_payload_triCount     (streamFifo_io_pop_payload_triCount[16:0]   ), //o
    .io_pop_payload_tag          (streamFifo_io_pop_payload_tag[3:0]         ), //o
    .io_flush                    (1'b0                                       ), //i
    .io_occupancy                (streamFifo_io_occupancy[6:0]               ), //o
    .io_availability             (streamFifo_io_availability[6:0]            ), //o
    .aclk                        (aclk                                       ), //i
    .aresetn                     (aresetn                                    )  //i
  );
  AxiVisibilityDma_StreamFifo_2 streamFifo_1 (
    .io_push_valid   (s_axis_datamover_sts_tvalid      ), //i
    .io_push_ready   (streamFifo_1_io_push_ready       ), //o
    .io_push_payload (s_axis_datamover_sts_tdata[7:0]  ), //i
    .io_pop_valid    (streamFifo_1_io_pop_valid        ), //o
    .io_pop_ready    (streamFifo_1_io_pop_ready        ), //i
    .io_pop_payload  (streamFifo_1_io_pop_payload[7:0] ), //o
    .io_flush        (1'b0                             ), //i
    .io_occupancy    (streamFifo_1_io_occupancy[2:0]   ), //o
    .io_availability (streamFifo_1_io_availability[2:0]), //o
    .aclk            (aclk                             ), //i
    .aresetn         (aresetn                          )  //i
  );
  `ifndef SYNTHESIS
  always @(*) begin
    case(filterState_1)
      FilterState_IDLE : filterState_1_string = "IDLE         ";
      FilterState_FILTER_STREAM : filterState_1_string = "FILTER_STREAM";
      FilterState_FLUSH_STALL : filterState_1_string = "FLUSH_STALL  ";
      FilterState_WAIT_RETIRE : filterState_1_string = "WAIT_RETIRE  ";
      FilterState_ADVANCE_TILE : filterState_1_string = "ADVANCE_TILE ";
      default : filterState_1_string = "?????????????";
    endcase
  end
  `endif

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
  assign read_hit_0x0004 = ((s_apb_PADDR == 7'h04) && busif_doRead);
  assign write_hit_0x0004 = ((s_apb_PADDR == 7'h04) && busif_doWrite);
  assign when_RegBase_l229 = s_apb_PWDATA[1];
  assign when_RegBase_l229_1 = s_apb_PWDATA[2];
  assign when_RegBase_l229_2 = s_apb_PWDATA[3];
  assign when_RegBase_l229_3 = s_apb_PWDATA[4];
  assign BUSY = dmaBusy;
  assign AXI_ERR_FLAG = axiReadError;
  assign DM_ERR_FLAG = dmErrorFlag;
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
  assign read_hit_0x0024 = ((s_apb_PADDR == 7'h24) && busif_doRead);
  assign write_hit_0x0024 = ((s_apb_PADDR == 7'h24) && busif_doWrite);
  assign STAT_VIS = statVisCount;
  assign read_hit_0x0028 = ((s_apb_PADDR == 7'h28) && busif_doRead);
  assign write_hit_0x0028 = ((s_apb_PADDR == 7'h28) && busif_doWrite);
  assign STAT_CMD = statCmdCount;
  assign read_hit_0x002c = ((s_apb_PADDR == 7'h2c) && busif_doRead);
  assign write_hit_0x002c = ((s_apb_PADDR == 7'h2c) && busif_doWrite);
  assign STAT_STS = statStsCount;
  assign read_hit_0x0030 = ((s_apb_PADDR == 7'h30) && busif_doRead);
  assign write_hit_0x0030 = ((s_apb_PADDR == 7'h30) && busif_doWrite);
  assign DM_LAST_STS = dmLastStsReg;
  assign read_hit_0x0034 = ((s_apb_PADDR == 7'h34) && busif_doRead);
  assign write_hit_0x0034 = ((s_apb_PADDR == 7'h34) && busif_doWrite);
  assign PERF_CYCLES = cycleCounter;
  always @(*) begin
    intrDone = 1'b0;
    if(!SOFT_RESET) begin
      case(filterState_1)
        FilterState_IDLE : begin
        end
        FilterState_FILTER_STREAM : begin
        end
        FilterState_FLUSH_STALL : begin
        end
        FilterState_WAIT_RETIRE : begin
        end
        default : begin
          intrDone = 1'b1;
        end
      endcase
    end
  end

  always @(*) begin
    intrError = 1'b0;
    if(rFire) begin
      if(when_AxiVisibilityDma_l481) begin
        intrError = 1'b1;
      end
    end
    if(io_pop_fire) begin
      if(when_AxiVisibilityDma_l595) begin
        intrError = 1'b1;
      end
    end
  end

  always @(*) begin
    intrFrameDone = 1'b0;
    if(!SOFT_RESET) begin
      case(filterState_1)
        FilterState_IDLE : begin
        end
        FilterState_FILTER_STREAM : begin
        end
        FilterState_FLUSH_STALL : begin
        end
        FilterState_WAIT_RETIRE : begin
        end
        default : begin
          if(AUTO_ADV_EN) begin
            if(when_AxiVisibilityDma_l1029) begin
              intrFrameDone = 1'b1;
            end
          end
        end
      endcase
    end
  end

  assign read_hit_0x0040 = ((s_apb_PADDR == 7'h40) && busif_doRead);
  assign write_hit_0x0040 = ((s_apb_PADDR == 7'h40) && busif_doWrite);
  assign read_hit_0x0044 = ((s_apb_PADDR == 7'h44) && busif_doRead);
  assign write_hit_0x0044 = ((s_apb_PADDR == 7'h44) && busif_doWrite);
  assign read_hit_0x0048 = ((s_apb_PADDR == 7'h48) && busif_doRead);
  assign write_hit_0x0048 = ((s_apb_PADDR == 7'h48) && busif_doWrite);
  assign read_hit_0x004c = ((s_apb_PADDR == 7'h4c) && busif_doRead);
  assign write_hit_0x004c = ((s_apb_PADDR == 7'h4c) && busif_doWrite);
  assign when_RegBase_l229_4 = s_apb_PWDATA[0];
  assign when_RegBase_l230 = s_apb_PWDATA[0];
  assign irqDoneStat = (done_raw && (! done_mask));
  assign when_RegBase_l229_5 = s_apb_PWDATA[1];
  assign when_RegBase_l230_1 = s_apb_PWDATA[1];
  assign irqErrorStat = (error_raw && (! error_mask));
  assign when_RegBase_l229_6 = s_apb_PWDATA[2];
  assign when_RegBase_l230_2 = s_apb_PWDATA[2];
  assign irqFrameDoneStat = (frame_done_raw && (! frame_done_mask));
  assign irqMerged = ((irqDoneStat || irqErrorStat) || irqFrameDoneStat);
  assign _zz_busif_reg_rdata = 29'h0;
  assign fullVbWordAddr = VB_BASE_LOW;
  assign fullVbBaseAddr = {fullVbWordAddr,4'b0000};
  assign fullTriWordAddr = TRI_BASE_LOW;
  assign rawBits = {_zz_busif_reg_rdata,{frame_done_raw,{error_raw,done_raw}}};
  assign ready = (! dmaBusy);
  assign irq = irqMerged;
  assign irq_done = rawBits[0];
  assign irq_error = rawBits[1];
  assign irq_frame_done = rawBits[2];
  assign when_AxiVisibilityDma_l399 = (IRQ_ENABLE && ((intrDone || intrError) || intrFrameDone));
  always @(*) begin
    m_axi_vb_rready = rBuffered_ready;
    if(when_Stream_l477) begin
      m_axi_vb_rready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! rBuffered_valid);
  assign rBuffered_valid = m_axi_vb_r_rValid;
  assign rBuffered_payload_data = m_axi_vb_r_rData_data;
  assign rBuffered_payload_id = m_axi_vb_r_rData_id;
  assign rBuffered_payload_resp = m_axi_vb_r_rData_resp;
  assign rBuffered_payload_last = m_axi_vb_r_rData_last;
  always @(*) begin
    visBitsIn[0] = rBuffered_payload_data[_zz_visBitsIn];
    visBitsIn[1] = rBuffered_payload_data[_zz_visBitsIn_1];
  end

  assign rBuffered_ready = vbFifo_io_push_ready;
  assign bytesTo4KbBoundary = (13'h1000 - _zz_bytesTo4KbBoundary);
  assign beatsTo4KbBoundary = {7'd0, _zz_beatsTo4KbBoundary};
  assign maxBurstBeats = 16'h0100;
  assign _zz_currentBurstLen = beatsTo4KbBoundary;
  assign _zz_currentBurstLen_1 = ((arBeatsRemaining < _zz__zz_currentBurstLen_1) ? arBeatsRemaining : _zz__zz_currentBurstLen_1_1);
  assign _zz_currentBurstLen_2 = maxBurstBeats;
  assign currentBurstLen = _zz_currentBurstLen_3[15:0];
  assign canIssueAr = ((32'h0 < arBeatsRemaining) && (outstandingReads < 4'b1000));
  assign m_axi_vb_arvalid = (canIssueAr && dmaBusy);
  assign m_axi_vb_araddr = arAddrReg;
  assign m_axi_vb_arlen = _zz_m_axi_vb_arlen[7:0];
  assign m_axi_vb_arsize = 3'b100;
  assign m_axi_vb_arburst = 2'b01;
  assign m_axi_vb_arid = 4'b0000;
  assign m_axi_vb_arregion = 4'b0000;
  assign m_axi_vb_arlock = 1'b0;
  assign m_axi_vb_arcache = 4'b0011;
  assign m_axi_vb_arprot = 3'b000;
  assign m_axi_vb_arqos = 4'b0000;
  assign arFire = (m_axi_vb_arvalid && m_axi_vb_arready);
  assign rFire = (m_axi_vb_rvalid && m_axi_vb_rready);
  assign when_AxiVisibilityDma_l473 = (arFire && (! (rFire && m_axi_vb_rlast)));
  assign when_AxiVisibilityDma_l475 = ((! arFire) && (rFire && m_axi_vb_rlast));
  assign when_AxiVisibilityDma_l481 = ((m_axi_vb_rresp == 2'b10) || (m_axi_vb_rresp == 2'b11));
  assign cmdStreamInternal_ready = streamFifo_io_push_ready;
  always @(*) begin
    dmArea_cmdPayload = 72'h0;
    dmArea_cmdPayload[22 : 0] = dmArea_bttBytes;
    dmArea_cmdPayload[23] = 1'b1;
    dmArea_cmdPayload[27 : 24] = 4'b0000;
    dmArea_cmdPayload[28] = 1'b0;
    dmArea_cmdPayload[29] = 1'b0;
    dmArea_cmdPayload[31 : 30] = streamFifo_io_pop_payload_tag[1 : 0];
    dmArea_cmdPayload[63 : 32] = dmArea_startByteAddr;
  end

  assign dmArea_bttUnits = (_zz_dmArea_bttUnits + _zz_dmArea_bttUnits_1);
  assign dmArea_bttBytes = _zz_dmArea_bttBytes[22:0];
  assign dmArea_startByteAddr = {streamFifo_io_pop_payload_triWordAddr,5'h0};
  assign m_axis_datamover_cmd_tvalid = streamFifo_io_pop_valid;
  assign m_axis_datamover_cmd_tdata = dmArea_cmdPayload;
  assign s_axis_datamover_sts_tready = streamFifo_1_io_push_ready;
  assign streamFifo_1_io_pop_ready = 1'b1;
  assign io_pop_fire = (streamFifo_1_io_pop_valid && streamFifo_1_io_pop_ready);
  assign _zz_dmLastStsReg = streamFifo_1_io_pop_payload[7 : 0];
  assign when_AxiVisibilityDma_l595 = ((! _zz_dmLastStsReg[7]) || (_zz_dmLastStsReg[6 : 4] != 3'b000));
  assign triIdx1 = (triCounter + 32'h00000001);
  assign isValid0 = (triCounter < shadowTriCount);
  assign isValid1 = (triIdx1 < shadowTriCount);
  assign rawV0 = vbFifo_io_pop_payload[0];
  assign rawV1 = vbFifo_io_pop_payload[1];
  assign v0 = (rawV0 && isValid0);
  assign v1 = (rawV1 && isValid1);
  assign isLastBeat = (shadowTriCount <= _zz_isLastBeat);
  assign isLastTri1 = (triIdx1 == _zz_isLastTri1);
  assign stepCount = (isValid1 ? 32'h00000002 : 32'h00000001);
  assign stepUnits = (isValid1 ? 27'h0000006 : 27'h0000003);
  assign isVisible = vbFifo_io_pop_payload[sliceIdx];
  assign isLastTri = (triCounter == _zz_isLastTri);
  assign triStep = 1'b0;
  always @(*) begin
    vbFifo_io_pop_ready = 1'b0;
    if(!SOFT_RESET) begin
      case(filterState_1)
        FilterState_IDLE : begin
        end
        FilterState_FILTER_STREAM : begin
          if(vbFifo_io_pop_valid) begin
            case(switch_AxiVisibilityDma_l761)
              2'b00 : begin
                if(runActive) begin
                  if(cmdStreamInternal_ready) begin
                    vbFifo_io_pop_ready = 1'b1;
                  end
                end else begin
                  vbFifo_io_pop_ready = 1'b1;
                end
              end
              2'b01 : begin
                if(runActive) begin
                  if(cmdStreamInternal_ready) begin
                    if(!isLastTri1) begin
                      vbFifo_io_pop_ready = 1'b1;
                    end
                  end
                end else begin
                  if(isLastTri1) begin
                    if(cmdStreamInternal_ready) begin
                      vbFifo_io_pop_ready = 1'b1;
                    end
                  end else begin
                    vbFifo_io_pop_ready = 1'b1;
                  end
                end
              end
              2'b10 : begin
                if(runActive) begin
                  if(when_AxiVisibilityDma_l839) begin
                    if(cmdStreamInternal_ready) begin
                      vbFifo_io_pop_ready = 1'b1;
                    end
                  end
                end else begin
                  if(cmdStreamInternal_ready) begin
                    vbFifo_io_pop_ready = 1'b1;
                  end
                end
              end
              default : begin
                if(runActive) begin
                  if(when_AxiVisibilityDma_l885) begin
                    if(isLastTri1) begin
                      if(cmdStreamInternal_ready) begin
                        vbFifo_io_pop_ready = 1'b1;
                      end
                    end else begin
                      vbFifo_io_pop_ready = 1'b1;
                    end
                  end
                end else begin
                  if(isLastTri1) begin
                    if(cmdStreamInternal_ready) begin
                      vbFifo_io_pop_ready = 1'b1;
                    end
                  end else begin
                    vbFifo_io_pop_ready = 1'b1;
                  end
                end
              end
            endcase
          end
        end
        FilterState_FLUSH_STALL : begin
        end
        FilterState_WAIT_RETIRE : begin
        end
        default : begin
        end
      endcase
    end
  end

  always @(*) begin
    cmdStreamInternal_valid = 1'b0;
    if(!SOFT_RESET) begin
      case(filterState_1)
        FilterState_IDLE : begin
        end
        FilterState_FILTER_STREAM : begin
          if(vbFifo_io_pop_valid) begin
            case(switch_AxiVisibilityDma_l761)
              2'b00 : begin
                if(runActive) begin
                  cmdStreamInternal_valid = 1'b1;
                end
              end
              2'b01 : begin
                if(runActive) begin
                  cmdStreamInternal_valid = 1'b1;
                end else begin
                  if(isLastTri1) begin
                    cmdStreamInternal_valid = 1'b1;
                  end
                end
              end
              2'b10 : begin
                if(runActive) begin
                  if(when_AxiVisibilityDma_l839) begin
                    cmdStreamInternal_valid = 1'b1;
                  end else begin
                    cmdStreamInternal_valid = 1'b1;
                  end
                end else begin
                  cmdStreamInternal_valid = 1'b1;
                end
              end
              default : begin
                if(runActive) begin
                  if(when_AxiVisibilityDma_l885) begin
                    if(isLastTri1) begin
                      cmdStreamInternal_valid = 1'b1;
                    end
                  end else begin
                    cmdStreamInternal_valid = 1'b1;
                  end
                end else begin
                  if(isLastTri1) begin
                    cmdStreamInternal_valid = 1'b1;
                  end
                end
              end
            endcase
          end
        end
        FilterState_FLUSH_STALL : begin
        end
        FilterState_WAIT_RETIRE : begin
        end
        default : begin
        end
      endcase
    end
  end

  always @(*) begin
    cmdStreamInternal_payload_triWordAddr = runStartWord;
    if(!SOFT_RESET) begin
      case(filterState_1)
        FilterState_IDLE : begin
        end
        FilterState_FILTER_STREAM : begin
          if(vbFifo_io_pop_valid) begin
            case(switch_AxiVisibilityDma_l761)
              2'b00 : begin
                if(runActive) begin
                  cmdStreamInternal_payload_triWordAddr = runStartWord;
                end
              end
              2'b01 : begin
                if(runActive) begin
                  cmdStreamInternal_payload_triWordAddr = runStartWord;
                end else begin
                  if(isLastTri1) begin
                    cmdStreamInternal_payload_triWordAddr = triAddr1;
                  end
                end
              end
              2'b10 : begin
                if(runActive) begin
                  if(when_AxiVisibilityDma_l839) begin
                    cmdStreamInternal_payload_triWordAddr = runStartWord;
                  end else begin
                    cmdStreamInternal_payload_triWordAddr = runStartWord;
                  end
                end else begin
                  cmdStreamInternal_payload_triWordAddr = triAddr0;
                end
              end
              default : begin
                if(runActive) begin
                  if(when_AxiVisibilityDma_l885) begin
                    if(isLastTri1) begin
                      cmdStreamInternal_payload_triWordAddr = runStartWord;
                    end
                  end else begin
                    cmdStreamInternal_payload_triWordAddr = runStartWord;
                  end
                end else begin
                  if(isLastTri1) begin
                    cmdStreamInternal_payload_triWordAddr = triAddr0;
                  end
                end
              end
            endcase
          end
        end
        FilterState_FLUSH_STALL : begin
        end
        FilterState_WAIT_RETIRE : begin
        end
        default : begin
        end
      endcase
    end
  end

  always @(*) begin
    cmdStreamInternal_payload_triCount = runLength;
    if(!SOFT_RESET) begin
      case(filterState_1)
        FilterState_IDLE : begin
        end
        FilterState_FILTER_STREAM : begin
          if(vbFifo_io_pop_valid) begin
            case(switch_AxiVisibilityDma_l761)
              2'b00 : begin
                if(runActive) begin
                  cmdStreamInternal_payload_triCount = runLength;
                end
              end
              2'b01 : begin
                if(runActive) begin
                  cmdStreamInternal_payload_triCount = runLength;
                end else begin
                  if(isLastTri1) begin
                    cmdStreamInternal_payload_triCount = 17'h00001;
                  end
                end
              end
              2'b10 : begin
                if(runActive) begin
                  if(when_AxiVisibilityDma_l839) begin
                    cmdStreamInternal_payload_triCount = (runLength + 17'h00001);
                  end else begin
                    cmdStreamInternal_payload_triCount = runLength;
                  end
                end else begin
                  cmdStreamInternal_payload_triCount = 17'h00001;
                end
              end
              default : begin
                if(runActive) begin
                  if(when_AxiVisibilityDma_l885) begin
                    if(isLastTri1) begin
                      cmdStreamInternal_payload_triCount = (runLength + 17'h00002);
                    end
                  end else begin
                    cmdStreamInternal_payload_triCount = runLength;
                  end
                end else begin
                  if(isLastTri1) begin
                    cmdStreamInternal_payload_triCount = 17'h00002;
                  end
                end
              end
            endcase
          end
        end
        FilterState_FLUSH_STALL : begin
        end
        FilterState_WAIT_RETIRE : begin
        end
        default : begin
        end
      endcase
    end
  end

  always @(*) begin
    cmdStreamInternal_payload_tag = tagCounter;
    if(!SOFT_RESET) begin
      case(filterState_1)
        FilterState_IDLE : begin
        end
        FilterState_FILTER_STREAM : begin
          if(vbFifo_io_pop_valid) begin
            case(switch_AxiVisibilityDma_l761)
              2'b00 : begin
                if(runActive) begin
                  cmdStreamInternal_payload_tag = tagCounter;
                end
              end
              2'b01 : begin
                if(runActive) begin
                  cmdStreamInternal_payload_tag = tagCounter;
                end else begin
                  if(isLastTri1) begin
                    cmdStreamInternal_payload_tag = tagCounter;
                  end
                end
              end
              2'b10 : begin
                if(runActive) begin
                  if(when_AxiVisibilityDma_l839) begin
                    cmdStreamInternal_payload_tag = tagCounter;
                  end else begin
                    cmdStreamInternal_payload_tag = tagCounter;
                  end
                end else begin
                  cmdStreamInternal_payload_tag = tagCounter;
                end
              end
              default : begin
                if(runActive) begin
                  if(when_AxiVisibilityDma_l885) begin
                    if(isLastTri1) begin
                      cmdStreamInternal_payload_tag = tagCounter;
                    end
                  end else begin
                    cmdStreamInternal_payload_tag = tagCounter;
                  end
                end else begin
                  if(isLastTri1) begin
                    cmdStreamInternal_payload_tag = tagCounter;
                  end
                end
              end
            endcase
          end
        end
        FilterState_FLUSH_STALL : begin
        end
        FilterState_WAIT_RETIRE : begin
        end
        default : begin
        end
      endcase
    end
  end

  assign when_AxiVisibilityDma_l709 = (START && (! dmaBusy));
  assign _zz_arBeatsRemaining = {1'd0, _zz__zz_arBeatsRemaining};
  assign when_AxiVisibilityDma_l750 = (TRI_COUNT == 32'h0);
  assign switch_AxiVisibilityDma_l761 = {v0,v1};
  assign when_AxiVisibilityDma_l839 = (runLength < shadowMaxTriangles);
  assign when_AxiVisibilityDma_l885 = (_zz_when_AxiVisibilityDma_l885 <= shadowMaxTriangles);
  assign when_AxiVisibilityDma_l1012 = (statStsCount == statCmdCount);
  assign when_AxiVisibilityDma_l1029 = (TILE_INDEX == 6'h3b);
  assign busif_bus_rdata = busif_reg_rdata;
  always @(posedge aclk or negedge aresetn) begin
    if(!aresetn) begin
      busif_reg_rderr <= 1'b0;
      busif_reg_rdata <= 32'h0;
      dmaBusy <= 1'b0;
      axiReadError <= 1'b0;
      dmErrorFlag <= 1'b0;
      dmLastStsReg <= 8'h0;
      cycleCounter <= 32'h0;
      statVisCount <= 32'h0;
      statCmdCount <= 32'h0;
      statStsCount <= 32'h0;
      START <= 1'b0;
      SOFT_RESET <= 1'b0;
      IRQ_ENABLE <= 1'b1;
      AUTO_ADV_EN <= 1'b1;
      DONE <= 1'b0;
      ERROR <= 1'b0;
      IRQ_STATUS <= 1'b0;
      FRAME_DONE <= 1'b0;
      VB_BASE_LOW <= 28'h0;
      VB_BASE_HIGH <= 32'h0;
      TRI_BASE_LOW <= 27'h0;
      TRI_BASE_HIGH <= 32'h0;
      TRI_COUNT <= 32'h0;
      TILE_INDEX <= 6'h0;
      BTT_LIMIT_TRI <= 17'h15555;
      done_raw <= 1'b0;
      done_mask <= 1'b0;
      error_raw <= 1'b0;
      error_mask <= 1'b0;
      frame_done_raw <= 1'b0;
      frame_done_mask <= 1'b0;
      activeTileIdx <= 6'h0;
      m_axi_vb_r_rValid <= 1'b0;
      arAddrReg <= 32'h0;
      arBeatsRemaining <= 32'h0;
      rBeatsRemaining <= 32'h0;
      outstandingReads <= 4'b0000;
      triCounter <= 32'h0;
      shadowTriCount <= 32'h0;
      triAddr0 <= 27'h0;
      triAddr1 <= 27'h0;
      shadowMaxTriangles <= 17'h15555;
      tagCounter <= 4'b0000;
      runActive <= 1'b0;
      runStartWord <= 27'h0;
      runLength <= 17'h0;
      sliceIdx <= 1'b0;
      filterState_1 <= FilterState_IDLE;
    end else begin
      if(when_RegBase_l328) begin
        START <= (! START);
      end else begin
        START <= 1'b0;
      end
      if(when_RegBase_l328_1) begin
        SOFT_RESET <= (! SOFT_RESET);
      end else begin
        SOFT_RESET <= 1'b0;
      end
      if(write_hit_0x0000) begin
        IRQ_ENABLE <= s_apb_PWDATA[2];
      end
      if(write_hit_0x0000) begin
        AUTO_ADV_EN <= s_apb_PWDATA[3];
      end
      if(write_hit_0x0004) begin
        if(when_RegBase_l229) begin
          DONE <= 1'b0;
        end
      end
      if(write_hit_0x0004) begin
        if(when_RegBase_l229_1) begin
          ERROR <= 1'b0;
        end
      end
      if(write_hit_0x0004) begin
        if(when_RegBase_l229_2) begin
          IRQ_STATUS <= 1'b0;
        end
      end
      if(write_hit_0x0004) begin
        if(when_RegBase_l229_3) begin
          FRAME_DONE <= 1'b0;
        end
      end
      if(write_hit_0x0008) begin
        VB_BASE_LOW <= s_apb_PWDATA[31 : 4];
      end
      if(write_hit_0x000c) begin
        VB_BASE_HIGH <= s_apb_PWDATA[31 : 0];
      end
      if(write_hit_0x0010) begin
        TRI_BASE_LOW <= s_apb_PWDATA[31 : 5];
      end
      if(write_hit_0x0014) begin
        TRI_BASE_HIGH <= s_apb_PWDATA[31 : 0];
      end
      if(write_hit_0x0018) begin
        TRI_COUNT <= s_apb_PWDATA[31 : 0];
      end
      if(write_hit_0x001c) begin
        TILE_INDEX <= s_apb_PWDATA[5 : 0];
      end
      if(write_hit_0x0020) begin
        BTT_LIMIT_TRI <= s_apb_PWDATA[16 : 0];
      end
      if(write_hit_0x0040) begin
        if(when_RegBase_l229_4) begin
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
        if(when_RegBase_l229_5) begin
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
        if(when_RegBase_l229_6) begin
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
      if(when_AxiVisibilityDma_l399) begin
        IRQ_STATUS <= 1'b1;
      end
      if(dmaBusy) begin
        cycleCounter <= (cycleCounter + 32'h00000001);
      end
      if(m_axi_vb_rready) begin
        m_axi_vb_r_rValid <= m_axi_vb_rvalid;
      end
      if(arFire) begin
        arAddrReg <= (arAddrReg + _zz_arAddrReg);
        arBeatsRemaining <= (arBeatsRemaining - _zz_arBeatsRemaining_1);
      end
      if(when_AxiVisibilityDma_l473) begin
        outstandingReads <= (outstandingReads + 4'b0001);
      end else begin
        if(when_AxiVisibilityDma_l475) begin
          outstandingReads <= (outstandingReads - 4'b0001);
        end
      end
      if(rFire) begin
        rBeatsRemaining <= (rBeatsRemaining - 32'h00000001);
        if(when_AxiVisibilityDma_l481) begin
          axiReadError <= 1'b1;
          ERROR <= 1'b1;
        end
      end
      if(io_pop_fire) begin
        dmLastStsReg <= _zz_dmLastStsReg;
        statStsCount <= (statStsCount + 32'h00000001);
        if(when_AxiVisibilityDma_l595) begin
          dmErrorFlag <= 1'b1;
          ERROR <= 1'b1;
        end
      end
      if(SOFT_RESET) begin
        filterState_1 <= FilterState_IDLE;
        dmaBusy <= 1'b0;
        axiReadError <= 1'b0;
        dmErrorFlag <= 1'b0;
        statVisCount <= 32'h0;
        statCmdCount <= 32'h0;
        statStsCount <= 32'h0;
        runActive <= 1'b0;
        runLength <= 17'h0;
        outstandingReads <= 4'b0000;
        sliceIdx <= 1'b0;
      end else begin
        case(filterState_1)
          FilterState_IDLE : begin
            if(when_AxiVisibilityDma_l709) begin
              dmaBusy <= 1'b1;
              DONE <= 1'b0;
              ERROR <= 1'b0;
              IRQ_STATUS <= 1'b0;
              FRAME_DONE <= 1'b0;
              axiReadError <= 1'b0;
              dmErrorFlag <= 1'b0;
              cycleCounter <= 32'h0;
              statVisCount <= 32'h0;
              statCmdCount <= 32'h0;
              statStsCount <= 32'h0;
              tagCounter <= 4'b0000;
              runActive <= 1'b0;
              runLength <= 17'h0;
              sliceIdx <= 1'b0;
              activeTileIdx <= TILE_INDEX;
              shadowTriCount <= TRI_COUNT;
              triAddr0 <= fullTriWordAddr;
              triAddr1 <= (fullTriWordAddr + 27'h0000003);
              shadowMaxTriangles <= ((BTT_LIMIT_TRI == 17'h0) ? 17'h15555 : BTT_LIMIT_TRI);
              arAddrReg <= fullVbBaseAddr;
              arBeatsRemaining <= _zz_arBeatsRemaining;
              rBeatsRemaining <= _zz_arBeatsRemaining;
              triCounter <= 32'h0;
              if(when_AxiVisibilityDma_l750) begin
                filterState_1 <= FilterState_ADVANCE_TILE;
              end else begin
                filterState_1 <= FilterState_FILTER_STREAM;
              end
            end
          end
          FilterState_FILTER_STREAM : begin
            if(vbFifo_io_pop_valid) begin
              case(switch_AxiVisibilityDma_l761)
                2'b00 : begin
                  if(runActive) begin
                    if(cmdStreamInternal_ready) begin
                      statCmdCount <= (statCmdCount + 32'h00000001);
                      tagCounter <= (tagCounter + 4'b0001);
                      runActive <= 1'b0;
                      runLength <= 17'h0;
                      triCounter <= (triCounter + stepCount);
                      triAddr0 <= (triAddr0 + stepUnits);
                      triAddr1 <= (triAddr1 + stepUnits);
                      if(isLastBeat) begin
                        filterState_1 <= FilterState_WAIT_RETIRE;
                      end
                    end
                  end else begin
                    triCounter <= (triCounter + stepCount);
                    triAddr0 <= (triAddr0 + stepUnits);
                    triAddr1 <= (triAddr1 + stepUnits);
                    if(isLastBeat) begin
                      filterState_1 <= FilterState_WAIT_RETIRE;
                    end
                  end
                end
                2'b01 : begin
                  if(runActive) begin
                    if(cmdStreamInternal_ready) begin
                      statCmdCount <= (statCmdCount + 32'h00000001);
                      tagCounter <= (tagCounter + 4'b0001);
                      if(isLastTri1) begin
                        runActive <= 1'b0;
                        runLength <= 17'h0;
                      end else begin
                        runActive <= 1'b1;
                        runStartWord <= triAddr1;
                        runLength <= 17'h00001;
                        statVisCount <= (statVisCount + 32'h00000001);
                        triCounter <= (triCounter + stepCount);
                        triAddr0 <= (triAddr0 + stepUnits);
                        triAddr1 <= (triAddr1 + stepUnits);
                      end
                    end
                  end else begin
                    if(isLastTri1) begin
                      if(cmdStreamInternal_ready) begin
                        statCmdCount <= (statCmdCount + 32'h00000001);
                        tagCounter <= (tagCounter + 4'b0001);
                        statVisCount <= (statVisCount + 32'h00000001);
                        triCounter <= (triCounter + stepCount);
                        triAddr0 <= (triAddr0 + stepUnits);
                        triAddr1 <= (triAddr1 + stepUnits);
                        filterState_1 <= FilterState_WAIT_RETIRE;
                      end
                    end else begin
                      runActive <= 1'b1;
                      runStartWord <= triAddr1;
                      runLength <= 17'h00001;
                      statVisCount <= (statVisCount + 32'h00000001);
                      triCounter <= (triCounter + stepCount);
                      triAddr0 <= (triAddr0 + stepUnits);
                      triAddr1 <= (triAddr1 + stepUnits);
                    end
                  end
                end
                2'b10 : begin
                  if(runActive) begin
                    if(when_AxiVisibilityDma_l839) begin
                      if(cmdStreamInternal_ready) begin
                        statCmdCount <= (statCmdCount + 32'h00000001);
                        tagCounter <= (tagCounter + 4'b0001);
                        statVisCount <= (statVisCount + 32'h00000001);
                        runActive <= 1'b0;
                        runLength <= 17'h0;
                        triCounter <= (triCounter + stepCount);
                        triAddr0 <= (triAddr0 + stepUnits);
                        triAddr1 <= (triAddr1 + stepUnits);
                        if(isLastBeat) begin
                          filterState_1 <= FilterState_WAIT_RETIRE;
                        end
                      end
                    end else begin
                      if(cmdStreamInternal_ready) begin
                        statCmdCount <= (statCmdCount + 32'h00000001);
                        tagCounter <= (tagCounter + 4'b0001);
                        runActive <= 1'b0;
                        runLength <= 17'h0;
                      end
                    end
                  end else begin
                    if(cmdStreamInternal_ready) begin
                      statCmdCount <= (statCmdCount + 32'h00000001);
                      tagCounter <= (tagCounter + 4'b0001);
                      statVisCount <= (statVisCount + 32'h00000001);
                      triCounter <= (triCounter + stepCount);
                      triAddr0 <= (triAddr0 + stepUnits);
                      triAddr1 <= (triAddr1 + stepUnits);
                      if(isLastBeat) begin
                        filterState_1 <= FilterState_WAIT_RETIRE;
                      end
                    end
                  end
                end
                default : begin
                  if(runActive) begin
                    if(when_AxiVisibilityDma_l885) begin
                      if(isLastTri1) begin
                        if(cmdStreamInternal_ready) begin
                          statCmdCount <= (statCmdCount + 32'h00000001);
                          tagCounter <= (tagCounter + 4'b0001);
                          statVisCount <= (statVisCount + 32'h00000002);
                          runActive <= 1'b0;
                          runLength <= 17'h0;
                          triCounter <= (triCounter + stepCount);
                          triAddr0 <= (triAddr0 + stepUnits);
                          triAddr1 <= (triAddr1 + stepUnits);
                          filterState_1 <= FilterState_WAIT_RETIRE;
                        end
                      end else begin
                        runLength <= (runLength + 17'h00002);
                        statVisCount <= (statVisCount + 32'h00000002);
                        triCounter <= (triCounter + stepCount);
                        triAddr0 <= (triAddr0 + stepUnits);
                        triAddr1 <= (triAddr1 + stepUnits);
                      end
                    end else begin
                      if(cmdStreamInternal_ready) begin
                        statCmdCount <= (statCmdCount + 32'h00000001);
                        tagCounter <= (tagCounter + 4'b0001);
                        runActive <= 1'b0;
                        runLength <= 17'h0;
                      end
                    end
                  end else begin
                    if(isLastTri1) begin
                      if(cmdStreamInternal_ready) begin
                        statCmdCount <= (statCmdCount + 32'h00000001);
                        tagCounter <= (tagCounter + 4'b0001);
                        statVisCount <= (statVisCount + 32'h00000002);
                        triCounter <= (triCounter + stepCount);
                        triAddr0 <= (triAddr0 + stepUnits);
                        triAddr1 <= (triAddr1 + stepUnits);
                        filterState_1 <= FilterState_WAIT_RETIRE;
                      end
                    end else begin
                      runActive <= 1'b1;
                      runStartWord <= triAddr0;
                      runLength <= 17'h00002;
                      statVisCount <= (statVisCount + 32'h00000002);
                      triCounter <= (triCounter + stepCount);
                      triAddr0 <= (triAddr0 + stepUnits);
                      triAddr1 <= (triAddr1 + stepUnits);
                    end
                  end
                end
              endcase
            end
          end
          FilterState_FLUSH_STALL : begin
            filterState_1 <= FilterState_FILTER_STREAM;
          end
          FilterState_WAIT_RETIRE : begin
            if(when_AxiVisibilityDma_l1012) begin
              filterState_1 <= FilterState_ADVANCE_TILE;
            end
          end
          default : begin
            dmaBusy <= 1'b0;
            DONE <= 1'b1;
            if(IRQ_ENABLE) begin
              IRQ_STATUS <= 1'b1;
            end
            if(AUTO_ADV_EN) begin
              if(when_AxiVisibilityDma_l1029) begin
                TILE_INDEX <= 6'h0;
                FRAME_DONE <= 1'b1;
              end else begin
                TILE_INDEX <= (TILE_INDEX + 6'h01);
              end
            end
            filterState_1 <= FilterState_IDLE;
          end
        endcase
      end
      if(busif_askRead) begin
        case(s_apb_PADDR)
          7'h0 : begin
            busif_reg_rdata <= {28'h0,{AUTO_ADV_EN,{IRQ_ENABLE,{SOFT_RESET,START}}}};
            busif_reg_rderr <= 1'b0;
          end
          7'h04 : begin
            busif_reg_rdata <= {25'h0,{DM_ERR_FLAG,{AXI_ERR_FLAG,{FRAME_DONE,{IRQ_STATUS,{ERROR,{DONE,BUSY}}}}}}};
            busif_reg_rderr <= 1'b0;
          end
          7'h08 : begin
            busif_reg_rdata <= {VB_BASE_LOW,4'b0000};
            busif_reg_rderr <= 1'b0;
          end
          7'h0c : begin
            busif_reg_rdata <= VB_BASE_HIGH;
            busif_reg_rderr <= 1'b0;
          end
          7'h10 : begin
            busif_reg_rdata <= {TRI_BASE_LOW,5'h0};
            busif_reg_rderr <= 1'b0;
          end
          7'h14 : begin
            busif_reg_rdata <= TRI_BASE_HIGH;
            busif_reg_rderr <= 1'b0;
          end
          7'h18 : begin
            busif_reg_rdata <= TRI_COUNT;
            busif_reg_rderr <= 1'b0;
          end
          7'h1c : begin
            busif_reg_rdata <= {26'h0,TILE_INDEX};
            busif_reg_rderr <= 1'b0;
          end
          7'h20 : begin
            busif_reg_rdata <= {15'h0,BTT_LIMIT_TRI};
            busif_reg_rderr <= 1'b0;
          end
          7'h24 : begin
            busif_reg_rdata <= STAT_VIS;
            busif_reg_rderr <= 1'b0;
          end
          7'h28 : begin
            busif_reg_rdata <= STAT_CMD;
            busif_reg_rderr <= 1'b0;
          end
          7'h2c : begin
            busif_reg_rdata <= STAT_STS;
            busif_reg_rderr <= 1'b0;
          end
          7'h30 : begin
            busif_reg_rdata <= {24'h0,DM_LAST_STS};
            busif_reg_rderr <= 1'b0;
          end
          7'h34 : begin
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

  always @(posedge aclk) begin
    if(m_axi_vb_rready) begin
      m_axi_vb_r_rData_data <= m_axi_vb_rdata;
      m_axi_vb_r_rData_id <= m_axi_vb_rid;
      m_axi_vb_r_rData_resp <= m_axi_vb_rresp;
      m_axi_vb_r_rData_last <= m_axi_vb_rlast;
    end
  end


endmodule

module AxiVisibilityDma_StreamFifo_2 (
  input  wire          io_push_valid,
  output wire          io_push_ready,
  input  wire [7:0]    io_push_payload,
  output wire          io_pop_valid,
  input  wire          io_pop_ready,
  output wire [7:0]    io_pop_payload,
  input  wire          io_flush,
  output wire [2:0]    io_occupancy,
  output wire [2:0]    io_availability,
  input  wire          aclk,
  input  wire          aresetn
);

  reg        [7:0]    logic_ram_spinal_port1;
  reg                 _zz_1;
  wire                logic_ptr_doPush;
  wire                logic_ptr_doPop;
  wire                logic_ptr_full;
  wire                logic_ptr_empty;
  reg        [2:0]    logic_ptr_push;
  reg        [2:0]    logic_ptr_pop;
  wire       [2:0]    logic_ptr_occupancy;
  wire       [2:0]    logic_ptr_popOnIo;
  wire                when_Stream_l1455;
  reg                 logic_ptr_wentUp;
  wire                io_push_fire;
  wire                logic_push_onRam_write_valid;
  wire       [1:0]    logic_push_onRam_write_payload_address;
  wire       [7:0]    logic_push_onRam_write_payload_data;
  wire                logic_pop_addressGen_valid;
  reg                 logic_pop_addressGen_ready;
  wire       [1:0]    logic_pop_addressGen_payload;
  wire                logic_pop_addressGen_fire;
  wire                logic_pop_sync_readArbitation_valid;
  wire                logic_pop_sync_readArbitation_ready;
  wire       [1:0]    logic_pop_sync_readArbitation_payload;
  reg                 logic_pop_addressGen_rValid;
  reg        [1:0]    logic_pop_addressGen_rData;
  wire                when_Stream_l477;
  wire                logic_pop_sync_readPort_cmd_valid;
  wire       [1:0]    logic_pop_sync_readPort_cmd_payload;
  wire       [7:0]    logic_pop_sync_readPort_rsp;
  wire                logic_pop_addressGen_toFlowFire_valid;
  wire       [1:0]    logic_pop_addressGen_toFlowFire_payload;
  wire                logic_pop_sync_readArbitation_translated_valid;
  wire                logic_pop_sync_readArbitation_translated_ready;
  wire       [7:0]    logic_pop_sync_readArbitation_translated_payload;
  wire                logic_pop_sync_readArbitation_fire;
  reg        [2:0]    logic_pop_sync_popReg;
  reg [7:0] logic_ram [0:3];

  always @(posedge aclk) begin
    if(_zz_1) begin
      logic_ram[logic_push_onRam_write_payload_address] <= logic_push_onRam_write_payload_data;
    end
  end

  always @(posedge aclk) begin
    if(logic_pop_sync_readPort_cmd_valid) begin
      logic_ram_spinal_port1 <= logic_ram[logic_pop_sync_readPort_cmd_payload];
    end
  end

  always @(*) begin
    _zz_1 = 1'b0;
    if(logic_push_onRam_write_valid) begin
      _zz_1 = 1'b1;
    end
  end

  assign when_Stream_l1455 = (logic_ptr_doPush != logic_ptr_doPop);
  assign logic_ptr_full = (((logic_ptr_push ^ logic_ptr_popOnIo) ^ 3'b100) == 3'b000);
  assign logic_ptr_empty = (logic_ptr_push == logic_ptr_pop);
  assign logic_ptr_occupancy = (logic_ptr_push - logic_ptr_popOnIo);
  assign io_push_ready = (! logic_ptr_full);
  assign io_push_fire = (io_push_valid && io_push_ready);
  assign logic_ptr_doPush = io_push_fire;
  assign logic_push_onRam_write_valid = io_push_fire;
  assign logic_push_onRam_write_payload_address = logic_ptr_push[1:0];
  assign logic_push_onRam_write_payload_data = io_push_payload;
  assign logic_pop_addressGen_valid = (! logic_ptr_empty);
  assign logic_pop_addressGen_payload = logic_ptr_pop[1:0];
  assign logic_pop_addressGen_fire = (logic_pop_addressGen_valid && logic_pop_addressGen_ready);
  assign logic_ptr_doPop = logic_pop_addressGen_fire;
  always @(*) begin
    logic_pop_addressGen_ready = logic_pop_sync_readArbitation_ready;
    if(when_Stream_l477) begin
      logic_pop_addressGen_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! logic_pop_sync_readArbitation_valid);
  assign logic_pop_sync_readArbitation_valid = logic_pop_addressGen_rValid;
  assign logic_pop_sync_readArbitation_payload = logic_pop_addressGen_rData;
  assign logic_pop_sync_readPort_rsp = logic_ram_spinal_port1;
  assign logic_pop_addressGen_toFlowFire_valid = logic_pop_addressGen_fire;
  assign logic_pop_addressGen_toFlowFire_payload = logic_pop_addressGen_payload;
  assign logic_pop_sync_readPort_cmd_valid = logic_pop_addressGen_toFlowFire_valid;
  assign logic_pop_sync_readPort_cmd_payload = logic_pop_addressGen_toFlowFire_payload;
  assign logic_pop_sync_readArbitation_translated_valid = logic_pop_sync_readArbitation_valid;
  assign logic_pop_sync_readArbitation_ready = logic_pop_sync_readArbitation_translated_ready;
  assign logic_pop_sync_readArbitation_translated_payload = logic_pop_sync_readPort_rsp;
  assign io_pop_valid = logic_pop_sync_readArbitation_translated_valid;
  assign logic_pop_sync_readArbitation_translated_ready = io_pop_ready;
  assign io_pop_payload = logic_pop_sync_readArbitation_translated_payload;
  assign logic_pop_sync_readArbitation_fire = (logic_pop_sync_readArbitation_valid && logic_pop_sync_readArbitation_ready);
  assign logic_ptr_popOnIo = logic_pop_sync_popReg;
  assign io_occupancy = logic_ptr_occupancy;
  assign io_availability = (3'b100 - logic_ptr_occupancy);
  always @(posedge aclk or negedge aresetn) begin
    if(!aresetn) begin
      logic_ptr_push <= 3'b000;
      logic_ptr_pop <= 3'b000;
      logic_ptr_wentUp <= 1'b0;
      logic_pop_addressGen_rValid <= 1'b0;
      logic_pop_sync_popReg <= 3'b000;
    end else begin
      if(when_Stream_l1455) begin
        logic_ptr_wentUp <= logic_ptr_doPush;
      end
      if(io_flush) begin
        logic_ptr_wentUp <= 1'b0;
      end
      if(logic_ptr_doPush) begin
        logic_ptr_push <= (logic_ptr_push + 3'b001);
      end
      if(logic_ptr_doPop) begin
        logic_ptr_pop <= (logic_ptr_pop + 3'b001);
      end
      if(io_flush) begin
        logic_ptr_push <= 3'b000;
        logic_ptr_pop <= 3'b000;
      end
      if(logic_pop_addressGen_ready) begin
        logic_pop_addressGen_rValid <= logic_pop_addressGen_valid;
      end
      if(io_flush) begin
        logic_pop_addressGen_rValid <= 1'b0;
      end
      if(logic_pop_sync_readArbitation_fire) begin
        logic_pop_sync_popReg <= logic_ptr_pop;
      end
      if(io_flush) begin
        logic_pop_sync_popReg <= 3'b000;
      end
    end
  end

  always @(posedge aclk) begin
    if(logic_pop_addressGen_ready) begin
      logic_pop_addressGen_rData <= logic_pop_addressGen_payload;
    end
  end


endmodule

module AxiVisibilityDma_StreamFifo_1 (
  input  wire          io_push_valid,
  output wire          io_push_ready,
  input  wire [26:0]   io_push_payload_triWordAddr,
  input  wire [16:0]   io_push_payload_triCount,
  input  wire [3:0]    io_push_payload_tag,
  output wire          io_pop_valid,
  input  wire          io_pop_ready,
  output wire [26:0]   io_pop_payload_triWordAddr,
  output wire [16:0]   io_pop_payload_triCount,
  output wire [3:0]    io_pop_payload_tag,
  input  wire          io_flush,
  output wire [6:0]    io_occupancy,
  output wire [6:0]    io_availability,
  input  wire          aclk,
  input  wire          aresetn
);

  reg        [47:0]   logic_ram_spinal_port1;
  wire       [47:0]   _zz_logic_ram_port;
  reg                 _zz_1;
  wire                logic_ptr_doPush;
  wire                logic_ptr_doPop;
  wire                logic_ptr_full;
  wire                logic_ptr_empty;
  reg        [6:0]    logic_ptr_push;
  reg        [6:0]    logic_ptr_pop;
  wire       [6:0]    logic_ptr_occupancy;
  wire       [6:0]    logic_ptr_popOnIo;
  wire                when_Stream_l1455;
  reg                 logic_ptr_wentUp;
  wire                io_push_fire;
  wire                logic_push_onRam_write_valid;
  wire       [5:0]    logic_push_onRam_write_payload_address;
  wire       [26:0]   logic_push_onRam_write_payload_data_triWordAddr;
  wire       [16:0]   logic_push_onRam_write_payload_data_triCount;
  wire       [3:0]    logic_push_onRam_write_payload_data_tag;
  wire                logic_pop_addressGen_valid;
  reg                 logic_pop_addressGen_ready;
  wire       [5:0]    logic_pop_addressGen_payload;
  wire                logic_pop_addressGen_fire;
  wire                logic_pop_sync_readArbitation_valid;
  wire                logic_pop_sync_readArbitation_ready;
  wire       [5:0]    logic_pop_sync_readArbitation_payload;
  reg                 logic_pop_addressGen_rValid;
  reg        [5:0]    logic_pop_addressGen_rData;
  wire                when_Stream_l477;
  wire                logic_pop_sync_readPort_cmd_valid;
  wire       [5:0]    logic_pop_sync_readPort_cmd_payload;
  wire       [26:0]   logic_pop_sync_readPort_rsp_triWordAddr;
  wire       [16:0]   logic_pop_sync_readPort_rsp_triCount;
  wire       [3:0]    logic_pop_sync_readPort_rsp_tag;
  wire       [47:0]   _zz_logic_pop_sync_readPort_rsp_triWordAddr;
  wire                logic_pop_addressGen_toFlowFire_valid;
  wire       [5:0]    logic_pop_addressGen_toFlowFire_payload;
  wire                logic_pop_sync_readArbitation_translated_valid;
  wire                logic_pop_sync_readArbitation_translated_ready;
  wire       [26:0]   logic_pop_sync_readArbitation_translated_payload_triWordAddr;
  wire       [16:0]   logic_pop_sync_readArbitation_translated_payload_triCount;
  wire       [3:0]    logic_pop_sync_readArbitation_translated_payload_tag;
  wire                logic_pop_sync_readArbitation_fire;
  reg        [6:0]    logic_pop_sync_popReg;
  reg [47:0] logic_ram [0:63];

  assign _zz_logic_ram_port = {logic_push_onRam_write_payload_data_tag,{logic_push_onRam_write_payload_data_triCount,logic_push_onRam_write_payload_data_triWordAddr}};
  always @(posedge aclk) begin
    if(_zz_1) begin
      logic_ram[logic_push_onRam_write_payload_address] <= _zz_logic_ram_port;
    end
  end

  always @(posedge aclk) begin
    if(logic_pop_sync_readPort_cmd_valid) begin
      logic_ram_spinal_port1 <= logic_ram[logic_pop_sync_readPort_cmd_payload];
    end
  end

  always @(*) begin
    _zz_1 = 1'b0;
    if(logic_push_onRam_write_valid) begin
      _zz_1 = 1'b1;
    end
  end

  assign when_Stream_l1455 = (logic_ptr_doPush != logic_ptr_doPop);
  assign logic_ptr_full = (((logic_ptr_push ^ logic_ptr_popOnIo) ^ 7'h40) == 7'h0);
  assign logic_ptr_empty = (logic_ptr_push == logic_ptr_pop);
  assign logic_ptr_occupancy = (logic_ptr_push - logic_ptr_popOnIo);
  assign io_push_ready = (! logic_ptr_full);
  assign io_push_fire = (io_push_valid && io_push_ready);
  assign logic_ptr_doPush = io_push_fire;
  assign logic_push_onRam_write_valid = io_push_fire;
  assign logic_push_onRam_write_payload_address = logic_ptr_push[5:0];
  assign logic_push_onRam_write_payload_data_triWordAddr = io_push_payload_triWordAddr;
  assign logic_push_onRam_write_payload_data_triCount = io_push_payload_triCount;
  assign logic_push_onRam_write_payload_data_tag = io_push_payload_tag;
  assign logic_pop_addressGen_valid = (! logic_ptr_empty);
  assign logic_pop_addressGen_payload = logic_ptr_pop[5:0];
  assign logic_pop_addressGen_fire = (logic_pop_addressGen_valid && logic_pop_addressGen_ready);
  assign logic_ptr_doPop = logic_pop_addressGen_fire;
  always @(*) begin
    logic_pop_addressGen_ready = logic_pop_sync_readArbitation_ready;
    if(when_Stream_l477) begin
      logic_pop_addressGen_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! logic_pop_sync_readArbitation_valid);
  assign logic_pop_sync_readArbitation_valid = logic_pop_addressGen_rValid;
  assign logic_pop_sync_readArbitation_payload = logic_pop_addressGen_rData;
  assign _zz_logic_pop_sync_readPort_rsp_triWordAddr = logic_ram_spinal_port1;
  assign logic_pop_sync_readPort_rsp_triWordAddr = _zz_logic_pop_sync_readPort_rsp_triWordAddr[26 : 0];
  assign logic_pop_sync_readPort_rsp_triCount = _zz_logic_pop_sync_readPort_rsp_triWordAddr[43 : 27];
  assign logic_pop_sync_readPort_rsp_tag = _zz_logic_pop_sync_readPort_rsp_triWordAddr[47 : 44];
  assign logic_pop_addressGen_toFlowFire_valid = logic_pop_addressGen_fire;
  assign logic_pop_addressGen_toFlowFire_payload = logic_pop_addressGen_payload;
  assign logic_pop_sync_readPort_cmd_valid = logic_pop_addressGen_toFlowFire_valid;
  assign logic_pop_sync_readPort_cmd_payload = logic_pop_addressGen_toFlowFire_payload;
  assign logic_pop_sync_readArbitation_translated_valid = logic_pop_sync_readArbitation_valid;
  assign logic_pop_sync_readArbitation_ready = logic_pop_sync_readArbitation_translated_ready;
  assign logic_pop_sync_readArbitation_translated_payload_triWordAddr = logic_pop_sync_readPort_rsp_triWordAddr;
  assign logic_pop_sync_readArbitation_translated_payload_triCount = logic_pop_sync_readPort_rsp_triCount;
  assign logic_pop_sync_readArbitation_translated_payload_tag = logic_pop_sync_readPort_rsp_tag;
  assign io_pop_valid = logic_pop_sync_readArbitation_translated_valid;
  assign logic_pop_sync_readArbitation_translated_ready = io_pop_ready;
  assign io_pop_payload_triWordAddr = logic_pop_sync_readArbitation_translated_payload_triWordAddr;
  assign io_pop_payload_triCount = logic_pop_sync_readArbitation_translated_payload_triCount;
  assign io_pop_payload_tag = logic_pop_sync_readArbitation_translated_payload_tag;
  assign logic_pop_sync_readArbitation_fire = (logic_pop_sync_readArbitation_valid && logic_pop_sync_readArbitation_ready);
  assign logic_ptr_popOnIo = logic_pop_sync_popReg;
  assign io_occupancy = logic_ptr_occupancy;
  assign io_availability = (7'h40 - logic_ptr_occupancy);
  always @(posedge aclk or negedge aresetn) begin
    if(!aresetn) begin
      logic_ptr_push <= 7'h0;
      logic_ptr_pop <= 7'h0;
      logic_ptr_wentUp <= 1'b0;
      logic_pop_addressGen_rValid <= 1'b0;
      logic_pop_sync_popReg <= 7'h0;
    end else begin
      if(when_Stream_l1455) begin
        logic_ptr_wentUp <= logic_ptr_doPush;
      end
      if(io_flush) begin
        logic_ptr_wentUp <= 1'b0;
      end
      if(logic_ptr_doPush) begin
        logic_ptr_push <= (logic_ptr_push + 7'h01);
      end
      if(logic_ptr_doPop) begin
        logic_ptr_pop <= (logic_ptr_pop + 7'h01);
      end
      if(io_flush) begin
        logic_ptr_push <= 7'h0;
        logic_ptr_pop <= 7'h0;
      end
      if(logic_pop_addressGen_ready) begin
        logic_pop_addressGen_rValid <= logic_pop_addressGen_valid;
      end
      if(io_flush) begin
        logic_pop_addressGen_rValid <= 1'b0;
      end
      if(logic_pop_sync_readArbitation_fire) begin
        logic_pop_sync_popReg <= logic_ptr_pop;
      end
      if(io_flush) begin
        logic_pop_sync_popReg <= 7'h0;
      end
    end
  end

  always @(posedge aclk) begin
    if(logic_pop_addressGen_ready) begin
      logic_pop_addressGen_rData <= logic_pop_addressGen_payload;
    end
  end


endmodule

module AxiVisibilityDma_StreamFifo (
  input  wire          io_push_valid,
  output wire          io_push_ready,
  input  wire [1:0]    io_push_payload,
  output wire          io_pop_valid,
  input  wire          io_pop_ready,
  output wire [1:0]    io_pop_payload,
  input  wire          io_flush,
  output wire [9:0]    io_occupancy,
  output wire [9:0]    io_availability,
  input  wire          aclk,
  input  wire          aresetn
);

  reg        [1:0]    logic_ram_spinal_port1;
  reg                 _zz_1;
  wire                logic_ptr_doPush;
  wire                logic_ptr_doPop;
  wire                logic_ptr_full;
  wire                logic_ptr_empty;
  reg        [9:0]    logic_ptr_push;
  reg        [9:0]    logic_ptr_pop;
  wire       [9:0]    logic_ptr_occupancy;
  wire       [9:0]    logic_ptr_popOnIo;
  wire                when_Stream_l1455;
  reg                 logic_ptr_wentUp;
  wire                io_push_fire;
  wire                logic_push_onRam_write_valid;
  wire       [8:0]    logic_push_onRam_write_payload_address;
  wire       [1:0]    logic_push_onRam_write_payload_data;
  wire                logic_pop_addressGen_valid;
  reg                 logic_pop_addressGen_ready;
  wire       [8:0]    logic_pop_addressGen_payload;
  wire                logic_pop_addressGen_fire;
  wire                logic_pop_sync_readArbitation_valid;
  wire                logic_pop_sync_readArbitation_ready;
  wire       [8:0]    logic_pop_sync_readArbitation_payload;
  reg                 logic_pop_addressGen_rValid;
  reg        [8:0]    logic_pop_addressGen_rData;
  wire                when_Stream_l477;
  wire                logic_pop_sync_readPort_cmd_valid;
  wire       [8:0]    logic_pop_sync_readPort_cmd_payload;
  wire       [1:0]    logic_pop_sync_readPort_rsp;
  wire                logic_pop_addressGen_toFlowFire_valid;
  wire       [8:0]    logic_pop_addressGen_toFlowFire_payload;
  wire                logic_pop_sync_readArbitation_translated_valid;
  wire                logic_pop_sync_readArbitation_translated_ready;
  wire       [1:0]    logic_pop_sync_readArbitation_translated_payload;
  wire                logic_pop_sync_readArbitation_fire;
  reg        [9:0]    logic_pop_sync_popReg;
  reg [1:0] logic_ram [0:511];

  always @(posedge aclk) begin
    if(_zz_1) begin
      logic_ram[logic_push_onRam_write_payload_address] <= logic_push_onRam_write_payload_data;
    end
  end

  always @(posedge aclk) begin
    if(logic_pop_sync_readPort_cmd_valid) begin
      logic_ram_spinal_port1 <= logic_ram[logic_pop_sync_readPort_cmd_payload];
    end
  end

  always @(*) begin
    _zz_1 = 1'b0;
    if(logic_push_onRam_write_valid) begin
      _zz_1 = 1'b1;
    end
  end

  assign when_Stream_l1455 = (logic_ptr_doPush != logic_ptr_doPop);
  assign logic_ptr_full = (((logic_ptr_push ^ logic_ptr_popOnIo) ^ 10'h200) == 10'h0);
  assign logic_ptr_empty = (logic_ptr_push == logic_ptr_pop);
  assign logic_ptr_occupancy = (logic_ptr_push - logic_ptr_popOnIo);
  assign io_push_ready = (! logic_ptr_full);
  assign io_push_fire = (io_push_valid && io_push_ready);
  assign logic_ptr_doPush = io_push_fire;
  assign logic_push_onRam_write_valid = io_push_fire;
  assign logic_push_onRam_write_payload_address = logic_ptr_push[8:0];
  assign logic_push_onRam_write_payload_data = io_push_payload;
  assign logic_pop_addressGen_valid = (! logic_ptr_empty);
  assign logic_pop_addressGen_payload = logic_ptr_pop[8:0];
  assign logic_pop_addressGen_fire = (logic_pop_addressGen_valid && logic_pop_addressGen_ready);
  assign logic_ptr_doPop = logic_pop_addressGen_fire;
  always @(*) begin
    logic_pop_addressGen_ready = logic_pop_sync_readArbitation_ready;
    if(when_Stream_l477) begin
      logic_pop_addressGen_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! logic_pop_sync_readArbitation_valid);
  assign logic_pop_sync_readArbitation_valid = logic_pop_addressGen_rValid;
  assign logic_pop_sync_readArbitation_payload = logic_pop_addressGen_rData;
  assign logic_pop_sync_readPort_rsp = logic_ram_spinal_port1;
  assign logic_pop_addressGen_toFlowFire_valid = logic_pop_addressGen_fire;
  assign logic_pop_addressGen_toFlowFire_payload = logic_pop_addressGen_payload;
  assign logic_pop_sync_readPort_cmd_valid = logic_pop_addressGen_toFlowFire_valid;
  assign logic_pop_sync_readPort_cmd_payload = logic_pop_addressGen_toFlowFire_payload;
  assign logic_pop_sync_readArbitation_translated_valid = logic_pop_sync_readArbitation_valid;
  assign logic_pop_sync_readArbitation_ready = logic_pop_sync_readArbitation_translated_ready;
  assign logic_pop_sync_readArbitation_translated_payload = logic_pop_sync_readPort_rsp;
  assign io_pop_valid = logic_pop_sync_readArbitation_translated_valid;
  assign logic_pop_sync_readArbitation_translated_ready = io_pop_ready;
  assign io_pop_payload = logic_pop_sync_readArbitation_translated_payload;
  assign logic_pop_sync_readArbitation_fire = (logic_pop_sync_readArbitation_valid && logic_pop_sync_readArbitation_ready);
  assign logic_ptr_popOnIo = logic_pop_sync_popReg;
  assign io_occupancy = logic_ptr_occupancy;
  assign io_availability = (10'h200 - logic_ptr_occupancy);
  always @(posedge aclk or negedge aresetn) begin
    if(!aresetn) begin
      logic_ptr_push <= 10'h0;
      logic_ptr_pop <= 10'h0;
      logic_ptr_wentUp <= 1'b0;
      logic_pop_addressGen_rValid <= 1'b0;
      logic_pop_sync_popReg <= 10'h0;
    end else begin
      if(when_Stream_l1455) begin
        logic_ptr_wentUp <= logic_ptr_doPush;
      end
      if(io_flush) begin
        logic_ptr_wentUp <= 1'b0;
      end
      if(logic_ptr_doPush) begin
        logic_ptr_push <= (logic_ptr_push + 10'h001);
      end
      if(logic_ptr_doPop) begin
        logic_ptr_pop <= (logic_ptr_pop + 10'h001);
      end
      if(io_flush) begin
        logic_ptr_push <= 10'h0;
        logic_ptr_pop <= 10'h0;
      end
      if(logic_pop_addressGen_ready) begin
        logic_pop_addressGen_rValid <= logic_pop_addressGen_valid;
      end
      if(io_flush) begin
        logic_pop_addressGen_rValid <= 1'b0;
      end
      if(logic_pop_sync_readArbitation_fire) begin
        logic_pop_sync_popReg <= logic_ptr_pop;
      end
      if(io_flush) begin
        logic_pop_sync_popReg <= 10'h0;
      end
    end
  end

  always @(posedge aclk) begin
    if(logic_pop_addressGen_ready) begin
      logic_pop_addressGen_rData <= logic_pop_addressGen_payload;
    end
  end


endmodule
