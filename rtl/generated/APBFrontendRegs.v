// Generator : SpinalHDL v1.12.3    git head : 591e64062329e5e2e2b81f4d52422948053edb97
// Component : APBFrontendRegs
// Git hash  : f921e41a46266c865ee28f084499d68632bd8f7c

`timescale 1ns/1ps

module APBFrontendRegs (
  input  wire          apb_clock,
  input  wire          apb_resetn,
  input  wire          thread_clk,
  input  wire          thread_resetn,
  input  wire [4:0]    s_apb_PADDR,
  input  wire [0:0]    s_apb_PSEL,
  input  wire          s_apb_PENABLE,
  output wire          s_apb_PREADY,
  input  wire          s_apb_PWRITE,
  input  wire [31:0]   s_apb_PWDATA,
  output wire [31:0]   s_apb_PRDATA,
  output wire          s_apb_PSLVERROR,
  input  wire          thread_empty,
  output wire          thread_sw_reset,
  output wire [4:0]    tile_x_index,
  output wire [4:0]    tile_y_index
);

  wire                streamCCByToggle_io_output_ready;
  wire                streamCCByToggle_1_io_output_ready;
  wire                thread_empty_buffercc_io_dataOut;
  wire                apbArea_RESET_pulseCCByToggle_io_pulseOut;
  wire                apbArea_RESET_pulseCCByToggle_toplevel_apb_resetn_synchronized_1;
  wire                streamCCByToggle_io_input_ready;
  wire                streamCCByToggle_io_output_valid;
  wire       [4:0]    streamCCByToggle_io_output_payload;
  wire                streamCCByToggle_1_io_input_ready;
  wire                streamCCByToggle_1_io_output_valid;
  wire       [4:0]    streamCCByToggle_1_io_output_payload;
  wire       [31:0]   apbArea_busif_bus_rdata;
  reg                 apbArea_busif_reg_rderr;
  reg        [31:0]   apbArea_busif_reg_rdata;
  wire                apbArea_busif_askWrite;
  wire                apbArea_busif_askRead;
  wire                apbArea_busif_doWrite;
  wire                apbArea_busif_doRead;
  wire                read_hit_0x0000;
  wire                write_hit_0x0000;
  wire                apbArea_EMPTY;
  reg                 apbArea_RESET;
  wire                when_RegBase_l328;
  wire                read_hit_0x0004;
  wire                write_hit_0x0004;
  reg        [4:0]    apbArea_TILE_X;
  wire                apbArea_tileXWriteStream_valid;
  wire                apbArea_tileXWriteStream_ready;
  wire       [4:0]    apbArea_tileXWriteStream_payload;
  wire                read_hit_0x0008;
  wire                write_hit_0x0008;
  reg        [4:0]    apbArea_TILE_Y;
  wire                apbArea_tileYWriteStream_valid;
  wire                apbArea_tileYWriteStream_ready;
  wire       [4:0]    apbArea_tileYWriteStream_payload;
  wire                read_hit_0x000c;
  wire                write_hit_0x000c;
  wire                read_hit_0x0010;
  wire                write_hit_0x0010;
  wire                read_hit_0x0014;
  wire                write_hit_0x0014;
  wire                read_hit_0x0018;
  wire                write_hit_0x0018;
  wire                read_hit_0x001c;
  wire                write_hit_0x001c;
  reg        [4:0]    threadArea_tileXIndex;
  reg        [4:0]    threadArea_tileYIndex;
  wire                io_output_fire;
  wire                io_output_fire_1;

  (* keep_hierarchy = "TRUE" *) APBFrontendRegs_BufferCC_6 thread_empty_buffercc (
    .io_dataIn  (thread_empty                    ), //i
    .io_dataOut (thread_empty_buffercc_io_dataOut), //o
    .apb_clock  (apb_clock                       ), //i
    .apb_resetn (apb_resetn                      )  //i
  );
  APBFrontendRegs_PulseCCByToggle apbArea_RESET_pulseCCByToggle (
    .io_pulseIn                         (apbArea_RESET                                                   ), //i
    .io_pulseOut                        (apbArea_RESET_pulseCCByToggle_io_pulseOut                       ), //o
    .apb_clock                          (apb_clock                                                       ), //i
    .apb_resetn                         (apb_resetn                                                      ), //i
    .thread_clk                         (thread_clk                                                      ), //i
    .toplevel_apb_resetn_synchronized_1 (apbArea_RESET_pulseCCByToggle_toplevel_apb_resetn_synchronized_1)  //o
  );
  APBFrontendRegs_StreamCCByToggle streamCCByToggle (
    .io_input_valid                     (apbArea_tileXWriteStream_valid                                  ), //i
    .io_input_ready                     (streamCCByToggle_io_input_ready                                 ), //o
    .io_input_payload                   (apbArea_tileXWriteStream_payload[4:0]                           ), //i
    .io_output_valid                    (streamCCByToggle_io_output_valid                                ), //o
    .io_output_ready                    (streamCCByToggle_io_output_ready                                ), //i
    .io_output_payload                  (streamCCByToggle_io_output_payload[4:0]                         ), //o
    .apb_clock                          (apb_clock                                                       ), //i
    .apb_resetn                         (apb_resetn                                                      ), //i
    .thread_clk                         (thread_clk                                                      ), //i
    .toplevel_apb_resetn_synchronized_1 (apbArea_RESET_pulseCCByToggle_toplevel_apb_resetn_synchronized_1)  //i
  );
  APBFrontendRegs_StreamCCByToggle streamCCByToggle_1 (
    .io_input_valid                     (apbArea_tileYWriteStream_valid                                  ), //i
    .io_input_ready                     (streamCCByToggle_1_io_input_ready                               ), //o
    .io_input_payload                   (apbArea_tileYWriteStream_payload[4:0]                           ), //i
    .io_output_valid                    (streamCCByToggle_1_io_output_valid                              ), //o
    .io_output_ready                    (streamCCByToggle_1_io_output_ready                              ), //i
    .io_output_payload                  (streamCCByToggle_1_io_output_payload[4:0]                       ), //o
    .apb_clock                          (apb_clock                                                       ), //i
    .apb_resetn                         (apb_resetn                                                      ), //i
    .thread_clk                         (thread_clk                                                      ), //i
    .toplevel_apb_resetn_synchronized_1 (apbArea_RESET_pulseCCByToggle_toplevel_apb_resetn_synchronized_1)  //i
  );
  assign s_apb_PREADY = 1'b1;
  assign s_apb_PRDATA = apbArea_busif_bus_rdata;
  assign apbArea_busif_askWrite = (s_apb_PSEL[0] && s_apb_PWRITE);
  assign apbArea_busif_askRead = ((s_apb_PSEL[0] && (! s_apb_PWRITE)) && (! s_apb_PENABLE));
  assign apbArea_busif_doWrite = ((apbArea_busif_askWrite && s_apb_PENABLE) && s_apb_PREADY);
  assign apbArea_busif_doRead = (((s_apb_PSEL[0] && (! s_apb_PWRITE)) && s_apb_PENABLE) && s_apb_PREADY);
  assign s_apb_PSLVERROR = apbArea_busif_reg_rderr;
  assign read_hit_0x0000 = ((s_apb_PADDR == 5'h0) && apbArea_busif_doRead);
  assign write_hit_0x0000 = ((s_apb_PADDR == 5'h0) && apbArea_busif_doWrite);
  assign when_RegBase_l328 = (write_hit_0x0000 && s_apb_PWDATA[1]);
  assign apbArea_EMPTY = thread_empty_buffercc_io_dataOut;
  assign read_hit_0x0004 = ((s_apb_PADDR == 5'h04) && apbArea_busif_doRead);
  assign write_hit_0x0004 = ((s_apb_PADDR == 5'h04) && apbArea_busif_doWrite);
  assign apbArea_tileXWriteStream_valid = write_hit_0x0004;
  assign apbArea_tileXWriteStream_payload = s_apb_PWDATA[4 : 0];
  assign read_hit_0x0008 = ((s_apb_PADDR == 5'h08) && apbArea_busif_doRead);
  assign write_hit_0x0008 = ((s_apb_PADDR == 5'h08) && apbArea_busif_doWrite);
  assign apbArea_tileYWriteStream_valid = write_hit_0x0008;
  assign apbArea_tileYWriteStream_payload = s_apb_PWDATA[4 : 0];
  assign read_hit_0x000c = ((s_apb_PADDR == 5'h0c) && apbArea_busif_doRead);
  assign write_hit_0x000c = ((s_apb_PADDR == 5'h0c) && apbArea_busif_doWrite);
  assign read_hit_0x0010 = ((s_apb_PADDR == 5'h10) && apbArea_busif_doRead);
  assign write_hit_0x0010 = ((s_apb_PADDR == 5'h10) && apbArea_busif_doWrite);
  assign read_hit_0x0014 = ((s_apb_PADDR == 5'h14) && apbArea_busif_doRead);
  assign write_hit_0x0014 = ((s_apb_PADDR == 5'h14) && apbArea_busif_doWrite);
  assign read_hit_0x0018 = ((s_apb_PADDR == 5'h18) && apbArea_busif_doRead);
  assign write_hit_0x0018 = ((s_apb_PADDR == 5'h18) && apbArea_busif_doWrite);
  assign read_hit_0x001c = ((s_apb_PADDR == 5'h1c) && apbArea_busif_doRead);
  assign write_hit_0x001c = ((s_apb_PADDR == 5'h1c) && apbArea_busif_doWrite);
  assign thread_sw_reset = apbArea_RESET_pulseCCByToggle_io_pulseOut;
  assign apbArea_tileXWriteStream_ready = streamCCByToggle_io_input_ready;
  assign apbArea_tileYWriteStream_ready = streamCCByToggle_1_io_input_ready;
  assign streamCCByToggle_io_output_ready = 1'b1;
  assign streamCCByToggle_1_io_output_ready = 1'b1;
  assign io_output_fire = (streamCCByToggle_io_output_valid && streamCCByToggle_io_output_ready);
  assign io_output_fire_1 = (streamCCByToggle_1_io_output_valid && streamCCByToggle_1_io_output_ready);
  assign tile_x_index = threadArea_tileXIndex;
  assign tile_y_index = threadArea_tileYIndex;
  assign apbArea_busif_bus_rdata = apbArea_busif_reg_rdata;
  always @(posedge apb_clock) begin
    if(!apb_resetn) begin
      apbArea_busif_reg_rderr <= 1'b0;
      apbArea_busif_reg_rdata <= 32'h0;
      apbArea_RESET <= 1'b0;
      apbArea_TILE_X <= 5'h0;
      apbArea_TILE_Y <= 5'h0;
    end else begin
      if(when_RegBase_l328) begin
        apbArea_RESET <= (! apbArea_RESET);
      end else begin
        apbArea_RESET <= 1'b0;
      end
      if(write_hit_0x0004) begin
        apbArea_TILE_X <= s_apb_PWDATA[4 : 0];
      end
      if(write_hit_0x0008) begin
        apbArea_TILE_Y <= s_apb_PWDATA[4 : 0];
      end
      if(apbArea_busif_askRead) begin
        case(s_apb_PADDR)
          5'h0 : begin
            apbArea_busif_reg_rdata <= {30'h0,{apbArea_RESET,apbArea_EMPTY}};
            apbArea_busif_reg_rderr <= 1'b0;
          end
          5'h04 : begin
            apbArea_busif_reg_rdata <= {27'h0,apbArea_TILE_X};
            apbArea_busif_reg_rderr <= 1'b0;
          end
          5'h08 : begin
            apbArea_busif_reg_rdata <= {27'h0,apbArea_TILE_Y};
            apbArea_busif_reg_rderr <= 1'b0;
          end
          default : begin
            apbArea_busif_reg_rdata <= 32'h0;
            apbArea_busif_reg_rderr <= ((|s_apb_PADDR[1 : 0]) ? 1'b1 : 1'b0);
          end
        endcase
      end else begin
        apbArea_busif_reg_rdata <= 32'h0;
        apbArea_busif_reg_rderr <= 1'b0;
      end
    end
  end

  always @(posedge thread_clk) begin
    if(!thread_resetn) begin
      threadArea_tileXIndex <= 5'h0;
      threadArea_tileYIndex <= 5'h0;
    end else begin
      if(io_output_fire) begin
        threadArea_tileXIndex <= streamCCByToggle_io_output_payload;
      end
      if(io_output_fire_1) begin
        threadArea_tileYIndex <= streamCCByToggle_1_io_output_payload;
      end
    end
  end


endmodule

//APBFrontendRegs_StreamCCByToggle_1 replaced by APBFrontendRegs_StreamCCByToggle

module APBFrontendRegs_StreamCCByToggle (
  input  wire          io_input_valid,
  output wire          io_input_ready,
  input  wire [4:0]    io_input_payload,
  output wire          io_output_valid,
  input  wire          io_output_ready,
  output wire [4:0]    io_output_payload,
  input  wire          apb_clock,
  input  wire          apb_resetn,
  input  wire          thread_clk,
  input  wire          toplevel_apb_resetn_synchronized_1
);

  wire                outHitSignal_buffercc_io_dataOut;
  wire                pushArea_target_buffercc_io_dataOut;
  wire                outHitSignal;
  wire                pushArea_hit;
  wire                pushArea_accept;
  (* altera_attribute = "-name ADV_NETLIST_OPT_ALLOWED NEVER_ALLOW" *) reg                 pushArea_target;
  (* altera_attribute = "-name ADV_NETLIST_OPT_ALLOWED NEVER_ALLOW" *) reg        [4:0]    pushArea_data;
  wire                io_input_fire;
  wire                popArea_stream_valid;
  reg                 popArea_stream_ready;
  wire       [4:0]    popArea_stream_payload;
  wire                popArea_target;
  wire                popArea_stream_fire;
  (* altera_attribute = "-name ADV_NETLIST_OPT_ALLOWED NEVER_ALLOW" *) reg                 popArea_hit;
  wire                popArea_stream_m2sPipe_valid;
  wire                popArea_stream_m2sPipe_ready;
  wire       [4:0]    popArea_stream_m2sPipe_payload;
  reg                 popArea_stream_rValid;
  (* async_reg = "true" , altera_attribute = "-name ADV_NETLIST_OPT_ALLOWED NEVER_ALLOW" *) reg        [4:0]    popArea_stream_rData;
  wire                when_Stream_l477;

  (* keep_hierarchy = "TRUE" *) APBFrontendRegs_BufferCC_2 outHitSignal_buffercc (
    .io_dataIn  (outHitSignal                    ), //i
    .io_dataOut (outHitSignal_buffercc_io_dataOut), //o
    .apb_clock  (apb_clock                       ), //i
    .apb_resetn (apb_resetn                      )  //i
  );
  (* keep_hierarchy = "TRUE" *) APBFrontendRegs_BufferCC_3 pushArea_target_buffercc (
    .io_dataIn                          (pushArea_target                    ), //i
    .io_dataOut                         (pushArea_target_buffercc_io_dataOut), //o
    .thread_clk                         (thread_clk                         ), //i
    .toplevel_apb_resetn_synchronized_1 (toplevel_apb_resetn_synchronized_1 )  //i
  );
  assign pushArea_hit = outHitSignal_buffercc_io_dataOut;
  assign io_input_fire = (io_input_valid && io_input_ready);
  assign pushArea_accept = io_input_fire;
  assign io_input_ready = (pushArea_hit == pushArea_target);
  assign popArea_target = pushArea_target_buffercc_io_dataOut;
  assign popArea_stream_fire = (popArea_stream_valid && popArea_stream_ready);
  assign outHitSignal = popArea_hit;
  assign popArea_stream_valid = (popArea_target != popArea_hit);
  assign popArea_stream_payload = pushArea_data;
  always @(*) begin
    popArea_stream_ready = popArea_stream_m2sPipe_ready;
    if(when_Stream_l477) begin
      popArea_stream_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! popArea_stream_m2sPipe_valid);
  assign popArea_stream_m2sPipe_valid = popArea_stream_rValid;
  assign popArea_stream_m2sPipe_payload = popArea_stream_rData;
  assign io_output_valid = popArea_stream_m2sPipe_valid;
  assign popArea_stream_m2sPipe_ready = io_output_ready;
  assign io_output_payload = popArea_stream_m2sPipe_payload;
  always @(posedge apb_clock) begin
    if(!apb_resetn) begin
      pushArea_target <= 1'b0;
    end else begin
      if(pushArea_accept) begin
        pushArea_target <= (! pushArea_target);
      end
    end
  end

  always @(posedge apb_clock) begin
    if(pushArea_accept) begin
      pushArea_data <= io_input_payload;
    end
  end

  always @(posedge thread_clk) begin
    if(!toplevel_apb_resetn_synchronized_1) begin
      popArea_hit <= 1'b0;
      popArea_stream_rValid <= 1'b0;
    end else begin
      if(popArea_stream_fire) begin
        popArea_hit <= popArea_target;
      end
      if(popArea_stream_ready) begin
        popArea_stream_rValid <= popArea_stream_valid;
      end
    end
  end

  always @(posedge thread_clk) begin
    if(popArea_stream_fire) begin
      popArea_stream_rData <= popArea_stream_payload;
    end
  end


endmodule

module APBFrontendRegs_PulseCCByToggle (
  input  wire          io_pulseIn,
  output wire          io_pulseOut,
  input  wire          apb_clock,
  input  wire          apb_resetn,
  input  wire          thread_clk,
  output wire          toplevel_apb_resetn_synchronized_1
);

  wire                toplevel_apb_resetn_asyncAssertSyncDeassert_buffercc_io_dataOut;
  wire                inArea_target_buffercc_io_dataOut;
  (* altera_attribute = "-name ADV_NETLIST_OPT_ALLOWED NEVER_ALLOW" *) reg                 inArea_target;
  wire                toplevel_apb_resetn_asyncAssertSyncDeassert;
  wire                toplevel_apb_resetn_synchronized;
  wire                outArea_target;
  reg                 outArea_target_regNext;

  (* keep_hierarchy = "TRUE" *) APBFrontendRegs_BufferCC toplevel_apb_resetn_asyncAssertSyncDeassert_buffercc (
    .io_dataIn  (toplevel_apb_resetn_asyncAssertSyncDeassert                    ), //i
    .io_dataOut (toplevel_apb_resetn_asyncAssertSyncDeassert_buffercc_io_dataOut), //o
    .thread_clk (thread_clk                                                     ), //i
    .apb_resetn (apb_resetn                                                     )  //i
  );
  (* keep_hierarchy = "TRUE" *) APBFrontendRegs_BufferCC_1 inArea_target_buffercc (
    .io_dataIn                        (inArea_target                    ), //i
    .io_dataOut                       (inArea_target_buffercc_io_dataOut), //o
    .thread_clk                       (thread_clk                       ), //i
    .toplevel_apb_resetn_synchronized (toplevel_apb_resetn_synchronized )  //i
  );
  assign toplevel_apb_resetn_asyncAssertSyncDeassert = (1'b1 ^ 1'b0);
  assign toplevel_apb_resetn_synchronized = toplevel_apb_resetn_asyncAssertSyncDeassert_buffercc_io_dataOut;
  assign outArea_target = inArea_target_buffercc_io_dataOut;
  assign io_pulseOut = (outArea_target ^ outArea_target_regNext);
  assign toplevel_apb_resetn_synchronized_1 = toplevel_apb_resetn_synchronized;
  always @(posedge apb_clock) begin
    if(!apb_resetn) begin
      inArea_target <= 1'b0;
    end else begin
      if(io_pulseIn) begin
        inArea_target <= (! inArea_target);
      end
    end
  end

  always @(posedge thread_clk) begin
    if(!toplevel_apb_resetn_synchronized) begin
      outArea_target_regNext <= 1'b0;
    end else begin
      outArea_target_regNext <= outArea_target;
    end
  end


endmodule

module APBFrontendRegs_BufferCC_6 (
  input  wire          io_dataIn,
  output wire          io_dataOut,
  input  wire          apb_clock,
  input  wire          apb_resetn
);

  (* async_reg = "true" *) reg                 buffers_0;
  (* async_reg = "true" *) reg                 buffers_1;

  assign io_dataOut = buffers_1;
  always @(posedge apb_clock) begin
    if(!apb_resetn) begin
      buffers_0 <= 1'b0;
      buffers_1 <= 1'b0;
    end else begin
      buffers_0 <= io_dataIn;
      buffers_1 <= buffers_0;
    end
  end


endmodule

//APBFrontendRegs_BufferCC_5 replaced by APBFrontendRegs_BufferCC_3

//APBFrontendRegs_BufferCC_4 replaced by APBFrontendRegs_BufferCC_2

module APBFrontendRegs_BufferCC_3 (
  input  wire          io_dataIn,
  output wire          io_dataOut,
  input  wire          thread_clk,
  input  wire          toplevel_apb_resetn_synchronized_1
);

  (* async_reg = "true" , altera_attribute = "-name ADV_NETLIST_OPT_ALLOWED NEVER_ALLOW" *) reg                 buffers_0;
  (* async_reg = "true" *) reg                 buffers_1;

  assign io_dataOut = buffers_1;
  always @(posedge thread_clk) begin
    if(!toplevel_apb_resetn_synchronized_1) begin
      buffers_0 <= 1'b0;
      buffers_1 <= 1'b0;
    end else begin
      buffers_0 <= io_dataIn;
      buffers_1 <= buffers_0;
    end
  end


endmodule

module APBFrontendRegs_BufferCC_2 (
  input  wire          io_dataIn,
  output wire          io_dataOut,
  input  wire          apb_clock,
  input  wire          apb_resetn
);

  (* async_reg = "true" , altera_attribute = "-name ADV_NETLIST_OPT_ALLOWED NEVER_ALLOW" *) reg                 buffers_0;
  (* async_reg = "true" *) reg                 buffers_1;

  assign io_dataOut = buffers_1;
  always @(posedge apb_clock) begin
    if(!apb_resetn) begin
      buffers_0 <= 1'b0;
      buffers_1 <= 1'b0;
    end else begin
      buffers_0 <= io_dataIn;
      buffers_1 <= buffers_0;
    end
  end


endmodule

module APBFrontendRegs_BufferCC_1 (
  input  wire          io_dataIn,
  output wire          io_dataOut,
  input  wire          thread_clk,
  input  wire          toplevel_apb_resetn_synchronized
);

  (* async_reg = "true" , altera_attribute = "-name ADV_NETLIST_OPT_ALLOWED NEVER_ALLOW" *) reg                 buffers_0;
  (* async_reg = "true" *) reg                 buffers_1;

  assign io_dataOut = buffers_1;
  always @(posedge thread_clk) begin
    if(!toplevel_apb_resetn_synchronized) begin
      buffers_0 <= 1'b0;
      buffers_1 <= 1'b0;
    end else begin
      buffers_0 <= io_dataIn;
      buffers_1 <= buffers_0;
    end
  end


endmodule

module APBFrontendRegs_BufferCC (
  input  wire          io_dataIn,
  output wire          io_dataOut,
  input  wire          thread_clk,
  input  wire          apb_resetn
);

  (* async_reg = "true" *) reg                 buffers_0;
  (* async_reg = "true" *) reg                 buffers_1;

  assign io_dataOut = buffers_1;
  always @(posedge thread_clk or negedge apb_resetn) begin
    if(!apb_resetn) begin
      buffers_0 <= 1'b0;
      buffers_1 <= 1'b0;
    end else begin
      buffers_0 <= io_dataIn;
      buffers_1 <= buffers_0;
    end
  end


endmodule
