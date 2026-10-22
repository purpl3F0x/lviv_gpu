// Generator : SpinalHDL v1.12.3    git head : 591e64062329e5e2e2b81f4d52422948053edb97
// Component : ApbThreadRegs
// Git hash  : 0867eb45c9a7627edf7c710aa90817a6ac31f5e6

`timescale 1ns/1ps

module ApbThreadRegs (
  input  wire [4:0]    s_apb_PADDR,
  input  wire [0:0]    s_apb_PSEL,
  input  wire          s_apb_PENABLE,
  output wire          s_apb_PREADY,
  input  wire          s_apb_PWRITE,
  input  wire [31:0]   s_apb_PWDATA,
  output wire [31:0]   s_apb_PRDATA,
  output wire          s_apb_PSLVERROR,
  input  wire          thread_busy,
  input  wire          zbuf_clear_busy,
  output wire          zbuf_clear,
  output wire          thread_soft_reset,
  output wire          cache_flush,
  input  wire          clk,
  input  wire          resetn,
  input  wire          thread_clk
);

  wire                thread_busy_buffercc_io_dataOut;
  wire                threadSoftResetPulse_pulseCCByToggle_io_pulseOut;
  wire                threadSoftResetPulse_pulseCCByToggle_resetn_synchronized_1;
  wire                zbuf_clear_busy_buffercc_io_dataOut;
  wire                zbufClearPulse_pulseCCByToggle_io_pulseOut;
  wire                cacheFlushPulse_pulseCCByToggle_io_pulseOut;
  wire       [31:0]   busif_bus_rdata;
  reg                 busif_reg_rderr;
  reg        [31:0]   busif_reg_rdata;
  wire                busif_askWrite;
  wire                busif_askRead;
  wire                busif_doWrite;
  wire                busif_doRead;
  wire                read_hit_0x0000;
  wire                write_hit_0x0000;
  wire                BUSY;
  reg                 threadSoftResetPulse;
  wire                read_hit_0x0004;
  wire                write_hit_0x0004;
  wire                ZBUF_CLEAR_1;
  reg                 zbufClearPulse;
  wire                read_hit_0x0008;
  wire                write_hit_0x0008;
  reg                 CACHE_FLUSH_1;
  reg                 cacheFlushPulse;
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

  (* keep_hierarchy = "TRUE" *) ApbThreadRegs_BufferCC_4 thread_busy_buffercc (
    .io_dataIn  (thread_busy                    ), //i
    .io_dataOut (thread_busy_buffercc_io_dataOut), //o
    .clk        (clk                            ), //i
    .resetn     (resetn                         )  //i
  );
  ApbThreadRegs_PulseCCByToggle threadSoftResetPulse_pulseCCByToggle (
    .io_pulseIn            (threadSoftResetPulse                                      ), //i
    .io_pulseOut           (threadSoftResetPulse_pulseCCByToggle_io_pulseOut          ), //o
    .clk                   (clk                                                       ), //i
    .resetn                (resetn                                                    ), //i
    .thread_clk            (thread_clk                                                ), //i
    .resetn_synchronized_1 (threadSoftResetPulse_pulseCCByToggle_resetn_synchronized_1)  //o
  );
  (* keep_hierarchy = "TRUE" *) ApbThreadRegs_BufferCC_4 zbuf_clear_busy_buffercc (
    .io_dataIn  (zbuf_clear_busy                    ), //i
    .io_dataOut (zbuf_clear_busy_buffercc_io_dataOut), //o
    .clk        (clk                                ), //i
    .resetn     (resetn                             )  //i
  );
  ApbThreadRegs_PulseCCByToggle_1 zbufClearPulse_pulseCCByToggle (
    .io_pulseIn            (zbufClearPulse                                            ), //i
    .io_pulseOut           (zbufClearPulse_pulseCCByToggle_io_pulseOut                ), //o
    .clk                   (clk                                                       ), //i
    .resetn                (resetn                                                    ), //i
    .thread_clk            (thread_clk                                                ), //i
    .resetn_synchronized_1 (threadSoftResetPulse_pulseCCByToggle_resetn_synchronized_1)  //i
  );
  ApbThreadRegs_PulseCCByToggle_1 cacheFlushPulse_pulseCCByToggle (
    .io_pulseIn            (cacheFlushPulse                                           ), //i
    .io_pulseOut           (cacheFlushPulse_pulseCCByToggle_io_pulseOut               ), //o
    .clk                   (clk                                                       ), //i
    .resetn                (resetn                                                    ), //i
    .thread_clk            (thread_clk                                                ), //i
    .resetn_synchronized_1 (threadSoftResetPulse_pulseCCByToggle_resetn_synchronized_1)  //i
  );
  assign s_apb_PREADY = 1'b1;
  assign s_apb_PRDATA = busif_bus_rdata;
  assign busif_askWrite = (s_apb_PSEL[0] && s_apb_PWRITE);
  assign busif_askRead = ((s_apb_PSEL[0] && (! s_apb_PWRITE)) && (! s_apb_PENABLE));
  assign busif_doWrite = ((busif_askWrite && s_apb_PENABLE) && s_apb_PREADY);
  assign busif_doRead = (((s_apb_PSEL[0] && (! s_apb_PWRITE)) && s_apb_PENABLE) && s_apb_PREADY);
  assign s_apb_PSLVERROR = busif_reg_rderr;
  assign read_hit_0x0000 = ((s_apb_PADDR == 5'h0) && busif_doRead);
  assign write_hit_0x0000 = ((s_apb_PADDR == 5'h0) && busif_doWrite);
  assign BUSY = thread_busy_buffercc_io_dataOut;
  assign thread_soft_reset = threadSoftResetPulse_pulseCCByToggle_io_pulseOut;
  assign read_hit_0x0004 = ((s_apb_PADDR == 5'h04) && busif_doRead);
  assign write_hit_0x0004 = ((s_apb_PADDR == 5'h04) && busif_doWrite);
  assign ZBUF_CLEAR_1 = zbuf_clear_busy_buffercc_io_dataOut;
  assign zbuf_clear = zbufClearPulse_pulseCCByToggle_io_pulseOut;
  assign read_hit_0x0008 = ((s_apb_PADDR == 5'h08) && busif_doRead);
  assign write_hit_0x0008 = ((s_apb_PADDR == 5'h08) && busif_doWrite);
  assign cache_flush = cacheFlushPulse_pulseCCByToggle_io_pulseOut;
  assign read_hit_0x000c = ((s_apb_PADDR == 5'h0c) && busif_doRead);
  assign write_hit_0x000c = ((s_apb_PADDR == 5'h0c) && busif_doWrite);
  assign read_hit_0x0010 = ((s_apb_PADDR == 5'h10) && busif_doRead);
  assign write_hit_0x0010 = ((s_apb_PADDR == 5'h10) && busif_doWrite);
  assign read_hit_0x0014 = ((s_apb_PADDR == 5'h14) && busif_doRead);
  assign write_hit_0x0014 = ((s_apb_PADDR == 5'h14) && busif_doWrite);
  assign read_hit_0x0018 = ((s_apb_PADDR == 5'h18) && busif_doRead);
  assign write_hit_0x0018 = ((s_apb_PADDR == 5'h18) && busif_doWrite);
  assign read_hit_0x001c = ((s_apb_PADDR == 5'h1c) && busif_doRead);
  assign write_hit_0x001c = ((s_apb_PADDR == 5'h1c) && busif_doWrite);
  assign busif_bus_rdata = busif_reg_rdata;
  always @(posedge clk) begin
    if(!resetn) begin
      busif_reg_rderr <= 1'b0;
      busif_reg_rdata <= 32'h0;
      threadSoftResetPulse <= 1'b0;
      zbufClearPulse <= 1'b0;
      CACHE_FLUSH_1 <= 1'b0;
      cacheFlushPulse <= 1'b0;
    end else begin
      threadSoftResetPulse <= (write_hit_0x0000 && s_apb_PWDATA[0]);
      zbufClearPulse <= (write_hit_0x0004 && s_apb_PWDATA[0]);
      if(write_hit_0x0008) begin
        CACHE_FLUSH_1 <= s_apb_PWDATA[0];
      end
      cacheFlushPulse <= (write_hit_0x0008 && s_apb_PWDATA[0]);
      if(busif_askRead) begin
        case(s_apb_PADDR)
          5'h0 : begin
            busif_reg_rdata <= {31'h0,BUSY};
            busif_reg_rderr <= 1'b0;
          end
          5'h04 : begin
            busif_reg_rdata <= {31'h0,ZBUF_CLEAR_1};
            busif_reg_rderr <= 1'b0;
          end
          5'h08 : begin
            busif_reg_rdata <= {31'h0,1'b0};
            busif_reg_rderr <= 1'b1;
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


endmodule

//ApbThreadRegs_PulseCCByToggle_2 replaced by ApbThreadRegs_PulseCCByToggle_1

module ApbThreadRegs_PulseCCByToggle_1 (
  input  wire          io_pulseIn,
  output wire          io_pulseOut,
  input  wire          clk,
  input  wire          resetn,
  input  wire          thread_clk,
  input  wire          resetn_synchronized_1
);

  wire                inArea_target_buffercc_io_dataOut;
  (* altera_attribute = "-name ADV_NETLIST_OPT_ALLOWED NEVER_ALLOW" *) reg                 inArea_target;
  wire                outArea_target;
  reg                 outArea_target_regNext;

  (* keep_hierarchy = "TRUE" *) ApbThreadRegs_BufferCC_2 inArea_target_buffercc (
    .io_dataIn             (inArea_target                    ), //i
    .io_dataOut            (inArea_target_buffercc_io_dataOut), //o
    .thread_clk            (thread_clk                       ), //i
    .resetn_synchronized_1 (resetn_synchronized_1            )  //i
  );
  assign outArea_target = inArea_target_buffercc_io_dataOut;
  assign io_pulseOut = (outArea_target ^ outArea_target_regNext);
  always @(posedge clk) begin
    if(!resetn) begin
      inArea_target <= 1'b0;
    end else begin
      if(io_pulseIn) begin
        inArea_target <= (! inArea_target);
      end
    end
  end

  always @(posedge thread_clk) begin
    if(!resetn_synchronized_1) begin
      outArea_target_regNext <= 1'b0;
    end else begin
      outArea_target_regNext <= outArea_target;
    end
  end


endmodule

//ApbThreadRegs_BufferCC_5 replaced by ApbThreadRegs_BufferCC_4

module ApbThreadRegs_PulseCCByToggle (
  input  wire          io_pulseIn,
  output wire          io_pulseOut,
  input  wire          clk,
  input  wire          resetn,
  input  wire          thread_clk,
  output wire          resetn_synchronized_1
);

  wire                resetn_asyncAssertSyncDeassert_buffercc_io_dataOut;
  wire                inArea_target_buffercc_io_dataOut;
  (* altera_attribute = "-name ADV_NETLIST_OPT_ALLOWED NEVER_ALLOW" *) reg                 inArea_target;
  wire                resetn_asyncAssertSyncDeassert;
  wire                resetn_synchronized;
  wire                outArea_target;
  reg                 outArea_target_regNext;

  (* keep_hierarchy = "TRUE" *) ApbThreadRegs_BufferCC resetn_asyncAssertSyncDeassert_buffercc (
    .io_dataIn  (resetn_asyncAssertSyncDeassert                    ), //i
    .io_dataOut (resetn_asyncAssertSyncDeassert_buffercc_io_dataOut), //o
    .thread_clk (thread_clk                                        ), //i
    .resetn     (resetn                                            )  //i
  );
  (* keep_hierarchy = "TRUE" *) ApbThreadRegs_BufferCC_1 inArea_target_buffercc (
    .io_dataIn           (inArea_target                    ), //i
    .io_dataOut          (inArea_target_buffercc_io_dataOut), //o
    .thread_clk          (thread_clk                       ), //i
    .resetn_synchronized (resetn_synchronized              )  //i
  );
  assign resetn_asyncAssertSyncDeassert = (1'b1 ^ 1'b0);
  assign resetn_synchronized = resetn_asyncAssertSyncDeassert_buffercc_io_dataOut;
  assign outArea_target = inArea_target_buffercc_io_dataOut;
  assign io_pulseOut = (outArea_target ^ outArea_target_regNext);
  assign resetn_synchronized_1 = resetn_synchronized;
  always @(posedge clk) begin
    if(!resetn) begin
      inArea_target <= 1'b0;
    end else begin
      if(io_pulseIn) begin
        inArea_target <= (! inArea_target);
      end
    end
  end

  always @(posedge thread_clk) begin
    if(!resetn_synchronized) begin
      outArea_target_regNext <= 1'b0;
    end else begin
      outArea_target_regNext <= outArea_target;
    end
  end


endmodule

module ApbThreadRegs_BufferCC_4 (
  input  wire          io_dataIn,
  output wire          io_dataOut,
  input  wire          clk,
  input  wire          resetn
);

  (* async_reg = "true" *) reg                 buffers_0;
  (* async_reg = "true" *) reg                 buffers_1;

  assign io_dataOut = buffers_1;
  always @(posedge clk) begin
    if(!resetn) begin
      buffers_0 <= 1'b0;
      buffers_1 <= 1'b0;
    end else begin
      buffers_0 <= io_dataIn;
      buffers_1 <= buffers_0;
    end
  end


endmodule

//ApbThreadRegs_BufferCC_3 replaced by ApbThreadRegs_BufferCC_2

module ApbThreadRegs_BufferCC_2 (
  input  wire          io_dataIn,
  output wire          io_dataOut,
  input  wire          thread_clk,
  input  wire          resetn_synchronized_1
);

  (* async_reg = "true" , altera_attribute = "-name ADV_NETLIST_OPT_ALLOWED NEVER_ALLOW" *) reg                 buffers_0;
  (* async_reg = "true" *) reg                 buffers_1;

  assign io_dataOut = buffers_1;
  always @(posedge thread_clk) begin
    if(!resetn_synchronized_1) begin
      buffers_0 <= 1'b0;
      buffers_1 <= 1'b0;
    end else begin
      buffers_0 <= io_dataIn;
      buffers_1 <= buffers_0;
    end
  end


endmodule

module ApbThreadRegs_BufferCC_1 (
  input  wire          io_dataIn,
  output wire          io_dataOut,
  input  wire          thread_clk,
  input  wire          resetn_synchronized
);

  (* async_reg = "true" , altera_attribute = "-name ADV_NETLIST_OPT_ALLOWED NEVER_ALLOW" *) reg                 buffers_0;
  (* async_reg = "true" *) reg                 buffers_1;

  assign io_dataOut = buffers_1;
  always @(posedge thread_clk) begin
    if(!resetn_synchronized) begin
      buffers_0 <= 1'b0;
      buffers_1 <= 1'b0;
    end else begin
      buffers_0 <= io_dataIn;
      buffers_1 <= buffers_0;
    end
  end


endmodule

module ApbThreadRegs_BufferCC (
  input  wire          io_dataIn,
  output wire          io_dataOut,
  input  wire          thread_clk,
  input  wire          resetn
);

  (* async_reg = "true" *) reg                 buffers_0;
  (* async_reg = "true" *) reg                 buffers_1;

  assign io_dataOut = buffers_1;
  always @(posedge thread_clk or negedge resetn) begin
    if(!resetn) begin
      buffers_0 <= 1'b0;
      buffers_1 <= 1'b0;
    end else begin
      buffers_0 <= io_dataIn;
      buffers_1 <= buffers_0;
    end
  end


endmodule
