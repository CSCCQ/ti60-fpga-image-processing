"""Freeze trained Keras variables, export full INT8, evaluate held-out samples."""
import os
os.environ['TF_CPP_MIN_LOG_LEVEL']='2'
os.environ['TF_ENABLE_ONEDNN_OPTS']='0'
import json,hashlib,time,re
from pathlib import Path
import numpy as np
import tensorflow as tf
from tensorflow.python.framework.convert_to_constants import convert_variables_to_constants_v2
from train import ROOT,ART,FONT,dataset
def run():
 started=time.time();model=tf.keras.models.load_model(ART/'digits_best.keras')
 held=np.load(ART/'test_samples.npz');xt,yt=held['x'],held['y']
 calibration,_=dataset(550,4116)
 scores=model.predict(xt.astype(np.float32)/255,batch_size=128,verbose=0)
 concrete=tf.function(lambda x:model(x,training=False)).get_concrete_function(tf.TensorSpec([1,32,32,1],tf.float32))
 frozen=convert_variables_to_constants_v2(concrete)
 # Freeze variables explicitly: avoids READ_VARIABLE in Keras 3 / TF 2.18
 # calibration, and produces a static graph compatible with the board SDK.
 module=tf.Module();module.infer=frozen
 tf.saved_model.save(module,str(ART/'saved_model_frozen'),signatures={'serving_default':frozen})
 converter=tf.lite.TFLiteConverter.from_concrete_functions([frozen])
 converter.optimizations=[tf.lite.Optimize.DEFAULT]
 converter._experimental_disable_per_channel=True
 converter.representative_dataset=lambda:([a[None].astype(np.float32)/255] for a in calibration)
 converter.target_spec.supported_ops=[tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
 converter.inference_input_type=tf.int8;converter.inference_output_type=tf.int8
 data=converter.convert();(ART/'digits_int8.tflite').write_bytes(data)
 inter=tf.lite.Interpreter(model_content=data,num_threads=2);inter.allocate_tensors()
 inp=inter.get_input_details()[0];out=inter.get_output_details()[0]
 scale,zp=inp['quantization'];oscale,ozp=out['quantization'];pred=[];confidence=[];margins=[]
 for a in xt:
  q=np.clip(np.rint(a.astype(np.float32)/255/scale)+zp,-128,127).astype(np.int8)
  inter.set_tensor(inp['index'],q[None]);inter.invoke()
  prob=(inter.get_tensor(out['index'])[0].astype(np.float32)-ozp)*oscale
  pred.append(int(prob.argmax()));confidence.append(float(prob.max()));rank=np.sort(prob);margins.append(float(rank[-1]-rank[-2]))
 pred=np.array(pred);confidence=np.array(confidence);margins=np.array(margins);cm=np.zeros((11,11),np.int32)
 np.add.at(cm,(yt,pred),1);accepted=(pred<10)&(confidence>=.85)&(margins>=.30)
 assert inp['shape'].tolist()==[1,32,32,1] and out['shape'].tolist()==[1,11]
 ops=[i['op_name'] for i in inter._get_ops_details()]
 assert set(ops)<=set(['CONV_2D','MAX_POOL_2D','RESHAPE','FULLY_CONNECTED','SOFTMAX','DELEGATE']),ops
 report={'source':'Calibri Bold 120pt in reference/test.docx','data_kind':'synthetic edge images; camera accuracy NOT yet measured',
  'font_sha256':hashlib.sha256(FONT.read_bytes()).hexdigest(),'seeds':{'train':1016,'validation':2116,'test':3116,'calibration':4116},
  'train_count':22000,'validation_count':3300,'test_count':len(yt),'calibration_count':550,
  'float_accuracy':float((scores.argmax(1)==yt).mean()),'int8_accuracy':float((pred==yt).mean()),
  'accepted_precision':float((pred[accepted]==yt[accepted]).mean()),
  'digit_recall_after_rejection':float(((pred==yt)&accepted&(yt<10)).sum()/(yt<10).sum()),
  'confusion_matrix':cm.tolist(),'input_quantization':[float(scale),int(zp)],'output_quantization':[float(oscale),int(ozp)],
  'model_bytes':len(data),'model_sha256':hashlib.sha256(data).hexdigest(),'parameter_count':model.count_params(),
  'ops':ops,'tensorflow':tf.__version__,'quantization':'INT8 input/output and all operators; per-tensor weights for legacy TFLM',
  'export_seconds':time.time()-started}
 report.update(json.loads((ART/'dataset_config.json').read_text()) if (ART/'dataset_config.json').exists() else {})
 (ART/'training_report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2),flush=True)
 assert report['int8_accuracy']>.97 and report['accepted_precision']>.99, 'Quantized quality gate failed'
if __name__=='__main__':run()
