# Xilinx IP configuration for US+: floating-point units and the orchestrator DSP macro.

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

create_ip -name floating_point -vendor xilinx.com -library ip -version 7.1 -module_name xil_fp_recip
set_property -dict [list \
    CONFIG.Operation_Type {Reciprocal} \
    CONFIG.A_Precision_Type {Single} \
    CONFIG.C_A_Exponent_Width {8} \
    CONFIG.C_A_Fraction_Width {24} \
    CONFIG.Result_Precision_Type {Single} \
    CONFIG.C_Result_Exponent_Width {8} \
    CONFIG.C_Result_Fraction_Width {24} \
    CONFIG.C_Latency {29} \
    CONFIG.C_Mult_Usage {Full_Usage} \
    CONFIG.C_Rate {1} \
    CONFIG.Flow_Control {NonBlocking} \
    CONFIG.Has_ACLKEN {true} \
    CONFIG.Has_RESULT_TREADY {false}] [get_ips xil_fp_recip]

create_ip -name floating_point -vendor xilinx.com -library ip -version 7.1 -module_name xil_fp_to_fx14_10
set_property -dict [list \
    CONFIG.A_Precision_Type {Single} \
    CONFIG.C_A_Exponent_Width {8} \
    CONFIG.C_A_Fraction_Width {24} \
    CONFIG.C_Latency {6} \
    CONFIG.C_Mult_Usage {No_Usage} \
    CONFIG.C_Rate {1} \
    CONFIG.C_Result_Exponent_Width {14} \
    CONFIG.C_Result_Fraction_Width {10} \
    CONFIG.Flow_Control {NonBlocking} \
    CONFIG.Has_ACLKEN {true} \
    CONFIG.Has_RESULT_TREADY {false} \
    CONFIG.Operation_Type {Float_to_fixed} \
    CONFIG.Result_Precision_Type {Custom}] [get_ips xil_fp_to_fx14_10]

create_ip -name floating_point -vendor xilinx.com -library ip -version 7.1 -module_name xil_fx28_20_to_fp32
set_property -dict [list \
    CONFIG.A_Precision_Type {Custom} \
    CONFIG.C_A_Exponent_Width {28} \
    CONFIG.C_A_Fraction_Width {20} \
    CONFIG.C_Latency {7} \
    CONFIG.C_Mult_Usage {No_Usage} \
    CONFIG.C_Rate {1} \
    CONFIG.C_Result_Exponent_Width {8} \
    CONFIG.C_Result_Fraction_Width {24} \
    CONFIG.Flow_Control {NonBlocking} \
    CONFIG.Has_ACLKEN {true} \
    CONFIG.Has_RESULT_TREADY {false} \
    CONFIG.Operation_Type {Fixed_to_float} \
    CONFIG.Result_Precision_Type {Single}] [get_ips xil_fx28_20_to_fp32]

create_ip -name floating_point -vendor xilinx.com -library ip -version 7.1 -module_name xil_fp_to_fx5_13
set_property -dict [list \
    CONFIG.A_Precision_Type {Single} \
    CONFIG.C_A_Exponent_Width {8} \
    CONFIG.C_A_Fraction_Width {24} \
    CONFIG.C_Latency {6} \
    CONFIG.C_Mult_Usage {No_Usage} \
    CONFIG.C_Rate {1} \
    CONFIG.C_Result_Exponent_Width {5} \
    CONFIG.C_Result_Fraction_Width {13} \
    CONFIG.Flow_Control {NonBlocking} \
    CONFIG.Has_ACLKEN {true} \
    CONFIG.Has_RESULT_TREADY {false} \
    CONFIG.Operation_Type {Float_to_fixed} \
    CONFIG.Result_Precision_Type {Custom}] [get_ips xil_fp_to_fx5_13]

