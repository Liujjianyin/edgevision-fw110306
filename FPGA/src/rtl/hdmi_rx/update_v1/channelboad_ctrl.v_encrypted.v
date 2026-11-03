module channelboad_ctrl(
    input clk,
    input rst_n,
    input align,
    input sync1,
    input sync2,
    input sync3,
    output reg re_sync

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
CaQP6ir2VwcaRBfZXYScAmCnJvrSQ/MfFs+pWp3TxO5NA2w2D+/ap16B5EV47Z86
MjJG2WcUV/vfQqMQKAILVTBW9tbXvj9FB7wfEWrDlbAags/9xCHyXPryijSU5e9d
on5vNODz5zenZ3uhvtC72xG2mV++nXk3ZY7jfND5Pc/73EPUTVwlkv3mtXH0PMBo
1F87GilWC9IZmGxXH/7Y61p8qESw3h6olJsyEd6FyYAhKbnqirW2vjffXJsxlVEJ
+f8j+/pihf4DDFcp5XNkP/PEwerVhqwpAdrSUTDQrLrC6gL8X5KYM3To8yK4JEzz
MO4ZzjPnlRd2FWbZwDMpKQ==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
d6Qy2/ghAH+v9usjTVazCXdkZfoRp0hlWtKgJ0YZ0vVtsLza2oQrqUHMOUfutnkF
i1530ebnWkatr7YSeBsmS8p5mRRHc7mJq56XJlIHuMzLHyWQlVrgQwWmm3BMRbVN
ftZC0JYQl2lFV7QQBTHf0FJ+RY1gsp71fRjDBhMkQJw=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=1344)
`pragma protect data_block
agZFtouIiSYlUFcyFrFSCEFJTIwC41HLhQjsKE/ILO/z7yFOgqrcipp2ZZUGhx29
UISxOFH9TXbfFivH94xUNonYb7VBWGt8Y5BvDFkGQ8+kNWOPf/ixr5jFt242wvIQ
60OLiELIz0CvPw1t6XQEZHEOv1pxAOoBP/Rr7aRTBaOPSZ/rQNUfDaEluej8E/Xo
eoTc5wcVPn19gULM5y5ncbMWNC5h6m75J56X0v/gbEacywZ6urBuLVP41fU9vpD6
qsjpZc9vnrX4zT6VqLy//1qMIGkJMZOMu7Ojl/+TMMkJouy3WUO4EAIVowzDFphC
zjYd90iBU9M7/q6XaX3PsPz+eHlQG/3bNOQhLtVDv97NF8gBK/hmBtgdfnIvDEaK
c4tOAPTJ10BkXL1wE2FdmaKZH361GZCjSGeauG+wXeiuMBvPfktkFdOa6pI7Vj9H
oxRO2BJabS9enThGiNBzahtirADXgbB6RYjT5I3zO+WNZlYbxVTYjEdBdK11xZuf
TUEoY7jMa6NhT5f5Zg98uDiDgaj4CESIlb3dvQYxoIfqAUaYo34mxXyCQJNRH+KT
POcUI1T1RDEV5JSny2Mp8xV19QiK/GxqD0mDvgTu7BqTw8tpM/VUCPYMyahcUEXL
Qxdk3T8U61CG1+7To91qTDubKmgh+ciWCG13NqTd4odB+AfeNO+oaGl6Cma9WEp8
Sxre0bFZsSOLdLjPHAvK+fnL2fMqcjhPAr1KsuFIr9aHGK/EOgAHwIa84yaDB4c/
ApHH/Ymw+bOmE/7ZpTd7QoLjfXyF1Wvdj9C7KDbBIqYLa6YYhZpYYX2gRagdVreo
nhw4/geABPXJikIIT4/zwIuy5zpw23QYbwircIHuEujzV4ppZC/HbK1Z3rHZIr2n
rsFXm7iZ26MT5SWdnGV3qYEmdq7GNudq4PrYWSOmJZP9+qcp4vmWt4vAW2MRgAYU
5cjMshgvEEXwqJqzgqbA63XuTltWgVr6UnuYZJFu2Smk2fQj7r9U8nzAFJcoCyFA
nYA4DEigKTw4fCJO8qJJQjnfvUalDn2Rvlx5cteDLoMI3R2RaDHDu5rIF/0Uvrdm
QtmQsi2t1VEx5rfHigFrc7maelrhDDhYOH5GaIvBo/5myxT/GX5YF0l369y/YWi1
7s15cVeAtzECKXovPrWpqpk2n+L40iv7GD+MQM69fw9/QlHO6ceqRcoZq/+PfoUu
xKhMGzrovr0FEDFtw/fE0BYR5U869zywbhSoQnWJTVneEXUKqxMEg9UWXXz81VIT
L5EBYwevPrt2c1qTyDD1sPDhvwl0IGwtLwLUty/B/CTTdatjXmPmF5LTOu5NteYw
xhPTCOos+H5G8LcgHkudwb4nzlwgR8UhOyL5hqDy9B5mHuqOUf68SnCeSsP1wR8n
mnD2YBhmGdn4is6EykJr0JIksua/bBRqN9qFaiiBtXsfNoo35l1Andu+J3ZdKURj
XXwiGlDwsTQNCgkotKeFxP3A0f6Rj12Uc1qnsEc/0nUR6rxkQdx5ZH0fXPVY9KeO
M17MSjUqxMTUmPW7oLsarE9w0AGj8ohPv/vT5OmLSaO+TosLJr+puX5VVGnO5MI9
0RPz952AWT29j5NCOJ+NfT3xrwllJagKPxl3VSebeunEfHB5GQJOyEfFwP9GnydY
sjRdszrnhQpw1m0yzheeIdFqEw2BTI039FtYLXE+ywOzWfEzhkyBqMgxe/jLIqlI
pgl3fVp7aNtmuluf5uMeq4x7h1FC2brYC1I+oTwzp9EHMRIsRAyQZpfUluzzf7X2
`pragma protect end_protected

