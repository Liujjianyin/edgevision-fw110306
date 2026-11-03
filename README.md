# EdgeVision FW110306

易灵思 Ti60F225 FPGA 实时 HDMI 图像边缘检测系统。当前版本面向仿金饰品智能色差检测的前景提取前端，完成视频接入、流式预处理、边缘提取、DDR3 帧缓存、HDMI 显示和上位机控制。

> 当前工程的饰品完整前景掩膜和色差判定仍是后续工作。饮料 CNN 是独立扩展验证，不代表饰品识别成果。

## Features

- HDMI 1920×1080 输入与 1080p60fps 输出
- 3×3 中值滤波、5×5 二项式高斯滤波、Sobel
- Canny 分支采用方向 NMS、双阈值和四邻域单次局部连接
- RGB 与边缘结果对齐写入 DDR3
- 实时三缓冲、冻结/恢复、三个静态槽、26 帧录制和 5 fps 回放
- C# WinForms 上位机控制算法、阈值、中值、显示、识别和 DDR 功能
- 四类饮料加背景 Tiny32 INT8 CNN 扩展：乌苏啤酒、小可口可乐、小青柠、百事可乐

## Repository layout

```text
FPGA/       Efinity project, Verilog/SystemVerilog, constraints, firmware
PC/         WinForms source and the FW110306 desktop executable
Model/      training/quantization scripts and deployed/candidate weights
```

## FPGA build

Requires Efinity 2026.1 and a Ti60F225 tool installation. Open `FPGA/src/ti60f225_oob.xml` or run from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File FPGA/build.ps1 -EfinityHome C:/Efinity/2026.1 -Stage all
```

The build script only synthesizes and generates bit/hex files. It does not program a board. Programming is a separate hardware operation and is intentionally not included in the GitHub build.

## PC build

Requires the .NET Framework C# compiler on Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File PC/build_ui.ps1
```

The compiled UI uses USB-UART. Select the actual COM port in the application; no COM number is hard-coded in the source.

## Model

The current FPGA model is in `Model/runs/drink4_background_20261103/` and the FPGA-compatible HEX copies are in `FPGA/src/drink_cnn_weights.hex` and `FPGA/src/drink_cnn_bias.hex`. `drink4_demo_retake_20261103_final` is a retraining candidate and was not deployed to the board.

Training images, labels and local manifests are intentionally excluded. Copy the data into the layout described in `Model/data/README.md`, set the environment variables below, then run the scripts from `Model/scripts/` in an isolated environment:

```powershell
$env:EDGEVISION_BACKGROUND_DIR = 'D:/your-data/empty-cloth'
$env:EDGEVISION_RETAKE_DIR = 'D:/your-data/demo_retake_20261103'
python Model/scripts/train_drink4_background.py
python Model/scripts/train_drink4_demo_retake.py
```

The scripts write local results under `Model/runs/`. They do not program the FPGA.

## Verification baseline

The FW110306 source was built with Efinity 2026.1.132.5.14 for Ti60F225. The recorded post-route minimum slack was setup +0.401 ns and hold +0.026 ns. A fresh build from the compact release passed interface, map, pnr and pgm generation; see the local delivery verification report outside this repository.

## Hardware and licensing

Keep this repository **private** unless you have confirmed that you may redistribute the Efinix device files, encrypted vendor IP, board collateral and model data. The repository contains generated FPGA firmware and vendor-dependent source files. Add a license only after deciding which parts you own and may license.

## Version

Firmware baseline: `FW110306`

This repository is a cleaned source release. It excludes private photos, local paths, old MIPI/HDMI revisions, handoff records, simulation/debug outputs and build caches.
