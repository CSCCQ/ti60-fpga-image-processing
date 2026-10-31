# 工程使用说明

我使用的开发环境是 Efinity 2026.1.132.3.9 和 Efinity RISC-V IDE 2026.1。工程中已经包含生成好的 IP、启动 ROM、数字模型，以及可以直接下载的位流和固件。

## 按键操作

| 操作 | 功能 |
|---|---|
| 长按 K1，约 1 秒 | 原图 → 中值滤波 → 中值 Sobel → 高斯滤波 → 高斯 Canny → 灰度/二值分屏 → 红边叠加 → 原图 |
| 中值 Sobel、高斯 Canny 模式长按 K2 | 开启或退出数字识别 |
| 红边叠加模式长按 K2 | 开启或退出图形识别 |
| 原图、中值滤波、高斯滤波、分屏模式长按 K2 | 不开启识别 |
| 单击 K1 / K2 | 阈值增加 / 减少 10；默认 200，范围 20～2040 |
| 实时模式双击 K1 | 冻结并保存一帧，再双击恢复；最多保存 10 帧，满后循环覆盖 |
| 三击 K1 | 进入或退出回放 |
| 回放模式双击 K1 / K2 | 向前 / 向后翻页 |

单击需要等待约半秒完成多击判定。回放中同样可以长按切换模式、开启识别和单击调整阈值。保存的帧放在 DDR 中，断电后清空。

左上角 FPS 统计 HDMI 输出帧数，因此冻结和回放时也会保持约 60；数字分类的处理速度需要单独测量。TH 是当前边缘检测阈值，右上角显示模式名称及冻结、回放状态。

## 目录结构

| 路径 | 内容 |
|---|---|
| `Ti60_Demo.xml`、`Ti60_Demo.peri.xml`、`Ti60_Demo.pt.sdc` | Efinity 工程、外设与引脚配置、时序约束 |
| `example_top.v`、`src/` | 摄像头、DDR、显示、滤波、边缘、识别和按键逻辑 |
| `ip/` | IP 源文件、参数、启动 ROM 和 DDR 初始化文件 |
| `embedded_sw/SapphireSoc32/` | RV32 BSP、驱动、TinyML 库和应用程序 |
| `ml/digits/` | 数据生成、训练、量化、导出脚本、模型和打印样张 |
| `release/fpga/` | 位流、Flash 配置文件及资源、时序报告 |
| `release/firmware/` | 数字识别固件 ELF、BIN、Intel HEX |
| `release/boot/` | Flash 固件镜像和引导程序 |
| `tools/` | 编译、文件校验、下载和固化脚本 |
| `docs/` | 算法说明、部署方法和测试记录 |

## 打开与编译

使用 Efinity 打开 `Ti60_Demo.xml`。现有 IP 和 ROM 已与位流配套，直接查看和编译工程时无需重新生成 SoC。

在本目录打开 PowerShell，先检查文件和构建依赖：

```powershell
& ./tools/Verify-Submission.ps1
& ./tools/Build-FPGA.ps1 -EfinityRoot 'E:/Efinity/2026.1' -CheckOnly
& ./tools/Build-Firmware.ps1 -IdeRoot 'E:/Efinity/efinity-riscv-ide-2026.1' -CheckOnly
```

去掉 `-CheckOnly` 即可编译。FPGA 输出在 `build/fpga`，固件输出在 `embedded_sw/SapphireSoc32/software/standalone/evsoc/build`。`release/` 中保留板上运行版本，构建脚本将新文件放在单独的输出目录中。

使用 RISC-V IDE 时，选择“导入已有工程”，导入 `embedded_sw/SapphireSoc32/software/standalone/evsoc`。保留上级 `common`、`driver` 和 BSP 的相对位置，其中 `common/tinyml_lib.a` 是链接需要的库，`ip/SapphireSoc32/*.bin` 是启动 ROM 数据。

重新生成 Flash 固件镜像前，先编译固件，再执行：

```powershell
& ./tools/Build-BootImage.ps1 -IdeRoot 'E:/Efinity/efinity-riscv-ide-2026.1' -Python python
```

生成结果在 `build/boot`。需要更新硬件启动 ROM 时使用 `-InstallRom`，并重新编译 FPGA、检查时序及板上运行情况。直接演示可以使用 `release/` 中的文件，步骤见 [部署说明](docs/部署说明.md)。
