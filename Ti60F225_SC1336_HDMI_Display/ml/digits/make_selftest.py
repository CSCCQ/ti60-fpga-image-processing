"""Embed ten known INT8 inputs to check board accelerator numerical agreement."""
import os
os.environ['TF_CPP_MIN_LOG_LEVEL']='2'
from pathlib import Path
import numpy as np,tensorflow as tf,json
root=Path(__file__).resolve().parents[2];art=root/'ml/digits/artifacts'
dst=root/'embedded_sw/SapphireSoc32/software/standalone/evsoc/src/model'
d=np.load(art/'test_samples.npz');inter=tf.lite.Interpreter(model_path=str(art/'digits_int8.tflite'));inter.allocate_tensors()
inp=inter.get_input_details()[0];out=inter.get_output_details()[0];scale,zp=out['quantization']
samples=[];expected=[];indices=[]
for label in range(10):
 for idx in np.where(d['y']==label)[0]:
  q=(d['x'][idx].astype(np.int16)-128).astype(np.int8)
  inter.set_tensor(inp['index'],q[None]);inter.invoke();result=inter.get_tensor(out['index'])[0]
  if result.argmax()==label and (int(result.max())-zp)*scale>=.95:
   samples.append(q.reshape(-1));expected.append(result);indices.append(int(idx));break
 else:raise RuntimeError('No known-good fixture for digit %d'%label)
newline=chr(10)
header=newline.join(['#ifndef GRAY_DIGIT_SELFTEST_H','#define GRAY_DIGIT_SELFTEST_H','#include <stdint.h>','extern const int8_t digit_test_inputs[10][1024];','extern const int8_t digit_test_outputs[10][11];','#endif',''])
body='#include "digit_selftest.h"'+newline
for name,rows,width in [('digit_test_inputs',samples,1024),('digit_test_outputs',expected,11)]:
 body+='const int8_t %s[10][%d]={'%(name,width)+newline
 body+=(','+newline).join('{'+','.join(str(int(v)) for v in row)+'}' for row in rows)+newline+'};'+newline
(dst/'digit_selftest.h').write_text(header);(dst/'digit_selftest.cc').write_text(body)
(art/'selftest_manifest.json').write_text(json.dumps({'test_sample_indices':indices,'expected_labels':list(range(10)),'max_output_difference_allowed':4},indent=2))
print('Exported ten labeled quantized fixtures for board self-test')
