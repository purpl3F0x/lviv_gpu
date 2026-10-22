// Generator : SpinalHDL v1.12.3    git head : 591e64062329e5e2e2b81f4d52422948053edb97
// Component : Axi4ToApbXbar
// Git hash  : 0867eb45c9a7627edf7c710aa90817a6ac31f5e6

`timescale 1ns/1ps

module Axi4ToApbXbar (
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 AWVALID" *) input  wire          m_axi_0_awvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 AWREADY" *) output wire          m_axi_0_awready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 AWADDR" *) input  wire [11:0]   m_axi_0_awaddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 AWID" *) input  wire [3:0]    m_axi_0_awid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 AWLEN" *) input  wire [7:0]    m_axi_0_awlen,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 AWSIZE" *) input  wire [2:0]    m_axi_0_awsize,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 AWBURST" *) input  wire [1:0]    m_axi_0_awburst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 WVALID" *) input  wire          m_axi_0_wvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 WREADY" *) output wire          m_axi_0_wready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 WDATA" *) input  wire [31:0]   m_axi_0_wdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 WSTRB" *) input  wire [3:0]    m_axi_0_wstrb,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 WLAST" *) input  wire          m_axi_0_wlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 BVALID" *) output wire          m_axi_0_bvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 BREADY" *) input  wire          m_axi_0_bready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 BID" *) output wire [3:0]    m_axi_0_bid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 BRESP" *) output wire [1:0]    m_axi_0_bresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 ARVALID" , X_INTERFACE_MODE = "slave" , X_INTERFACE_PARAMETER = "PROTOCOL AXI4, READ_WRITE_MODE READ_WRITE, ADDR_WIDTH 12, DATA_WIDTH 32, ID_WIDTH 4, NUM_READ_OUTSTANDING 32, NUM_WRITE_OUTSTANDING 32, MAX_BURST_LENGTH 1" *) input  wire          m_axi_0_arvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 ARREADY" *) output wire          m_axi_0_arready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 ARADDR" *) input  wire [11:0]   m_axi_0_araddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 ARID" *) input  wire [3:0]    m_axi_0_arid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 ARLEN" *) input  wire [7:0]    m_axi_0_arlen,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 ARSIZE" *) input  wire [2:0]    m_axi_0_arsize,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 ARBURST" *) input  wire [1:0]    m_axi_0_arburst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 RVALID" *) output wire          m_axi_0_rvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 RREADY" *) input  wire          m_axi_0_rready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 RDATA" *) output wire [31:0]   m_axi_0_rdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 RID" *) output wire [3:0]    m_axi_0_rid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 RRESP" *) output wire [1:0]    m_axi_0_rresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_0 RLAST" *) output wire          m_axi_0_rlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 AWVALID" *) input  wire          m_axi_1_awvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 AWREADY" *) output wire          m_axi_1_awready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 AWADDR" *) input  wire [11:0]   m_axi_1_awaddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 AWID" *) input  wire [3:0]    m_axi_1_awid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 AWLEN" *) input  wire [7:0]    m_axi_1_awlen,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 AWSIZE" *) input  wire [2:0]    m_axi_1_awsize,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 AWBURST" *) input  wire [1:0]    m_axi_1_awburst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 WVALID" *) input  wire          m_axi_1_wvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 WREADY" *) output wire          m_axi_1_wready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 WDATA" *) input  wire [31:0]   m_axi_1_wdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 WSTRB" *) input  wire [3:0]    m_axi_1_wstrb,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 WLAST" *) input  wire          m_axi_1_wlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 BVALID" *) output wire          m_axi_1_bvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 BREADY" *) input  wire          m_axi_1_bready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 BID" *) output wire [3:0]    m_axi_1_bid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 BRESP" *) output wire [1:0]    m_axi_1_bresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 ARVALID" , X_INTERFACE_MODE = "slave" , X_INTERFACE_PARAMETER = "PROTOCOL AXI4, READ_WRITE_MODE READ_WRITE, ADDR_WIDTH 12, DATA_WIDTH 32, ID_WIDTH 4, NUM_READ_OUTSTANDING 32, NUM_WRITE_OUTSTANDING 32, MAX_BURST_LENGTH 1" *) input  wire          m_axi_1_arvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 ARREADY" *) output wire          m_axi_1_arready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 ARADDR" *) input  wire [11:0]   m_axi_1_araddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 ARID" *) input  wire [3:0]    m_axi_1_arid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 ARLEN" *) input  wire [7:0]    m_axi_1_arlen,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 ARSIZE" *) input  wire [2:0]    m_axi_1_arsize,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 ARBURST" *) input  wire [1:0]    m_axi_1_arburst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 RVALID" *) output wire          m_axi_1_rvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 RREADY" *) input  wire          m_axi_1_rready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 RDATA" *) output wire [31:0]   m_axi_1_rdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 RID" *) output wire [3:0]    m_axi_1_rid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 RRESP" *) output wire [1:0]    m_axi_1_rresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_1 RLAST" *) output wire          m_axi_1_rlast,
  output wire [9:0]    lut_PADDR,
  output wire [0:0]    lut_PSEL,
  output wire          lut_PENABLE,
  input  wire          lut_PREADY,
  output wire          lut_PWRITE,
  output wire [31:0]   lut_PWDATA,
  input  wire [31:0]   lut_PRDATA,
  input  wire          lut_PSLVERROR,
  output wire [4:0]    frontend_PADDR,
  output wire [0:0]    frontend_PSEL,
  output wire          frontend_PENABLE,
  input  wire          frontend_PREADY,
  output wire          frontend_PWRITE,
  output wire [31:0]   frontend_PWDATA,
  input  wire [31:0]   frontend_PRDATA,
  input  wire          frontend_PSLVERROR,
  output wire [4:0]    threadRegs_0_PADDR,
  output wire [0:0]    threadRegs_0_PSEL,
  output wire          threadRegs_0_PENABLE,
  input  wire          threadRegs_0_PREADY,
  output wire          threadRegs_0_PWRITE,
  output wire [31:0]   threadRegs_0_PWDATA,
  input  wire [31:0]   threadRegs_0_PRDATA,
  input  wire          threadRegs_0_PSLVERROR,
  output wire [4:0]    threadRegs_1_PADDR,
  output wire [0:0]    threadRegs_1_PSEL,
  output wire          threadRegs_1_PENABLE,
  input  wire          threadRegs_1_PREADY,
  output wire          threadRegs_1_PWRITE,
  output wire [31:0]   threadRegs_1_PWDATA,
  input  wire [31:0]   threadRegs_1_PRDATA,
  input  wire          threadRegs_1_PSLVERROR,
  output wire [4:0]    threadRegs_2_PADDR,
  output wire [0:0]    threadRegs_2_PSEL,
  output wire          threadRegs_2_PENABLE,
  input  wire          threadRegs_2_PREADY,
  output wire          threadRegs_2_PWRITE,
  output wire [31:0]   threadRegs_2_PWDATA,
  input  wire [31:0]   threadRegs_2_PRDATA,
  input  wire          threadRegs_2_PSLVERROR,
  output wire [4:0]    threadRegs_3_PADDR,
  output wire [0:0]    threadRegs_3_PSEL,
  output wire          threadRegs_3_PENABLE,
  input  wire          threadRegs_3_PREADY,
  output wire          threadRegs_3_PWRITE,
  output wire [31:0]   threadRegs_3_PWDATA,
  input  wire [31:0]   threadRegs_3_PRDATA,
  input  wire          threadRegs_3_PSLVERROR,
  output wire [6:0]    tileDma_PADDR,
  output wire [0:0]    tileDma_PSEL,
  output wire          tileDma_PENABLE,
  input  wire          tileDma_PREADY,
  output wire          tileDma_PWRITE,
  output wire [31:0]   tileDma_PWDATA,
  input  wire [31:0]   tileDma_PRDATA,
  input  wire          tileDma_PSLVERROR,
  output wire [6:0]    visDma_PADDR,
  output wire [0:0]    visDma_PSEL,
  output wire          visDma_PENABLE,
  input  wire          visDma_PREADY,
  output wire          visDma_PWRITE,
  output wire [31:0]   visDma_PWDATA,
  input  wire [31:0]   visDma_PRDATA,
  input  wire          visDma_PSLVERROR,
  input  wire          clk,
  input  wire          resetn
);

  wire                arbiter_io_sharedInputs_0_arw_payload_write;
  wire                arbiter_io_sharedInputs_1_arw_payload_write;
  wire       [9:0]    lutSlice_io_s_PADDR;
  wire       [4:0]    frontendSlice_io_s_PADDR;
  wire       [4:0]    threadSlices_0_io_s_PADDR;
  wire       [4:0]    threadSlices_1_io_s_PADDR;
  wire       [4:0]    threadSlices_2_io_s_PADDR;
  wire       [4:0]    threadSlices_3_io_s_PADDR;
  wire       [6:0]    tileDmaSlice_io_s_PADDR;
  wire       [6:0]    visDmaSlice_io_s_PADDR;
  wire                apbBridge_io_axi_arw_ready;
  wire                apbBridge_io_axi_w_ready;
  wire                apbBridge_io_axi_b_valid;
  wire       [4:0]    apbBridge_io_axi_b_payload_id;
  wire       [1:0]    apbBridge_io_axi_b_payload_resp;
  wire                apbBridge_io_axi_r_valid;
  wire       [31:0]   apbBridge_io_axi_r_payload_data;
  wire       [4:0]    apbBridge_io_axi_r_payload_id;
  wire       [1:0]    apbBridge_io_axi_r_payload_resp;
  wire                apbBridge_io_axi_r_payload_last;
  wire       [11:0]   apbBridge_io_apb_PADDR;
  wire       [0:0]    apbBridge_io_apb_PSEL;
  wire                apbBridge_io_apb_PENABLE;
  wire                apbBridge_io_apb_PWRITE;
  wire       [31:0]   apbBridge_io_apb_PWDATA;
  wire                arbiter_io_sharedInputs_0_arw_ready;
  wire                arbiter_io_sharedInputs_0_w_ready;
  wire                arbiter_io_sharedInputs_0_b_valid;
  wire       [3:0]    arbiter_io_sharedInputs_0_b_payload_id;
  wire       [1:0]    arbiter_io_sharedInputs_0_b_payload_resp;
  wire                arbiter_io_sharedInputs_0_r_valid;
  wire       [31:0]   arbiter_io_sharedInputs_0_r_payload_data;
  wire       [3:0]    arbiter_io_sharedInputs_0_r_payload_id;
  wire       [1:0]    arbiter_io_sharedInputs_0_r_payload_resp;
  wire                arbiter_io_sharedInputs_0_r_payload_last;
  wire                arbiter_io_sharedInputs_1_arw_ready;
  wire                arbiter_io_sharedInputs_1_w_ready;
  wire                arbiter_io_sharedInputs_1_b_valid;
  wire       [3:0]    arbiter_io_sharedInputs_1_b_payload_id;
  wire       [1:0]    arbiter_io_sharedInputs_1_b_payload_resp;
  wire                arbiter_io_sharedInputs_1_r_valid;
  wire       [31:0]   arbiter_io_sharedInputs_1_r_payload_data;
  wire       [3:0]    arbiter_io_sharedInputs_1_r_payload_id;
  wire       [1:0]    arbiter_io_sharedInputs_1_r_payload_resp;
  wire                arbiter_io_sharedInputs_1_r_payload_last;
  wire                arbiter_io_output_arw_valid;
  wire       [11:0]   arbiter_io_output_arw_payload_addr;
  wire       [4:0]    arbiter_io_output_arw_payload_id;
  wire       [7:0]    arbiter_io_output_arw_payload_len;
  wire       [2:0]    arbiter_io_output_arw_payload_size;
  wire       [1:0]    arbiter_io_output_arw_payload_burst;
  wire                arbiter_io_output_arw_payload_write;
  wire                arbiter_io_output_w_valid;
  wire       [31:0]   arbiter_io_output_w_payload_data;
  wire       [3:0]    arbiter_io_output_w_payload_strb;
  wire                arbiter_io_output_w_payload_last;
  wire                arbiter_io_output_b_ready;
  wire                arbiter_io_output_r_ready;
  wire                m_axi_0_ar_fifo_io_push_ready;
  wire                m_axi_0_ar_fifo_io_pop_valid;
  wire       [11:0]   m_axi_0_ar_fifo_io_pop_payload_addr;
  wire       [3:0]    m_axi_0_ar_fifo_io_pop_payload_id;
  wire       [7:0]    m_axi_0_ar_fifo_io_pop_payload_len;
  wire       [2:0]    m_axi_0_ar_fifo_io_pop_payload_size;
  wire       [1:0]    m_axi_0_ar_fifo_io_pop_payload_burst;
  wire       [5:0]    m_axi_0_ar_fifo_io_occupancy;
  wire       [5:0]    m_axi_0_ar_fifo_io_availability;
  wire                m_axi_0_aw_fifo_io_push_ready;
  wire                m_axi_0_aw_fifo_io_pop_valid;
  wire       [11:0]   m_axi_0_aw_fifo_io_pop_payload_addr;
  wire       [3:0]    m_axi_0_aw_fifo_io_pop_payload_id;
  wire       [7:0]    m_axi_0_aw_fifo_io_pop_payload_len;
  wire       [2:0]    m_axi_0_aw_fifo_io_pop_payload_size;
  wire       [1:0]    m_axi_0_aw_fifo_io_pop_payload_burst;
  wire       [5:0]    m_axi_0_aw_fifo_io_occupancy;
  wire       [5:0]    m_axi_0_aw_fifo_io_availability;
  wire                m_axi_0_w_fifo_io_push_ready;
  wire                m_axi_0_w_fifo_io_pop_valid;
  wire       [31:0]   m_axi_0_w_fifo_io_pop_payload_data;
  wire       [3:0]    m_axi_0_w_fifo_io_pop_payload_strb;
  wire                m_axi_0_w_fifo_io_pop_payload_last;
  wire       [5:0]    m_axi_0_w_fifo_io_occupancy;
  wire       [5:0]    m_axi_0_w_fifo_io_availability;
  wire                streamArbiter_io_inputs_0_ready;
  wire                streamArbiter_io_inputs_1_ready;
  wire                streamArbiter_io_output_valid;
  wire       [11:0]   streamArbiter_io_output_payload_addr;
  wire       [3:0]    streamArbiter_io_output_payload_id;
  wire       [7:0]    streamArbiter_io_output_payload_len;
  wire       [2:0]    streamArbiter_io_output_payload_size;
  wire       [1:0]    streamArbiter_io_output_payload_burst;
  wire       [0:0]    streamArbiter_io_chosen;
  wire       [1:0]    streamArbiter_io_chosenOH;
  wire                m_axi_1_ar_fifo_io_push_ready;
  wire                m_axi_1_ar_fifo_io_pop_valid;
  wire       [11:0]   m_axi_1_ar_fifo_io_pop_payload_addr;
  wire       [3:0]    m_axi_1_ar_fifo_io_pop_payload_id;
  wire       [7:0]    m_axi_1_ar_fifo_io_pop_payload_len;
  wire       [2:0]    m_axi_1_ar_fifo_io_pop_payload_size;
  wire       [1:0]    m_axi_1_ar_fifo_io_pop_payload_burst;
  wire       [5:0]    m_axi_1_ar_fifo_io_occupancy;
  wire       [5:0]    m_axi_1_ar_fifo_io_availability;
  wire                m_axi_1_aw_fifo_io_push_ready;
  wire                m_axi_1_aw_fifo_io_pop_valid;
  wire       [11:0]   m_axi_1_aw_fifo_io_pop_payload_addr;
  wire       [3:0]    m_axi_1_aw_fifo_io_pop_payload_id;
  wire       [7:0]    m_axi_1_aw_fifo_io_pop_payload_len;
  wire       [2:0]    m_axi_1_aw_fifo_io_pop_payload_size;
  wire       [1:0]    m_axi_1_aw_fifo_io_pop_payload_burst;
  wire       [5:0]    m_axi_1_aw_fifo_io_occupancy;
  wire       [5:0]    m_axi_1_aw_fifo_io_availability;
  wire                m_axi_1_w_fifo_io_push_ready;
  wire                m_axi_1_w_fifo_io_pop_valid;
  wire       [31:0]   m_axi_1_w_fifo_io_pop_payload_data;
  wire       [3:0]    m_axi_1_w_fifo_io_pop_payload_strb;
  wire                m_axi_1_w_fifo_io_pop_payload_last;
  wire       [5:0]    m_axi_1_w_fifo_io_occupancy;
  wire       [5:0]    m_axi_1_w_fifo_io_availability;
  wire                streamArbiter_1_io_inputs_0_ready;
  wire                streamArbiter_1_io_inputs_1_ready;
  wire                streamArbiter_1_io_output_valid;
  wire       [11:0]   streamArbiter_1_io_output_payload_addr;
  wire       [3:0]    streamArbiter_1_io_output_payload_id;
  wire       [7:0]    streamArbiter_1_io_output_payload_len;
  wire       [2:0]    streamArbiter_1_io_output_payload_size;
  wire       [1:0]    streamArbiter_1_io_output_payload_burst;
  wire       [0:0]    streamArbiter_1_io_chosen;
  wire       [1:0]    streamArbiter_1_io_chosenOH;
  wire                lutSlice_io_s_PREADY;
  wire       [31:0]   lutSlice_io_s_PRDATA;
  wire                lutSlice_io_s_PSLVERROR;
  wire       [9:0]    lutSlice_io_m_PADDR;
  wire       [0:0]    lutSlice_io_m_PSEL;
  wire                lutSlice_io_m_PENABLE;
  wire                lutSlice_io_m_PWRITE;
  wire       [31:0]   lutSlice_io_m_PWDATA;
  wire                frontendSlice_io_s_PREADY;
  wire       [31:0]   frontendSlice_io_s_PRDATA;
  wire                frontendSlice_io_s_PSLVERROR;
  wire       [4:0]    frontendSlice_io_m_PADDR;
  wire       [0:0]    frontendSlice_io_m_PSEL;
  wire                frontendSlice_io_m_PENABLE;
  wire                frontendSlice_io_m_PWRITE;
  wire       [31:0]   frontendSlice_io_m_PWDATA;
  wire                threadSlices_0_io_s_PREADY;
  wire       [31:0]   threadSlices_0_io_s_PRDATA;
  wire                threadSlices_0_io_s_PSLVERROR;
  wire       [4:0]    threadSlices_0_io_m_PADDR;
  wire       [0:0]    threadSlices_0_io_m_PSEL;
  wire                threadSlices_0_io_m_PENABLE;
  wire                threadSlices_0_io_m_PWRITE;
  wire       [31:0]   threadSlices_0_io_m_PWDATA;
  wire                threadSlices_1_io_s_PREADY;
  wire       [31:0]   threadSlices_1_io_s_PRDATA;
  wire                threadSlices_1_io_s_PSLVERROR;
  wire       [4:0]    threadSlices_1_io_m_PADDR;
  wire       [0:0]    threadSlices_1_io_m_PSEL;
  wire                threadSlices_1_io_m_PENABLE;
  wire                threadSlices_1_io_m_PWRITE;
  wire       [31:0]   threadSlices_1_io_m_PWDATA;
  wire                threadSlices_2_io_s_PREADY;
  wire       [31:0]   threadSlices_2_io_s_PRDATA;
  wire                threadSlices_2_io_s_PSLVERROR;
  wire       [4:0]    threadSlices_2_io_m_PADDR;
  wire       [0:0]    threadSlices_2_io_m_PSEL;
  wire                threadSlices_2_io_m_PENABLE;
  wire                threadSlices_2_io_m_PWRITE;
  wire       [31:0]   threadSlices_2_io_m_PWDATA;
  wire                threadSlices_3_io_s_PREADY;
  wire       [31:0]   threadSlices_3_io_s_PRDATA;
  wire                threadSlices_3_io_s_PSLVERROR;
  wire       [4:0]    threadSlices_3_io_m_PADDR;
  wire       [0:0]    threadSlices_3_io_m_PSEL;
  wire                threadSlices_3_io_m_PENABLE;
  wire                threadSlices_3_io_m_PWRITE;
  wire       [31:0]   threadSlices_3_io_m_PWDATA;
  wire                tileDmaSlice_io_s_PREADY;
  wire       [31:0]   tileDmaSlice_io_s_PRDATA;
  wire                tileDmaSlice_io_s_PSLVERROR;
  wire       [6:0]    tileDmaSlice_io_m_PADDR;
  wire       [0:0]    tileDmaSlice_io_m_PSEL;
  wire                tileDmaSlice_io_m_PENABLE;
  wire                tileDmaSlice_io_m_PWRITE;
  wire       [31:0]   tileDmaSlice_io_m_PWDATA;
  wire                visDmaSlice_io_s_PREADY;
  wire       [31:0]   visDmaSlice_io_s_PRDATA;
  wire                visDmaSlice_io_s_PSLVERROR;
  wire       [6:0]    visDmaSlice_io_m_PADDR;
  wire       [0:0]    visDmaSlice_io_m_PSEL;
  wire                visDmaSlice_io_m_PENABLE;
  wire                visDmaSlice_io_m_PWRITE;
  wire       [31:0]   visDmaSlice_io_m_PWDATA;
  wire                io_apb_decoder_io_input_PREADY;
  wire       [31:0]   io_apb_decoder_io_input_PRDATA;
  wire                io_apb_decoder_io_input_PSLVERROR;
  wire       [11:0]   io_apb_decoder_io_output_PADDR;
  wire       [7:0]    io_apb_decoder_io_output_PSEL;
  wire                io_apb_decoder_io_output_PENABLE;
  wire                io_apb_decoder_io_output_PWRITE;
  wire       [31:0]   io_apb_decoder_io_output_PWDATA;
  wire                apb3Router_io_input_PREADY;
  wire       [31:0]   apb3Router_io_input_PRDATA;
  wire                apb3Router_io_input_PSLVERROR;
  wire       [11:0]   apb3Router_io_outputs_0_PADDR;
  wire       [0:0]    apb3Router_io_outputs_0_PSEL;
  wire                apb3Router_io_outputs_0_PENABLE;
  wire                apb3Router_io_outputs_0_PWRITE;
  wire       [31:0]   apb3Router_io_outputs_0_PWDATA;
  wire       [11:0]   apb3Router_io_outputs_1_PADDR;
  wire       [0:0]    apb3Router_io_outputs_1_PSEL;
  wire                apb3Router_io_outputs_1_PENABLE;
  wire                apb3Router_io_outputs_1_PWRITE;
  wire       [31:0]   apb3Router_io_outputs_1_PWDATA;
  wire       [11:0]   apb3Router_io_outputs_2_PADDR;
  wire       [0:0]    apb3Router_io_outputs_2_PSEL;
  wire                apb3Router_io_outputs_2_PENABLE;
  wire                apb3Router_io_outputs_2_PWRITE;
  wire       [31:0]   apb3Router_io_outputs_2_PWDATA;
  wire       [11:0]   apb3Router_io_outputs_3_PADDR;
  wire       [0:0]    apb3Router_io_outputs_3_PSEL;
  wire                apb3Router_io_outputs_3_PENABLE;
  wire                apb3Router_io_outputs_3_PWRITE;
  wire       [31:0]   apb3Router_io_outputs_3_PWDATA;
  wire       [11:0]   apb3Router_io_outputs_4_PADDR;
  wire       [0:0]    apb3Router_io_outputs_4_PSEL;
  wire                apb3Router_io_outputs_4_PENABLE;
  wire                apb3Router_io_outputs_4_PWRITE;
  wire       [31:0]   apb3Router_io_outputs_4_PWDATA;
  wire       [11:0]   apb3Router_io_outputs_5_PADDR;
  wire       [0:0]    apb3Router_io_outputs_5_PSEL;
  wire                apb3Router_io_outputs_5_PENABLE;
  wire                apb3Router_io_outputs_5_PWRITE;
  wire       [31:0]   apb3Router_io_outputs_5_PWDATA;
  wire       [11:0]   apb3Router_io_outputs_6_PADDR;
  wire       [0:0]    apb3Router_io_outputs_6_PSEL;
  wire                apb3Router_io_outputs_6_PENABLE;
  wire                apb3Router_io_outputs_6_PWRITE;
  wire       [31:0]   apb3Router_io_outputs_6_PWDATA;
  wire       [11:0]   apb3Router_io_outputs_7_PADDR;
  wire       [0:0]    apb3Router_io_outputs_7_PSEL;
  wire                apb3Router_io_outputs_7_PENABLE;
  wire                apb3Router_io_outputs_7_PWRITE;
  wire       [31:0]   apb3Router_io_outputs_7_PWDATA;

  Axi4ToApbXbar_Axi4SharedToApb3Bridge apbBridge (
    .io_axi_arw_valid         (arbiter_io_output_arw_valid             ), //i
    .io_axi_arw_ready         (apbBridge_io_axi_arw_ready              ), //o
    .io_axi_arw_payload_addr  (arbiter_io_output_arw_payload_addr[11:0]), //i
    .io_axi_arw_payload_id    (arbiter_io_output_arw_payload_id[4:0]   ), //i
    .io_axi_arw_payload_len   (arbiter_io_output_arw_payload_len[7:0]  ), //i
    .io_axi_arw_payload_size  (arbiter_io_output_arw_payload_size[2:0] ), //i
    .io_axi_arw_payload_burst (arbiter_io_output_arw_payload_burst[1:0]), //i
    .io_axi_arw_payload_write (arbiter_io_output_arw_payload_write     ), //i
    .io_axi_w_valid           (arbiter_io_output_w_valid               ), //i
    .io_axi_w_ready           (apbBridge_io_axi_w_ready                ), //o
    .io_axi_w_payload_data    (arbiter_io_output_w_payload_data[31:0]  ), //i
    .io_axi_w_payload_strb    (arbiter_io_output_w_payload_strb[3:0]   ), //i
    .io_axi_w_payload_last    (arbiter_io_output_w_payload_last        ), //i
    .io_axi_b_valid           (apbBridge_io_axi_b_valid                ), //o
    .io_axi_b_ready           (arbiter_io_output_b_ready               ), //i
    .io_axi_b_payload_id      (apbBridge_io_axi_b_payload_id[4:0]      ), //o
    .io_axi_b_payload_resp    (apbBridge_io_axi_b_payload_resp[1:0]    ), //o
    .io_axi_r_valid           (apbBridge_io_axi_r_valid                ), //o
    .io_axi_r_ready           (arbiter_io_output_r_ready               ), //i
    .io_axi_r_payload_data    (apbBridge_io_axi_r_payload_data[31:0]   ), //o
    .io_axi_r_payload_id      (apbBridge_io_axi_r_payload_id[4:0]      ), //o
    .io_axi_r_payload_resp    (apbBridge_io_axi_r_payload_resp[1:0]    ), //o
    .io_axi_r_payload_last    (apbBridge_io_axi_r_payload_last         ), //o
    .io_apb_PADDR             (apbBridge_io_apb_PADDR[11:0]            ), //o
    .io_apb_PSEL              (apbBridge_io_apb_PSEL                   ), //o
    .io_apb_PENABLE           (apbBridge_io_apb_PENABLE                ), //o
    .io_apb_PREADY            (io_apb_decoder_io_input_PREADY          ), //i
    .io_apb_PWRITE            (apbBridge_io_apb_PWRITE                 ), //o
    .io_apb_PWDATA            (apbBridge_io_apb_PWDATA[31:0]           ), //o
    .io_apb_PRDATA            (io_apb_decoder_io_input_PRDATA[31:0]    ), //i
    .io_apb_PSLVERROR         (io_apb_decoder_io_input_PSLVERROR       ), //i
    .clk                      (clk                                     ), //i
    .resetn                   (resetn                                  )  //i
  );
  Axi4ToApbXbar_Axi4SharedArbiter arbiter (
    .io_sharedInputs_0_arw_valid         (streamArbiter_io_output_valid                 ), //i
    .io_sharedInputs_0_arw_ready         (arbiter_io_sharedInputs_0_arw_ready           ), //o
    .io_sharedInputs_0_arw_payload_addr  (streamArbiter_io_output_payload_addr[11:0]    ), //i
    .io_sharedInputs_0_arw_payload_id    (streamArbiter_io_output_payload_id[3:0]       ), //i
    .io_sharedInputs_0_arw_payload_len   (streamArbiter_io_output_payload_len[7:0]      ), //i
    .io_sharedInputs_0_arw_payload_size  (streamArbiter_io_output_payload_size[2:0]     ), //i
    .io_sharedInputs_0_arw_payload_burst (streamArbiter_io_output_payload_burst[1:0]    ), //i
    .io_sharedInputs_0_arw_payload_write (arbiter_io_sharedInputs_0_arw_payload_write   ), //i
    .io_sharedInputs_0_w_valid           (m_axi_0_w_fifo_io_pop_valid                   ), //i
    .io_sharedInputs_0_w_ready           (arbiter_io_sharedInputs_0_w_ready             ), //o
    .io_sharedInputs_0_w_payload_data    (m_axi_0_w_fifo_io_pop_payload_data[31:0]      ), //i
    .io_sharedInputs_0_w_payload_strb    (m_axi_0_w_fifo_io_pop_payload_strb[3:0]       ), //i
    .io_sharedInputs_0_w_payload_last    (m_axi_0_w_fifo_io_pop_payload_last            ), //i
    .io_sharedInputs_0_b_valid           (arbiter_io_sharedInputs_0_b_valid             ), //o
    .io_sharedInputs_0_b_ready           (m_axi_0_bready                                ), //i
    .io_sharedInputs_0_b_payload_id      (arbiter_io_sharedInputs_0_b_payload_id[3:0]   ), //o
    .io_sharedInputs_0_b_payload_resp    (arbiter_io_sharedInputs_0_b_payload_resp[1:0] ), //o
    .io_sharedInputs_0_r_valid           (arbiter_io_sharedInputs_0_r_valid             ), //o
    .io_sharedInputs_0_r_ready           (m_axi_0_rready                                ), //i
    .io_sharedInputs_0_r_payload_data    (arbiter_io_sharedInputs_0_r_payload_data[31:0]), //o
    .io_sharedInputs_0_r_payload_id      (arbiter_io_sharedInputs_0_r_payload_id[3:0]   ), //o
    .io_sharedInputs_0_r_payload_resp    (arbiter_io_sharedInputs_0_r_payload_resp[1:0] ), //o
    .io_sharedInputs_0_r_payload_last    (arbiter_io_sharedInputs_0_r_payload_last      ), //o
    .io_sharedInputs_1_arw_valid         (streamArbiter_1_io_output_valid               ), //i
    .io_sharedInputs_1_arw_ready         (arbiter_io_sharedInputs_1_arw_ready           ), //o
    .io_sharedInputs_1_arw_payload_addr  (streamArbiter_1_io_output_payload_addr[11:0]  ), //i
    .io_sharedInputs_1_arw_payload_id    (streamArbiter_1_io_output_payload_id[3:0]     ), //i
    .io_sharedInputs_1_arw_payload_len   (streamArbiter_1_io_output_payload_len[7:0]    ), //i
    .io_sharedInputs_1_arw_payload_size  (streamArbiter_1_io_output_payload_size[2:0]   ), //i
    .io_sharedInputs_1_arw_payload_burst (streamArbiter_1_io_output_payload_burst[1:0]  ), //i
    .io_sharedInputs_1_arw_payload_write (arbiter_io_sharedInputs_1_arw_payload_write   ), //i
    .io_sharedInputs_1_w_valid           (m_axi_1_w_fifo_io_pop_valid                   ), //i
    .io_sharedInputs_1_w_ready           (arbiter_io_sharedInputs_1_w_ready             ), //o
    .io_sharedInputs_1_w_payload_data    (m_axi_1_w_fifo_io_pop_payload_data[31:0]      ), //i
    .io_sharedInputs_1_w_payload_strb    (m_axi_1_w_fifo_io_pop_payload_strb[3:0]       ), //i
    .io_sharedInputs_1_w_payload_last    (m_axi_1_w_fifo_io_pop_payload_last            ), //i
    .io_sharedInputs_1_b_valid           (arbiter_io_sharedInputs_1_b_valid             ), //o
    .io_sharedInputs_1_b_ready           (m_axi_1_bready                                ), //i
    .io_sharedInputs_1_b_payload_id      (arbiter_io_sharedInputs_1_b_payload_id[3:0]   ), //o
    .io_sharedInputs_1_b_payload_resp    (arbiter_io_sharedInputs_1_b_payload_resp[1:0] ), //o
    .io_sharedInputs_1_r_valid           (arbiter_io_sharedInputs_1_r_valid             ), //o
    .io_sharedInputs_1_r_ready           (m_axi_1_rready                                ), //i
    .io_sharedInputs_1_r_payload_data    (arbiter_io_sharedInputs_1_r_payload_data[31:0]), //o
    .io_sharedInputs_1_r_payload_id      (arbiter_io_sharedInputs_1_r_payload_id[3:0]   ), //o
    .io_sharedInputs_1_r_payload_resp    (arbiter_io_sharedInputs_1_r_payload_resp[1:0] ), //o
    .io_sharedInputs_1_r_payload_last    (arbiter_io_sharedInputs_1_r_payload_last      ), //o
    .io_output_arw_valid                 (arbiter_io_output_arw_valid                   ), //o
    .io_output_arw_ready                 (apbBridge_io_axi_arw_ready                    ), //i
    .io_output_arw_payload_addr          (arbiter_io_output_arw_payload_addr[11:0]      ), //o
    .io_output_arw_payload_id            (arbiter_io_output_arw_payload_id[4:0]         ), //o
    .io_output_arw_payload_len           (arbiter_io_output_arw_payload_len[7:0]        ), //o
    .io_output_arw_payload_size          (arbiter_io_output_arw_payload_size[2:0]       ), //o
    .io_output_arw_payload_burst         (arbiter_io_output_arw_payload_burst[1:0]      ), //o
    .io_output_arw_payload_write         (arbiter_io_output_arw_payload_write           ), //o
    .io_output_w_valid                   (arbiter_io_output_w_valid                     ), //o
    .io_output_w_ready                   (apbBridge_io_axi_w_ready                      ), //i
    .io_output_w_payload_data            (arbiter_io_output_w_payload_data[31:0]        ), //o
    .io_output_w_payload_strb            (arbiter_io_output_w_payload_strb[3:0]         ), //o
    .io_output_w_payload_last            (arbiter_io_output_w_payload_last              ), //o
    .io_output_b_valid                   (apbBridge_io_axi_b_valid                      ), //i
    .io_output_b_ready                   (arbiter_io_output_b_ready                     ), //o
    .io_output_b_payload_id              (apbBridge_io_axi_b_payload_id[4:0]            ), //i
    .io_output_b_payload_resp            (apbBridge_io_axi_b_payload_resp[1:0]          ), //i
    .io_output_r_valid                   (apbBridge_io_axi_r_valid                      ), //i
    .io_output_r_ready                   (arbiter_io_output_r_ready                     ), //o
    .io_output_r_payload_data            (apbBridge_io_axi_r_payload_data[31:0]         ), //i
    .io_output_r_payload_id              (apbBridge_io_axi_r_payload_id[4:0]            ), //i
    .io_output_r_payload_resp            (apbBridge_io_axi_r_payload_resp[1:0]          ), //i
    .io_output_r_payload_last            (apbBridge_io_axi_r_payload_last               ), //i
    .clk                                 (clk                                           ), //i
    .resetn                              (resetn                                        )  //i
  );
  Axi4ToApbXbar_StreamFifo_1 m_axi_0_ar_fifo (
    .io_push_valid         (m_axi_0_arvalid                          ), //i
    .io_push_ready         (m_axi_0_ar_fifo_io_push_ready            ), //o
    .io_push_payload_addr  (m_axi_0_araddr[11:0]                     ), //i
    .io_push_payload_id    (m_axi_0_arid[3:0]                        ), //i
    .io_push_payload_len   (m_axi_0_arlen[7:0]                       ), //i
    .io_push_payload_size  (m_axi_0_arsize[2:0]                      ), //i
    .io_push_payload_burst (m_axi_0_arburst[1:0]                     ), //i
    .io_pop_valid          (m_axi_0_ar_fifo_io_pop_valid             ), //o
    .io_pop_ready          (streamArbiter_io_inputs_0_ready          ), //i
    .io_pop_payload_addr   (m_axi_0_ar_fifo_io_pop_payload_addr[11:0]), //o
    .io_pop_payload_id     (m_axi_0_ar_fifo_io_pop_payload_id[3:0]   ), //o
    .io_pop_payload_len    (m_axi_0_ar_fifo_io_pop_payload_len[7:0]  ), //o
    .io_pop_payload_size   (m_axi_0_ar_fifo_io_pop_payload_size[2:0] ), //o
    .io_pop_payload_burst  (m_axi_0_ar_fifo_io_pop_payload_burst[1:0]), //o
    .io_flush              (1'b0                                     ), //i
    .io_occupancy          (m_axi_0_ar_fifo_io_occupancy[5:0]        ), //o
    .io_availability       (m_axi_0_ar_fifo_io_availability[5:0]     ), //o
    .clk                   (clk                                      ), //i
    .resetn                (resetn                                   )  //i
  );
  Axi4ToApbXbar_StreamFifo_1 m_axi_0_aw_fifo (
    .io_push_valid         (m_axi_0_awvalid                          ), //i
    .io_push_ready         (m_axi_0_aw_fifo_io_push_ready            ), //o
    .io_push_payload_addr  (m_axi_0_awaddr[11:0]                     ), //i
    .io_push_payload_id    (m_axi_0_awid[3:0]                        ), //i
    .io_push_payload_len   (m_axi_0_awlen[7:0]                       ), //i
    .io_push_payload_size  (m_axi_0_awsize[2:0]                      ), //i
    .io_push_payload_burst (m_axi_0_awburst[1:0]                     ), //i
    .io_pop_valid          (m_axi_0_aw_fifo_io_pop_valid             ), //o
    .io_pop_ready          (streamArbiter_io_inputs_1_ready          ), //i
    .io_pop_payload_addr   (m_axi_0_aw_fifo_io_pop_payload_addr[11:0]), //o
    .io_pop_payload_id     (m_axi_0_aw_fifo_io_pop_payload_id[3:0]   ), //o
    .io_pop_payload_len    (m_axi_0_aw_fifo_io_pop_payload_len[7:0]  ), //o
    .io_pop_payload_size   (m_axi_0_aw_fifo_io_pop_payload_size[2:0] ), //o
    .io_pop_payload_burst  (m_axi_0_aw_fifo_io_pop_payload_burst[1:0]), //o
    .io_flush              (1'b0                                     ), //i
    .io_occupancy          (m_axi_0_aw_fifo_io_occupancy[5:0]        ), //o
    .io_availability       (m_axi_0_aw_fifo_io_availability[5:0]     ), //o
    .clk                   (clk                                      ), //i
    .resetn                (resetn                                   )  //i
  );
  Axi4ToApbXbar_StreamFifo_3 m_axi_0_w_fifo (
    .io_push_valid        (m_axi_0_wvalid                          ), //i
    .io_push_ready        (m_axi_0_w_fifo_io_push_ready            ), //o
    .io_push_payload_data (m_axi_0_wdata[31:0]                     ), //i
    .io_push_payload_strb (m_axi_0_wstrb[3:0]                      ), //i
    .io_push_payload_last (m_axi_0_wlast                           ), //i
    .io_pop_valid         (m_axi_0_w_fifo_io_pop_valid             ), //o
    .io_pop_ready         (arbiter_io_sharedInputs_0_w_ready       ), //i
    .io_pop_payload_data  (m_axi_0_w_fifo_io_pop_payload_data[31:0]), //o
    .io_pop_payload_strb  (m_axi_0_w_fifo_io_pop_payload_strb[3:0] ), //o
    .io_pop_payload_last  (m_axi_0_w_fifo_io_pop_payload_last      ), //o
    .io_flush             (1'b0                                    ), //i
    .io_occupancy         (m_axi_0_w_fifo_io_occupancy[5:0]        ), //o
    .io_availability      (m_axi_0_w_fifo_io_availability[5:0]     ), //o
    .clk                  (clk                                     ), //i
    .resetn               (resetn                                  )  //i
  );
  Axi4ToApbXbar_StreamArbiter_1 streamArbiter (
    .io_inputs_0_valid         (m_axi_0_ar_fifo_io_pop_valid              ), //i
    .io_inputs_0_ready         (streamArbiter_io_inputs_0_ready           ), //o
    .io_inputs_0_payload_addr  (m_axi_0_ar_fifo_io_pop_payload_addr[11:0] ), //i
    .io_inputs_0_payload_id    (m_axi_0_ar_fifo_io_pop_payload_id[3:0]    ), //i
    .io_inputs_0_payload_len   (m_axi_0_ar_fifo_io_pop_payload_len[7:0]   ), //i
    .io_inputs_0_payload_size  (m_axi_0_ar_fifo_io_pop_payload_size[2:0]  ), //i
    .io_inputs_0_payload_burst (m_axi_0_ar_fifo_io_pop_payload_burst[1:0] ), //i
    .io_inputs_1_valid         (m_axi_0_aw_fifo_io_pop_valid              ), //i
    .io_inputs_1_ready         (streamArbiter_io_inputs_1_ready           ), //o
    .io_inputs_1_payload_addr  (m_axi_0_aw_fifo_io_pop_payload_addr[11:0] ), //i
    .io_inputs_1_payload_id    (m_axi_0_aw_fifo_io_pop_payload_id[3:0]    ), //i
    .io_inputs_1_payload_len   (m_axi_0_aw_fifo_io_pop_payload_len[7:0]   ), //i
    .io_inputs_1_payload_size  (m_axi_0_aw_fifo_io_pop_payload_size[2:0]  ), //i
    .io_inputs_1_payload_burst (m_axi_0_aw_fifo_io_pop_payload_burst[1:0] ), //i
    .io_output_valid           (streamArbiter_io_output_valid             ), //o
    .io_output_ready           (arbiter_io_sharedInputs_0_arw_ready       ), //i
    .io_output_payload_addr    (streamArbiter_io_output_payload_addr[11:0]), //o
    .io_output_payload_id      (streamArbiter_io_output_payload_id[3:0]   ), //o
    .io_output_payload_len     (streamArbiter_io_output_payload_len[7:0]  ), //o
    .io_output_payload_size    (streamArbiter_io_output_payload_size[2:0] ), //o
    .io_output_payload_burst   (streamArbiter_io_output_payload_burst[1:0]), //o
    .io_chosen                 (streamArbiter_io_chosen                   ), //o
    .io_chosenOH               (streamArbiter_io_chosenOH[1:0]            ), //o
    .clk                       (clk                                       ), //i
    .resetn                    (resetn                                    )  //i
  );
  Axi4ToApbXbar_StreamFifo_1 m_axi_1_ar_fifo (
    .io_push_valid         (m_axi_1_arvalid                          ), //i
    .io_push_ready         (m_axi_1_ar_fifo_io_push_ready            ), //o
    .io_push_payload_addr  (m_axi_1_araddr[11:0]                     ), //i
    .io_push_payload_id    (m_axi_1_arid[3:0]                        ), //i
    .io_push_payload_len   (m_axi_1_arlen[7:0]                       ), //i
    .io_push_payload_size  (m_axi_1_arsize[2:0]                      ), //i
    .io_push_payload_burst (m_axi_1_arburst[1:0]                     ), //i
    .io_pop_valid          (m_axi_1_ar_fifo_io_pop_valid             ), //o
    .io_pop_ready          (streamArbiter_1_io_inputs_0_ready        ), //i
    .io_pop_payload_addr   (m_axi_1_ar_fifo_io_pop_payload_addr[11:0]), //o
    .io_pop_payload_id     (m_axi_1_ar_fifo_io_pop_payload_id[3:0]   ), //o
    .io_pop_payload_len    (m_axi_1_ar_fifo_io_pop_payload_len[7:0]  ), //o
    .io_pop_payload_size   (m_axi_1_ar_fifo_io_pop_payload_size[2:0] ), //o
    .io_pop_payload_burst  (m_axi_1_ar_fifo_io_pop_payload_burst[1:0]), //o
    .io_flush              (1'b0                                     ), //i
    .io_occupancy          (m_axi_1_ar_fifo_io_occupancy[5:0]        ), //o
    .io_availability       (m_axi_1_ar_fifo_io_availability[5:0]     ), //o
    .clk                   (clk                                      ), //i
    .resetn                (resetn                                   )  //i
  );
  Axi4ToApbXbar_StreamFifo_1 m_axi_1_aw_fifo (
    .io_push_valid         (m_axi_1_awvalid                          ), //i
    .io_push_ready         (m_axi_1_aw_fifo_io_push_ready            ), //o
    .io_push_payload_addr  (m_axi_1_awaddr[11:0]                     ), //i
    .io_push_payload_id    (m_axi_1_awid[3:0]                        ), //i
    .io_push_payload_len   (m_axi_1_awlen[7:0]                       ), //i
    .io_push_payload_size  (m_axi_1_awsize[2:0]                      ), //i
    .io_push_payload_burst (m_axi_1_awburst[1:0]                     ), //i
    .io_pop_valid          (m_axi_1_aw_fifo_io_pop_valid             ), //o
    .io_pop_ready          (streamArbiter_1_io_inputs_1_ready        ), //i
    .io_pop_payload_addr   (m_axi_1_aw_fifo_io_pop_payload_addr[11:0]), //o
    .io_pop_payload_id     (m_axi_1_aw_fifo_io_pop_payload_id[3:0]   ), //o
    .io_pop_payload_len    (m_axi_1_aw_fifo_io_pop_payload_len[7:0]  ), //o
    .io_pop_payload_size   (m_axi_1_aw_fifo_io_pop_payload_size[2:0] ), //o
    .io_pop_payload_burst  (m_axi_1_aw_fifo_io_pop_payload_burst[1:0]), //o
    .io_flush              (1'b0                                     ), //i
    .io_occupancy          (m_axi_1_aw_fifo_io_occupancy[5:0]        ), //o
    .io_availability       (m_axi_1_aw_fifo_io_availability[5:0]     ), //o
    .clk                   (clk                                      ), //i
    .resetn                (resetn                                   )  //i
  );
  Axi4ToApbXbar_StreamFifo_3 m_axi_1_w_fifo (
    .io_push_valid        (m_axi_1_wvalid                          ), //i
    .io_push_ready        (m_axi_1_w_fifo_io_push_ready            ), //o
    .io_push_payload_data (m_axi_1_wdata[31:0]                     ), //i
    .io_push_payload_strb (m_axi_1_wstrb[3:0]                      ), //i
    .io_push_payload_last (m_axi_1_wlast                           ), //i
    .io_pop_valid         (m_axi_1_w_fifo_io_pop_valid             ), //o
    .io_pop_ready         (arbiter_io_sharedInputs_1_w_ready       ), //i
    .io_pop_payload_data  (m_axi_1_w_fifo_io_pop_payload_data[31:0]), //o
    .io_pop_payload_strb  (m_axi_1_w_fifo_io_pop_payload_strb[3:0] ), //o
    .io_pop_payload_last  (m_axi_1_w_fifo_io_pop_payload_last      ), //o
    .io_flush             (1'b0                                    ), //i
    .io_occupancy         (m_axi_1_w_fifo_io_occupancy[5:0]        ), //o
    .io_availability      (m_axi_1_w_fifo_io_availability[5:0]     ), //o
    .clk                  (clk                                     ), //i
    .resetn               (resetn                                  )  //i
  );
  Axi4ToApbXbar_StreamArbiter_1 streamArbiter_1 (
    .io_inputs_0_valid         (m_axi_1_ar_fifo_io_pop_valid                ), //i
    .io_inputs_0_ready         (streamArbiter_1_io_inputs_0_ready           ), //o
    .io_inputs_0_payload_addr  (m_axi_1_ar_fifo_io_pop_payload_addr[11:0]   ), //i
    .io_inputs_0_payload_id    (m_axi_1_ar_fifo_io_pop_payload_id[3:0]      ), //i
    .io_inputs_0_payload_len   (m_axi_1_ar_fifo_io_pop_payload_len[7:0]     ), //i
    .io_inputs_0_payload_size  (m_axi_1_ar_fifo_io_pop_payload_size[2:0]    ), //i
    .io_inputs_0_payload_burst (m_axi_1_ar_fifo_io_pop_payload_burst[1:0]   ), //i
    .io_inputs_1_valid         (m_axi_1_aw_fifo_io_pop_valid                ), //i
    .io_inputs_1_ready         (streamArbiter_1_io_inputs_1_ready           ), //o
    .io_inputs_1_payload_addr  (m_axi_1_aw_fifo_io_pop_payload_addr[11:0]   ), //i
    .io_inputs_1_payload_id    (m_axi_1_aw_fifo_io_pop_payload_id[3:0]      ), //i
    .io_inputs_1_payload_len   (m_axi_1_aw_fifo_io_pop_payload_len[7:0]     ), //i
    .io_inputs_1_payload_size  (m_axi_1_aw_fifo_io_pop_payload_size[2:0]    ), //i
    .io_inputs_1_payload_burst (m_axi_1_aw_fifo_io_pop_payload_burst[1:0]   ), //i
    .io_output_valid           (streamArbiter_1_io_output_valid             ), //o
    .io_output_ready           (arbiter_io_sharedInputs_1_arw_ready         ), //i
    .io_output_payload_addr    (streamArbiter_1_io_output_payload_addr[11:0]), //o
    .io_output_payload_id      (streamArbiter_1_io_output_payload_id[3:0]   ), //o
    .io_output_payload_len     (streamArbiter_1_io_output_payload_len[7:0]  ), //o
    .io_output_payload_size    (streamArbiter_1_io_output_payload_size[2:0] ), //o
    .io_output_payload_burst   (streamArbiter_1_io_output_payload_burst[1:0]), //o
    .io_chosen                 (streamArbiter_1_io_chosen                   ), //o
    .io_chosenOH               (streamArbiter_1_io_chosenOH[1:0]            ), //o
    .clk                       (clk                                         ), //i
    .resetn                    (resetn                                      )  //i
  );
  Axi4ToApbXbar_Apb3RegSlice lutSlice (
    .io_s_PADDR     (lutSlice_io_s_PADDR[9:0]            ), //i
    .io_s_PSEL      (apb3Router_io_outputs_0_PSEL        ), //i
    .io_s_PENABLE   (apb3Router_io_outputs_0_PENABLE     ), //i
    .io_s_PREADY    (lutSlice_io_s_PREADY                ), //o
    .io_s_PWRITE    (apb3Router_io_outputs_0_PWRITE      ), //i
    .io_s_PWDATA    (apb3Router_io_outputs_0_PWDATA[31:0]), //i
    .io_s_PRDATA    (lutSlice_io_s_PRDATA[31:0]          ), //o
    .io_s_PSLVERROR (lutSlice_io_s_PSLVERROR             ), //o
    .io_m_PADDR     (lutSlice_io_m_PADDR[9:0]            ), //o
    .io_m_PSEL      (lutSlice_io_m_PSEL                  ), //o
    .io_m_PENABLE   (lutSlice_io_m_PENABLE               ), //o
    .io_m_PREADY    (lut_PREADY                          ), //i
    .io_m_PWRITE    (lutSlice_io_m_PWRITE                ), //o
    .io_m_PWDATA    (lutSlice_io_m_PWDATA[31:0]          ), //o
    .io_m_PRDATA    (lut_PRDATA[31:0]                    ), //i
    .io_m_PSLVERROR (lut_PSLVERROR                       ), //i
    .clk            (clk                                 ), //i
    .resetn         (resetn                              )  //i
  );
  Axi4ToApbXbar_Apb3RegSlice_1 frontendSlice (
    .io_s_PADDR     (frontendSlice_io_s_PADDR[4:0]       ), //i
    .io_s_PSEL      (apb3Router_io_outputs_1_PSEL        ), //i
    .io_s_PENABLE   (apb3Router_io_outputs_1_PENABLE     ), //i
    .io_s_PREADY    (frontendSlice_io_s_PREADY           ), //o
    .io_s_PWRITE    (apb3Router_io_outputs_1_PWRITE      ), //i
    .io_s_PWDATA    (apb3Router_io_outputs_1_PWDATA[31:0]), //i
    .io_s_PRDATA    (frontendSlice_io_s_PRDATA[31:0]     ), //o
    .io_s_PSLVERROR (frontendSlice_io_s_PSLVERROR        ), //o
    .io_m_PADDR     (frontendSlice_io_m_PADDR[4:0]       ), //o
    .io_m_PSEL      (frontendSlice_io_m_PSEL             ), //o
    .io_m_PENABLE   (frontendSlice_io_m_PENABLE          ), //o
    .io_m_PREADY    (frontend_PREADY                     ), //i
    .io_m_PWRITE    (frontendSlice_io_m_PWRITE           ), //o
    .io_m_PWDATA    (frontendSlice_io_m_PWDATA[31:0]     ), //o
    .io_m_PRDATA    (frontend_PRDATA[31:0]               ), //i
    .io_m_PSLVERROR (frontend_PSLVERROR                  ), //i
    .clk            (clk                                 ), //i
    .resetn         (resetn                              )  //i
  );
  Axi4ToApbXbar_Apb3RegSlice_1 threadSlices_0 (
    .io_s_PADDR     (threadSlices_0_io_s_PADDR[4:0]      ), //i
    .io_s_PSEL      (apb3Router_io_outputs_2_PSEL        ), //i
    .io_s_PENABLE   (apb3Router_io_outputs_2_PENABLE     ), //i
    .io_s_PREADY    (threadSlices_0_io_s_PREADY          ), //o
    .io_s_PWRITE    (apb3Router_io_outputs_2_PWRITE      ), //i
    .io_s_PWDATA    (apb3Router_io_outputs_2_PWDATA[31:0]), //i
    .io_s_PRDATA    (threadSlices_0_io_s_PRDATA[31:0]    ), //o
    .io_s_PSLVERROR (threadSlices_0_io_s_PSLVERROR       ), //o
    .io_m_PADDR     (threadSlices_0_io_m_PADDR[4:0]      ), //o
    .io_m_PSEL      (threadSlices_0_io_m_PSEL            ), //o
    .io_m_PENABLE   (threadSlices_0_io_m_PENABLE         ), //o
    .io_m_PREADY    (threadRegs_0_PREADY                 ), //i
    .io_m_PWRITE    (threadSlices_0_io_m_PWRITE          ), //o
    .io_m_PWDATA    (threadSlices_0_io_m_PWDATA[31:0]    ), //o
    .io_m_PRDATA    (threadRegs_0_PRDATA[31:0]           ), //i
    .io_m_PSLVERROR (threadRegs_0_PSLVERROR              ), //i
    .clk            (clk                                 ), //i
    .resetn         (resetn                              )  //i
  );
  Axi4ToApbXbar_Apb3RegSlice_1 threadSlices_1 (
    .io_s_PADDR     (threadSlices_1_io_s_PADDR[4:0]      ), //i
    .io_s_PSEL      (apb3Router_io_outputs_3_PSEL        ), //i
    .io_s_PENABLE   (apb3Router_io_outputs_3_PENABLE     ), //i
    .io_s_PREADY    (threadSlices_1_io_s_PREADY          ), //o
    .io_s_PWRITE    (apb3Router_io_outputs_3_PWRITE      ), //i
    .io_s_PWDATA    (apb3Router_io_outputs_3_PWDATA[31:0]), //i
    .io_s_PRDATA    (threadSlices_1_io_s_PRDATA[31:0]    ), //o
    .io_s_PSLVERROR (threadSlices_1_io_s_PSLVERROR       ), //o
    .io_m_PADDR     (threadSlices_1_io_m_PADDR[4:0]      ), //o
    .io_m_PSEL      (threadSlices_1_io_m_PSEL            ), //o
    .io_m_PENABLE   (threadSlices_1_io_m_PENABLE         ), //o
    .io_m_PREADY    (threadRegs_1_PREADY                 ), //i
    .io_m_PWRITE    (threadSlices_1_io_m_PWRITE          ), //o
    .io_m_PWDATA    (threadSlices_1_io_m_PWDATA[31:0]    ), //o
    .io_m_PRDATA    (threadRegs_1_PRDATA[31:0]           ), //i
    .io_m_PSLVERROR (threadRegs_1_PSLVERROR              ), //i
    .clk            (clk                                 ), //i
    .resetn         (resetn                              )  //i
  );
  Axi4ToApbXbar_Apb3RegSlice_1 threadSlices_2 (
    .io_s_PADDR     (threadSlices_2_io_s_PADDR[4:0]      ), //i
    .io_s_PSEL      (apb3Router_io_outputs_4_PSEL        ), //i
    .io_s_PENABLE   (apb3Router_io_outputs_4_PENABLE     ), //i
    .io_s_PREADY    (threadSlices_2_io_s_PREADY          ), //o
    .io_s_PWRITE    (apb3Router_io_outputs_4_PWRITE      ), //i
    .io_s_PWDATA    (apb3Router_io_outputs_4_PWDATA[31:0]), //i
    .io_s_PRDATA    (threadSlices_2_io_s_PRDATA[31:0]    ), //o
    .io_s_PSLVERROR (threadSlices_2_io_s_PSLVERROR       ), //o
    .io_m_PADDR     (threadSlices_2_io_m_PADDR[4:0]      ), //o
    .io_m_PSEL      (threadSlices_2_io_m_PSEL            ), //o
    .io_m_PENABLE   (threadSlices_2_io_m_PENABLE         ), //o
    .io_m_PREADY    (threadRegs_2_PREADY                 ), //i
    .io_m_PWRITE    (threadSlices_2_io_m_PWRITE          ), //o
    .io_m_PWDATA    (threadSlices_2_io_m_PWDATA[31:0]    ), //o
    .io_m_PRDATA    (threadRegs_2_PRDATA[31:0]           ), //i
    .io_m_PSLVERROR (threadRegs_2_PSLVERROR              ), //i
    .clk            (clk                                 ), //i
    .resetn         (resetn                              )  //i
  );
  Axi4ToApbXbar_Apb3RegSlice_1 threadSlices_3 (
    .io_s_PADDR     (threadSlices_3_io_s_PADDR[4:0]      ), //i
    .io_s_PSEL      (apb3Router_io_outputs_5_PSEL        ), //i
    .io_s_PENABLE   (apb3Router_io_outputs_5_PENABLE     ), //i
    .io_s_PREADY    (threadSlices_3_io_s_PREADY          ), //o
    .io_s_PWRITE    (apb3Router_io_outputs_5_PWRITE      ), //i
    .io_s_PWDATA    (apb3Router_io_outputs_5_PWDATA[31:0]), //i
    .io_s_PRDATA    (threadSlices_3_io_s_PRDATA[31:0]    ), //o
    .io_s_PSLVERROR (threadSlices_3_io_s_PSLVERROR       ), //o
    .io_m_PADDR     (threadSlices_3_io_m_PADDR[4:0]      ), //o
    .io_m_PSEL      (threadSlices_3_io_m_PSEL            ), //o
    .io_m_PENABLE   (threadSlices_3_io_m_PENABLE         ), //o
    .io_m_PREADY    (threadRegs_3_PREADY                 ), //i
    .io_m_PWRITE    (threadSlices_3_io_m_PWRITE          ), //o
    .io_m_PWDATA    (threadSlices_3_io_m_PWDATA[31:0]    ), //o
    .io_m_PRDATA    (threadRegs_3_PRDATA[31:0]           ), //i
    .io_m_PSLVERROR (threadRegs_3_PSLVERROR              ), //i
    .clk            (clk                                 ), //i
    .resetn         (resetn                              )  //i
  );
  Axi4ToApbXbar_Apb3RegSlice_6 tileDmaSlice (
    .io_s_PADDR     (tileDmaSlice_io_s_PADDR[6:0]        ), //i
    .io_s_PSEL      (apb3Router_io_outputs_6_PSEL        ), //i
    .io_s_PENABLE   (apb3Router_io_outputs_6_PENABLE     ), //i
    .io_s_PREADY    (tileDmaSlice_io_s_PREADY            ), //o
    .io_s_PWRITE    (apb3Router_io_outputs_6_PWRITE      ), //i
    .io_s_PWDATA    (apb3Router_io_outputs_6_PWDATA[31:0]), //i
    .io_s_PRDATA    (tileDmaSlice_io_s_PRDATA[31:0]      ), //o
    .io_s_PSLVERROR (tileDmaSlice_io_s_PSLVERROR         ), //o
    .io_m_PADDR     (tileDmaSlice_io_m_PADDR[6:0]        ), //o
    .io_m_PSEL      (tileDmaSlice_io_m_PSEL              ), //o
    .io_m_PENABLE   (tileDmaSlice_io_m_PENABLE           ), //o
    .io_m_PREADY    (tileDma_PREADY                      ), //i
    .io_m_PWRITE    (tileDmaSlice_io_m_PWRITE            ), //o
    .io_m_PWDATA    (tileDmaSlice_io_m_PWDATA[31:0]      ), //o
    .io_m_PRDATA    (tileDma_PRDATA[31:0]                ), //i
    .io_m_PSLVERROR (tileDma_PSLVERROR                   ), //i
    .clk            (clk                                 ), //i
    .resetn         (resetn                              )  //i
  );
  Axi4ToApbXbar_Apb3RegSlice_6 visDmaSlice (
    .io_s_PADDR     (visDmaSlice_io_s_PADDR[6:0]         ), //i
    .io_s_PSEL      (apb3Router_io_outputs_7_PSEL        ), //i
    .io_s_PENABLE   (apb3Router_io_outputs_7_PENABLE     ), //i
    .io_s_PREADY    (visDmaSlice_io_s_PREADY             ), //o
    .io_s_PWRITE    (apb3Router_io_outputs_7_PWRITE      ), //i
    .io_s_PWDATA    (apb3Router_io_outputs_7_PWDATA[31:0]), //i
    .io_s_PRDATA    (visDmaSlice_io_s_PRDATA[31:0]       ), //o
    .io_s_PSLVERROR (visDmaSlice_io_s_PSLVERROR          ), //o
    .io_m_PADDR     (visDmaSlice_io_m_PADDR[6:0]         ), //o
    .io_m_PSEL      (visDmaSlice_io_m_PSEL               ), //o
    .io_m_PENABLE   (visDmaSlice_io_m_PENABLE            ), //o
    .io_m_PREADY    (visDma_PREADY                       ), //i
    .io_m_PWRITE    (visDmaSlice_io_m_PWRITE             ), //o
    .io_m_PWDATA    (visDmaSlice_io_m_PWDATA[31:0]       ), //o
    .io_m_PRDATA    (visDma_PRDATA[31:0]                 ), //i
    .io_m_PSLVERROR (visDma_PSLVERROR                    ), //i
    .clk            (clk                                 ), //i
    .resetn         (resetn                              )  //i
  );
  Axi4ToApbXbar_Apb3Decoder io_apb_decoder (
    .io_input_PADDR      (apbBridge_io_apb_PADDR[11:0]         ), //i
    .io_input_PSEL       (apbBridge_io_apb_PSEL                ), //i
    .io_input_PENABLE    (apbBridge_io_apb_PENABLE             ), //i
    .io_input_PREADY     (io_apb_decoder_io_input_PREADY       ), //o
    .io_input_PWRITE     (apbBridge_io_apb_PWRITE              ), //i
    .io_input_PWDATA     (apbBridge_io_apb_PWDATA[31:0]        ), //i
    .io_input_PRDATA     (io_apb_decoder_io_input_PRDATA[31:0] ), //o
    .io_input_PSLVERROR  (io_apb_decoder_io_input_PSLVERROR    ), //o
    .io_output_PADDR     (io_apb_decoder_io_output_PADDR[11:0] ), //o
    .io_output_PSEL      (io_apb_decoder_io_output_PSEL[7:0]   ), //o
    .io_output_PENABLE   (io_apb_decoder_io_output_PENABLE     ), //o
    .io_output_PREADY    (apb3Router_io_input_PREADY           ), //i
    .io_output_PWRITE    (io_apb_decoder_io_output_PWRITE      ), //o
    .io_output_PWDATA    (io_apb_decoder_io_output_PWDATA[31:0]), //o
    .io_output_PRDATA    (apb3Router_io_input_PRDATA[31:0]     ), //i
    .io_output_PSLVERROR (apb3Router_io_input_PSLVERROR        )  //i
  );
  Axi4ToApbXbar_Apb3Router apb3Router (
    .io_input_PADDR         (io_apb_decoder_io_output_PADDR[11:0] ), //i
    .io_input_PSEL          (io_apb_decoder_io_output_PSEL[7:0]   ), //i
    .io_input_PENABLE       (io_apb_decoder_io_output_PENABLE     ), //i
    .io_input_PREADY        (apb3Router_io_input_PREADY           ), //o
    .io_input_PWRITE        (io_apb_decoder_io_output_PWRITE      ), //i
    .io_input_PWDATA        (io_apb_decoder_io_output_PWDATA[31:0]), //i
    .io_input_PRDATA        (apb3Router_io_input_PRDATA[31:0]     ), //o
    .io_input_PSLVERROR     (apb3Router_io_input_PSLVERROR        ), //o
    .io_outputs_0_PADDR     (apb3Router_io_outputs_0_PADDR[11:0]  ), //o
    .io_outputs_0_PSEL      (apb3Router_io_outputs_0_PSEL         ), //o
    .io_outputs_0_PENABLE   (apb3Router_io_outputs_0_PENABLE      ), //o
    .io_outputs_0_PREADY    (lutSlice_io_s_PREADY                 ), //i
    .io_outputs_0_PWRITE    (apb3Router_io_outputs_0_PWRITE       ), //o
    .io_outputs_0_PWDATA    (apb3Router_io_outputs_0_PWDATA[31:0] ), //o
    .io_outputs_0_PRDATA    (lutSlice_io_s_PRDATA[31:0]           ), //i
    .io_outputs_0_PSLVERROR (lutSlice_io_s_PSLVERROR              ), //i
    .io_outputs_1_PADDR     (apb3Router_io_outputs_1_PADDR[11:0]  ), //o
    .io_outputs_1_PSEL      (apb3Router_io_outputs_1_PSEL         ), //o
    .io_outputs_1_PENABLE   (apb3Router_io_outputs_1_PENABLE      ), //o
    .io_outputs_1_PREADY    (frontendSlice_io_s_PREADY            ), //i
    .io_outputs_1_PWRITE    (apb3Router_io_outputs_1_PWRITE       ), //o
    .io_outputs_1_PWDATA    (apb3Router_io_outputs_1_PWDATA[31:0] ), //o
    .io_outputs_1_PRDATA    (frontendSlice_io_s_PRDATA[31:0]      ), //i
    .io_outputs_1_PSLVERROR (frontendSlice_io_s_PSLVERROR         ), //i
    .io_outputs_2_PADDR     (apb3Router_io_outputs_2_PADDR[11:0]  ), //o
    .io_outputs_2_PSEL      (apb3Router_io_outputs_2_PSEL         ), //o
    .io_outputs_2_PENABLE   (apb3Router_io_outputs_2_PENABLE      ), //o
    .io_outputs_2_PREADY    (threadSlices_0_io_s_PREADY           ), //i
    .io_outputs_2_PWRITE    (apb3Router_io_outputs_2_PWRITE       ), //o
    .io_outputs_2_PWDATA    (apb3Router_io_outputs_2_PWDATA[31:0] ), //o
    .io_outputs_2_PRDATA    (threadSlices_0_io_s_PRDATA[31:0]     ), //i
    .io_outputs_2_PSLVERROR (threadSlices_0_io_s_PSLVERROR        ), //i
    .io_outputs_3_PADDR     (apb3Router_io_outputs_3_PADDR[11:0]  ), //o
    .io_outputs_3_PSEL      (apb3Router_io_outputs_3_PSEL         ), //o
    .io_outputs_3_PENABLE   (apb3Router_io_outputs_3_PENABLE      ), //o
    .io_outputs_3_PREADY    (threadSlices_1_io_s_PREADY           ), //i
    .io_outputs_3_PWRITE    (apb3Router_io_outputs_3_PWRITE       ), //o
    .io_outputs_3_PWDATA    (apb3Router_io_outputs_3_PWDATA[31:0] ), //o
    .io_outputs_3_PRDATA    (threadSlices_1_io_s_PRDATA[31:0]     ), //i
    .io_outputs_3_PSLVERROR (threadSlices_1_io_s_PSLVERROR        ), //i
    .io_outputs_4_PADDR     (apb3Router_io_outputs_4_PADDR[11:0]  ), //o
    .io_outputs_4_PSEL      (apb3Router_io_outputs_4_PSEL         ), //o
    .io_outputs_4_PENABLE   (apb3Router_io_outputs_4_PENABLE      ), //o
    .io_outputs_4_PREADY    (threadSlices_2_io_s_PREADY           ), //i
    .io_outputs_4_PWRITE    (apb3Router_io_outputs_4_PWRITE       ), //o
    .io_outputs_4_PWDATA    (apb3Router_io_outputs_4_PWDATA[31:0] ), //o
    .io_outputs_4_PRDATA    (threadSlices_2_io_s_PRDATA[31:0]     ), //i
    .io_outputs_4_PSLVERROR (threadSlices_2_io_s_PSLVERROR        ), //i
    .io_outputs_5_PADDR     (apb3Router_io_outputs_5_PADDR[11:0]  ), //o
    .io_outputs_5_PSEL      (apb3Router_io_outputs_5_PSEL         ), //o
    .io_outputs_5_PENABLE   (apb3Router_io_outputs_5_PENABLE      ), //o
    .io_outputs_5_PREADY    (threadSlices_3_io_s_PREADY           ), //i
    .io_outputs_5_PWRITE    (apb3Router_io_outputs_5_PWRITE       ), //o
    .io_outputs_5_PWDATA    (apb3Router_io_outputs_5_PWDATA[31:0] ), //o
    .io_outputs_5_PRDATA    (threadSlices_3_io_s_PRDATA[31:0]     ), //i
    .io_outputs_5_PSLVERROR (threadSlices_3_io_s_PSLVERROR        ), //i
    .io_outputs_6_PADDR     (apb3Router_io_outputs_6_PADDR[11:0]  ), //o
    .io_outputs_6_PSEL      (apb3Router_io_outputs_6_PSEL         ), //o
    .io_outputs_6_PENABLE   (apb3Router_io_outputs_6_PENABLE      ), //o
    .io_outputs_6_PREADY    (tileDmaSlice_io_s_PREADY             ), //i
    .io_outputs_6_PWRITE    (apb3Router_io_outputs_6_PWRITE       ), //o
    .io_outputs_6_PWDATA    (apb3Router_io_outputs_6_PWDATA[31:0] ), //o
    .io_outputs_6_PRDATA    (tileDmaSlice_io_s_PRDATA[31:0]       ), //i
    .io_outputs_6_PSLVERROR (tileDmaSlice_io_s_PSLVERROR          ), //i
    .io_outputs_7_PADDR     (apb3Router_io_outputs_7_PADDR[11:0]  ), //o
    .io_outputs_7_PSEL      (apb3Router_io_outputs_7_PSEL         ), //o
    .io_outputs_7_PENABLE   (apb3Router_io_outputs_7_PENABLE      ), //o
    .io_outputs_7_PREADY    (visDmaSlice_io_s_PREADY              ), //i
    .io_outputs_7_PWRITE    (apb3Router_io_outputs_7_PWRITE       ), //o
    .io_outputs_7_PWDATA    (apb3Router_io_outputs_7_PWDATA[31:0] ), //o
    .io_outputs_7_PRDATA    (visDmaSlice_io_s_PRDATA[31:0]        ), //i
    .io_outputs_7_PSLVERROR (visDmaSlice_io_s_PSLVERROR           ), //i
    .clk                    (clk                                  ), //i
    .resetn                 (resetn                               )  //i
  );
  assign m_axi_0_arready = m_axi_0_ar_fifo_io_push_ready;
  assign m_axi_0_awready = m_axi_0_aw_fifo_io_push_ready;
  assign m_axi_0_wready = m_axi_0_w_fifo_io_push_ready;
  assign m_axi_0_rvalid = arbiter_io_sharedInputs_0_r_valid;
  assign m_axi_0_rdata = arbiter_io_sharedInputs_0_r_payload_data;
  assign m_axi_0_rid = arbiter_io_sharedInputs_0_r_payload_id;
  assign m_axi_0_rresp = arbiter_io_sharedInputs_0_r_payload_resp;
  assign m_axi_0_rlast = arbiter_io_sharedInputs_0_r_payload_last;
  assign m_axi_0_bvalid = arbiter_io_sharedInputs_0_b_valid;
  assign m_axi_0_bid = arbiter_io_sharedInputs_0_b_payload_id;
  assign m_axi_0_bresp = arbiter_io_sharedInputs_0_b_payload_resp;
  assign arbiter_io_sharedInputs_0_arw_payload_write = streamArbiter_io_chosenOH[1];
  assign m_axi_1_arready = m_axi_1_ar_fifo_io_push_ready;
  assign m_axi_1_awready = m_axi_1_aw_fifo_io_push_ready;
  assign m_axi_1_wready = m_axi_1_w_fifo_io_push_ready;
  assign m_axi_1_rvalid = arbiter_io_sharedInputs_1_r_valid;
  assign m_axi_1_rdata = arbiter_io_sharedInputs_1_r_payload_data;
  assign m_axi_1_rid = arbiter_io_sharedInputs_1_r_payload_id;
  assign m_axi_1_rresp = arbiter_io_sharedInputs_1_r_payload_resp;
  assign m_axi_1_rlast = arbiter_io_sharedInputs_1_r_payload_last;
  assign m_axi_1_bvalid = arbiter_io_sharedInputs_1_b_valid;
  assign m_axi_1_bid = arbiter_io_sharedInputs_1_b_payload_id;
  assign m_axi_1_bresp = arbiter_io_sharedInputs_1_b_payload_resp;
  assign arbiter_io_sharedInputs_1_arw_payload_write = streamArbiter_1_io_chosenOH[1];
  assign lut_PADDR = lutSlice_io_m_PADDR;
  assign lut_PSEL = lutSlice_io_m_PSEL;
  assign lut_PENABLE = lutSlice_io_m_PENABLE;
  assign lut_PWRITE = lutSlice_io_m_PWRITE;
  assign lut_PWDATA = lutSlice_io_m_PWDATA;
  assign frontend_PADDR = frontendSlice_io_m_PADDR;
  assign frontend_PSEL = frontendSlice_io_m_PSEL;
  assign frontend_PENABLE = frontendSlice_io_m_PENABLE;
  assign frontend_PWRITE = frontendSlice_io_m_PWRITE;
  assign frontend_PWDATA = frontendSlice_io_m_PWDATA;
  assign threadRegs_0_PADDR = threadSlices_0_io_m_PADDR;
  assign threadRegs_0_PSEL = threadSlices_0_io_m_PSEL;
  assign threadRegs_0_PENABLE = threadSlices_0_io_m_PENABLE;
  assign threadRegs_0_PWRITE = threadSlices_0_io_m_PWRITE;
  assign threadRegs_0_PWDATA = threadSlices_0_io_m_PWDATA;
  assign threadRegs_1_PADDR = threadSlices_1_io_m_PADDR;
  assign threadRegs_1_PSEL = threadSlices_1_io_m_PSEL;
  assign threadRegs_1_PENABLE = threadSlices_1_io_m_PENABLE;
  assign threadRegs_1_PWRITE = threadSlices_1_io_m_PWRITE;
  assign threadRegs_1_PWDATA = threadSlices_1_io_m_PWDATA;
  assign threadRegs_2_PADDR = threadSlices_2_io_m_PADDR;
  assign threadRegs_2_PSEL = threadSlices_2_io_m_PSEL;
  assign threadRegs_2_PENABLE = threadSlices_2_io_m_PENABLE;
  assign threadRegs_2_PWRITE = threadSlices_2_io_m_PWRITE;
  assign threadRegs_2_PWDATA = threadSlices_2_io_m_PWDATA;
  assign threadRegs_3_PADDR = threadSlices_3_io_m_PADDR;
  assign threadRegs_3_PSEL = threadSlices_3_io_m_PSEL;
  assign threadRegs_3_PENABLE = threadSlices_3_io_m_PENABLE;
  assign threadRegs_3_PWRITE = threadSlices_3_io_m_PWRITE;
  assign threadRegs_3_PWDATA = threadSlices_3_io_m_PWDATA;
  assign tileDma_PADDR = tileDmaSlice_io_m_PADDR;
  assign tileDma_PSEL = tileDmaSlice_io_m_PSEL;
  assign tileDma_PENABLE = tileDmaSlice_io_m_PENABLE;
  assign tileDma_PWRITE = tileDmaSlice_io_m_PWRITE;
  assign tileDma_PWDATA = tileDmaSlice_io_m_PWDATA;
  assign visDma_PADDR = visDmaSlice_io_m_PADDR;
  assign visDma_PSEL = visDmaSlice_io_m_PSEL;
  assign visDma_PENABLE = visDmaSlice_io_m_PENABLE;
  assign visDma_PWRITE = visDmaSlice_io_m_PWRITE;
  assign visDma_PWDATA = visDmaSlice_io_m_PWDATA;
  assign lutSlice_io_s_PADDR = apb3Router_io_outputs_0_PADDR[9:0];
  assign frontendSlice_io_s_PADDR = apb3Router_io_outputs_1_PADDR[4:0];
  assign threadSlices_0_io_s_PADDR = apb3Router_io_outputs_2_PADDR[4:0];
  assign threadSlices_1_io_s_PADDR = apb3Router_io_outputs_3_PADDR[4:0];
  assign threadSlices_2_io_s_PADDR = apb3Router_io_outputs_4_PADDR[4:0];
  assign threadSlices_3_io_s_PADDR = apb3Router_io_outputs_5_PADDR[4:0];
  assign tileDmaSlice_io_s_PADDR = apb3Router_io_outputs_6_PADDR[6:0];
  assign visDmaSlice_io_s_PADDR = apb3Router_io_outputs_7_PADDR[6:0];

endmodule

module Axi4ToApbXbar_Apb3Router (
  input  wire [11:0]   io_input_PADDR,
  input  wire [7:0]    io_input_PSEL,
  input  wire          io_input_PENABLE,
  output wire          io_input_PREADY,
  input  wire          io_input_PWRITE,
  input  wire [31:0]   io_input_PWDATA,
  output wire [31:0]   io_input_PRDATA,
  output wire          io_input_PSLVERROR,
  output wire [11:0]   io_outputs_0_PADDR,
  output wire [0:0]    io_outputs_0_PSEL,
  output wire          io_outputs_0_PENABLE,
  input  wire          io_outputs_0_PREADY,
  output wire          io_outputs_0_PWRITE,
  output wire [31:0]   io_outputs_0_PWDATA,
  input  wire [31:0]   io_outputs_0_PRDATA,
  input  wire          io_outputs_0_PSLVERROR,
  output wire [11:0]   io_outputs_1_PADDR,
  output wire [0:0]    io_outputs_1_PSEL,
  output wire          io_outputs_1_PENABLE,
  input  wire          io_outputs_1_PREADY,
  output wire          io_outputs_1_PWRITE,
  output wire [31:0]   io_outputs_1_PWDATA,
  input  wire [31:0]   io_outputs_1_PRDATA,
  input  wire          io_outputs_1_PSLVERROR,
  output wire [11:0]   io_outputs_2_PADDR,
  output wire [0:0]    io_outputs_2_PSEL,
  output wire          io_outputs_2_PENABLE,
  input  wire          io_outputs_2_PREADY,
  output wire          io_outputs_2_PWRITE,
  output wire [31:0]   io_outputs_2_PWDATA,
  input  wire [31:0]   io_outputs_2_PRDATA,
  input  wire          io_outputs_2_PSLVERROR,
  output wire [11:0]   io_outputs_3_PADDR,
  output wire [0:0]    io_outputs_3_PSEL,
  output wire          io_outputs_3_PENABLE,
  input  wire          io_outputs_3_PREADY,
  output wire          io_outputs_3_PWRITE,
  output wire [31:0]   io_outputs_3_PWDATA,
  input  wire [31:0]   io_outputs_3_PRDATA,
  input  wire          io_outputs_3_PSLVERROR,
  output wire [11:0]   io_outputs_4_PADDR,
  output wire [0:0]    io_outputs_4_PSEL,
  output wire          io_outputs_4_PENABLE,
  input  wire          io_outputs_4_PREADY,
  output wire          io_outputs_4_PWRITE,
  output wire [31:0]   io_outputs_4_PWDATA,
  input  wire [31:0]   io_outputs_4_PRDATA,
  input  wire          io_outputs_4_PSLVERROR,
  output wire [11:0]   io_outputs_5_PADDR,
  output wire [0:0]    io_outputs_5_PSEL,
  output wire          io_outputs_5_PENABLE,
  input  wire          io_outputs_5_PREADY,
  output wire          io_outputs_5_PWRITE,
  output wire [31:0]   io_outputs_5_PWDATA,
  input  wire [31:0]   io_outputs_5_PRDATA,
  input  wire          io_outputs_5_PSLVERROR,
  output wire [11:0]   io_outputs_6_PADDR,
  output wire [0:0]    io_outputs_6_PSEL,
  output wire          io_outputs_6_PENABLE,
  input  wire          io_outputs_6_PREADY,
  output wire          io_outputs_6_PWRITE,
  output wire [31:0]   io_outputs_6_PWDATA,
  input  wire [31:0]   io_outputs_6_PRDATA,
  input  wire          io_outputs_6_PSLVERROR,
  output wire [11:0]   io_outputs_7_PADDR,
  output wire [0:0]    io_outputs_7_PSEL,
  output wire          io_outputs_7_PENABLE,
  input  wire          io_outputs_7_PREADY,
  output wire          io_outputs_7_PWRITE,
  output wire [31:0]   io_outputs_7_PWDATA,
  input  wire [31:0]   io_outputs_7_PRDATA,
  input  wire          io_outputs_7_PSLVERROR,
  input  wire          clk,
  input  wire          resetn
);

  reg                 _zz_io_input_PREADY;
  reg        [31:0]   _zz_io_input_PRDATA;
  reg                 _zz_io_input_PSLVERROR;
  wire                _zz_selIndex;
  wire                _zz_selIndex_1;
  wire                _zz_selIndex_2;
  wire                _zz_selIndex_3;
  wire                _zz_selIndex_4;
  wire                _zz_selIndex_5;
  wire                _zz_selIndex_6;
  reg        [2:0]    selIndex;

  always @(*) begin
    case(selIndex)
      3'b000 : begin
        _zz_io_input_PREADY = io_outputs_0_PREADY;
        _zz_io_input_PRDATA = io_outputs_0_PRDATA;
        _zz_io_input_PSLVERROR = io_outputs_0_PSLVERROR;
      end
      3'b001 : begin
        _zz_io_input_PREADY = io_outputs_1_PREADY;
        _zz_io_input_PRDATA = io_outputs_1_PRDATA;
        _zz_io_input_PSLVERROR = io_outputs_1_PSLVERROR;
      end
      3'b010 : begin
        _zz_io_input_PREADY = io_outputs_2_PREADY;
        _zz_io_input_PRDATA = io_outputs_2_PRDATA;
        _zz_io_input_PSLVERROR = io_outputs_2_PSLVERROR;
      end
      3'b011 : begin
        _zz_io_input_PREADY = io_outputs_3_PREADY;
        _zz_io_input_PRDATA = io_outputs_3_PRDATA;
        _zz_io_input_PSLVERROR = io_outputs_3_PSLVERROR;
      end
      3'b100 : begin
        _zz_io_input_PREADY = io_outputs_4_PREADY;
        _zz_io_input_PRDATA = io_outputs_4_PRDATA;
        _zz_io_input_PSLVERROR = io_outputs_4_PSLVERROR;
      end
      3'b101 : begin
        _zz_io_input_PREADY = io_outputs_5_PREADY;
        _zz_io_input_PRDATA = io_outputs_5_PRDATA;
        _zz_io_input_PSLVERROR = io_outputs_5_PSLVERROR;
      end
      3'b110 : begin
        _zz_io_input_PREADY = io_outputs_6_PREADY;
        _zz_io_input_PRDATA = io_outputs_6_PRDATA;
        _zz_io_input_PSLVERROR = io_outputs_6_PSLVERROR;
      end
      default : begin
        _zz_io_input_PREADY = io_outputs_7_PREADY;
        _zz_io_input_PRDATA = io_outputs_7_PRDATA;
        _zz_io_input_PSLVERROR = io_outputs_7_PSLVERROR;
      end
    endcase
  end

  assign io_outputs_0_PADDR = io_input_PADDR;
  assign io_outputs_0_PENABLE = io_input_PENABLE;
  assign io_outputs_0_PSEL[0] = io_input_PSEL[0];
  assign io_outputs_0_PWRITE = io_input_PWRITE;
  assign io_outputs_0_PWDATA = io_input_PWDATA;
  assign io_outputs_1_PADDR = io_input_PADDR;
  assign io_outputs_1_PENABLE = io_input_PENABLE;
  assign io_outputs_1_PSEL[0] = io_input_PSEL[1];
  assign io_outputs_1_PWRITE = io_input_PWRITE;
  assign io_outputs_1_PWDATA = io_input_PWDATA;
  assign io_outputs_2_PADDR = io_input_PADDR;
  assign io_outputs_2_PENABLE = io_input_PENABLE;
  assign io_outputs_2_PSEL[0] = io_input_PSEL[2];
  assign io_outputs_2_PWRITE = io_input_PWRITE;
  assign io_outputs_2_PWDATA = io_input_PWDATA;
  assign io_outputs_3_PADDR = io_input_PADDR;
  assign io_outputs_3_PENABLE = io_input_PENABLE;
  assign io_outputs_3_PSEL[0] = io_input_PSEL[3];
  assign io_outputs_3_PWRITE = io_input_PWRITE;
  assign io_outputs_3_PWDATA = io_input_PWDATA;
  assign io_outputs_4_PADDR = io_input_PADDR;
  assign io_outputs_4_PENABLE = io_input_PENABLE;
  assign io_outputs_4_PSEL[0] = io_input_PSEL[4];
  assign io_outputs_4_PWRITE = io_input_PWRITE;
  assign io_outputs_4_PWDATA = io_input_PWDATA;
  assign io_outputs_5_PADDR = io_input_PADDR;
  assign io_outputs_5_PENABLE = io_input_PENABLE;
  assign io_outputs_5_PSEL[0] = io_input_PSEL[5];
  assign io_outputs_5_PWRITE = io_input_PWRITE;
  assign io_outputs_5_PWDATA = io_input_PWDATA;
  assign io_outputs_6_PADDR = io_input_PADDR;
  assign io_outputs_6_PENABLE = io_input_PENABLE;
  assign io_outputs_6_PSEL[0] = io_input_PSEL[6];
  assign io_outputs_6_PWRITE = io_input_PWRITE;
  assign io_outputs_6_PWDATA = io_input_PWDATA;
  assign io_outputs_7_PADDR = io_input_PADDR;
  assign io_outputs_7_PENABLE = io_input_PENABLE;
  assign io_outputs_7_PSEL[0] = io_input_PSEL[7];
  assign io_outputs_7_PWRITE = io_input_PWRITE;
  assign io_outputs_7_PWDATA = io_input_PWDATA;
  assign _zz_selIndex = io_input_PSEL[3];
  assign _zz_selIndex_1 = io_input_PSEL[5];
  assign _zz_selIndex_2 = io_input_PSEL[6];
  assign _zz_selIndex_3 = io_input_PSEL[7];
  assign _zz_selIndex_4 = (((io_input_PSEL[1] || _zz_selIndex) || _zz_selIndex_1) || _zz_selIndex_3);
  assign _zz_selIndex_5 = (((io_input_PSEL[2] || _zz_selIndex) || _zz_selIndex_2) || _zz_selIndex_3);
  assign _zz_selIndex_6 = (((io_input_PSEL[4] || _zz_selIndex_1) || _zz_selIndex_2) || _zz_selIndex_3);
  assign io_input_PREADY = _zz_io_input_PREADY;
  assign io_input_PRDATA = _zz_io_input_PRDATA;
  assign io_input_PSLVERROR = _zz_io_input_PSLVERROR;
  always @(posedge clk) begin
    selIndex <= {_zz_selIndex_6,{_zz_selIndex_5,_zz_selIndex_4}};
  end


endmodule

module Axi4ToApbXbar_Apb3Decoder (
  input  wire [11:0]   io_input_PADDR,
  input  wire [0:0]    io_input_PSEL,
  input  wire          io_input_PENABLE,
  output reg           io_input_PREADY,
  input  wire          io_input_PWRITE,
  input  wire [31:0]   io_input_PWDATA,
  output wire [31:0]   io_input_PRDATA,
  output reg           io_input_PSLVERROR,
  output wire [11:0]   io_output_PADDR,
  output reg  [7:0]    io_output_PSEL,
  output wire          io_output_PENABLE,
  input  wire          io_output_PREADY,
  output wire          io_output_PWRITE,
  output wire [31:0]   io_output_PWDATA,
  input  wire [31:0]   io_output_PRDATA,
  input  wire          io_output_PSLVERROR
);

  wire                when_Apb3Decoder_l88;

  assign io_output_PADDR = io_input_PADDR;
  assign io_output_PENABLE = io_input_PENABLE;
  assign io_output_PWRITE = io_input_PWRITE;
  assign io_output_PWDATA = io_input_PWDATA;
  always @(*) begin
    io_output_PSEL[0] = (((io_input_PADDR & (~ 12'h3ff)) == 12'h0) && io_input_PSEL[0]);
    io_output_PSEL[1] = (((io_input_PADDR & (~ 12'h01f)) == 12'h800) && io_input_PSEL[0]);
    io_output_PSEL[2] = (((io_input_PADDR & (~ 12'h01f)) == 12'h820) && io_input_PSEL[0]);
    io_output_PSEL[3] = (((io_input_PADDR & (~ 12'h01f)) == 12'h840) && io_input_PSEL[0]);
    io_output_PSEL[4] = (((io_input_PADDR & (~ 12'h01f)) == 12'h860) && io_input_PSEL[0]);
    io_output_PSEL[5] = (((io_input_PADDR & (~ 12'h01f)) == 12'h880) && io_input_PSEL[0]);
    io_output_PSEL[6] = (((io_input_PADDR & (~ 12'h07f)) == 12'hf00) && io_input_PSEL[0]);
    io_output_PSEL[7] = (((io_input_PADDR & (~ 12'h07f)) == 12'hf80) && io_input_PSEL[0]);
  end

  always @(*) begin
    io_input_PREADY = io_output_PREADY;
    if(when_Apb3Decoder_l88) begin
      io_input_PREADY = 1'b1;
    end
  end

  assign io_input_PRDATA = io_output_PRDATA;
  always @(*) begin
    io_input_PSLVERROR = io_output_PSLVERROR;
    if(when_Apb3Decoder_l88) begin
      io_input_PSLVERROR = 1'b1;
    end
  end

  assign when_Apb3Decoder_l88 = (io_input_PSEL[0] && (io_output_PSEL == 8'h0));

endmodule

//Axi4ToApbXbar_Apb3RegSlice_7 replaced by Axi4ToApbXbar_Apb3RegSlice_6

module Axi4ToApbXbar_Apb3RegSlice_6 (
  input  wire [6:0]    io_s_PADDR,
  input  wire [0:0]    io_s_PSEL,
  input  wire          io_s_PENABLE,
  output wire          io_s_PREADY,
  input  wire          io_s_PWRITE,
  input  wire [31:0]   io_s_PWDATA,
  output wire [31:0]   io_s_PRDATA,
  output wire          io_s_PSLVERROR,
  output wire [6:0]    io_m_PADDR,
  output wire [0:0]    io_m_PSEL,
  output wire          io_m_PENABLE,
  input  wire          io_m_PREADY,
  output wire          io_m_PWRITE,
  output wire [31:0]   io_m_PWDATA,
  input  wire [31:0]   io_m_PRDATA,
  input  wire          io_m_PSLVERROR,
  input  wire          clk,
  input  wire          resetn
);

  wire                stageInsts_0_io_s_PREADY;
  wire       [31:0]   stageInsts_0_io_s_PRDATA;
  wire                stageInsts_0_io_s_PSLVERROR;
  wire       [6:0]    stageInsts_0_io_m_PADDR;
  wire       [0:0]    stageInsts_0_io_m_PSEL;
  wire                stageInsts_0_io_m_PENABLE;
  wire                stageInsts_0_io_m_PWRITE;
  wire       [31:0]   stageInsts_0_io_m_PWDATA;

  Axi4ToApbXbar_Apb3RegSliceStage_6 stageInsts_0 (
    .io_s_PADDR     (io_s_PADDR[6:0]               ), //i
    .io_s_PSEL      (io_s_PSEL                     ), //i
    .io_s_PENABLE   (io_s_PENABLE                  ), //i
    .io_s_PREADY    (stageInsts_0_io_s_PREADY      ), //o
    .io_s_PWRITE    (io_s_PWRITE                   ), //i
    .io_s_PWDATA    (io_s_PWDATA[31:0]             ), //i
    .io_s_PRDATA    (stageInsts_0_io_s_PRDATA[31:0]), //o
    .io_s_PSLVERROR (stageInsts_0_io_s_PSLVERROR   ), //o
    .io_m_PADDR     (stageInsts_0_io_m_PADDR[6:0]  ), //o
    .io_m_PSEL      (stageInsts_0_io_m_PSEL        ), //o
    .io_m_PENABLE   (stageInsts_0_io_m_PENABLE     ), //o
    .io_m_PREADY    (io_m_PREADY                   ), //i
    .io_m_PWRITE    (stageInsts_0_io_m_PWRITE      ), //o
    .io_m_PWDATA    (stageInsts_0_io_m_PWDATA[31:0]), //o
    .io_m_PRDATA    (io_m_PRDATA[31:0]             ), //i
    .io_m_PSLVERROR (io_m_PSLVERROR                ), //i
    .clk            (clk                           ), //i
    .resetn         (resetn                        )  //i
  );
  assign io_s_PREADY = stageInsts_0_io_s_PREADY;
  assign io_s_PRDATA = stageInsts_0_io_s_PRDATA;
  assign io_s_PSLVERROR = stageInsts_0_io_s_PSLVERROR;
  assign io_m_PADDR = stageInsts_0_io_m_PADDR;
  assign io_m_PSEL = stageInsts_0_io_m_PSEL;
  assign io_m_PENABLE = stageInsts_0_io_m_PENABLE;
  assign io_m_PWRITE = stageInsts_0_io_m_PWRITE;
  assign io_m_PWDATA = stageInsts_0_io_m_PWDATA;

endmodule

//Axi4ToApbXbar_Apb3RegSlice_5 replaced by Axi4ToApbXbar_Apb3RegSlice_1

//Axi4ToApbXbar_Apb3RegSlice_4 replaced by Axi4ToApbXbar_Apb3RegSlice_1

//Axi4ToApbXbar_Apb3RegSlice_3 replaced by Axi4ToApbXbar_Apb3RegSlice_1

//Axi4ToApbXbar_Apb3RegSlice_2 replaced by Axi4ToApbXbar_Apb3RegSlice_1

module Axi4ToApbXbar_Apb3RegSlice_1 (
  input  wire [4:0]    io_s_PADDR,
  input  wire [0:0]    io_s_PSEL,
  input  wire          io_s_PENABLE,
  output wire          io_s_PREADY,
  input  wire          io_s_PWRITE,
  input  wire [31:0]   io_s_PWDATA,
  output wire [31:0]   io_s_PRDATA,
  output wire          io_s_PSLVERROR,
  output wire [4:0]    io_m_PADDR,
  output wire [0:0]    io_m_PSEL,
  output wire          io_m_PENABLE,
  input  wire          io_m_PREADY,
  output wire          io_m_PWRITE,
  output wire [31:0]   io_m_PWDATA,
  input  wire [31:0]   io_m_PRDATA,
  input  wire          io_m_PSLVERROR,
  input  wire          clk,
  input  wire          resetn
);

  wire                stageInsts_0_io_s_PREADY;
  wire       [31:0]   stageInsts_0_io_s_PRDATA;
  wire                stageInsts_0_io_s_PSLVERROR;
  wire       [4:0]    stageInsts_0_io_m_PADDR;
  wire       [0:0]    stageInsts_0_io_m_PSEL;
  wire                stageInsts_0_io_m_PENABLE;
  wire                stageInsts_0_io_m_PWRITE;
  wire       [31:0]   stageInsts_0_io_m_PWDATA;

  Axi4ToApbXbar_Apb3RegSliceStage_1 stageInsts_0 (
    .io_s_PADDR     (io_s_PADDR[4:0]               ), //i
    .io_s_PSEL      (io_s_PSEL                     ), //i
    .io_s_PENABLE   (io_s_PENABLE                  ), //i
    .io_s_PREADY    (stageInsts_0_io_s_PREADY      ), //o
    .io_s_PWRITE    (io_s_PWRITE                   ), //i
    .io_s_PWDATA    (io_s_PWDATA[31:0]             ), //i
    .io_s_PRDATA    (stageInsts_0_io_s_PRDATA[31:0]), //o
    .io_s_PSLVERROR (stageInsts_0_io_s_PSLVERROR   ), //o
    .io_m_PADDR     (stageInsts_0_io_m_PADDR[4:0]  ), //o
    .io_m_PSEL      (stageInsts_0_io_m_PSEL        ), //o
    .io_m_PENABLE   (stageInsts_0_io_m_PENABLE     ), //o
    .io_m_PREADY    (io_m_PREADY                   ), //i
    .io_m_PWRITE    (stageInsts_0_io_m_PWRITE      ), //o
    .io_m_PWDATA    (stageInsts_0_io_m_PWDATA[31:0]), //o
    .io_m_PRDATA    (io_m_PRDATA[31:0]             ), //i
    .io_m_PSLVERROR (io_m_PSLVERROR                ), //i
    .clk            (clk                           ), //i
    .resetn         (resetn                        )  //i
  );
  assign io_s_PREADY = stageInsts_0_io_s_PREADY;
  assign io_s_PRDATA = stageInsts_0_io_s_PRDATA;
  assign io_s_PSLVERROR = stageInsts_0_io_s_PSLVERROR;
  assign io_m_PADDR = stageInsts_0_io_m_PADDR;
  assign io_m_PSEL = stageInsts_0_io_m_PSEL;
  assign io_m_PENABLE = stageInsts_0_io_m_PENABLE;
  assign io_m_PWRITE = stageInsts_0_io_m_PWRITE;
  assign io_m_PWDATA = stageInsts_0_io_m_PWDATA;

endmodule

module Axi4ToApbXbar_Apb3RegSlice (
  input  wire [9:0]    io_s_PADDR,
  input  wire [0:0]    io_s_PSEL,
  input  wire          io_s_PENABLE,
  output wire          io_s_PREADY,
  input  wire          io_s_PWRITE,
  input  wire [31:0]   io_s_PWDATA,
  output wire [31:0]   io_s_PRDATA,
  output wire          io_s_PSLVERROR,
  output wire [9:0]    io_m_PADDR,
  output wire [0:0]    io_m_PSEL,
  output wire          io_m_PENABLE,
  input  wire          io_m_PREADY,
  output wire          io_m_PWRITE,
  output wire [31:0]   io_m_PWDATA,
  input  wire [31:0]   io_m_PRDATA,
  input  wire          io_m_PSLVERROR,
  input  wire          clk,
  input  wire          resetn
);

  wire                stageInsts_0_io_s_PREADY;
  wire       [31:0]   stageInsts_0_io_s_PRDATA;
  wire                stageInsts_0_io_s_PSLVERROR;
  wire       [9:0]    stageInsts_0_io_m_PADDR;
  wire       [0:0]    stageInsts_0_io_m_PSEL;
  wire                stageInsts_0_io_m_PENABLE;
  wire                stageInsts_0_io_m_PWRITE;
  wire       [31:0]   stageInsts_0_io_m_PWDATA;

  Axi4ToApbXbar_Apb3RegSliceStage stageInsts_0 (
    .io_s_PADDR     (io_s_PADDR[9:0]               ), //i
    .io_s_PSEL      (io_s_PSEL                     ), //i
    .io_s_PENABLE   (io_s_PENABLE                  ), //i
    .io_s_PREADY    (stageInsts_0_io_s_PREADY      ), //o
    .io_s_PWRITE    (io_s_PWRITE                   ), //i
    .io_s_PWDATA    (io_s_PWDATA[31:0]             ), //i
    .io_s_PRDATA    (stageInsts_0_io_s_PRDATA[31:0]), //o
    .io_s_PSLVERROR (stageInsts_0_io_s_PSLVERROR   ), //o
    .io_m_PADDR     (stageInsts_0_io_m_PADDR[9:0]  ), //o
    .io_m_PSEL      (stageInsts_0_io_m_PSEL        ), //o
    .io_m_PENABLE   (stageInsts_0_io_m_PENABLE     ), //o
    .io_m_PREADY    (io_m_PREADY                   ), //i
    .io_m_PWRITE    (stageInsts_0_io_m_PWRITE      ), //o
    .io_m_PWDATA    (stageInsts_0_io_m_PWDATA[31:0]), //o
    .io_m_PRDATA    (io_m_PRDATA[31:0]             ), //i
    .io_m_PSLVERROR (io_m_PSLVERROR                ), //i
    .clk            (clk                           ), //i
    .resetn         (resetn                        )  //i
  );
  assign io_s_PREADY = stageInsts_0_io_s_PREADY;
  assign io_s_PRDATA = stageInsts_0_io_s_PRDATA;
  assign io_s_PSLVERROR = stageInsts_0_io_s_PSLVERROR;
  assign io_m_PADDR = stageInsts_0_io_m_PADDR;
  assign io_m_PSEL = stageInsts_0_io_m_PSEL;
  assign io_m_PENABLE = stageInsts_0_io_m_PENABLE;
  assign io_m_PWRITE = stageInsts_0_io_m_PWRITE;
  assign io_m_PWDATA = stageInsts_0_io_m_PWDATA;

endmodule

//Axi4ToApbXbar_StreamArbiter_2 replaced by Axi4ToApbXbar_StreamArbiter_1

//Axi4ToApbXbar_StreamFifo_6 replaced by Axi4ToApbXbar_StreamFifo_3

//Axi4ToApbXbar_StreamFifo_5 replaced by Axi4ToApbXbar_StreamFifo_1

//Axi4ToApbXbar_StreamFifo_4 replaced by Axi4ToApbXbar_StreamFifo_1

module Axi4ToApbXbar_StreamArbiter_1 (
  input  wire          io_inputs_0_valid,
  output wire          io_inputs_0_ready,
  input  wire [11:0]   io_inputs_0_payload_addr,
  input  wire [3:0]    io_inputs_0_payload_id,
  input  wire [7:0]    io_inputs_0_payload_len,
  input  wire [2:0]    io_inputs_0_payload_size,
  input  wire [1:0]    io_inputs_0_payload_burst,
  input  wire          io_inputs_1_valid,
  output wire          io_inputs_1_ready,
  input  wire [11:0]   io_inputs_1_payload_addr,
  input  wire [3:0]    io_inputs_1_payload_id,
  input  wire [7:0]    io_inputs_1_payload_len,
  input  wire [2:0]    io_inputs_1_payload_size,
  input  wire [1:0]    io_inputs_1_payload_burst,
  output wire          io_output_valid,
  input  wire          io_output_ready,
  output wire [11:0]   io_output_payload_addr,
  output wire [3:0]    io_output_payload_id,
  output wire [7:0]    io_output_payload_len,
  output wire [2:0]    io_output_payload_size,
  output wire [1:0]    io_output_payload_burst,
  output wire [0:0]    io_chosen,
  output wire [1:0]    io_chosenOH,
  input  wire          clk,
  input  wire          resetn
);

  wire       [3:0]    _zz__zz_maskProposal_0_2;
  wire       [3:0]    _zz__zz_maskProposal_0_2_1;
  wire       [1:0]    _zz__zz_maskProposal_0_2_2;
  reg                 locked;
  wire                maskProposal_0;
  wire                maskProposal_1;
  reg                 maskLocked_0;
  reg                 maskLocked_1;
  wire                maskRouted_0;
  wire                maskRouted_1;
  wire       [1:0]    _zz_maskProposal_0;
  wire       [3:0]    _zz_maskProposal_0_1;
  wire       [3:0]    _zz_maskProposal_0_2;
  wire       [1:0]    _zz_maskProposal_0_3;
  wire                io_output_fire;
  wire                _zz_io_chosen;

  assign _zz__zz_maskProposal_0_2 = (_zz_maskProposal_0_1 - _zz__zz_maskProposal_0_2_1);
  assign _zz__zz_maskProposal_0_2_2 = {maskLocked_0,maskLocked_1};
  assign _zz__zz_maskProposal_0_2_1 = {2'd0, _zz__zz_maskProposal_0_2_2};
  assign maskRouted_0 = (locked ? maskLocked_0 : maskProposal_0);
  assign maskRouted_1 = (locked ? maskLocked_1 : maskProposal_1);
  assign _zz_maskProposal_0 = {io_inputs_1_valid,io_inputs_0_valid};
  assign _zz_maskProposal_0_1 = {_zz_maskProposal_0,_zz_maskProposal_0};
  assign _zz_maskProposal_0_2 = (_zz_maskProposal_0_1 & (~ _zz__zz_maskProposal_0_2));
  assign _zz_maskProposal_0_3 = (_zz_maskProposal_0_2[3 : 2] | _zz_maskProposal_0_2[1 : 0]);
  assign maskProposal_0 = _zz_maskProposal_0_3[0];
  assign maskProposal_1 = _zz_maskProposal_0_3[1];
  assign io_output_fire = (io_output_valid && io_output_ready);
  assign io_output_valid = ((io_inputs_0_valid && maskRouted_0) || (io_inputs_1_valid && maskRouted_1));
  assign io_output_payload_addr = (maskRouted_0 ? io_inputs_0_payload_addr : io_inputs_1_payload_addr);
  assign io_output_payload_id = (maskRouted_0 ? io_inputs_0_payload_id : io_inputs_1_payload_id);
  assign io_output_payload_len = (maskRouted_0 ? io_inputs_0_payload_len : io_inputs_1_payload_len);
  assign io_output_payload_size = (maskRouted_0 ? io_inputs_0_payload_size : io_inputs_1_payload_size);
  assign io_output_payload_burst = (maskRouted_0 ? io_inputs_0_payload_burst : io_inputs_1_payload_burst);
  assign io_inputs_0_ready = ((1'b0 || maskRouted_0) && io_output_ready);
  assign io_inputs_1_ready = ((1'b0 || maskRouted_1) && io_output_ready);
  assign io_chosenOH = {maskRouted_1,maskRouted_0};
  assign _zz_io_chosen = io_chosenOH[1];
  assign io_chosen = _zz_io_chosen;
  always @(posedge clk) begin
    if(!resetn) begin
      locked <= 1'b0;
      maskLocked_0 <= 1'b0;
      maskLocked_1 <= 1'b1;
    end else begin
      if(io_output_valid) begin
        maskLocked_0 <= maskRouted_0;
        maskLocked_1 <= maskRouted_1;
      end
      if(io_output_valid) begin
        locked <= 1'b1;
      end
      if(io_output_fire) begin
        locked <= 1'b0;
      end
    end
  end


endmodule

module Axi4ToApbXbar_StreamFifo_3 (
  input  wire          io_push_valid,
  output wire          io_push_ready,
  input  wire [31:0]   io_push_payload_data,
  input  wire [3:0]    io_push_payload_strb,
  input  wire          io_push_payload_last,
  output wire          io_pop_valid,
  input  wire          io_pop_ready,
  output wire [31:0]   io_pop_payload_data,
  output wire [3:0]    io_pop_payload_strb,
  output wire          io_pop_payload_last,
  input  wire          io_flush,
  output wire [5:0]    io_occupancy,
  output wire [5:0]    io_availability,
  input  wire          clk,
  input  wire          resetn
);

  reg        [36:0]   logic_ram_spinal_port1;
  wire       [36:0]   _zz_logic_ram_port;
  reg                 _zz_1;
  wire                logic_ptr_doPush;
  wire                logic_ptr_doPop;
  wire                logic_ptr_full;
  wire                logic_ptr_empty;
  reg        [5:0]    logic_ptr_push;
  reg        [5:0]    logic_ptr_pop;
  wire       [5:0]    logic_ptr_occupancy;
  wire       [5:0]    logic_ptr_popOnIo;
  wire                when_Stream_l1455;
  reg                 logic_ptr_wentUp;
  wire                io_push_fire;
  wire                logic_push_onRam_write_valid;
  wire       [4:0]    logic_push_onRam_write_payload_address;
  wire       [31:0]   logic_push_onRam_write_payload_data_data;
  wire       [3:0]    logic_push_onRam_write_payload_data_strb;
  wire                logic_push_onRam_write_payload_data_last;
  wire                logic_pop_addressGen_valid;
  reg                 logic_pop_addressGen_ready;
  wire       [4:0]    logic_pop_addressGen_payload;
  wire                logic_pop_addressGen_fire;
  wire                logic_pop_sync_readArbitation_valid;
  wire                logic_pop_sync_readArbitation_ready;
  wire       [4:0]    logic_pop_sync_readArbitation_payload;
  reg                 logic_pop_addressGen_rValid;
  reg        [4:0]    logic_pop_addressGen_rData;
  wire                when_Stream_l477;
  wire                logic_pop_sync_readPort_cmd_valid;
  wire       [4:0]    logic_pop_sync_readPort_cmd_payload;
  wire       [31:0]   logic_pop_sync_readPort_rsp_data;
  wire       [3:0]    logic_pop_sync_readPort_rsp_strb;
  wire                logic_pop_sync_readPort_rsp_last;
  wire       [36:0]   _zz_logic_pop_sync_readPort_rsp_data;
  wire                logic_pop_addressGen_toFlowFire_valid;
  wire       [4:0]    logic_pop_addressGen_toFlowFire_payload;
  wire                logic_pop_sync_readArbitation_translated_valid;
  wire                logic_pop_sync_readArbitation_translated_ready;
  wire       [31:0]   logic_pop_sync_readArbitation_translated_payload_data;
  wire       [3:0]    logic_pop_sync_readArbitation_translated_payload_strb;
  wire                logic_pop_sync_readArbitation_translated_payload_last;
  wire                logic_pop_sync_readArbitation_fire;
  reg        [5:0]    logic_pop_sync_popReg;
  reg [36:0] logic_ram [0:31];

  assign _zz_logic_ram_port = {logic_push_onRam_write_payload_data_last,{logic_push_onRam_write_payload_data_strb,logic_push_onRam_write_payload_data_data}};
  always @(posedge clk) begin
    if(_zz_1) begin
      logic_ram[logic_push_onRam_write_payload_address] <= _zz_logic_ram_port;
    end
  end

  always @(posedge clk) begin
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
  assign logic_ptr_full = (((logic_ptr_push ^ logic_ptr_popOnIo) ^ 6'h20) == 6'h0);
  assign logic_ptr_empty = (logic_ptr_push == logic_ptr_pop);
  assign logic_ptr_occupancy = (logic_ptr_push - logic_ptr_popOnIo);
  assign io_push_ready = (! logic_ptr_full);
  assign io_push_fire = (io_push_valid && io_push_ready);
  assign logic_ptr_doPush = io_push_fire;
  assign logic_push_onRam_write_valid = io_push_fire;
  assign logic_push_onRam_write_payload_address = logic_ptr_push[4:0];
  assign logic_push_onRam_write_payload_data_data = io_push_payload_data;
  assign logic_push_onRam_write_payload_data_strb = io_push_payload_strb;
  assign logic_push_onRam_write_payload_data_last = io_push_payload_last;
  assign logic_pop_addressGen_valid = (! logic_ptr_empty);
  assign logic_pop_addressGen_payload = logic_ptr_pop[4:0];
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
  assign _zz_logic_pop_sync_readPort_rsp_data = logic_ram_spinal_port1;
  assign logic_pop_sync_readPort_rsp_data = _zz_logic_pop_sync_readPort_rsp_data[31 : 0];
  assign logic_pop_sync_readPort_rsp_strb = _zz_logic_pop_sync_readPort_rsp_data[35 : 32];
  assign logic_pop_sync_readPort_rsp_last = _zz_logic_pop_sync_readPort_rsp_data[36];
  assign logic_pop_addressGen_toFlowFire_valid = logic_pop_addressGen_fire;
  assign logic_pop_addressGen_toFlowFire_payload = logic_pop_addressGen_payload;
  assign logic_pop_sync_readPort_cmd_valid = logic_pop_addressGen_toFlowFire_valid;
  assign logic_pop_sync_readPort_cmd_payload = logic_pop_addressGen_toFlowFire_payload;
  assign logic_pop_sync_readArbitation_translated_valid = logic_pop_sync_readArbitation_valid;
  assign logic_pop_sync_readArbitation_ready = logic_pop_sync_readArbitation_translated_ready;
  assign logic_pop_sync_readArbitation_translated_payload_data = logic_pop_sync_readPort_rsp_data;
  assign logic_pop_sync_readArbitation_translated_payload_strb = logic_pop_sync_readPort_rsp_strb;
  assign logic_pop_sync_readArbitation_translated_payload_last = logic_pop_sync_readPort_rsp_last;
  assign io_pop_valid = logic_pop_sync_readArbitation_translated_valid;
  assign logic_pop_sync_readArbitation_translated_ready = io_pop_ready;
  assign io_pop_payload_data = logic_pop_sync_readArbitation_translated_payload_data;
  assign io_pop_payload_strb = logic_pop_sync_readArbitation_translated_payload_strb;
  assign io_pop_payload_last = logic_pop_sync_readArbitation_translated_payload_last;
  assign logic_pop_sync_readArbitation_fire = (logic_pop_sync_readArbitation_valid && logic_pop_sync_readArbitation_ready);
  assign logic_ptr_popOnIo = logic_pop_sync_popReg;
  assign io_occupancy = logic_ptr_occupancy;
  assign io_availability = (6'h20 - logic_ptr_occupancy);
  always @(posedge clk) begin
    if(!resetn) begin
      logic_ptr_push <= 6'h0;
      logic_ptr_pop <= 6'h0;
      logic_ptr_wentUp <= 1'b0;
      logic_pop_addressGen_rValid <= 1'b0;
      logic_pop_sync_popReg <= 6'h0;
    end else begin
      if(when_Stream_l1455) begin
        logic_ptr_wentUp <= logic_ptr_doPush;
      end
      if(io_flush) begin
        logic_ptr_wentUp <= 1'b0;
      end
      if(logic_ptr_doPush) begin
        logic_ptr_push <= (logic_ptr_push + 6'h01);
      end
      if(logic_ptr_doPop) begin
        logic_ptr_pop <= (logic_ptr_pop + 6'h01);
      end
      if(io_flush) begin
        logic_ptr_push <= 6'h0;
        logic_ptr_pop <= 6'h0;
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
        logic_pop_sync_popReg <= 6'h0;
      end
    end
  end

  always @(posedge clk) begin
    if(logic_pop_addressGen_ready) begin
      logic_pop_addressGen_rData <= logic_pop_addressGen_payload;
    end
  end


endmodule

//Axi4ToApbXbar_StreamFifo_2 replaced by Axi4ToApbXbar_StreamFifo_1

module Axi4ToApbXbar_StreamFifo_1 (
  input  wire          io_push_valid,
  output wire          io_push_ready,
  input  wire [11:0]   io_push_payload_addr,
  input  wire [3:0]    io_push_payload_id,
  input  wire [7:0]    io_push_payload_len,
  input  wire [2:0]    io_push_payload_size,
  input  wire [1:0]    io_push_payload_burst,
  output wire          io_pop_valid,
  input  wire          io_pop_ready,
  output wire [11:0]   io_pop_payload_addr,
  output wire [3:0]    io_pop_payload_id,
  output wire [7:0]    io_pop_payload_len,
  output wire [2:0]    io_pop_payload_size,
  output wire [1:0]    io_pop_payload_burst,
  input  wire          io_flush,
  output wire [5:0]    io_occupancy,
  output wire [5:0]    io_availability,
  input  wire          clk,
  input  wire          resetn
);

  reg        [28:0]   logic_ram_spinal_port1;
  wire       [28:0]   _zz_logic_ram_port;
  reg                 _zz_1;
  wire                logic_ptr_doPush;
  wire                logic_ptr_doPop;
  wire                logic_ptr_full;
  wire                logic_ptr_empty;
  reg        [5:0]    logic_ptr_push;
  reg        [5:0]    logic_ptr_pop;
  wire       [5:0]    logic_ptr_occupancy;
  wire       [5:0]    logic_ptr_popOnIo;
  wire                when_Stream_l1455;
  reg                 logic_ptr_wentUp;
  wire                io_push_fire;
  wire                logic_push_onRam_write_valid;
  wire       [4:0]    logic_push_onRam_write_payload_address;
  wire       [11:0]   logic_push_onRam_write_payload_data_addr;
  wire       [3:0]    logic_push_onRam_write_payload_data_id;
  wire       [7:0]    logic_push_onRam_write_payload_data_len;
  wire       [2:0]    logic_push_onRam_write_payload_data_size;
  wire       [1:0]    logic_push_onRam_write_payload_data_burst;
  wire                logic_pop_addressGen_valid;
  reg                 logic_pop_addressGen_ready;
  wire       [4:0]    logic_pop_addressGen_payload;
  wire                logic_pop_addressGen_fire;
  wire                logic_pop_sync_readArbitation_valid;
  wire                logic_pop_sync_readArbitation_ready;
  wire       [4:0]    logic_pop_sync_readArbitation_payload;
  reg                 logic_pop_addressGen_rValid;
  reg        [4:0]    logic_pop_addressGen_rData;
  wire                when_Stream_l477;
  wire                logic_pop_sync_readPort_cmd_valid;
  wire       [4:0]    logic_pop_sync_readPort_cmd_payload;
  wire       [11:0]   logic_pop_sync_readPort_rsp_addr;
  wire       [3:0]    logic_pop_sync_readPort_rsp_id;
  wire       [7:0]    logic_pop_sync_readPort_rsp_len;
  wire       [2:0]    logic_pop_sync_readPort_rsp_size;
  wire       [1:0]    logic_pop_sync_readPort_rsp_burst;
  wire       [28:0]   _zz_logic_pop_sync_readPort_rsp_addr;
  wire                logic_pop_addressGen_toFlowFire_valid;
  wire       [4:0]    logic_pop_addressGen_toFlowFire_payload;
  wire                logic_pop_sync_readArbitation_translated_valid;
  wire                logic_pop_sync_readArbitation_translated_ready;
  wire       [11:0]   logic_pop_sync_readArbitation_translated_payload_addr;
  wire       [3:0]    logic_pop_sync_readArbitation_translated_payload_id;
  wire       [7:0]    logic_pop_sync_readArbitation_translated_payload_len;
  wire       [2:0]    logic_pop_sync_readArbitation_translated_payload_size;
  wire       [1:0]    logic_pop_sync_readArbitation_translated_payload_burst;
  wire                logic_pop_sync_readArbitation_fire;
  reg        [5:0]    logic_pop_sync_popReg;
  reg [28:0] logic_ram [0:31];

  assign _zz_logic_ram_port = {logic_push_onRam_write_payload_data_burst,{logic_push_onRam_write_payload_data_size,{logic_push_onRam_write_payload_data_len,{logic_push_onRam_write_payload_data_id,logic_push_onRam_write_payload_data_addr}}}};
  always @(posedge clk) begin
    if(_zz_1) begin
      logic_ram[logic_push_onRam_write_payload_address] <= _zz_logic_ram_port;
    end
  end

  always @(posedge clk) begin
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
  assign logic_ptr_full = (((logic_ptr_push ^ logic_ptr_popOnIo) ^ 6'h20) == 6'h0);
  assign logic_ptr_empty = (logic_ptr_push == logic_ptr_pop);
  assign logic_ptr_occupancy = (logic_ptr_push - logic_ptr_popOnIo);
  assign io_push_ready = (! logic_ptr_full);
  assign io_push_fire = (io_push_valid && io_push_ready);
  assign logic_ptr_doPush = io_push_fire;
  assign logic_push_onRam_write_valid = io_push_fire;
  assign logic_push_onRam_write_payload_address = logic_ptr_push[4:0];
  assign logic_push_onRam_write_payload_data_addr = io_push_payload_addr;
  assign logic_push_onRam_write_payload_data_id = io_push_payload_id;
  assign logic_push_onRam_write_payload_data_len = io_push_payload_len;
  assign logic_push_onRam_write_payload_data_size = io_push_payload_size;
  assign logic_push_onRam_write_payload_data_burst = io_push_payload_burst;
  assign logic_pop_addressGen_valid = (! logic_ptr_empty);
  assign logic_pop_addressGen_payload = logic_ptr_pop[4:0];
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
  assign _zz_logic_pop_sync_readPort_rsp_addr = logic_ram_spinal_port1;
  assign logic_pop_sync_readPort_rsp_addr = _zz_logic_pop_sync_readPort_rsp_addr[11 : 0];
  assign logic_pop_sync_readPort_rsp_id = _zz_logic_pop_sync_readPort_rsp_addr[15 : 12];
  assign logic_pop_sync_readPort_rsp_len = _zz_logic_pop_sync_readPort_rsp_addr[23 : 16];
  assign logic_pop_sync_readPort_rsp_size = _zz_logic_pop_sync_readPort_rsp_addr[26 : 24];
  assign logic_pop_sync_readPort_rsp_burst = _zz_logic_pop_sync_readPort_rsp_addr[28 : 27];
  assign logic_pop_addressGen_toFlowFire_valid = logic_pop_addressGen_fire;
  assign logic_pop_addressGen_toFlowFire_payload = logic_pop_addressGen_payload;
  assign logic_pop_sync_readPort_cmd_valid = logic_pop_addressGen_toFlowFire_valid;
  assign logic_pop_sync_readPort_cmd_payload = logic_pop_addressGen_toFlowFire_payload;
  assign logic_pop_sync_readArbitation_translated_valid = logic_pop_sync_readArbitation_valid;
  assign logic_pop_sync_readArbitation_ready = logic_pop_sync_readArbitation_translated_ready;
  assign logic_pop_sync_readArbitation_translated_payload_addr = logic_pop_sync_readPort_rsp_addr;
  assign logic_pop_sync_readArbitation_translated_payload_id = logic_pop_sync_readPort_rsp_id;
  assign logic_pop_sync_readArbitation_translated_payload_len = logic_pop_sync_readPort_rsp_len;
  assign logic_pop_sync_readArbitation_translated_payload_size = logic_pop_sync_readPort_rsp_size;
  assign logic_pop_sync_readArbitation_translated_payload_burst = logic_pop_sync_readPort_rsp_burst;
  assign io_pop_valid = logic_pop_sync_readArbitation_translated_valid;
  assign logic_pop_sync_readArbitation_translated_ready = io_pop_ready;
  assign io_pop_payload_addr = logic_pop_sync_readArbitation_translated_payload_addr;
  assign io_pop_payload_id = logic_pop_sync_readArbitation_translated_payload_id;
  assign io_pop_payload_len = logic_pop_sync_readArbitation_translated_payload_len;
  assign io_pop_payload_size = logic_pop_sync_readArbitation_translated_payload_size;
  assign io_pop_payload_burst = logic_pop_sync_readArbitation_translated_payload_burst;
  assign logic_pop_sync_readArbitation_fire = (logic_pop_sync_readArbitation_valid && logic_pop_sync_readArbitation_ready);
  assign logic_ptr_popOnIo = logic_pop_sync_popReg;
  assign io_occupancy = logic_ptr_occupancy;
  assign io_availability = (6'h20 - logic_ptr_occupancy);
  always @(posedge clk) begin
    if(!resetn) begin
      logic_ptr_push <= 6'h0;
      logic_ptr_pop <= 6'h0;
      logic_ptr_wentUp <= 1'b0;
      logic_pop_addressGen_rValid <= 1'b0;
      logic_pop_sync_popReg <= 6'h0;
    end else begin
      if(when_Stream_l1455) begin
        logic_ptr_wentUp <= logic_ptr_doPush;
      end
      if(io_flush) begin
        logic_ptr_wentUp <= 1'b0;
      end
      if(logic_ptr_doPush) begin
        logic_ptr_push <= (logic_ptr_push + 6'h01);
      end
      if(logic_ptr_doPop) begin
        logic_ptr_pop <= (logic_ptr_pop + 6'h01);
      end
      if(io_flush) begin
        logic_ptr_push <= 6'h0;
        logic_ptr_pop <= 6'h0;
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
        logic_pop_sync_popReg <= 6'h0;
      end
    end
  end

  always @(posedge clk) begin
    if(logic_pop_addressGen_ready) begin
      logic_pop_addressGen_rData <= logic_pop_addressGen_payload;
    end
  end


endmodule

module Axi4ToApbXbar_Axi4SharedArbiter (
  input  wire          io_sharedInputs_0_arw_valid,
  output wire          io_sharedInputs_0_arw_ready,
  input  wire [11:0]   io_sharedInputs_0_arw_payload_addr,
  input  wire [3:0]    io_sharedInputs_0_arw_payload_id,
  input  wire [7:0]    io_sharedInputs_0_arw_payload_len,
  input  wire [2:0]    io_sharedInputs_0_arw_payload_size,
  input  wire [1:0]    io_sharedInputs_0_arw_payload_burst,
  input  wire          io_sharedInputs_0_arw_payload_write,
  input  wire          io_sharedInputs_0_w_valid,
  output wire          io_sharedInputs_0_w_ready,
  input  wire [31:0]   io_sharedInputs_0_w_payload_data,
  input  wire [3:0]    io_sharedInputs_0_w_payload_strb,
  input  wire          io_sharedInputs_0_w_payload_last,
  output wire          io_sharedInputs_0_b_valid,
  input  wire          io_sharedInputs_0_b_ready,
  output wire [3:0]    io_sharedInputs_0_b_payload_id,
  output wire [1:0]    io_sharedInputs_0_b_payload_resp,
  output wire          io_sharedInputs_0_r_valid,
  input  wire          io_sharedInputs_0_r_ready,
  output wire [31:0]   io_sharedInputs_0_r_payload_data,
  output wire [3:0]    io_sharedInputs_0_r_payload_id,
  output wire [1:0]    io_sharedInputs_0_r_payload_resp,
  output wire          io_sharedInputs_0_r_payload_last,
  input  wire          io_sharedInputs_1_arw_valid,
  output wire          io_sharedInputs_1_arw_ready,
  input  wire [11:0]   io_sharedInputs_1_arw_payload_addr,
  input  wire [3:0]    io_sharedInputs_1_arw_payload_id,
  input  wire [7:0]    io_sharedInputs_1_arw_payload_len,
  input  wire [2:0]    io_sharedInputs_1_arw_payload_size,
  input  wire [1:0]    io_sharedInputs_1_arw_payload_burst,
  input  wire          io_sharedInputs_1_arw_payload_write,
  input  wire          io_sharedInputs_1_w_valid,
  output wire          io_sharedInputs_1_w_ready,
  input  wire [31:0]   io_sharedInputs_1_w_payload_data,
  input  wire [3:0]    io_sharedInputs_1_w_payload_strb,
  input  wire          io_sharedInputs_1_w_payload_last,
  output wire          io_sharedInputs_1_b_valid,
  input  wire          io_sharedInputs_1_b_ready,
  output wire [3:0]    io_sharedInputs_1_b_payload_id,
  output wire [1:0]    io_sharedInputs_1_b_payload_resp,
  output wire          io_sharedInputs_1_r_valid,
  input  wire          io_sharedInputs_1_r_ready,
  output wire [31:0]   io_sharedInputs_1_r_payload_data,
  output wire [3:0]    io_sharedInputs_1_r_payload_id,
  output wire [1:0]    io_sharedInputs_1_r_payload_resp,
  output wire          io_sharedInputs_1_r_payload_last,
  output wire          io_output_arw_valid,
  input  wire          io_output_arw_ready,
  output wire [11:0]   io_output_arw_payload_addr,
  output wire [4:0]    io_output_arw_payload_id,
  output wire [7:0]    io_output_arw_payload_len,
  output wire [2:0]    io_output_arw_payload_size,
  output wire [1:0]    io_output_arw_payload_burst,
  output wire          io_output_arw_payload_write,
  output wire          io_output_w_valid,
  input  wire          io_output_w_ready,
  output wire [31:0]   io_output_w_payload_data,
  output wire [3:0]    io_output_w_payload_strb,
  output wire          io_output_w_payload_last,
  input  wire          io_output_b_valid,
  output wire          io_output_b_ready,
  input  wire [4:0]    io_output_b_payload_id,
  input  wire [1:0]    io_output_b_payload_resp,
  input  wire          io_output_r_valid,
  output wire          io_output_r_ready,
  input  wire [31:0]   io_output_r_payload_data,
  input  wire [4:0]    io_output_r_payload_id,
  input  wire [1:0]    io_output_r_payload_resp,
  input  wire          io_output_r_payload_last,
  input  wire          clk,
  input  wire          resetn
);

  reg                 cmdArbiter_io_output_ready;
  wire                cmdRouteFork_throwWhen_translated_fifo_io_pop_ready;
  wire                cmdArbiter_io_inputs_0_ready;
  wire                cmdArbiter_io_inputs_1_ready;
  wire                cmdArbiter_io_output_valid;
  wire       [11:0]   cmdArbiter_io_output_payload_addr;
  wire       [3:0]    cmdArbiter_io_output_payload_id;
  wire       [7:0]    cmdArbiter_io_output_payload_len;
  wire       [2:0]    cmdArbiter_io_output_payload_size;
  wire       [1:0]    cmdArbiter_io_output_payload_burst;
  wire                cmdArbiter_io_output_payload_write;
  wire       [0:0]    cmdArbiter_io_chosen;
  wire       [1:0]    cmdArbiter_io_chosenOH;
  wire                cmdRouteFork_throwWhen_translated_fifo_io_push_ready;
  wire                cmdRouteFork_throwWhen_translated_fifo_io_pop_valid;
  wire       [0:0]    cmdRouteFork_throwWhen_translated_fifo_io_pop_payload;
  wire       [2:0]    cmdRouteFork_throwWhen_translated_fifo_io_occupancy;
  wire       [2:0]    cmdRouteFork_throwWhen_translated_fifo_io_availability;
  wire       [1:0]    _zz__zz_io_output_arw_payload_id;
  wire       [1:0]    _zz__zz_io_output_arw_payload_id_1;
  wire       [1:0]    _zz__zz_cmdRouteFork_throwWhen_translated_payload;
  reg                 _zz_writeLogic_routeDataInput_valid;
  reg                 _zz_writeLogic_routeDataInput_ready;
  reg        [31:0]   _zz_writeLogic_routeDataInput_payload_data;
  reg        [3:0]    _zz_writeLogic_routeDataInput_payload_strb;
  reg                 _zz_writeLogic_routeDataInput_payload_last;
  reg                 _zz_io_output_b_ready;
  reg                 _zz_io_output_r_ready;
  wire                inputsCmd_0_valid;
  wire                inputsCmd_0_ready;
  wire       [11:0]   inputsCmd_0_payload_addr;
  wire       [3:0]    inputsCmd_0_payload_id;
  wire       [7:0]    inputsCmd_0_payload_len;
  wire       [2:0]    inputsCmd_0_payload_size;
  wire       [1:0]    inputsCmd_0_payload_burst;
  wire                inputsCmd_0_payload_write;
  wire                inputsCmd_1_valid;
  wire                inputsCmd_1_ready;
  wire       [11:0]   inputsCmd_1_payload_addr;
  wire       [3:0]    inputsCmd_1_payload_id;
  wire       [7:0]    inputsCmd_1_payload_len;
  wire       [2:0]    inputsCmd_1_payload_size;
  wire       [1:0]    inputsCmd_1_payload_burst;
  wire                inputsCmd_1_payload_write;
  wire                cmdOutputFork_valid;
  wire                cmdOutputFork_ready;
  wire       [11:0]   cmdOutputFork_payload_addr;
  wire       [3:0]    cmdOutputFork_payload_id;
  wire       [7:0]    cmdOutputFork_payload_len;
  wire       [2:0]    cmdOutputFork_payload_size;
  wire       [1:0]    cmdOutputFork_payload_burst;
  wire                cmdOutputFork_payload_write;
  wire                cmdRouteFork_valid;
  reg                 cmdRouteFork_ready;
  wire       [11:0]   cmdRouteFork_payload_addr;
  wire       [3:0]    cmdRouteFork_payload_id;
  wire       [7:0]    cmdRouteFork_payload_len;
  wire       [2:0]    cmdRouteFork_payload_size;
  wire       [1:0]    cmdRouteFork_payload_burst;
  wire                cmdRouteFork_payload_write;
  reg                 cmdArbiter_io_output_fork2_logic_linkEnable_0;
  reg                 cmdArbiter_io_output_fork2_logic_linkEnable_1;
  wire                when_Stream_l1253;
  wire                when_Stream_l1253_1;
  wire                cmdOutputFork_fire;
  wire                cmdRouteFork_fire;
  wire                _zz_io_output_arw_payload_id;
  wire                _zz_io_output_arw_payload_id_1;
  wire                when_Stream_l581;
  reg                 cmdRouteFork_throwWhen_valid;
  wire                cmdRouteFork_throwWhen_ready;
  wire       [11:0]   cmdRouteFork_throwWhen_payload_addr;
  wire       [3:0]    cmdRouteFork_throwWhen_payload_id;
  wire       [7:0]    cmdRouteFork_throwWhen_payload_len;
  wire       [2:0]    cmdRouteFork_throwWhen_payload_size;
  wire       [1:0]    cmdRouteFork_throwWhen_payload_burst;
  wire                cmdRouteFork_throwWhen_payload_write;
  wire                _zz_cmdRouteFork_throwWhen_translated_payload;
  wire                cmdRouteFork_throwWhen_translated_valid;
  wire                cmdRouteFork_throwWhen_translated_ready;
  wire       [0:0]    cmdRouteFork_throwWhen_translated_payload;
  wire                writeLogic_routeDataInput_valid;
  wire                writeLogic_routeDataInput_ready;
  wire       [31:0]   writeLogic_routeDataInput_payload_data;
  wire       [3:0]    writeLogic_routeDataInput_payload_strb;
  wire                writeLogic_routeDataInput_payload_last;
  wire                io_output_w_fire;
  wire       [0:0]    writeLogic_writeRspIndex;
  wire                writeLogic_writeRspSels_0;
  wire                writeLogic_writeRspSels_1;
  wire       [0:0]    readRspIndex;
  wire                readRspSels_0;
  wire                readRspSels_1;

  assign _zz__zz_io_output_arw_payload_id = cmdArbiter_io_chosenOH[1 : 0];
  assign _zz__zz_io_output_arw_payload_id_1 = cmdArbiter_io_chosenOH[1 : 0];
  assign _zz__zz_cmdRouteFork_throwWhen_translated_payload = cmdArbiter_io_chosenOH[1 : 0];
  Axi4ToApbXbar_StreamArbiter cmdArbiter (
    .io_inputs_0_valid         (inputsCmd_0_valid                      ), //i
    .io_inputs_0_ready         (cmdArbiter_io_inputs_0_ready           ), //o
    .io_inputs_0_payload_addr  (inputsCmd_0_payload_addr[11:0]         ), //i
    .io_inputs_0_payload_id    (inputsCmd_0_payload_id[3:0]            ), //i
    .io_inputs_0_payload_len   (inputsCmd_0_payload_len[7:0]           ), //i
    .io_inputs_0_payload_size  (inputsCmd_0_payload_size[2:0]          ), //i
    .io_inputs_0_payload_burst (inputsCmd_0_payload_burst[1:0]         ), //i
    .io_inputs_0_payload_write (inputsCmd_0_payload_write              ), //i
    .io_inputs_1_valid         (inputsCmd_1_valid                      ), //i
    .io_inputs_1_ready         (cmdArbiter_io_inputs_1_ready           ), //o
    .io_inputs_1_payload_addr  (inputsCmd_1_payload_addr[11:0]         ), //i
    .io_inputs_1_payload_id    (inputsCmd_1_payload_id[3:0]            ), //i
    .io_inputs_1_payload_len   (inputsCmd_1_payload_len[7:0]           ), //i
    .io_inputs_1_payload_size  (inputsCmd_1_payload_size[2:0]          ), //i
    .io_inputs_1_payload_burst (inputsCmd_1_payload_burst[1:0]         ), //i
    .io_inputs_1_payload_write (inputsCmd_1_payload_write              ), //i
    .io_output_valid           (cmdArbiter_io_output_valid             ), //o
    .io_output_ready           (cmdArbiter_io_output_ready             ), //i
    .io_output_payload_addr    (cmdArbiter_io_output_payload_addr[11:0]), //o
    .io_output_payload_id      (cmdArbiter_io_output_payload_id[3:0]   ), //o
    .io_output_payload_len     (cmdArbiter_io_output_payload_len[7:0]  ), //o
    .io_output_payload_size    (cmdArbiter_io_output_payload_size[2:0] ), //o
    .io_output_payload_burst   (cmdArbiter_io_output_payload_burst[1:0]), //o
    .io_output_payload_write   (cmdArbiter_io_output_payload_write     ), //o
    .io_chosen                 (cmdArbiter_io_chosen                   ), //o
    .io_chosenOH               (cmdArbiter_io_chosenOH[1:0]            ), //o
    .clk                       (clk                                    ), //i
    .resetn                    (resetn                                 )  //i
  );
  Axi4ToApbXbar_StreamFifoLowLatency cmdRouteFork_throwWhen_translated_fifo (
    .io_push_valid   (cmdRouteFork_throwWhen_translated_valid                    ), //i
    .io_push_ready   (cmdRouteFork_throwWhen_translated_fifo_io_push_ready       ), //o
    .io_push_payload (cmdRouteFork_throwWhen_translated_payload                  ), //i
    .io_pop_valid    (cmdRouteFork_throwWhen_translated_fifo_io_pop_valid        ), //o
    .io_pop_ready    (cmdRouteFork_throwWhen_translated_fifo_io_pop_ready        ), //i
    .io_pop_payload  (cmdRouteFork_throwWhen_translated_fifo_io_pop_payload      ), //o
    .io_flush        (1'b0                                                       ), //i
    .io_occupancy    (cmdRouteFork_throwWhen_translated_fifo_io_occupancy[2:0]   ), //o
    .io_availability (cmdRouteFork_throwWhen_translated_fifo_io_availability[2:0]), //o
    .clk             (clk                                                        ), //i
    .resetn          (resetn                                                     )  //i
  );
  always @(*) begin
    case(cmdRouteFork_throwWhen_translated_fifo_io_pop_payload)
      1'b0 : begin
        _zz_writeLogic_routeDataInput_valid = io_sharedInputs_0_w_valid;
        _zz_writeLogic_routeDataInput_ready = io_sharedInputs_0_w_ready;
        _zz_writeLogic_routeDataInput_payload_data = io_sharedInputs_0_w_payload_data;
        _zz_writeLogic_routeDataInput_payload_strb = io_sharedInputs_0_w_payload_strb;
        _zz_writeLogic_routeDataInput_payload_last = io_sharedInputs_0_w_payload_last;
      end
      default : begin
        _zz_writeLogic_routeDataInput_valid = io_sharedInputs_1_w_valid;
        _zz_writeLogic_routeDataInput_ready = io_sharedInputs_1_w_ready;
        _zz_writeLogic_routeDataInput_payload_data = io_sharedInputs_1_w_payload_data;
        _zz_writeLogic_routeDataInput_payload_strb = io_sharedInputs_1_w_payload_strb;
        _zz_writeLogic_routeDataInput_payload_last = io_sharedInputs_1_w_payload_last;
      end
    endcase
  end

  always @(*) begin
    case(writeLogic_writeRspIndex)
      1'b0 : _zz_io_output_b_ready = io_sharedInputs_0_b_ready;
      default : _zz_io_output_b_ready = io_sharedInputs_1_b_ready;
    endcase
  end

  always @(*) begin
    case(readRspIndex)
      1'b0 : _zz_io_output_r_ready = io_sharedInputs_0_r_ready;
      default : _zz_io_output_r_ready = io_sharedInputs_1_r_ready;
    endcase
  end

  assign inputsCmd_0_valid = io_sharedInputs_0_arw_valid;
  assign io_sharedInputs_0_arw_ready = inputsCmd_0_ready;
  assign inputsCmd_0_payload_addr = io_sharedInputs_0_arw_payload_addr;
  assign inputsCmd_0_payload_id = io_sharedInputs_0_arw_payload_id;
  assign inputsCmd_0_payload_len = io_sharedInputs_0_arw_payload_len;
  assign inputsCmd_0_payload_size = io_sharedInputs_0_arw_payload_size;
  assign inputsCmd_0_payload_burst = io_sharedInputs_0_arw_payload_burst;
  assign inputsCmd_0_payload_write = io_sharedInputs_0_arw_payload_write;
  assign inputsCmd_1_valid = io_sharedInputs_1_arw_valid;
  assign io_sharedInputs_1_arw_ready = inputsCmd_1_ready;
  assign inputsCmd_1_payload_addr = io_sharedInputs_1_arw_payload_addr;
  assign inputsCmd_1_payload_id = io_sharedInputs_1_arw_payload_id;
  assign inputsCmd_1_payload_len = io_sharedInputs_1_arw_payload_len;
  assign inputsCmd_1_payload_size = io_sharedInputs_1_arw_payload_size;
  assign inputsCmd_1_payload_burst = io_sharedInputs_1_arw_payload_burst;
  assign inputsCmd_1_payload_write = io_sharedInputs_1_arw_payload_write;
  assign inputsCmd_0_ready = cmdArbiter_io_inputs_0_ready;
  assign inputsCmd_1_ready = cmdArbiter_io_inputs_1_ready;
  always @(*) begin
    cmdArbiter_io_output_ready = 1'b1;
    if(when_Stream_l1253) begin
      cmdArbiter_io_output_ready = 1'b0;
    end
    if(when_Stream_l1253_1) begin
      cmdArbiter_io_output_ready = 1'b0;
    end
  end

  assign when_Stream_l1253 = ((! cmdOutputFork_ready) && cmdArbiter_io_output_fork2_logic_linkEnable_0);
  assign when_Stream_l1253_1 = ((! cmdRouteFork_ready) && cmdArbiter_io_output_fork2_logic_linkEnable_1);
  assign cmdOutputFork_valid = (cmdArbiter_io_output_valid && cmdArbiter_io_output_fork2_logic_linkEnable_0);
  assign cmdOutputFork_payload_addr = cmdArbiter_io_output_payload_addr;
  assign cmdOutputFork_payload_id = cmdArbiter_io_output_payload_id;
  assign cmdOutputFork_payload_len = cmdArbiter_io_output_payload_len;
  assign cmdOutputFork_payload_size = cmdArbiter_io_output_payload_size;
  assign cmdOutputFork_payload_burst = cmdArbiter_io_output_payload_burst;
  assign cmdOutputFork_payload_write = cmdArbiter_io_output_payload_write;
  assign cmdOutputFork_fire = (cmdOutputFork_valid && cmdOutputFork_ready);
  assign cmdRouteFork_valid = (cmdArbiter_io_output_valid && cmdArbiter_io_output_fork2_logic_linkEnable_1);
  assign cmdRouteFork_payload_addr = cmdArbiter_io_output_payload_addr;
  assign cmdRouteFork_payload_id = cmdArbiter_io_output_payload_id;
  assign cmdRouteFork_payload_len = cmdArbiter_io_output_payload_len;
  assign cmdRouteFork_payload_size = cmdArbiter_io_output_payload_size;
  assign cmdRouteFork_payload_burst = cmdArbiter_io_output_payload_burst;
  assign cmdRouteFork_payload_write = cmdArbiter_io_output_payload_write;
  assign cmdRouteFork_fire = (cmdRouteFork_valid && cmdRouteFork_ready);
  assign io_output_arw_valid = cmdOutputFork_valid;
  assign cmdOutputFork_ready = io_output_arw_ready;
  assign io_output_arw_payload_addr = cmdOutputFork_payload_addr;
  assign io_output_arw_payload_len = cmdOutputFork_payload_len;
  assign io_output_arw_payload_size = cmdOutputFork_payload_size;
  assign io_output_arw_payload_burst = cmdOutputFork_payload_burst;
  assign io_output_arw_payload_write = cmdOutputFork_payload_write;
  assign _zz_io_output_arw_payload_id = _zz__zz_io_output_arw_payload_id[1];
  assign _zz_io_output_arw_payload_id_1 = _zz__zz_io_output_arw_payload_id_1[1];
  assign io_output_arw_payload_id = (cmdOutputFork_payload_write ? {_zz_io_output_arw_payload_id,cmdOutputFork_payload_id} : {_zz_io_output_arw_payload_id_1,cmdOutputFork_payload_id});
  assign when_Stream_l581 = (! cmdRouteFork_payload_write);
  always @(*) begin
    cmdRouteFork_throwWhen_valid = cmdRouteFork_valid;
    if(when_Stream_l581) begin
      cmdRouteFork_throwWhen_valid = 1'b0;
    end
  end

  always @(*) begin
    cmdRouteFork_ready = cmdRouteFork_throwWhen_ready;
    if(when_Stream_l581) begin
      cmdRouteFork_ready = 1'b1;
    end
  end

  assign cmdRouteFork_throwWhen_payload_addr = cmdRouteFork_payload_addr;
  assign cmdRouteFork_throwWhen_payload_id = cmdRouteFork_payload_id;
  assign cmdRouteFork_throwWhen_payload_len = cmdRouteFork_payload_len;
  assign cmdRouteFork_throwWhen_payload_size = cmdRouteFork_payload_size;
  assign cmdRouteFork_throwWhen_payload_burst = cmdRouteFork_payload_burst;
  assign cmdRouteFork_throwWhen_payload_write = cmdRouteFork_payload_write;
  assign _zz_cmdRouteFork_throwWhen_translated_payload = _zz__zz_cmdRouteFork_throwWhen_translated_payload[1];
  assign cmdRouteFork_throwWhen_translated_valid = cmdRouteFork_throwWhen_valid;
  assign cmdRouteFork_throwWhen_ready = cmdRouteFork_throwWhen_translated_ready;
  assign cmdRouteFork_throwWhen_translated_payload = _zz_cmdRouteFork_throwWhen_translated_payload;
  assign cmdRouteFork_throwWhen_translated_ready = cmdRouteFork_throwWhen_translated_fifo_io_push_ready;
  assign writeLogic_routeDataInput_valid = _zz_writeLogic_routeDataInput_valid;
  assign writeLogic_routeDataInput_ready = _zz_writeLogic_routeDataInput_ready;
  assign writeLogic_routeDataInput_payload_data = _zz_writeLogic_routeDataInput_payload_data;
  assign writeLogic_routeDataInput_payload_strb = _zz_writeLogic_routeDataInput_payload_strb;
  assign writeLogic_routeDataInput_payload_last = _zz_writeLogic_routeDataInput_payload_last;
  assign io_output_w_valid = (cmdRouteFork_throwWhen_translated_fifo_io_pop_valid && writeLogic_routeDataInput_valid);
  assign io_output_w_payload_data = writeLogic_routeDataInput_payload_data;
  assign io_output_w_payload_strb = writeLogic_routeDataInput_payload_strb;
  assign io_output_w_payload_last = writeLogic_routeDataInput_payload_last;
  assign io_sharedInputs_0_w_ready = ((cmdRouteFork_throwWhen_translated_fifo_io_pop_valid && io_output_w_ready) && (cmdRouteFork_throwWhen_translated_fifo_io_pop_payload == 1'b0));
  assign io_sharedInputs_1_w_ready = ((cmdRouteFork_throwWhen_translated_fifo_io_pop_valid && io_output_w_ready) && (cmdRouteFork_throwWhen_translated_fifo_io_pop_payload == 1'b1));
  assign io_output_w_fire = (io_output_w_valid && io_output_w_ready);
  assign cmdRouteFork_throwWhen_translated_fifo_io_pop_ready = (io_output_w_fire && io_output_w_payload_last);
  assign writeLogic_writeRspIndex = io_output_b_payload_id[4 : 4];
  assign writeLogic_writeRspSels_0 = (writeLogic_writeRspIndex == 1'b0);
  assign writeLogic_writeRspSels_1 = (writeLogic_writeRspIndex == 1'b1);
  assign io_sharedInputs_0_b_valid = (io_output_b_valid && writeLogic_writeRspSels_0);
  assign io_sharedInputs_0_b_payload_resp = io_output_b_payload_resp;
  assign io_sharedInputs_0_b_payload_id = io_output_b_payload_id[3:0];
  assign io_sharedInputs_1_b_valid = (io_output_b_valid && writeLogic_writeRspSels_1);
  assign io_sharedInputs_1_b_payload_resp = io_output_b_payload_resp;
  assign io_sharedInputs_1_b_payload_id = io_output_b_payload_id[3:0];
  assign io_output_b_ready = _zz_io_output_b_ready;
  assign readRspIndex = io_output_r_payload_id[4 : 4];
  assign readRspSels_0 = (readRspIndex == 1'b0);
  assign readRspSels_1 = (readRspIndex == 1'b1);
  assign io_sharedInputs_0_r_valid = (io_output_r_valid && readRspSels_0);
  assign io_sharedInputs_0_r_payload_data = io_output_r_payload_data;
  assign io_sharedInputs_0_r_payload_resp = io_output_r_payload_resp;
  assign io_sharedInputs_0_r_payload_last = io_output_r_payload_last;
  assign io_sharedInputs_0_r_payload_id = io_output_r_payload_id[3:0];
  assign io_sharedInputs_1_r_valid = (io_output_r_valid && readRspSels_1);
  assign io_sharedInputs_1_r_payload_data = io_output_r_payload_data;
  assign io_sharedInputs_1_r_payload_resp = io_output_r_payload_resp;
  assign io_sharedInputs_1_r_payload_last = io_output_r_payload_last;
  assign io_sharedInputs_1_r_payload_id = io_output_r_payload_id[3:0];
  assign io_output_r_ready = _zz_io_output_r_ready;
  always @(posedge clk) begin
    if(!resetn) begin
      cmdArbiter_io_output_fork2_logic_linkEnable_0 <= 1'b1;
      cmdArbiter_io_output_fork2_logic_linkEnable_1 <= 1'b1;
    end else begin
      if(cmdOutputFork_fire) begin
        cmdArbiter_io_output_fork2_logic_linkEnable_0 <= 1'b0;
      end
      if(cmdRouteFork_fire) begin
        cmdArbiter_io_output_fork2_logic_linkEnable_1 <= 1'b0;
      end
      if(cmdArbiter_io_output_ready) begin
        cmdArbiter_io_output_fork2_logic_linkEnable_0 <= 1'b1;
        cmdArbiter_io_output_fork2_logic_linkEnable_1 <= 1'b1;
      end
    end
  end


endmodule

module Axi4ToApbXbar_Axi4SharedToApb3Bridge (
  input  wire          io_axi_arw_valid,
  output reg           io_axi_arw_ready,
  input  wire [11:0]   io_axi_arw_payload_addr,
  input  wire [4:0]    io_axi_arw_payload_id,
  input  wire [7:0]    io_axi_arw_payload_len,
  input  wire [2:0]    io_axi_arw_payload_size,
  input  wire [1:0]    io_axi_arw_payload_burst,
  input  wire          io_axi_arw_payload_write,
  input  wire          io_axi_w_valid,
  output reg           io_axi_w_ready,
  input  wire [31:0]   io_axi_w_payload_data,
  input  wire [3:0]    io_axi_w_payload_strb,
  input  wire          io_axi_w_payload_last,
  output reg           io_axi_b_valid,
  input  wire          io_axi_b_ready,
  output wire [4:0]    io_axi_b_payload_id,
  output wire [1:0]    io_axi_b_payload_resp,
  output reg           io_axi_r_valid,
  input  wire          io_axi_r_ready,
  output wire [31:0]   io_axi_r_payload_data,
  output wire [4:0]    io_axi_r_payload_id,
  output wire [1:0]    io_axi_r_payload_resp,
  output wire          io_axi_r_payload_last,
  output wire [11:0]   io_apb_PADDR,
  output reg  [0:0]    io_apb_PSEL,
  output reg           io_apb_PENABLE,
  input  wire          io_apb_PREADY,
  output wire          io_apb_PWRITE,
  output wire [31:0]   io_apb_PWDATA,
  input  wire [31:0]   io_apb_PRDATA,
  input  wire          io_apb_PSLVERROR,
  input  wire          clk,
  input  wire          resetn
);
  localparam Axi4ToApb3BridgePhase_SETUP = 2'd0;
  localparam Axi4ToApb3BridgePhase_ACCESS_1 = 2'd1;
  localparam Axi4ToApb3BridgePhase_RESPONSE = 2'd2;

  reg        [1:0]    phase;
  reg                 write;
  reg        [31:0]   readedData;
  reg        [4:0]    id;
  wire                when_Axi4SharedToApb3Bridge_l91;
  wire                when_Axi4SharedToApb3Bridge_l97;
  `ifndef SYNTHESIS
  reg [63:0] phase_string;
  `endif


  `ifndef SYNTHESIS
  always @(*) begin
    case(phase)
      Axi4ToApb3BridgePhase_SETUP : phase_string = "SETUP   ";
      Axi4ToApb3BridgePhase_ACCESS_1 : phase_string = "ACCESS_1";
      Axi4ToApb3BridgePhase_RESPONSE : phase_string = "RESPONSE";
      default : phase_string = "????????";
    endcase
  end
  `endif

  always @(*) begin
    io_axi_arw_ready = 1'b0;
    case(phase)
      Axi4ToApb3BridgePhase_SETUP : begin
        if(when_Axi4SharedToApb3Bridge_l91) begin
          if(when_Axi4SharedToApb3Bridge_l97) begin
            io_axi_arw_ready = 1'b1;
          end
        end
      end
      Axi4ToApb3BridgePhase_ACCESS_1 : begin
        if(io_apb_PREADY) begin
          io_axi_arw_ready = 1'b1;
        end
      end
      default : begin
      end
    endcase
  end

  always @(*) begin
    io_axi_w_ready = 1'b0;
    case(phase)
      Axi4ToApb3BridgePhase_SETUP : begin
        if(when_Axi4SharedToApb3Bridge_l91) begin
          if(when_Axi4SharedToApb3Bridge_l97) begin
            io_axi_w_ready = 1'b1;
          end
        end
      end
      Axi4ToApb3BridgePhase_ACCESS_1 : begin
        if(io_apb_PREADY) begin
          io_axi_w_ready = write;
        end
      end
      default : begin
      end
    endcase
  end

  always @(*) begin
    io_axi_b_valid = 1'b0;
    case(phase)
      Axi4ToApb3BridgePhase_SETUP : begin
      end
      Axi4ToApb3BridgePhase_ACCESS_1 : begin
      end
      default : begin
        if(write) begin
          io_axi_b_valid = 1'b1;
        end
      end
    endcase
  end

  always @(*) begin
    io_axi_r_valid = 1'b0;
    case(phase)
      Axi4ToApb3BridgePhase_SETUP : begin
      end
      Axi4ToApb3BridgePhase_ACCESS_1 : begin
      end
      default : begin
        if(!write) begin
          io_axi_r_valid = 1'b1;
        end
      end
    endcase
  end

  always @(*) begin
    io_apb_PSEL[0] = 1'b0;
    case(phase)
      Axi4ToApb3BridgePhase_SETUP : begin
        if(when_Axi4SharedToApb3Bridge_l91) begin
          io_apb_PSEL[0] = 1'b1;
          if(when_Axi4SharedToApb3Bridge_l97) begin
            io_apb_PSEL[0] = 1'b0;
          end
        end
      end
      Axi4ToApb3BridgePhase_ACCESS_1 : begin
        io_apb_PSEL[0] = 1'b1;
      end
      default : begin
      end
    endcase
  end

  always @(*) begin
    io_apb_PENABLE = 1'b0;
    case(phase)
      Axi4ToApb3BridgePhase_SETUP : begin
      end
      Axi4ToApb3BridgePhase_ACCESS_1 : begin
        io_apb_PENABLE = 1'b1;
      end
      default : begin
      end
    endcase
  end

  assign when_Axi4SharedToApb3Bridge_l91 = (io_axi_arw_valid && ((! io_axi_arw_payload_write) || io_axi_w_valid));
  assign when_Axi4SharedToApb3Bridge_l97 = (io_axi_arw_payload_write && (io_axi_w_payload_strb == 4'b0000));
  assign io_apb_PADDR = io_axi_arw_payload_addr;
  assign io_apb_PWDATA = io_axi_w_payload_data;
  assign io_apb_PWRITE = io_axi_arw_payload_write;
  assign io_axi_r_payload_resp = {io_apb_PSLVERROR,1'b0};
  assign io_axi_b_payload_resp = {io_apb_PSLVERROR,1'b0};
  assign io_axi_r_payload_id = id;
  assign io_axi_b_payload_id = id;
  assign io_axi_r_payload_data = readedData;
  assign io_axi_r_payload_last = 1'b1;
  always @(posedge clk) begin
    if(!resetn) begin
      phase <= Axi4ToApb3BridgePhase_SETUP;
    end else begin
      case(phase)
        Axi4ToApb3BridgePhase_SETUP : begin
          if(when_Axi4SharedToApb3Bridge_l91) begin
            phase <= Axi4ToApb3BridgePhase_ACCESS_1;
            if(when_Axi4SharedToApb3Bridge_l97) begin
              phase <= Axi4ToApb3BridgePhase_RESPONSE;
            end
          end
        end
        Axi4ToApb3BridgePhase_ACCESS_1 : begin
          if(io_apb_PREADY) begin
            phase <= Axi4ToApb3BridgePhase_RESPONSE;
          end
        end
        default : begin
          if(write) begin
            if(io_axi_b_ready) begin
              phase <= Axi4ToApb3BridgePhase_SETUP;
            end
          end else begin
            if(io_axi_r_ready) begin
              phase <= Axi4ToApb3BridgePhase_SETUP;
            end
          end
        end
      endcase
    end
  end

  always @(posedge clk) begin
    case(phase)
      Axi4ToApb3BridgePhase_SETUP : begin
        write <= io_axi_arw_payload_write;
        id <= io_axi_arw_payload_id;
      end
      Axi4ToApb3BridgePhase_ACCESS_1 : begin
        if(io_apb_PREADY) begin
          readedData <= io_apb_PRDATA;
        end
      end
      default : begin
      end
    endcase
  end


endmodule

//Axi4ToApbXbar_Apb3RegSliceStage_7 replaced by Axi4ToApbXbar_Apb3RegSliceStage_6

module Axi4ToApbXbar_Apb3RegSliceStage_6 (
  input  wire [6:0]    io_s_PADDR,
  input  wire [0:0]    io_s_PSEL,
  input  wire          io_s_PENABLE,
  output wire          io_s_PREADY,
  input  wire          io_s_PWRITE,
  input  wire [31:0]   io_s_PWDATA,
  output wire [31:0]   io_s_PRDATA,
  output wire          io_s_PSLVERROR,
  output wire [6:0]    io_m_PADDR,
  output wire [0:0]    io_m_PSEL,
  output wire          io_m_PENABLE,
  input  wire          io_m_PREADY,
  output wire          io_m_PWRITE,
  output wire [31:0]   io_m_PWDATA,
  input  wire [31:0]   io_m_PRDATA,
  input  wire          io_m_PSLVERROR,
  input  wire          clk,
  input  wire          resetn
);

  reg        [6:0]    paddr;
  reg        [31:0]   pwdata;
  reg                 pwrite;
  reg        [31:0]   prdata;
  reg                 pslverr;
  reg                 psel;
  reg                 penable;
  reg                 pready;
  wire                when_Apb3RegSlice_l48;
  wire                when_Apb3RegSlice_l55;
  wire                when_Apb3RegSlice_l59;

  assign io_m_PADDR = paddr;
  assign io_m_PWDATA = pwdata;
  assign io_m_PWRITE = pwrite;
  assign io_m_PSEL = psel;
  assign io_m_PENABLE = penable;
  assign io_s_PREADY = pready;
  assign io_s_PRDATA = prdata;
  assign io_s_PSLVERROR = pslverr;
  assign when_Apb3RegSlice_l48 = ((((! psel) && (! pready)) && io_s_PSEL[0]) && (! io_s_PENABLE));
  assign when_Apb3RegSlice_l55 = (psel && (! penable));
  assign when_Apb3RegSlice_l59 = ((psel && penable) && io_m_PREADY);
  always @(posedge clk) begin
    if(!resetn) begin
      prdata <= 32'h0;
      pslverr <= 1'b0;
      psel <= 1'b0;
      penable <= 1'b0;
      pready <= 1'b0;
    end else begin
      pready <= 1'b0;
      if(when_Apb3RegSlice_l48) begin
        psel <= 1'b1;
      end
      if(when_Apb3RegSlice_l55) begin
        penable <= 1'b1;
      end
      if(when_Apb3RegSlice_l59) begin
        psel <= 1'b0;
        penable <= 1'b0;
        pready <= 1'b1;
        prdata <= io_m_PRDATA;
        pslverr <= io_m_PSLVERROR;
      end
    end
  end

  always @(posedge clk) begin
    if(when_Apb3RegSlice_l48) begin
      paddr <= io_s_PADDR;
      pwdata <= io_s_PWDATA;
      pwrite <= io_s_PWRITE;
    end
  end


endmodule

//Axi4ToApbXbar_Apb3RegSliceStage_5 replaced by Axi4ToApbXbar_Apb3RegSliceStage_1

//Axi4ToApbXbar_Apb3RegSliceStage_4 replaced by Axi4ToApbXbar_Apb3RegSliceStage_1

//Axi4ToApbXbar_Apb3RegSliceStage_3 replaced by Axi4ToApbXbar_Apb3RegSliceStage_1

//Axi4ToApbXbar_Apb3RegSliceStage_2 replaced by Axi4ToApbXbar_Apb3RegSliceStage_1

module Axi4ToApbXbar_Apb3RegSliceStage_1 (
  input  wire [4:0]    io_s_PADDR,
  input  wire [0:0]    io_s_PSEL,
  input  wire          io_s_PENABLE,
  output wire          io_s_PREADY,
  input  wire          io_s_PWRITE,
  input  wire [31:0]   io_s_PWDATA,
  output wire [31:0]   io_s_PRDATA,
  output wire          io_s_PSLVERROR,
  output wire [4:0]    io_m_PADDR,
  output wire [0:0]    io_m_PSEL,
  output wire          io_m_PENABLE,
  input  wire          io_m_PREADY,
  output wire          io_m_PWRITE,
  output wire [31:0]   io_m_PWDATA,
  input  wire [31:0]   io_m_PRDATA,
  input  wire          io_m_PSLVERROR,
  input  wire          clk,
  input  wire          resetn
);

  reg        [4:0]    paddr;
  reg        [31:0]   pwdata;
  reg                 pwrite;
  reg        [31:0]   prdata;
  reg                 pslverr;
  reg                 psel;
  reg                 penable;
  reg                 pready;
  wire                when_Apb3RegSlice_l48;
  wire                when_Apb3RegSlice_l55;
  wire                when_Apb3RegSlice_l59;

  assign io_m_PADDR = paddr;
  assign io_m_PWDATA = pwdata;
  assign io_m_PWRITE = pwrite;
  assign io_m_PSEL = psel;
  assign io_m_PENABLE = penable;
  assign io_s_PREADY = pready;
  assign io_s_PRDATA = prdata;
  assign io_s_PSLVERROR = pslverr;
  assign when_Apb3RegSlice_l48 = ((((! psel) && (! pready)) && io_s_PSEL[0]) && (! io_s_PENABLE));
  assign when_Apb3RegSlice_l55 = (psel && (! penable));
  assign when_Apb3RegSlice_l59 = ((psel && penable) && io_m_PREADY);
  always @(posedge clk) begin
    if(!resetn) begin
      prdata <= 32'h0;
      pslverr <= 1'b0;
      psel <= 1'b0;
      penable <= 1'b0;
      pready <= 1'b0;
    end else begin
      pready <= 1'b0;
      if(when_Apb3RegSlice_l48) begin
        psel <= 1'b1;
      end
      if(when_Apb3RegSlice_l55) begin
        penable <= 1'b1;
      end
      if(when_Apb3RegSlice_l59) begin
        psel <= 1'b0;
        penable <= 1'b0;
        pready <= 1'b1;
        prdata <= io_m_PRDATA;
        pslverr <= io_m_PSLVERROR;
      end
    end
  end

  always @(posedge clk) begin
    if(when_Apb3RegSlice_l48) begin
      paddr <= io_s_PADDR;
      pwdata <= io_s_PWDATA;
      pwrite <= io_s_PWRITE;
    end
  end


endmodule

module Axi4ToApbXbar_Apb3RegSliceStage (
  input  wire [9:0]    io_s_PADDR,
  input  wire [0:0]    io_s_PSEL,
  input  wire          io_s_PENABLE,
  output wire          io_s_PREADY,
  input  wire          io_s_PWRITE,
  input  wire [31:0]   io_s_PWDATA,
  output wire [31:0]   io_s_PRDATA,
  output wire          io_s_PSLVERROR,
  output wire [9:0]    io_m_PADDR,
  output wire [0:0]    io_m_PSEL,
  output wire          io_m_PENABLE,
  input  wire          io_m_PREADY,
  output wire          io_m_PWRITE,
  output wire [31:0]   io_m_PWDATA,
  input  wire [31:0]   io_m_PRDATA,
  input  wire          io_m_PSLVERROR,
  input  wire          clk,
  input  wire          resetn
);

  reg        [9:0]    paddr;
  reg        [31:0]   pwdata;
  reg                 pwrite;
  reg        [31:0]   prdata;
  reg                 pslverr;
  reg                 psel;
  reg                 penable;
  reg                 pready;
  wire                when_Apb3RegSlice_l48;
  wire                when_Apb3RegSlice_l55;
  wire                when_Apb3RegSlice_l59;

  assign io_m_PADDR = paddr;
  assign io_m_PWDATA = pwdata;
  assign io_m_PWRITE = pwrite;
  assign io_m_PSEL = psel;
  assign io_m_PENABLE = penable;
  assign io_s_PREADY = pready;
  assign io_s_PRDATA = prdata;
  assign io_s_PSLVERROR = pslverr;
  assign when_Apb3RegSlice_l48 = ((((! psel) && (! pready)) && io_s_PSEL[0]) && (! io_s_PENABLE));
  assign when_Apb3RegSlice_l55 = (psel && (! penable));
  assign when_Apb3RegSlice_l59 = ((psel && penable) && io_m_PREADY);
  always @(posedge clk) begin
    if(!resetn) begin
      prdata <= 32'h0;
      pslverr <= 1'b0;
      psel <= 1'b0;
      penable <= 1'b0;
      pready <= 1'b0;
    end else begin
      pready <= 1'b0;
      if(when_Apb3RegSlice_l48) begin
        psel <= 1'b1;
      end
      if(when_Apb3RegSlice_l55) begin
        penable <= 1'b1;
      end
      if(when_Apb3RegSlice_l59) begin
        psel <= 1'b0;
        penable <= 1'b0;
        pready <= 1'b1;
        prdata <= io_m_PRDATA;
        pslverr <= io_m_PSLVERROR;
      end
    end
  end

  always @(posedge clk) begin
    if(when_Apb3RegSlice_l48) begin
      paddr <= io_s_PADDR;
      pwdata <= io_s_PWDATA;
      pwrite <= io_s_PWRITE;
    end
  end


endmodule

module Axi4ToApbXbar_StreamFifoLowLatency (
  input  wire          io_push_valid,
  output wire          io_push_ready,
  input  wire [0:0]    io_push_payload,
  output wire          io_pop_valid,
  input  wire          io_pop_ready,
  output wire [0:0]    io_pop_payload,
  input  wire          io_flush,
  output wire [2:0]    io_occupancy,
  output wire [2:0]    io_availability,
  input  wire          clk,
  input  wire          resetn
);

  wire                fifo_io_push_ready;
  wire                fifo_io_pop_valid;
  wire       [0:0]    fifo_io_pop_payload;
  wire       [2:0]    fifo_io_occupancy;
  wire       [2:0]    fifo_io_availability;

  Axi4ToApbXbar_StreamFifo fifo (
    .io_push_valid   (io_push_valid            ), //i
    .io_push_ready   (fifo_io_push_ready       ), //o
    .io_push_payload (io_push_payload          ), //i
    .io_pop_valid    (fifo_io_pop_valid        ), //o
    .io_pop_ready    (io_pop_ready             ), //i
    .io_pop_payload  (fifo_io_pop_payload      ), //o
    .io_flush        (io_flush                 ), //i
    .io_occupancy    (fifo_io_occupancy[2:0]   ), //o
    .io_availability (fifo_io_availability[2:0]), //o
    .clk             (clk                      ), //i
    .resetn          (resetn                   )  //i
  );
  assign io_push_ready = fifo_io_push_ready;
  assign io_pop_valid = fifo_io_pop_valid;
  assign io_pop_payload = fifo_io_pop_payload;
  assign io_occupancy = fifo_io_occupancy;
  assign io_availability = fifo_io_availability;

endmodule

module Axi4ToApbXbar_StreamArbiter (
  input  wire          io_inputs_0_valid,
  output wire          io_inputs_0_ready,
  input  wire [11:0]   io_inputs_0_payload_addr,
  input  wire [3:0]    io_inputs_0_payload_id,
  input  wire [7:0]    io_inputs_0_payload_len,
  input  wire [2:0]    io_inputs_0_payload_size,
  input  wire [1:0]    io_inputs_0_payload_burst,
  input  wire          io_inputs_0_payload_write,
  input  wire          io_inputs_1_valid,
  output wire          io_inputs_1_ready,
  input  wire [11:0]   io_inputs_1_payload_addr,
  input  wire [3:0]    io_inputs_1_payload_id,
  input  wire [7:0]    io_inputs_1_payload_len,
  input  wire [2:0]    io_inputs_1_payload_size,
  input  wire [1:0]    io_inputs_1_payload_burst,
  input  wire          io_inputs_1_payload_write,
  output wire          io_output_valid,
  input  wire          io_output_ready,
  output wire [11:0]   io_output_payload_addr,
  output wire [3:0]    io_output_payload_id,
  output wire [7:0]    io_output_payload_len,
  output wire [2:0]    io_output_payload_size,
  output wire [1:0]    io_output_payload_burst,
  output wire          io_output_payload_write,
  output wire [0:0]    io_chosen,
  output wire [1:0]    io_chosenOH,
  input  wire          clk,
  input  wire          resetn
);

  wire       [3:0]    _zz__zz_maskProposal_0_2;
  wire       [3:0]    _zz__zz_maskProposal_0_2_1;
  wire       [1:0]    _zz__zz_maskProposal_0_2_2;
  reg                 locked;
  wire                maskProposal_0;
  wire                maskProposal_1;
  reg                 maskLocked_0;
  reg                 maskLocked_1;
  wire                maskRouted_0;
  wire                maskRouted_1;
  wire       [1:0]    _zz_maskProposal_0;
  wire       [3:0]    _zz_maskProposal_0_1;
  wire       [3:0]    _zz_maskProposal_0_2;
  wire       [1:0]    _zz_maskProposal_0_3;
  wire                io_output_fire;
  wire                _zz_io_chosen;

  assign _zz__zz_maskProposal_0_2 = (_zz_maskProposal_0_1 - _zz__zz_maskProposal_0_2_1);
  assign _zz__zz_maskProposal_0_2_2 = {maskLocked_0,maskLocked_1};
  assign _zz__zz_maskProposal_0_2_1 = {2'd0, _zz__zz_maskProposal_0_2_2};
  assign maskRouted_0 = (locked ? maskLocked_0 : maskProposal_0);
  assign maskRouted_1 = (locked ? maskLocked_1 : maskProposal_1);
  assign _zz_maskProposal_0 = {io_inputs_1_valid,io_inputs_0_valid};
  assign _zz_maskProposal_0_1 = {_zz_maskProposal_0,_zz_maskProposal_0};
  assign _zz_maskProposal_0_2 = (_zz_maskProposal_0_1 & (~ _zz__zz_maskProposal_0_2));
  assign _zz_maskProposal_0_3 = (_zz_maskProposal_0_2[3 : 2] | _zz_maskProposal_0_2[1 : 0]);
  assign maskProposal_0 = _zz_maskProposal_0_3[0];
  assign maskProposal_1 = _zz_maskProposal_0_3[1];
  assign io_output_fire = (io_output_valid && io_output_ready);
  assign io_output_valid = ((io_inputs_0_valid && maskRouted_0) || (io_inputs_1_valid && maskRouted_1));
  assign io_output_payload_addr = (maskRouted_0 ? io_inputs_0_payload_addr : io_inputs_1_payload_addr);
  assign io_output_payload_id = (maskRouted_0 ? io_inputs_0_payload_id : io_inputs_1_payload_id);
  assign io_output_payload_len = (maskRouted_0 ? io_inputs_0_payload_len : io_inputs_1_payload_len);
  assign io_output_payload_size = (maskRouted_0 ? io_inputs_0_payload_size : io_inputs_1_payload_size);
  assign io_output_payload_burst = (maskRouted_0 ? io_inputs_0_payload_burst : io_inputs_1_payload_burst);
  assign io_output_payload_write = (maskRouted_0 ? io_inputs_0_payload_write : io_inputs_1_payload_write);
  assign io_inputs_0_ready = ((1'b0 || maskRouted_0) && io_output_ready);
  assign io_inputs_1_ready = ((1'b0 || maskRouted_1) && io_output_ready);
  assign io_chosenOH = {maskRouted_1,maskRouted_0};
  assign _zz_io_chosen = io_chosenOH[1];
  assign io_chosen = _zz_io_chosen;
  always @(posedge clk) begin
    if(!resetn) begin
      locked <= 1'b0;
      maskLocked_0 <= 1'b0;
      maskLocked_1 <= 1'b1;
    end else begin
      if(io_output_valid) begin
        maskLocked_0 <= maskRouted_0;
        maskLocked_1 <= maskRouted_1;
      end
      if(io_output_valid) begin
        locked <= 1'b1;
      end
      if(io_output_fire) begin
        locked <= 1'b0;
      end
    end
  end


endmodule

module Axi4ToApbXbar_StreamFifo (
  input  wire          io_push_valid,
  output wire          io_push_ready,
  input  wire [0:0]    io_push_payload,
  output reg           io_pop_valid,
  input  wire          io_pop_ready,
  output reg  [0:0]    io_pop_payload,
  input  wire          io_flush,
  output wire [2:0]    io_occupancy,
  output wire [2:0]    io_availability,
  input  wire          clk,
  input  wire          resetn
);

  wire       [0:0]    logic_ram_spinal_port1;
  wire       [0:0]    _zz_logic_ram_port;
  reg                 _zz_1;
  reg                 logic_ptr_doPush;
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
  wire       [0:0]    logic_push_onRam_write_payload_data;
  wire                logic_pop_addressGen_valid;
  wire                logic_pop_addressGen_ready;
  wire       [1:0]    logic_pop_addressGen_payload;
  wire                logic_pop_addressGen_fire;
  wire       [0:0]    logic_pop_async_readed;
  wire                logic_pop_addressGen_translated_valid;
  wire                logic_pop_addressGen_translated_ready;
  wire       [0:0]    logic_pop_addressGen_translated_payload;
  (* ram_style = "distributed" *) reg [0:0] logic_ram [0:3];

  assign _zz_logic_ram_port = logic_push_onRam_write_payload_data;
  always @(posedge clk) begin
    if(_zz_1) begin
      logic_ram[logic_push_onRam_write_payload_address] <= _zz_logic_ram_port;
    end
  end

  assign logic_ram_spinal_port1 = logic_ram[logic_pop_addressGen_payload];
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
  always @(*) begin
    logic_ptr_doPush = io_push_fire;
    if(logic_ptr_empty) begin
      if(io_pop_ready) begin
        logic_ptr_doPush = 1'b0;
      end
    end
  end

  assign logic_push_onRam_write_valid = io_push_fire;
  assign logic_push_onRam_write_payload_address = logic_ptr_push[1:0];
  assign logic_push_onRam_write_payload_data = io_push_payload;
  assign logic_pop_addressGen_valid = (! logic_ptr_empty);
  assign logic_pop_addressGen_payload = logic_ptr_pop[1:0];
  assign logic_pop_addressGen_fire = (logic_pop_addressGen_valid && logic_pop_addressGen_ready);
  assign logic_ptr_doPop = logic_pop_addressGen_fire;
  assign logic_pop_async_readed = logic_ram_spinal_port1;
  assign logic_pop_addressGen_translated_valid = logic_pop_addressGen_valid;
  assign logic_pop_addressGen_ready = logic_pop_addressGen_translated_ready;
  assign logic_pop_addressGen_translated_payload = logic_pop_async_readed;
  always @(*) begin
    io_pop_valid = logic_pop_addressGen_translated_valid;
    if(logic_ptr_empty) begin
      io_pop_valid = io_push_valid;
    end
  end

  assign logic_pop_addressGen_translated_ready = io_pop_ready;
  always @(*) begin
    io_pop_payload = logic_pop_addressGen_translated_payload;
    if(logic_ptr_empty) begin
      io_pop_payload = io_push_payload;
    end
  end

  assign logic_ptr_popOnIo = logic_ptr_pop;
  assign io_occupancy = logic_ptr_occupancy;
  assign io_availability = (3'b100 - logic_ptr_occupancy);
  always @(posedge clk) begin
    if(!resetn) begin
      logic_ptr_push <= 3'b000;
      logic_ptr_pop <= 3'b000;
      logic_ptr_wentUp <= 1'b0;
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
    end
  end


endmodule
