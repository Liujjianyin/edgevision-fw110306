`timescale 1ns / 1ps


module dvi_decoder (
  input  wire         pclk,           // regenerated pixel clock
  input  wire [9:0]   bdata,		// Blue data in
  input  wire [9:0]   gdata,		// Green data in
  input  wire [9:0]   rdata,		// Red data in
  input  wire         rst_n,        // external reset input, e.g. reset button
  // output reg          reset,          // rx reset
  output reg         hsync,          // hsync data
  output reg         vsync,          // vsync data
  output reg         de,             // data enable  
  output reg [7:0]   red,      // pixel data out
  output reg [7:0]   green,    // pixel data out
  output reg [7:0]   blue,      // pixel data out  

  output wire         DLY_INC,
  output wire         DLY_RST,
  output wire         DLY_ENA,

  output wire [23:0]  audio_L ,
  output wire [23:0]  audio_R ,
  output wire         audio_valid ,
  output wire         audio_param_valid ,
  output wire         audio_max_word_length,     
  output wire [2:0]   audio_stae,          
  output wire [3:0]   audio_ch,            
  output wire [3:0]   audio_samp_freq,     
  output wire [2:0]   audio_samp_word_len,
  
output wire [1:0]      avi_infoframe_S   ,
output wire [1:0]      avi_infoframe_B   ,
output wire            avi_infoframe_A   ,
output wire [1:0]      avi_infoframe_Y   ,
output wire [3:0]      avi_infoframe_R   ,
output wire [1:0]      avi_infoframe_M   ,
output wire [1:0]      avi_infoframe_C   ,
output wire [1:0]      avi_infoframe_SC  ,
output wire [1:0]      avi_infoframe_Q   ,
output wire [2:0]      avi_infoframe_EC  ,
output wire            avi_infoframe_ITC ,
output wire [6:0]      avi_infoframe_VIC ,
output wire [3:0]      avi_infoframe_PR  ,
output wire [1:0]      avi_infoframe_CN  ,
output wire [1:0]      avi_infoframe_YQ  ,
output wire [15:0]     avi_infoframe_ETB ,
output wire [15:0]     avi_infoframe_SBB ,
output wire [15:0]     avi_infoframe_ELB ,
output wire [15:0]     avi_infoframe_SRB 
  
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
NCWrH8R6GCe4is1UguLubsRW8o2ppJsw4q1BSE4ZpjuD08Fst9cmrx+0TIx/JyXK
peEwccmwDzN99NtnjDNCV/L4YQeYOvv7FMUga5e5NuAqXFVlh2UlwDYgNyOaujBW
HTACjJbX28Y3ZwxpC+4BZq3TtnUrKZxuR+/1RV7YtcrFOdQdfe1uFqQw24HV0FXj
3jxqRUrV0ouE5S/cKGEdsXBN5XHOR5ab6PwG/Se64K0nYPPXRIEvfIbPeZzkbpwQ
dN2DYGR4F2IPKUhZKf97y0pffZQRlwb0w8i7svgW12g99SafYDp2Uy+kN8k3eGah
LGenbKtlzwT2qcgFCYd8tg==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
gLyaUERM2ZEEdSpXApe2Wb2VZaDeI5ruCDVy10lM7/gWLG7YkNuXnDSa46vn9Rnf
fXfxk2ruHwNghPnvtolEicXcHc6O1Yt4zCaRVLgjj09JYOzpq3SVxEaCT6lHMXO8
Vh/E+XZAt4TV6POEaqf9qDZDRnINPwBuuwhL9b8bB6U=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=8368)
`pragma protect data_block
8+WIXcxaTAynlJ/sOGcEBczNmNe6aUur6RcdsSJ8Jwtwa6YoxQqBwvHff3u+mP3s
s8fFHuw85mjEm53RMs+1iKbXMYPLtxZ/ieEHbzo+R1gtMFKIieP8J8Ji0RyWuiUe
QQ8JlKqTr9RGIKf7yD2LM/nkrrII+GnQ62Tp4z3VkzWy07Zkzsxvsvda0SRKVfIW
WfEpJucjoNbckaJlYht49KbAWSqbNVYEHWZ8USFIJ/490JMGYpHYlYHLBluRp0k0
DsaoqgVHbTR23QNJ7eeZUw31Sj/6S5aFagsaNNUCkZngjXPK7b/HKgdyJ7u+6stu
sWESDI6PeKeBNgW+wH+7Kk/arSsO6/KsjMZfMrAxg7A1hrOYmRErSbXl3rgiJ/Cl
bYqPysDeA4Hld00q/sWC6rdtGRZXyu5fMkD7Ng994ckUiOHUBKiUwl/gEFgVg1rH
1RtAx/glhqQzy+waYRrik9+ZV37ckOBIeWadhDiRtssJbo5mO5Z8tGlFX7mei6+S
dj1wWN4HHrnJQB+4s2IF/gZ2Y4NnnbKIjgTGf9045vz1e+KRx9gWbmNy3KvyAwbd
g4NhLLS1QTV8rJInUTYI1X4MOWJlvNWNV7HnMaE6bLixFS5SdRlxxJhWNYTpHoVO
26Bkg2p9LGdpKDPcASEYdPuULlmtbwD7Gcb4QgKfPNl85+LouyhlDie0hk0RM9tA
eik9Zv2grapigO3POksQfrQqLrWkblkWCn0G1r/LbOm0MqLZazSz5Kr8e1hDAUAS
wmZbxOjdGd/L2Z4zAM+AJPrwKI0BGX20FChG8qOjy/YBwizxr3fUXnMP7lVJkwS8
/JJiqMzklr+40obMYdMBJm75dTaPZw6mYAWrXfJICrZPsWPT00RtlxWEYwTDCzPh
T6oyO16H1ITu3FK3+E6fErWjofhpla4TsE8MaGfsYFFPkFjZMqaMdCevULyYp5W1
qJXzA+EyNfSHKcvtZHYfGKxjTYcI8xAFVgHILjC/L/M+IPzcPzAsO1HNINQnm3+/
rjSo7Ow++Mn+f7MhhGvgLEs2ioLmjF8cHuc8N2C69YbVx177oAF97zYMFh3q8i94
MN+qOz4M7E97XBQ327pnfZzHSym6e6Z7uD3RBF6QYo0oS8BSOBR9SO8CrtpJqsmr
JJiPUMOdfEIn7UQ4ZNh/dqVNX1etTXICmeRBi7ZYqLNjC4x3aKEWKVO2E5zuppSH
RDPe9evA3TuENKUOE/93Ca6bfbWI405Um8rDJOOQ1kC1dxjYg3AlMxF2UtOanoX9
8oP2LO20DZQdAnRuhdkVVJXTHOVi8+NPbAio04DklJ6PyzoSYWXCJlnCQgAeghL5
hDS0rW4IzGkUCysm4J1ho+QB1KUQV0jLgBe7ggkK8rdas3kv/YoLmNyItNBwu+15
j1/T/kL3xEZKAjmE6QYR54uU8BL5kqtwLkInRNJqy4k12qACrx71gKNKsQa9S5SC
bojwAujSDG5CEglHN3chjzx9vZRYGRyeMqUwfsWVVZEM+wMj7ttKGUiKGKlrH3Vw
SdB80tAIKvNq2Ez/ZtPsnWB1ofohFIyuC+uXMj2u1wodAulPvhjstLd8+49/IPh5
AqwKgTOZo5DZ+L5oK+RBhzHIogXP5yZyCWxikliup9R1q7Z4TL+DOoc3nO+IaPpP
mrgj387T5X6IoEVkdfO5t2+am9YU3LymewvDDhlzJE0+Q/Lz4ddpcniltg3rfB+z
24DfKZLOBXcPR5UumUc/mFcIVU2oKb0pgexhOcXnvsNUaE6/K1YUBT9DLNQKRCmK
SXQ/04YJfToPDe04yGf2ZbE3NPI90plyKB+NootbkkXvp8aPSAjlBj2qhDWCXivp
WGjPnF51DHAcTnMnB1UZnOFevcJqk7k2/YAOHOI6CKc9ZL/xq55C4xytF/SFXwOZ
f4N+FcNzSt7RWZmJqw+5mVumoM/6lPQdTzxZFG+kFIqNm1wbzG1iKKWoPsIxbIq4
3qwBirB2SaNwm5CvGhl2a98EL/jwzAZsDmMlnMQrkNbF5tT14TZbc63GMahUosO3
ZumUSVJYQTldU4pmWhbfO0q/NYl7m1ttWqWGq0LrG32QxlR8tuS5jJfkYtDbwoMW
CSCVSiko6Xqw4mmTWQQhoSQvYKpSllRX7DJyiWUgIK9GSrbGTZvU+P8JtzeZGAf/
QE+kUAdEh7AyDn6WjVYvQyJPAl93wWV/sDOHaVuDJ+lzWwKzYKzxK5r7F2Nx+al/
3iGpFYdtAaRllKXzmMGUgxpt/M4vGJsww5zsvJsuqF4mqQpVzzOdjc2mbKWQ06Im
AvACeurQ3pAMTfpYFrVExJh2Ns38Txnks6S3CRuhquCFILjOCPasUOiMOB1ZuZkf
dRkcKn6Z4eqzK0YA2vh/VL7jN05v5csf/lwKo48st/jtkRQVlUHq4KJpFQblypNN
7uW6hwTOsWFArfeqvFGf4HN3jG/Smivqgb0Z5zfmcq8aQJzmmX6tHvdmL9MROIRX
Gmqf1bFzEUDoK4PxRvo/dWRPu/jVa+YszjbW8EPgQJMpOce6so0gae3dMiZxL1vz
ggM7fNs6YG+LJntk50hqRTINYyiaHeVwr02O1Jer+hPyivLjjL4LYzXh3fTd7JCc
zTt/dVOFRtP2jdP+NMhGFZyXLzKBQIVwqOjuK5dmcTW3FBhjXjJMqQ0PF92dYPjV
dzVH7hZEPeRMsLq8F6RonupK3j0Els0a0b7CkiaMfC4mOrcIQs7EwkJ70ODbhfsd
UUCDzkUdvw1aIUyQ5QsDsHjB+SoNiQIXeY+lDsI3d7s2zKOn7OneaIsg2SIY3m3o
EIn/++rwARD2SgVmHUdpROsMbukDmydjC4u6VEocX15kg6lIvzr2r0Nk9vA1hfQy
2XEKsp8FMdw7mL1HynZfAWSyZz6Owpk//fVyZMUhbj3EQnXGdGqY4p1JuJKvY1ZX
aArTs8uuF0Pio4AgVkAcEMQ2lgmseiD9TpjgwXW2+Bg+PhEEk61FAwM9cJDZ1Phs
wBYPbZd04cTT4lHJTP0tMCE2hBuI2z5zdnPE2T01UxFjyqkmAwdxZnsDVYKPR4Bi
SGJHL0KjvQQMDDPXXcul9RruRDsSUS2kOnrGCPNdBquHTE1dX9Zs2yWsn/lJzWBd
rwVvMkhAahlJ4P32YgNLZSwVEi02qE7N7Y3iGoTm7ar6t2uWdMRTCWT7/GLPn4wf
6Vrbn4FSR4+LRGmNJnnQ3VXxmTQ7vjyKady8JG8Q6Q+A16dCzVLjsQkRqrT5G5Ip
UmBoc56XmGnZ8de7Tss3eKqSZudmnpPJXd/RsAqOsmWbJ7qTNr68yf5iorASo5db
egzxjM6JEoIxKWG6Sz5o35Vj3BucL5ATcGlAzX7WhEPIONkzfIXxC0qWFp4Uxc6n
M/ipECXV8E0m//nSLbuJ2CiHeosZFHKmueXk/4Y3yRELgmgbY1KURS+/cdIy6t8m
PQ8Vip22og5RBAKZb2idWuJaaHSANnMmwtgZj/D4ZQJJfZ7i3k41sJLfjZloGCMi
kfZDoSsUpORt/ySh72HEy4hPgNFmeNLTIQ2aqbBeGRDmfdIfmmNbgie6RAfLQQyN
Eo1uMDFYltEQT60sOInI+Dkft/SjDTCmQdQV7fdLZiv+54USF2eAlYs/iWQLGa8u
EUjopzg6AxUNFt4KrCtkbQK8XM91zm6J2OhhATc/GtPL8z19Tt6NmbE6+ChqBntA
LQ4p1sU11pujpnk9GWKMOG1ueeKGS4qZotaPhO3+ESDiYx3WQunnZhaU0mlOYFpu
vzLPP3TyM6cO26ipvXtaq4HNzfV1yxXUFoakVtibrZiz3/bNO3hboqvBg1GtMgdC
r5l6SUp7491izUPD5xJHgoaDRYm3w90/FUurlJ3eHiWAZ4ARLjFYLChcx3WOOjpT
dIQEF7pIDHpWFT96Tp/Buo6gNHPBt5Mu4U84L1KxqjeXoI5jfde5zLsNnoPDzBPI
Yw0Uiya7Imgniu5eZO+baMPRZ8GskadfzmiKYy9aiC2yHCtwKQuAiACaydnKMvYv
PuUYRW9qcb54m0B7f8gDP9pBuf7tLwEI+kuDWNvhl8NYeXw51Ch3S2ZO56Ol5z0k
HlbhLbREDmIZmz9ojVswqzve2AjepVJA5ErzAYhW7YiAD5QKBUfUNgU7Xgx9Dx1k
JkkC8tYTjbLbPo7Y/29FluJOWlaSpzSw4urVfKK+5E0okNhfuVVSbt7klV6/5oYT
vrsbVeGl1L68lSUmudxm9w8cyCW2OSD+wxJzncke/19dTBjuA5YIEgDsQVJxaSvC
jd9EqDiEndejoqIeYZR2lUIEoS8+eo2cRlbMpeaqA1ey+K+Nx6C78GKOOdKq2olx
+J5aTw3es0pUavxVzZEx1kL+3hw4HXwPAbLUmK2FDKRqyhT6QW9iQ3DU3CZ6tKFa
Rlm4Ub5ziuCEjc9wyR+NF2XVtSScYxZafL6M50P3d6RaMbTBEIdCu/uh+5u5yZzh
yyWesSOb/QjjnwrztbUboJYeYVdNB0XdTkEzz+6003ShO0VZ6Lp4BcD5RVVkgoS4
XyaHN9S4JaL5lpgbQU5y7nUM5tFhDxwK5wxCixhvfT39x9rQ7tLHQuYaYT9IaEXt
TGTisUTsUQGWcDWg1fNTW9cM/fimOzfjh06OB1MpTROq5miM1qVQ9k/gtVw+FXVj
qFEtBW9tOXTfFawBWUR7iY+n2WoDjxviNIZrK0UONn6dhVkgtuDX9HCj9MlggNad
3RScmqIp0Lu3F8ItGoQgswqpZtLbkxTEoU8LvFQN3s5hMvoE9qZkKemYh2e4ptyt
qcnp66cMkrNilDlogDDDB++IrMxrcFqOqg3DAUOCv5M1v7MJzEiB0vgfeIiIMCLh
+Kbtt+ohXnYNnfi9YOossR+AdFBQvMukbAJeM+SlqfjMYuPjNJlthgs+S7zYkTXg
46uA6ESMZON08WPA0BWlkffbdGVs9ey3Qis0kfR/PjlGgpsJ3PQ70EQ9/0ZhLNce
vK+VBSxB2RRrrOxywWiUp6ipeEOGorzWWtWGTCe/3W61nLa++auJ8lg5Ft7pCliJ
lPunE8y06AqZ13WI+p9yc83vmHGQu8iUrMFtXz7/8Twzqzhu3+qmY3nkBTdqD0Wj
ysOKbGEdlbkNjt8t/3oNom4aN4OYb8Ik7FgjLEGL/9ks28bhRcdxU3tvgIKzlUWw
NUi3WYWeel+HCtuzz222LJ0/h6rNLPmreX6qXIC4XQ4P/4tGXB8tyH/N8X6tClHX
UCpEjpkC30Wo0hsTfC8jwzQYH1mFIWLYSyG0Z/dbU9+ozrX/LKsBZMtbFi34pAFn
DUnOxqmGKJdHPCA6EmDqsOLrTG+s90QktmNggGTX9BgdaB8BXi1/WfpiMEOxi6Tt
qb5uCziGcHOwfMLCdllbDMEtH9muYcRMEdCQgXuWZn5b57QYlSnLeQLnMdwZXlpM
0PW4xUPQBVdMpLJUcS7rLUqQAqXLW/WaeEl8DCEfG1+776NYTkFyquV4NWueA0fn
6b1ykZIKw7mQ2FlmECGGCLOv7VLK3z71bkMO2xaT/V3qrHCxQDcfQutlp2DE628l
2Ao5zruOYE+svfWfp1l72HqfoX5vyvLupvJTDDwrLP0tyjcLyVtQREKn3RKKPVLB
BGYhSHSl2rslMAeVX8M2RfL7Rj7metKlnTnurVueTpr0Jcjj8i7vc78Hb9bdgfjO
GBQFzlFE2EZHm7ASzpm9UpiLuajtqMlwI2/LhI6VO3pUiwpYgqlS0chewYPuwgxd
kUINpExuDHD87X+KG9srNMm9vD08rLb/QDQ+rjP3FMvJAObqEsmLYtn/MMxZGL1j
DsvlCryQC9emIHudjx+qwHPpJLYv7xu6OhI6gdgw4YMAK/id9o68r4tv5O3oJgeX
vzVa2wsJphwgVNnFnWHL7jiiNAyiSCaJlQv7Mm9ETJ5hjGnHvPU6OpfJ7DO16NMo
q6L1lFtKkFt7QF9p9+abiUZHH7lMFbO4vMRFVNjRRhESJuLcp6+XEcHFvxLDOzjb
qsRw2Er4mnwpjEcLLryGE8fhBL4j530eWq6DaTP/yjKE3rqnQfpsaMNMvH4m9G/P
W2p5d2ZV/AccsTSGLFi6dvrBefk3DHHOYUpPqK8qQ066/IOO+ES1G97ajBmFOCyq
/fjbigtx/tFuxFe6H8jeDPdlChclwjthpv1Bgxi9/7v42hTf3ipKC2tn2uiDW+DJ
LG0pzOmc180fMcmyK1Ey3KqKqxAQ3CJh1UW/KfCm0kqEwOPXMRCGPGk/naGonqb7
kV2qAvTAdI+ebRp9wVl5AYuyeThrRYVbuBIcwImt8hBhe3NZVYx2vSLnBuaMZYCw
bhJ0glYZAHA54pS9ZjVbfuAuazABlNptOb/YV4Ess3v0jfMETCK2NXNvHzjHF7ok
UpK4Zucse/EYvl/xT+NUlw3PHIuiXZU4NKgocimSvWSfk2EcPbMAs5ZUlWgzd5ms
ojLMMbhnY5AomWGxWp58FukJuq24j4v3tXHOm8URM4eCnh83e0wqCjt9VvUwWWLL
KTNcv7EV/ndyxeRs6eqARSZMNCv2Yym7kVPC25FaQr3QQJGWZOXJTrUVzMbg66HV
TT77dlL5P4sFdVb/UwrrxYPXWmwweg7zhV+4LJW2KUGxOC1AFGPOT3BZ031EmzA4
l3gfBcMELoTtdmGRrAexMqtdPAXcsdNz0n2OoFdJ3MSy9LV79RGI46d0fsEOUZcB
RhOPu2oVqQGgQvOfHyaQ/QiRd2mwAAlZmApVasGYNxEZ1Xop165HSUL5+eNRLnsK
kURl18twlLYB6ljsRh5BccgTwHPbEmvxAchCbohWn39t1YGnocWgx53Rr6qKSYYX
dC4GSJHeViGgVdEXl3g/uc35ybPTYucaoYwX6OrAVRNploQjEBNnLvs5XrVuF3X9
eg0J9Zouydqc8HNdmEdpjqwHrnAcu/q3de0GetrFAEsq2VyZk64KIBByfbJyY4Re
Li8ztZNdImmwTDv1wbwe7p1o8Pj95DKqgVkJGxEb3ILVq7/A6P52Qxe8G23Cg1CC
eYDjAS/+aEMrlW18P1oD/IUVnHWBCzZAZX7vTTk1apt9u3dD+kB8rABcvDgJrgYG
MUXZ7wW/0M2pefQZy8QtABhTRyCNHUaaYXvgBfgYs7c7l1D96O5PnnNoa1Hybslv
PF3S3i297e2Y6uTHamZegknARHjMllF0JiaIAIPag+XzDmRPaxRjLjWnopsvqgQJ
YNmOivJsH3hzmXcNKiCH7A/u4plGn7mNOOJV3cUyZY29PCTQlsYFKYGCIQ9wNf1E
UcoEyQ6ynbuY83XC/wHykdD/txsChsKziFFyIg0SfSgP1b+ogHUzF14gRkZwUlH4
QT4O07M4NmZyBIL7z2tpV7X2gvev7QdgSdybE6zkDrPvhnZxrLEHHzsFmjxrGtGk
XvQn26uLcOZbjDxCXe1PljMfZ7S4Zhcx1t1QUEBOmMeGnu+lnfakTvprJRIpIMwH
FxfZJyAkZ/RDmTdhqXWyTrSTKQqMlPDMXoSMOcYwK1D78cQGcKsc0clid0ajYVMs
056DH+IH6zcTozqaf73qsD4wDBI61AjgLxARD+AMslbzbGZGiMVGp3o2zIyNTgXP
DzdF66cXyfW+/kw7YCngSU0Tr9iPDZ9HqUmzYEwxAua29cOquOf4jyNGx5CJ4y5l
8QLFRzlTe3kNlIaEEMKUxVL0ompP2mHju+7SDznklWE2G7PO03/K1Tfmx01/1bPC
D9J8rCBYJDd0P4F4+fyTufIcq6moM7iOkyyHmEB4ECWz9c/LIgJbAOdNl3o3KgH+
eBCh6TvotpEEwHdpcZnJcwLy86fvXTlFGEGlv98CH1UjymyzhywdYtVF8EgCBqqn
2c8RLwMZnRfNMwn/405XVXUZA2DBtRNxRq7dpSWbVwtHttviFvbYpAVfzchu36uO
PhwqEYgcdOGdIozrqtlC2kzEsxcv5zG/Pl6mXYj9T39hOCwLmNDHfpsoq6zNWmmJ
AVmbNE9k4CvUdKde4vc6RM92vdqPvmSye1UFk/s8HwBJpiF+wyTUscV6uWNrPQ+e
e2ydzrEXtqkRxih42MoSb0tfS/lCZY/ZgLrzUZemBx8latSiss01c135X4olC/fU
AFtX6Pkqdd2RhGIyORTH6UgT36EEyNwwaYCGvSLIPD/JGGIKgt0LUb609Q9I9QTc
tEMX7bJjJtrS6LGjZmTI5o1js3JC1s+miahEQz5aGlwFCBDlcKWVYbJP3HIJQEKb
SYoNi5k5L/NTl42FqF05FASCYN5f+iSIuZS2AzZg2q5bkO1BdCaXhAj4A+VvIBHA
IuFQOBLxi/H0zrEXd/lBiAltYgzLUYEl9VQow6TaFRdS6ZD1rvXWb0ABADO6FRzL
bHcYOxsBTJSPgs+fppw7h1IH8a8rwVexPsfSWoH6eh5dfvUteJjIcg6lCw6Fsb2O
e9pVj2/csbvPCEZUysGYvAWsjJdzYMO6DM/ekiydrAEJ65sw2rtrxkemtq5f4ETe
NtnY5AbO6wa5ftym4dLDq9VPRKYCCZdLSQl7OnW+vsyLSn6Eg0yUbJhIJbEUU2Ty
PdfazQjRlhDivFPGsP1Jwgxe5UlDWenecd51ziw8j9pJLCsT+8+bMsgaNU8Kq4eu
cmbVeVzeYnDJrz07bBCk2QLQUikjH1BEE7bFayD96HlVxLZH/91COuJdW/1DkxFp
yhHz9iAUKPQOZFgMjUJpdMVoklrp860Uw6W3mQkzHYzEkejFUa0Cnulx0uUnF5BO
AEGuoF4hMcnHciJG2gVq/zJO6ItEAMucAN+Ov46T9i/+iHBP720ofiFHMQG6ymEH
T2dXVFBVeAxZJ5emASjjOuaMqEW3DAPvesyZdCUXY/Mz+iS4E6+aNbtDyKrOHHPx
rQ7U6Z56YyMXkTVHnNtpUzFNJymuwIh4e/gYKYdMOVzPKd851YGRgFEAgm5QX0ub
je9KoZ7CCpSo2Z2v+eHQRUSEdKVQGIBxJVDyDLnAlPP+VMOqaf7Z8imT1bZ8qBIf
PZaTt/oUnZ1Hu/FGn0/2zUMzffLG44dmYwGDe4VaqvZwTKRK1hqpdhhMGZ1wurCX
2JSuq70uatw3iskGkAhPpMHPV6hYqLe5nwD0AwuIYdL2CPDmgGeaoRuFBJroXSX7
mgbWmEdB2t2572VMakusbJzXtGNYqEFZ1cM278JRBqxXFDz0RmlI/VJWSqQBj5YO
5DlvC/DesBXJ71t7OslqNM7Kasw/qiw3B8W38f7RQWBXvohW/WwfOyQrRxUk7olO
n1uV/F/EfvjiaZ7fp4OTOvQE5H7GENK1ZO9qEqF6Gx4SwnRK4s+NQ05WUI4BdEPr
5lc6xFnpBQA9MeWXXsVT627Zo6UWCuKm9ol+xri7RMM0Qm3JMQEGVrRqVP08CJr7
qUkkJfvybjMVy5CBKpKI0b22j3PV2BWJDN0L2qB8ZnXCZFlbNUO39dMT/0YkxXRd
4jrGCT02a8H818uMx2pyiR78mqlxFDwmLXDVJL1S0jcqqKUVUUnS9UtM2jF8cBr1
U1aFqOLNX++Z+MHNOb4uwQIOT6G3crXKJEOA8+mSi/zkDKY+PhbMqrZ/rPP/JdPZ
MTAKKsj3mu9T48qBOMoauaeQZbrTu736TTxvcnzPPaE76Hqj4HuudLsnQ3QS9A/U
3aRELrHANDyN9vKunKwu5/ShbPVV16Ojocoyv0CvmsOesRCt9Fs42eI1EV7ouo+q
tT5Gwl0O6mvLm7btpoku3Qnvcu2jOfMgLuaUxwkpELl4jc9r7JUwKur/h1VFfyMP
b0qd2TkW/c7QhWRGzvgDlVsXoh8Fs0M2qO/8pE0gaaVtaNtkYajuSbKTWXfGnytR
bLX4xJFAf/dryAb9zlNHX1giQY2uTJ3ufNBmc2Gd3ul5tUj9Tc/gYptREzwC3c3x
wWupQ28gsBoW9/q96bBzY+XY1DWhSm6yjMCUUaIAFZNbUUCj0TF+f7CHo3KNL7/U
gQY2m38rMIU5ZpNWmmV5TJszZQWnlqmo3lJHaiNDnkWQqij+9ppxWVRPtRTV0GZp
CwlBmHVFX9tes1QSHReFooMndB6nVepVg869lyjkqzjClPlIQ0lDEL4n0ruaNupg
QIGIy44z6pLChXVYBlZ2Mm2W6GY5jiXBlOmUsXKTgkphInwoxSdlZ1dzZ8Z/IuQ8
1LLkPHurrxmavfJ71bKBZd8gS2Y4uq/5DHLSl6z0X8mKx+WCMqXcAl33G21+LsV1
OC2NRE4iZos7ayymRT9a+iwAr4ZdvKhEf8S66xzPHFb3tEjxkCVufCVa17c1dzYp
n4LI0vTnqu3j4bmQGpyZvskG27ypmpNF+qmUtpZq8ysyFsfs6/y9OaxBdtR+28xw
ArtotceQ2J1yYhSWjYMQgpYS+pFqLOOajb2iJ0ZJQCYudNpCG5tCksEi2T5X8QRJ
FLYnk4huzMyWJjpC4d2NomvFQYhFbeifBpE8Mu8scQUdQL5tweHwCQW6NLoOqFlD
vnxTy1E02gRky11mauWxTg7HxvoVJhumSxFwvVJ6JF7vEx6kNB4zEnGoY9LH5ZAX
TPL7ifqh59Z2ovpUMpytXsT+5RiNtSJJpxWwWgkHgNzKCbVCxdJqMpgBR8AG6BiE
86thw8KNhabBseSKtJtiOGPGOJiRjURR1+7BRRPivPVz6dkREx2V+HxYR71OoJOL
aSWaC00M5wc1sUnIVnfpqDCeUAkwbfkmuz6CRUo2of91uCG0W9z1baUARPuvBHXP
fBkYHhMBAwV5xTvmG2yWhxRjyB/28esEFmPptrizScwG0Krjuvci9+y/SNYIlDhY
ZHaC50dVkmfpyK4cRTe8DhrKvbh3/mcFDssppcGM1vu9IoYhCoE3uiqES4IswDBQ
5L3WC1uxj395KQAk/JMjpQqQR2rwVfVjzuzopXGZ+ZblNlRDEK0sewuY5wGxGtLt
okjZyVu62tYXkpHx4nywCZCKXEC9o/9ec4I+rig5WTJ0lxsDHy/3jAoFEFAfo6Ky
VaNQ5p3Kr77EceECxitJKVikaXX+gSG0/yd4WoefIUDJ/XddFkKNAOvdAD9iFBYH
iPYYPg001tHbaVBUXhsWwcWbmA+A7HWj+ohPovBPMUBevZqiblU/dY+Vy0XaIbXH
v36vo54Sh0LGBuSJFdYo5g==
`pragma protect end_protected
