"""Reproducible Calibri Bold edge-digit training, full INT8 export and evaluation.
Training data is synthetic; the held-out test is NOT a measured camera accuracy.
Run with the isolated .venv. Source font is the font used by reference/test.docx.
"""
import os
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'
os.environ['TF_ENABLE_ONEDNN_OPTS'] = '0'
import argparse, hashlib, json, time
from pathlib import Path
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
ART = ROOT / 'artifacts'
FONT = Path(os.environ.get('GRAY_DIGIT_FONT', str(Path(os.environ.get('WINDIR', 'C:/Windows'))/'Fonts/calibrib.ttf')))
SIZE = 32

def normalize(edge, box=None):
    """Same integer forward/max mapping as firmware; no bilinear grey pixels."""
    yy, xx = np.where(edge != 0)
    out = np.zeros((SIZE, SIZE), np.uint8)
    if not len(xx): return out
    x0, y0, x1, y1 = box or (int(xx.min()), int(yy.min()), int(xx.max()), int(yy.max()))
    w, h = x1-x0+1, y1-y0+1
    dw, dh = max(1, w*24//max(w,h)), max(1, h*24//max(w,h))
    ox, oy = (SIZE-dw)//2, (SIZE-dh)//2
    keep=(xx>=x0)&(xx<=x1)&(yy>=y0)&(yy<=y1)
    out[oy+(yy[keep]-y0)*dh//h, ox+(xx[keep]-x0)*dw//w] = 255
    return out

def sample(label, rng):
    img = Image.new('L', (160,160), 255)
    draw = ImageDraw.Draw(img)
    if label < 10:
        glyph = str(label)
    else:
        glyph = rng.choice(list('ABCDEFGHJKLMNPQRSTUVXYZ@#?+=%'))
    font = ImageFont.truetype(str(FONT), int(rng.integers(65,140)))
    bbox = draw.textbbox((0,0), glyph, font=font)
    draw.text(((160-bbox[2]+bbox[0])/2-bbox[0],(160-bbox[3]+bbox[1])/2-bbox[1]),glyph,font=font,fill=int(rng.integers(0,70)))
    a = np.asarray(img).copy()
    if label == 10 and rng.random() < .5:
        a[:] = 255
        for _ in range(int(rng.integers(1,5))):
            p1=tuple(int(v) for v in rng.integers(15,145,2)); p2=tuple(int(v) for v in rng.integers(15,145,2))
            if rng.random()<.45: cv2.rectangle(a,p1,p2,0,int(rng.integers(1,7)))
            elif rng.random()<.5: cv2.ellipse(a,(80,80),tuple(int(v) for v in rng.integers(15,65,2)),0,0,int(rng.integers(120,360)),0,3)
            else: cv2.line(a,p1,p2,0,int(rng.integers(1,7)))
    # Perspective and mild rotation, not arbitrary rotation (6/9 are ambiguous).
    src=np.float32([[15,15],[145,15],[145,145],[15,145]])
    dst=src+rng.uniform(-13,13,(4,2)).astype(np.float32)
    a=cv2.warpPerspective(a,cv2.getPerspectiveTransform(src,dst),(160,160),borderValue=255)
    m=cv2.getRotationMatrix2D((80,80),float(rng.uniform(-18,18)),float(rng.uniform(.85,1.08)))
    m[0,0:2]*=rng.uniform(.8,1.15)
    a=cv2.warpAffine(a,m,(160,160),borderValue=255)
    # Mild barrel/pincushion curvature like the camera away from its centre.
    if rng.random()<.65:
        yy,xx=np.mgrid[:160,:160].astype(np.float32); cx,cy=rng.uniform(40,120,2)
        dx=(xx-cx)/100; dy=(yy-cy)/100; k=rng.uniform(-.08,.08)
        factor=1+k*(dx*dx+dy*dy)
        a=cv2.remap(a,(cx+dx*100*factor).astype(np.float32),(cy+dy*100*factor).astype(np.float32),cv2.INTER_LINEAR,borderMode=cv2.BORDER_CONSTANT,borderValue=255)
    a=cv2.GaussianBlur(a,(5,5),float(rng.uniform(.5,1.7)))
    hi=int(rng.integers(50,190)); edge=cv2.Canny(a,hi//2,hi)
    # Simulate the FPGA max-pooled snapshot; varying apparent print sizes.
    factor=int(rng.integers(1,6))
    sz=(160//factor)*factor
    edge=edge[:sz,:sz].reshape(sz//factor,factor,sz//factor,factor).max((1,3))
    if rng.random()<.18: edge[rng.random(edge.shape)<.025]=0
    return normalize(edge)

def dataset(n,seed):
    rng=np.random.default_rng(seed)
    ys=np.arange(n,dtype=np.int32)%11
    xs=np.stack([sample(int(y),rng) for y in ys])
    order=rng.permutation(n)
    return xs[order,:,:,None],ys[order]

def preview(x,y):
    sheet=Image.new('RGB',(11*100,6*112),'#222222'); d=ImageDraw.Draw(sheet)
    for label in range(11):
        for row,idx in enumerate(np.where(y==label)[0][:6]):
            im=Image.fromarray(x[idx,:,:,0]).resize((96,96),Image.Resampling.NEAREST)
            sheet.paste(im,(label*100,row*112)); d.text((label*100,row*112+96),str(label) if label<10 else 'reject',fill='white')
    sheet.save(ART/'training_preview.png')

def main():
    p=argparse.ArgumentParser(); p.add_argument('--epochs',type=int,default=22); p.add_argument('--samples',type=int,default=22000); args=p.parse_args()
    ART.mkdir(exist_ok=True); started=time.time()
    import tensorflow as tf
    tf.keras.utils.set_random_seed(20261016)
    tf.config.threading.set_intra_op_parallelism_threads(6)
    tf.config.threading.set_inter_op_parallelism_threads(2)
    print('Generating independent train/validation/test samples',flush=True)
    x,y=dataset(args.samples,1016); xv,yv=dataset(3300,2116); xt,yt=dataset(3300,3116)
    preview(x,y); np.savez_compressed(ART/'test_samples.npz',x=xt,y=yt)
    model=tf.keras.Sequential([tf.keras.layers.Input((32,32,1)),
      tf.keras.layers.Conv2D(8,3,padding='same',activation='relu'),tf.keras.layers.MaxPooling2D(2),
      tf.keras.layers.Conv2D(16,3,padding='same',activation='relu'),tf.keras.layers.MaxPooling2D(2),
      tf.keras.layers.Conv2D(24,3,padding='same',activation='relu'),tf.keras.layers.MaxPooling2D(2),
      tf.keras.layers.Flatten(),tf.keras.layers.Dense(32,activation='relu'),tf.keras.layers.Dense(11,activation='softmax')])
    model.compile(optimizer=tf.keras.optimizers.Adam(.001),loss='sparse_categorical_crossentropy',metrics=['accuracy'])
    model.summary()
    hist=model.fit(x.astype(np.float32)/255,y,batch_size=128,epochs=args.epochs,validation_data=(xv.astype(np.float32)/255,yv),
      callbacks=[tf.keras.callbacks.ModelCheckpoint(str(ART/'digits_best.keras'),monitor='val_accuracy',save_best_only=True),
      tf.keras.callbacks.ReduceLROnPlateau(monitor='val_loss',factor=.5,patience=3,min_lr=0.00005)],verbose=2)
    model=tf.keras.models.load_model(ART/'digits_best.keras')
    (ART/'fit_history.json').write_text(json.dumps(hist.history,indent=2))
    (ART/'dataset_config.json').write_text(json.dumps({'train_count':args.samples,'validation_count':3300,'test_count':3300,'epochs':args.epochs},indent=2))
    from export import run
    run()

if __name__=='__main__': main()
