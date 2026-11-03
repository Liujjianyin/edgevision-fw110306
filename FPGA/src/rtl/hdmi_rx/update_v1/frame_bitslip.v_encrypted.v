

module frame_bitslip (
    input                   clk     ,
    input                   rst_n    ,
    input                   bitslip ,
    input           [9:0]   data_in ,
    output reg      [9:0]   data_out,
    output reg              align_fail
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
X2TJ1M9D3P+LarykLPKSPrIyubA8VC5uq+RNDl68Of4eUDX+IsFEssROmj3zWIJk
sbSEgU2qukMcXjeoKDynwYBzT44/dz+nU8dKIFkWgqtJX4nnSeCLV2FkBPK3kc6t
vzwJ3L24VV7L3TXtqRs77so852srv+n6+pr4ud5vKGxttfmP/qdGM+7yblYoP5KX
uIhe3hFutbJ1Q6hhA3QJSwJZJaZ497Rg0Bh2jHxG8mCPqPvSXAlb4FeSUZCnjVpg
Zf7gqt/dNp4O1B0HfUruMittmzbA7aiBfNAnrNpqSz7/YEMODJKI38BnX6hnwkwh
mUgZmWM1SCRuXXabDoyR/A==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
a13nVIh0Z1JMVZCYUiS74WxumjaFV/YudzUmVm6/BGgsmMgvMNJzhYuhZLKCxEp7
3mJCh9wtoEPSPnagaT3753K+M2tXNB1eD3Ynzo+AlTUNcC7LyXt302spHJiCUmC4
bJ3VKH8+vnvVOz6LBHjptzY2hr7cqD2W+HErsPOIUTk=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=2240)
`pragma protect data_block
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
`pragma protect end_protected
