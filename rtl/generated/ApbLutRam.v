// Generator : SpinalHDL v1.12.3    git head : 591e64062329e5e2e2b81f4d52422948053edb97
// Component : ApbLutRam
// Git hash  : 0867eb45c9a7627edf7c710aa90817a6ac31f5e6

`timescale 1ns/1ps

module ApbLutRam (
  input  wire [9:0]    s_apb_PADDR,
  input  wire [0:0]    s_apb_PSEL,
  input  wire          s_apb_PENABLE,
  output wire          s_apb_PREADY,
  input  wire          s_apb_PWRITE,
  input  wire [31:0]   s_apb_PWDATA,
  output wire [31:0]   s_apb_PRDATA,
  output wire          s_apb_PSLVERROR,
  input  wire [6:0]    lut_0_data_addr,
  output wire [31:0]   lut_0_base,
  output wire [3:0]    lut_0_size,
  input  wire [6:0]    lut_1_data_addr,
  output wire [31:0]   lut_1_base,
  output wire [3:0]    lut_1_size,
  input  wire [6:0]    lut_2_data_addr,
  output wire [31:0]   lut_2_base,
  output wire [3:0]    lut_2_size,
  input  wire [6:0]    lut_3_data_addr,
  output wire [31:0]   lut_3_base,
  output wire [3:0]    lut_3_size,
  input  wire          resetn,
  input  wire          clk
);

  wire       [31:0]   baseRams_0_spinal_port1;
  wire       [31:0]   baseRams_0_spinal_port2;
  wire       [31:0]   baseRams_1_spinal_port1;
  wire       [31:0]   baseRams_2_spinal_port1;
  wire       [31:0]   baseRams_3_spinal_port1;
  wire       [3:0]    sizeRams_0_spinal_port1;
  wire       [3:0]    sizeRams_0_spinal_port2;
  wire       [3:0]    sizeRams_1_spinal_port1;
  wire       [3:0]    sizeRams_2_spinal_port1;
  wire       [3:0]    sizeRams_3_spinal_port1;
  wire       [7:0]    _zz_apbWordAddr;
  wire                _zz_baseRams_0_port;
  wire       [3:0]    _zz_sizeRams_0_port;
  wire                _zz_sizeRams_0_port_1;
  wire                _zz_baseRams_1_port;
  wire       [3:0]    _zz_sizeRams_1_port;
  wire                _zz_sizeRams_1_port_1;
  wire                _zz_baseRams_2_port;
  wire       [3:0]    _zz_sizeRams_2_port;
  wire                _zz_sizeRams_2_port_1;
  wire                _zz_baseRams_3_port;
  wire       [3:0]    _zz_sizeRams_3_port;
  wire                _zz_sizeRams_3_port_1;
  wire                baseHit;
  wire                sizeHit;
  wire       [6:0]    apbWordAddr;
  wire                apbWrite;
  wire       [31:0]   baseReadData;
  wire       [31:0]   sizeReadData;
  wire       [31:0]   apbReadData;
  (* ram_style = "distributed" *) reg [31:0] baseRams_0 [0:127];
  (* ram_style = "distributed" *) reg [31:0] baseRams_1 [0:127];
  (* ram_style = "distributed" *) reg [31:0] baseRams_2 [0:127];
  (* ram_style = "distributed" *) reg [31:0] baseRams_3 [0:127];
  (* ram_style = "distributed" *) reg [3:0] sizeRams_0 [0:127];
  (* ram_style = "distributed" *) reg [3:0] sizeRams_1 [0:127];
  (* ram_style = "distributed" *) reg [3:0] sizeRams_2 [0:127];
  (* ram_style = "distributed" *) reg [3:0] sizeRams_3 [0:127];

  assign _zz_apbWordAddr = (s_apb_PADDR >>> 2'd2);
  assign _zz_baseRams_0_port = (apbWrite && baseHit);
  assign _zz_baseRams_1_port = (apbWrite && baseHit);
  assign _zz_baseRams_2_port = (apbWrite && baseHit);
  assign _zz_baseRams_3_port = (apbWrite && baseHit);
  assign _zz_sizeRams_0_port = s_apb_PWDATA[3 : 0];
  assign _zz_sizeRams_0_port_1 = (apbWrite && sizeHit);
  assign _zz_sizeRams_1_port = s_apb_PWDATA[3 : 0];
  assign _zz_sizeRams_1_port_1 = (apbWrite && sizeHit);
  assign _zz_sizeRams_2_port = s_apb_PWDATA[3 : 0];
  assign _zz_sizeRams_2_port_1 = (apbWrite && sizeHit);
  assign _zz_sizeRams_3_port = s_apb_PWDATA[3 : 0];
  assign _zz_sizeRams_3_port_1 = (apbWrite && sizeHit);
  always @(posedge clk) begin
    if(_zz_baseRams_0_port) begin
      baseRams_0[apbWordAddr] <= s_apb_PWDATA;
    end
  end

  assign baseRams_0_spinal_port1 = baseRams_0[lut_0_data_addr];
  assign baseRams_0_spinal_port2 = baseRams_0[apbWordAddr];
  always @(posedge clk) begin
    if(_zz_baseRams_1_port) begin
      baseRams_1[apbWordAddr] <= s_apb_PWDATA;
    end
  end

  assign baseRams_1_spinal_port1 = baseRams_1[lut_1_data_addr];
  always @(posedge clk) begin
    if(_zz_baseRams_2_port) begin
      baseRams_2[apbWordAddr] <= s_apb_PWDATA;
    end
  end

  assign baseRams_2_spinal_port1 = baseRams_2[lut_2_data_addr];
  always @(posedge clk) begin
    if(_zz_baseRams_3_port) begin
      baseRams_3[apbWordAddr] <= s_apb_PWDATA;
    end
  end

  assign baseRams_3_spinal_port1 = baseRams_3[lut_3_data_addr];
  always @(posedge clk) begin
    if(_zz_sizeRams_0_port_1) begin
      sizeRams_0[apbWordAddr] <= _zz_sizeRams_0_port;
    end
  end

  assign sizeRams_0_spinal_port1 = sizeRams_0[lut_0_data_addr];
  assign sizeRams_0_spinal_port2 = sizeRams_0[apbWordAddr];
  always @(posedge clk) begin
    if(_zz_sizeRams_1_port_1) begin
      sizeRams_1[apbWordAddr] <= _zz_sizeRams_1_port;
    end
  end

  assign sizeRams_1_spinal_port1 = sizeRams_1[lut_1_data_addr];
  always @(posedge clk) begin
    if(_zz_sizeRams_2_port_1) begin
      sizeRams_2[apbWordAddr] <= _zz_sizeRams_2_port;
    end
  end

  assign sizeRams_2_spinal_port1 = sizeRams_2[lut_2_data_addr];
  always @(posedge clk) begin
    if(_zz_sizeRams_3_port_1) begin
      sizeRams_3[apbWordAddr] <= _zz_sizeRams_3_port;
    end
  end

  assign sizeRams_3_spinal_port1 = sizeRams_3[lut_3_data_addr];
  assign baseHit = ((s_apb_PADDR & (~ 10'h1ff)) == 10'h0);
  assign sizeHit = ((s_apb_PADDR & (~ 10'h1ff)) == 10'h200);
  assign apbWordAddr = _zz_apbWordAddr[6:0];
  assign apbWrite = (((s_apb_PSEL[0] && s_apb_PENABLE) && s_apb_PWRITE) && (! (! resetn)));
  assign lut_0_base = baseRams_0_spinal_port1;
  assign lut_0_size = sizeRams_0_spinal_port1;
  assign lut_1_base = baseRams_1_spinal_port1;
  assign lut_1_size = sizeRams_1_spinal_port1;
  assign lut_2_base = baseRams_2_spinal_port1;
  assign lut_2_size = sizeRams_2_spinal_port1;
  assign lut_3_base = baseRams_3_spinal_port1;
  assign lut_3_size = sizeRams_3_spinal_port1;
  assign baseReadData = baseRams_0_spinal_port2;
  assign sizeReadData = {28'd0, sizeRams_0_spinal_port2};
  assign apbReadData = (baseHit ? baseReadData : sizeReadData);
  assign s_apb_PREADY = 1'b1;
  assign s_apb_PSLVERROR = 1'b0;
  assign s_apb_PRDATA = apbReadData;

endmodule
