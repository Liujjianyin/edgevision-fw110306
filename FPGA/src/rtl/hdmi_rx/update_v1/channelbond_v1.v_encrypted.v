`timescale 1ns / 1ps
//****************************************Copyright (c)***********************************//

//****************************************************************************************//

module channelbond (
  input  wire       clk,
  input  wire [9:0] i_data,
  // input  wire       sync_code,
  input  wire       pos_sync_code,
  input  wire       align_flag0,
  input  wire       other_ch0_rdy,
  input  wire       other_ch1_rdy,
  output reg        iamrdy,
  output wire       bond_rdy,
  output wire [9:0]  sdata
);

//Encryption begin
`pragma protect begin_protected
`pragma protect version=1
`pragma protect encrypt_agent="ipecrypt"
`pragma protect encrypt_agent_info="http://ipencrypter.com Version: 20.0.8"
`pragma protect author="author-a"
`pragma protect author_info="author-a-details"

`pragma protect key_keyowner="Efinix Inc."
`pragma protect key_keyname="EFX_K01"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=256)
`pragma protect key_block
mFpGOq14DbtlECRSmrahP7zMQZmQxBZ4Vl1ofsq1EahMcrMjDWYKfsHoY8wrvaBx
xklCStu/dVKkEUpjRvltMA4ejOewEZ28iKJtFvEjjiNeJIdnEc5nhskdCn9kUt/e
9qZSAOVrq2vWjYY/Ll/NNWM7eDE5IdWLUdyPW/HNahLAKrhQwwJYP8cS9W7IsNnU
xtD5R9l1uXkNZslDzimhLRB6Yow320dFAstvS2moT5JNARCUikMvQCjgKOEo3fjC
gv3ln9DqyEAwV0dKBHJxdDOqZ9wMoX4UrE3GhDUKLmkWzWcS5RjdnU+ysN4Sj1wf
S9ZwZPWd1iI6d0sNL2O33g==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
HUZIVpZEdIpGW10xvS7AbZUQdTs8aBHM0KkVp4VvZG9BVMZ1fybb5vsQZEgnXvpl
s8M/wdiEb7CsbOxO1B4/RvxpBj3Zbt+zl/5uk5tPSSsRMMvsDw15TTjZbiXJIQYM
lJ9SFEHqNNSnNZyUp/8XK4b59OtqQjpt96GlX5pU0Qg=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=2880)
`pragma protect data_block
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
`pragma protect end_protected
