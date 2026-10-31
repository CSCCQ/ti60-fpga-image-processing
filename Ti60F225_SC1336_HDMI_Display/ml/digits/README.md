# 模型训练与导出

已验收模型是 `artifacts/digits_int8.tflite`。训练代码、Keras权重、冻结模型、测试样本、训练统计、Generator输出参数及打印样张一并保留。演示和部署不需要重新训练。

建议Python 3.11，建立独立环境后：

```powershell
python -m venv .venv
./.venv/Scripts/python.exe -m pip install -r requirements.txt
./.venv/Scripts/python.exe train.py
```

训练使用Windows字体 `C:/Windows/Fonts/calibrib.ttf`；其他路径可设置 `GRAY_DIGIT_FONT`。字体文件未重新分发。最终训练22,000样本，验证3,300样本，独立测试3,300样本，量化校准550样本；随机种子及混淆矩阵见 `artifacts/training_report.json`。99.39%准确率仅对应合成测试集。

训练会调用 `export.py` 导出完整INT8 TFLite。需自行安装官方 [TinyML Generator](https://github.com/Efinix-Inc/tinyml/tree/main/tools/tinyml_generator)，然后设置其分析器位置：

```powershell
$env:TINYML_ANALYZER='你的TinyML Generator目录/bin/tflite.exe'
./.venv/Scripts/python.exe generate.py
```

`generate.py` 使用官方分析器，更新 `src/tinyml/tinyml_core0_define.v` 和应用 `src/model/` 下模型数组及参数，再生成板端自检样本。随后需要重新构建固件；硬件参数变化时还必须重新构建FPGA，并完成配套测试。训练/导出会改变开发源码和模型，**不会自动更新已验收的 `release/` 镜像**。

当前卷积走STANDARD TinyML硬件加速，全连接等算子使用SDK软件实现。训练目标为指定样式、基本正立且不粘连的印刷数字0–9，含非数字拒识类别。当前屏幕在框旁显示分类结果。
