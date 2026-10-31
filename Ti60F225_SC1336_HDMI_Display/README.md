# 工程说明

## 目录

| 路径 | 用途 |
|---|---|
| `Ti60_Demo.xml`、`Ti60_Demo.peri.xml`、`Ti60_Demo.pt.sdc` | Efinity 工程、外设及引脚配置、时序约束 |
| `example_top.v`、`src/` | 摄像头、DDR、显示、滤波、边缘、识别与按键 RTL |
| `ip/` | 已生成的必需 IP、参数、启动 ROM 和 DDR 初始化文件 |
| `embedded_sw/SapphireSoc32/` | RV32 BSP、驱动、TinyML 库和应用源码 |
| `ml/digits/` | 数据生成、训练、量化、Generator 导出脚本及最终模型 |
| `release/fpga/` | 最终 `.bit`、Flash `.hex`、时序及资源报告 |
| `release/firmware/` | 最终数字固件 ELF、BIN、Intel HEX |
| `release/boot/` | 带校验头的 Flash 固件、引导程序及清单 |
| `tools/` | 独立构建、校验、下载及固化脚本 |
| `docs/` | 技术与部署说明、关键验收证据 |

## 按键

| 操作 | 功能 |
|---|---|
| 长按 K1（约1秒） | 彩色原图→中值滤波→中值sobel→高斯滤波→高斯canny→灰度二值分屏→红边叠加→原图 |
| 两种全屏二值模式长按 K2 | 开启/退出数字识别 |
| 红边叠加模式长按 K2 | 开启/退出形状识别 |
| 原图、两种滤波灰度、分屏模式长按 K2 | 不进入识别 |
| 单击 K1 / K2 | 阈值增加/减少10；默认200、范围20～2040；等待约半秒完成多击判定 |
| 实时模式双击 K1 | 冻结并保存一帧，再双击恢复；最多10帧，满后覆盖最早帧 |
| 三击 K1 | 进入/退出回放 |
| 回放双击 K1 / K2 | 前后翻页 |

回放中保留长按切模式、识别启停及单击调阈值。冻结和回放帧位于易失性 DDR，断电不会保留这些拍摄帧。FPS 是显示输出帧计数测量值，冻结或回放仍按固定 HDMI 时序输出。

## 打开及重新构建

已验证的软件：Efinity **2026.1.132.3.9**，Efinity RISC-V IDE **2026.1**。保持现有已生成 IP 与 ROM 文件，不要为查看工程重新生成 SoC。打开 `Ti60_Demo.xml` 即可。

PowerShell 在本工程目录执行：

```powershell
& ./tools/Verify-Submission.ps1
& ./tools/Build-FPGA.ps1 -EfinityRoot 'E:/Efinity/2026.1' -CheckOnly
& ./tools/Build-Firmware.ps1 -IdeRoot 'E:/Efinity/efinity-riscv-ide-2026.1' -CheckOnly
```

移除 `-CheckOnly` 即执行相应构建。FPGA输出到 `build/fpga`，固件输出到 `embedded_sw/SapphireSoc32/software/standalone/evsoc/build`，不覆盖已验收 `release/` 文件。

RISC-V IDE 使用“导入已有工程”选择 `embedded_sw/SapphireSoc32/software/standalone/evsoc`，保留上级 `common`、`driver` 及 BSP 的相对目录结构。`common/tinyml_lib.a` 是必需库；`ip/SapphireSoc32/*.bin` 是启动 ROM 数据，不能按普通编译缓存删除。

如需更改固件并重建 Flash 镜像，先构建固件，然后：

```powershell
& ./tools/Build-BootImage.ps1 -IdeRoot 'E:/Efinity/efinity-riscv-ide-2026.1' -Python python
```

结果位于 `build/boot`。仅在需要更新硬件启动 ROM 时加 `-InstallRom`，之后必须重新构建 FPGA 并检查时序、容量和板上效果。提交的最终位流不需要重新训练或重新编译即可部署。

## 当前最终版指标

1280×720 / 60 Hz HDMI；XLR 60716/60800，RAM 256/256，DSP 38/160；最终时序报告最小 slack 0.018 ns、已审计路径无负 slack。数字 INT8 模型22064字节、17411参数，独立合成测试集3300张分类准确率99.39%。实板已确认七模式、识别、回放、按键及断电自启动。

完整部署步骤见 [部署说明](docs/部署说明.md)，算法及测量范围见 [技术说明](docs/技术说明.md)。
