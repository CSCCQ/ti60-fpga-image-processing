# Ti60 FPGA 图像处理与数字识别系统

基于易灵思 Ti60F225、SC1336 摄像头与 RV32 SapphireSoC 的图像处理工程。当前提交版本是已完成 Flash 固化、回读校验和断电启动验收的 **V3 版本**。

## 功能

- 1280×720、60 Hz HDMI 输出，七种显示模式，中文模式提示，FPS 与阈值显示。
- 中值/Sobel 与高斯/Canny 两种二值边缘处理；低阈值噪点抑制与四周伪边缘屏蔽。
- 印刷数字 0–9 的定位与 INT8 CNN 分类，最多16个数字框，框旁显示结果。
- 三角形、矩形、圆形识别，形状识别横向 ROI 为100～1180。
- 冻结与最多10帧循环保存；回放中仍可切换处理方式、调阈值和识别。
- FPGA 配置和数字固件保存在 Flash，上电自动运行。

## 从这里开始

工程主目录：[`Ti60F225_SC1336_HDMI_Display`](Ti60F225_SC1336_HDMI_Display)。

| 内容 | 入口 |
|---|---|
| 操作、编译与文件说明 | [工程说明](Ti60F225_SC1336_HDMI_Display/README.md) |
| Efinity 工程 | [Ti60_Demo.xml](Ti60F225_SC1336_HDMI_Display/Ti60_Demo.xml) |
| 最终位流与固件 | [release](Ti60F225_SC1336_HDMI_Display/release) |
| 烧录、自动启动 | [部署说明](Ti60F225_SC1336_HDMI_Display/docs/部署说明.md) |
| 架构、模型及指标口径 | [技术说明](Ti60F225_SC1336_HDMI_Display/docs/技术说明.md) |
| 验证结果 | [验证说明](Ti60F225_SC1336_HDMI_Display/docs/verification/README.md) |

本仓库与提交的 RAR 使用同一份工程。旧版位流、历次调试与仿真工作目录、IDE缓存、虚拟环境、软件下载包未纳入提交。硬件 RTL、嵌入式固件源代码以及最终模型/位流/固件内容保持与验收版一致。

60 Hz 指 HDMI 显示刷新率；模型99.39%的分类准确率来自独立合成测试集，不等同于真实摄像头全场景准确率。详见技术说明。
