"""Official Efinix model analyzer plus reproducible model/config export.
FC stays on the SDK's software path; only Conv2D uses STANDARD TinyML hardware.
"""
from pathlib import Path
import subprocess,json,re,hashlib,os
root=Path(__file__).resolve().parents[2];art=root/'ml/digits/artifacts'
app=root/'embedded_sw/SapphireSoc32/software/standalone/evsoc/src/model'
analyzer=os.environ.get('TINYML_ANALYZER')
if not analyzer: raise SystemExit('Set TINYML_ANALYZER to the official TinyML Generator bin/tflite.exe')
exe=Path(analyzer)
if not exe.is_file(): raise SystemExit('TinyML analyzer does not exist: '+str(exe))
model=art/'digits_int8.tflite'
r=subprocess.run([str(exe),str(model),'8','1'],capture_output=True,text=True)
(art/'generator_analysis.txt').write_text(r.stdout+r.stderr,encoding='utf-8')
assert r.returncode==0,(r.returncode,r.stderr[-1500:])
params={};inside=False
for line in r.stderr.splitlines():
 if line.startswith('===='):inside=not inside
 elif inside and ':' in line:
  k,v=line.split(':',1)
  if v.strip().lstrip('-').isdigit():params[k.strip().upper()]=int(v.strip())
assert params,'Official analyzer did not return parameters'
required=['CONV_DEPTHW_STD_OUT_CH_FIFO_A','CONV_DEPTHW_STD_FILTER_FIFO_A','CONV_DEPTHW_STD_CNT_DTH']
assert all(k in params and params[k]>0 for k in required),params
src=root/'src/tinyml/tinyml_core0_define.v'
hw=src.read_text()
for k in required:
 hw,n=re.subn(r'('+re.escape(chr(96)+'define TML_C0_'+k)+r'\s+)\d+',lambda m:m[1]+str(params[k]),hw)
 assert n==1,k
src.write_text(hw);(art/'tinyml_core0_define.v').write_text(hw)
data=model.read_bytes();name='digits_int8_model_data'
header='#ifndef GRAY_DIGITS_MODEL_H\n#define GRAY_DIGITS_MODEL_H\nextern const unsigned char '+name+'[];\nextern const unsigned int '+name+'_len;\n#endif\n'
body='#include "digits_int8_model_data.h"\nalignas(16) const unsigned char '+name+'[]={\n'
body+='\n'.join(','.join('0x%02x'%x for x in data[i:i+16])+',' for i in range(0,len(data),16))
body+='\n};\nconst unsigned int '+name+'_len='+str(len(data))+';\n'
(app/'digits_int8_model_data.h').write_text(header);(app/'digits_int8_model_data.cc').write_text(body)
# SDK accel_settings.cc owns layer_mode; do not introduce the GUI's older
# duplicate global. Software modes agree exactly with the instantiated IP.
sw={'conv_depthw_mode':2,'conv_depthw_lite_parallel':4,'add_mode':0,'fc_mode':0,'mul_mode':0,'min_max_mode':0,'tinyml_cache':1}
(app/'define.h').write_text('#ifndef GRAY_DIGITS_DEFINE_H\n#define GRAY_DIGITS_DEFINE_H\n'+''.join('extern int %s;\n'%k for k in sw)+'#endif\n')
(app/'define.cc').write_text('#include "define.h"\n'+''.join('int %s=%d;\n'%(k,v) for k,v in sw.items()))
report={'analyzer':str(exe),'analyzer_sha256':hashlib.sha256(exe.read_bytes()).hexdigest(),'model_sha256':hashlib.sha256(data).hexdigest(),'in_parallel':8,'out_parallel':1,'parameters':params,'software_modes':sw,'bytes':len(data)}
(art/'generator_report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))

subprocess.run([__import__('sys').executable,str(root/'ml/digits/make_selftest.py')],check=True)
