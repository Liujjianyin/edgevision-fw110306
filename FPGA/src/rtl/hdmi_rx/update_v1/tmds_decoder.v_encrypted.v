`timescale 1ns / 1ps


module tmds_decoder (
    input              rst_n        ,   
    input              pixelclk    ,   //TMDS clock x1 (CLKDIV)
    input              ctrl_time   ,
    input   [9:0]      datain   	 ,   //TMDS data channel positive
    input   [1:0]      potherchrdy ,   //����2������ͬ������ź� 
    input              all_align   ,
    input             re_channelbond,
    input             re_algin_start,
    output             align_fail  ,
    output             pmerdy      ,   //����ͬ������ź� 
    output             paligned      ,   //����У׼����ź�
    output [9:0]       bond_data   ,
    output      wire    sync_code,
    output             pc0         ,   //�����ź�
    output             pc1         ,   //�����ź�
    output             pvde        ,   //������Чʹ��
    output   [7:0]     pdatain        //�����8bit��ɫ����

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
j6OfkAZsJktHLDVxI/1HA+0CSzXwEO50rp8j3jvvB3PVEe6Q2Y21LX6SxOOFNZ0z
w/q/gJ+3MrbMrQtSSBKZ6pWr3ipv/kH4Kprb4ylfZSNaL5HpoiGlTJIGDZBwNcTh
zU1563Y2KF5Wkq9W5Yhnk7TuQqfXTCpCsueHXvO0FfBoC2En6LfpF9j7jyaNmJgy
G5jBgt9ZMLzLT8wEwQHLvoO/uhm7AwTTPDOoXPQi7GqC7A1y2YdvvK2fmELA+J++
V9rbrzKGPG5AkwuvAcns0J5/Q2tL9Ne+8maNKT6N6RhYvFREUTj0uF63cypQESGN
M6sBZ5QFBzDtKM70PZeOCw==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
CxGAmyQSPDDQSJFiJZSy2EvPaBcDKzornm1A/73kIR1fuB30sXJne+NGGMzPZ5Hc
10FZEKQVuGeqfAgk38YhJC3SYFhn/OAcARuSE5nLBHYwW5LxWCDMZoAadRaX00fg
egj5uIlRNRz90mzyZ33bnNojk4AihFI8rpTXAD2kOiM=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=2288)
`pragma protect data_block
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
`pragma protect end_protected
