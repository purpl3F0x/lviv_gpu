# Fragment Shader Pipeline Architecture

Here is the detailed visual representation of the datapath. It includes the exact RTL register names (in parentheses), explicit bit widths for each bus, constant inputs, and explicitly defines the routing conditions inside every MUX.

```mermaid
flowchart TD
    %% Inputs
    PIX["pixel_color [32b]"]
    TEX["texture_color [32b]"]
    ENV["env_color [32b]"]
    OP["op"]
    ZERO["Constant 8'd0"]

    %% Stage 1 Adders
    ADD_SAT(("+ (Clamp)"))
    PIX -- "8b (PIX.rgb)" --> ADD_SAT
    TEX -- "8b (TEX.rgb)" --> ADD_SAT
    ADD_SAT -- "8b (add_s1)" --> FINAL_MUX

    %% Stage 1 Muxes
    MUX_M1[\ "m1_b MUX<br>DECAL: 255-TEX.a<br>BLEND: 255-TEX.rgb" /]
    TEX -- "8b" --> MUX_M1
    OP -. "select" .-> MUX_M1

    MUX_M2A[\ "m2_a MUX<br>DECAL: TEX.rgb<br>BLEND: ENV.rgb" /]
    TEX -- "8b" --> MUX_M2A
    ENV -- "8b" --> MUX_M2A
    ZERO -- "8b" --> MUX_M2A
    OP -. "select" .-> MUX_M2A

    MUX_M2B[\ "m2_b MUX<br>DECAL: TEX.a<br>BLEND: TEX.rgb" /]
    TEX -- "8b" --> MUX_M2B
    ZERO -- "8b" --> MUX_M2B
    OP -. "select" .-> MUX_M2B

    %% Stage 2 Multipliers
    MULT_M1((×))
    MULT_M2((×))
    MULT_A((×))

    PIX -- "8b (m1_a)" --> MULT_M1
    MUX_M1 -- "8b (m1_b)" --> MULT_M1
    
    MUX_M2A -- "8b (m2_a)" --> MULT_M2
    MUX_M2B -- "8b (m2_b)" --> MULT_M2
    
    PIX -- "8b (PIX.a)" --> MULT_A
    TEX -- "8b (TEX.a)" --> MULT_A

    %% Stage 3 Adders
    ADD16((+))
    MULT_M1 -- "16b (prod1)" --> ADD16
    MULT_M2 -- "16b (prod2)" --> ADD16

    %% Stage 4 Shifters
    SHIFT_RGB["+128 & >> 8<br>(Round)"]
    SHIFT_A["+128 & >> 8<br>(Round)"]
    ADD16 -- "17b (sum_rgb)" --> SHIFT_RGB
    MULT_A -- "16b (prod_a)" --> SHIFT_A

    %% Stage 5 Mux
    FINAL_MUX[\ "fragment_color MUX<br>REPLACE: Ct<br>MODULATE: div_a, div_rgb<br>DECAL: Cf_a, div_rgb<br>BLEND: div_a, div_rgb<br>ADD: div_a, add_s1" /]
    SHIFT_RGB -- "8b (div_rgb)" --> FINAL_MUX
    SHIFT_A -- "8b (div_a)" --> FINAL_MUX
    
    PIX -. "8b (Cf_a)" .-> FINAL_MUX
    TEX -. "32b (Ct)" .-> FINAL_MUX
    OP -. "select" .-> FINAL_MUX

    OUT["fragment_color [32b]"]
    FINAL_MUX -- "32b" --> OUT
```
