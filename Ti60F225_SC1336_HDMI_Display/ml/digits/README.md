# 数字模型训练与导出

我使用轻量 CNN 对候选数字区域分类，模型输入为 32×32，输出包括 0～9 和非数字拒识类别。卷积使用 STANDARD TinyML 硬件加速，全连接等算子使用 SDK 软件实现。

当前运行模型为 `artifacts/digits_int8.tflite`。目录中包含训练代码、Keras 权重、冻结模型、测试样本、统计结果、Generator 参数和打印样张，直接运行板上演示时可以使用现成模型。

## 数据与训练

训练样式为 Calibri Bold 印刷数字，加入缩放、轻微旋转、透视、模糊和断边等变化。训练集 22,000 张，验证集 3,300 张，独立测试集 3,300 张，量化校准集 550 张。随机种子、测试结果和混淆矩阵保存在 `artifacts/training_report.json`。

建议使用 Python 3.11，在本目录创建环境：

```powershell
python -m venv .venv
./.venv/Scripts/python.exe -m pip install -r requirements.txt
./.venv/Scripts/python.exe train.py
```

默认字体路径为 `C:/Windows/Fonts/calibrib.ttf`，可以通过 `GRAY_DIGIT_FONT` 指定其他位置。训练会调用 `export.py` 导出完整 INT8 TFLite 模型。当前模型在独立合成测试集上的分类准确率为 99.39%，主要适用于基本正立、分离且足够大的指定印刷数字。

## Generator 导出与部署

安装官方 [TinyML Generator](https://github.com/Efinix-Inc/tinyml/tree/main/tools/tinyml_generator)，指定分析器路径后执行：

```powershell
$env:TINYML_ANALYZER='TinyML Generator安装目录/bin/tflite.exe'
./.venv/Scripts/python.exe generate.py
```

脚本调用官方分析器，更新工程中的 `src/tinyml/tinyml_core0_define.v`、应用 `src/model/` 下的模型数组和参数，并生成板端自检样本。

换模型后需要重新编译固件；如果硬件参数发生变化，还需要重新编译 FPGA。完成数字识别和显示测试后，再生成 Flash 镜像并固化。训练和导出只更新开发用文件，`release/` 中保留当前板上运行的模型配套版本，部署方法见 [下载与上电启动](../../docs/部署说明.md)。
