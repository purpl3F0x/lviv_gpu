# ###################################
# ####       BLOCKING IPs        ####
# ###################################

# create_ip -name floating_point -vendor xilinx.com -library ip -version 7.1 -module_name xil_fp_add_blocking
# set_property -dict [list \
#   CONFIG.Add_Sub_Value {Add} \
#   CONFIG.Axi_Optimize_Goal {Performance} \
#   CONFIG.C_Latency {14} \
#   CONFIG.Has_ARESETn {true} \
# ] [get_ips xil_fp_add_blocking]


# create_ip -name floating_point -vendor xilinx.com -library ip -version 7.1 -module_name xil_fp_mul_blocking
# set_property -dict [list \
#   CONFIG.A_Precision_Type {Single} \
#   CONFIG.Axi_Optimize_Goal {Performance} \
#   CONFIG.C_A_Exponent_Width {8} \
#   CONFIG.C_A_Fraction_Width {24} \
#   CONFIG.C_Latency {9} \
#   CONFIG.C_Mult_Usage {Max_Usage} \
#   CONFIG.C_Rate {1} \
#   CONFIG.C_Result_Exponent_Width {8} \
#   CONFIG.C_Result_Fraction_Width {24} \
#   CONFIG.Maximum_Latency {true} \
#   CONFIG.Has_ARESETn {true} \
#   CONFIG.Operation_Type {Multiply} \
#   CONFIG.Result_Precision_Type {Single} \
# ] [get_ips xil_fp_mul_blocking]


# create_ip -name floating_point -vendor xilinx.com -library ip -version 7.1 -module_name xil_fp_fma_blocking
# set_property -dict [list \
#   CONFIG.A_Precision_Type {Single} \
#   CONFIG.Add_Sub_Value {Add} \
#   CONFIG.Axi_Optimize_Goal {Performance} \
#   CONFIG.C_A_Exponent_Width {8} \
#   CONFIG.C_A_Fraction_Width {24} \
#   CONFIG.C_Latency {22} \
#   CONFIG.C_Mult_Usage {Full_Usage} \
#   CONFIG.C_Rate {1} \
#   CONFIG.C_Result_Exponent_Width {8} \
#   CONFIG.C_Result_Fraction_Width {24} \
#   CONFIG.Has_ARESETn {true} \
#   CONFIG.Operation_Type {FMA} \
#   CONFIG.Result_Precision_Type {Single} \
# ] [get_ips xil_fp_fma_blocking]

# create_ip -name floating_point -vendor xilinx.com -library ip -version 7.1 -module_name xil_fp_recip_blocking
# set_property -dict [list \
#   CONFIG.A_Precision_Type {Single} \
#   CONFIG.Axi_Optimize_Goal {Performance} \
#   CONFIG.C_A_Exponent_Width {8} \
#   CONFIG.C_A_Fraction_Width {24} \
#   CONFIG.C_Latency {32} \
#   CONFIG.C_Mult_Usage {Full_Usage} \
#   CONFIG.C_Rate {1} \
#   CONFIG.C_Result_Exponent_Width {8} \
#   CONFIG.C_Result_Fraction_Width {24} \
#   CONFIG.Has_ARESETn {true} \
#   CONFIG.Operation_Type {Reciprocal} \
#   CONFIG.Result_Precision_Type {Single} \
# ] [get_ips xil_fp_recip_blocking]


# Non-blocking IPs (Max Latency)

create_ip -name floating_point -vendor xilinx.com -library ip -version 7.1 -module_name xil_fp_add
set_property -dict [list \
  CONFIG.Add_Sub_Value {Add} \
  CONFIG.C_Latency {11} \
  CONFIG.Flow_Control {NonBlocking} \
  CONFIG.Has_ACLKEN {true} \
  CONFIG.Has_RESULT_TREADY {false}] [get_ips xil_fp_add]

create_ip -name floating_point -vendor xilinx.com -library ip -version 7.1 -module_name xil_fp_sub
set_property -dict [list \
  CONFIG.Add_Sub_Value {Subtract} \
  CONFIG.C_Latency {11} \
  CONFIG.Flow_Control {NonBlocking} \
  CONFIG.Has_ACLKEN {true} \
  CONFIG.Has_RESULT_TREADY {false}] [get_ips xil_fp_sub]

create_ip -name floating_point -vendor xilinx.com -library ip -version 7.1 -module_name xil_fp_mul
set_property -dict [list \
  CONFIG.A_Precision_Type {Single} \
  CONFIG.C_A_Exponent_Width {8} \
  CONFIG.C_A_Fraction_Width {24} \
  CONFIG.C_Latency {8} \
  CONFIG.C_Mult_Usage {Full_Usage} \
  CONFIG.C_Rate {1} \
  CONFIG.C_Result_Exponent_Width {8} \
  CONFIG.C_Result_Fraction_Width {24} \
  CONFIG.Flow_Control {NonBlocking} \
  CONFIG.Has_ACLKEN {true} \
  CONFIG.Has_RESULT_TREADY {false} \
  CONFIG.Operation_Type {Multiply} \
  CONFIG.Result_Precision_Type {Single}] [get_ips xil_fp_mul]

create_ip -name floating_point -vendor xilinx.com -library ip -version 7.1 -module_name xil_fp_fma
set_property -dict [list \
  CONFIG.A_Precision_Type {Single} \
  CONFIG.Add_Sub_Value {Add} \
  CONFIG.C_A_Exponent_Width {8} \
  CONFIG.C_A_Fraction_Width {24} \
  CONFIG.C_Latency {19} \
  CONFIG.C_Mult_Usage {Full_Usage} \
  CONFIG.C_Rate {1} \
  CONFIG.C_Result_Exponent_Width {8} \
  CONFIG.C_Result_Fraction_Width {24} \
  CONFIG.Flow_Control {NonBlocking} \
  CONFIG.Has_ACLKEN {true} \
  CONFIG.Has_RESULT_TREADY {false} \
  CONFIG.Operation_Type {FMA} \
  CONFIG.Result_Precision_Type {Single} \
] [get_ips xil_fp_fma]