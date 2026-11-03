"""Four beverage classes plus explicit cloth-background rejection; isolated run."""
import os
os.environ['OMP_NUM_THREADS'] = '4'
import json, math, time, hashlib
from pathlib import Path
import cv2
import numpy as np
from PIL import Image, ImageOps
import torch
from torch import nn
from torch.nn import functional as F

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'runs/drink4_background_20261103'
BACKGROUND = Path(os.environ.get('EDGEVISION_BACKGROUND_DIR', str(ROOT / 'data' / 'background')))
NAMES = ['乌苏啤酒', '小可口可乐', '小青柠', '百事可乐', '背景']
PRICES = [8.0, 2.5, 5.0, 3.0, None]

class Net(nn.Module):
    def __init__(self):
        super().__init__()
        self.c1=nn.Conv2d(3,8,3,2,1); self.c2=nn.Conv2d(8,16,3,2,1)
        self.c3=nn.Conv2d(16,24,3,2,1); self.fc=nn.Linear(24,5)
    def forward(self,x):
        for c in (self.c1,self.c2,self.c3): x=torch.clamp(c(x),0,1)
        return self.fc(x.mean((2,3)))

def sample(path):
    im=np.asarray(ImageOps.exif_transpose(Image.open(path)).convert('RGB'))
    full=cv2.resize(im,(1920,1080),interpolation=cv2.INTER_LINEAR)
    rows=np.floor((np.arange(32)*2+1)*1080/64).astype(int)
    cols=np.floor((np.arange(32)*2+1)*1920/64).astype(int)
    return full[rows[:,None],cols[None,:]]

def main():
    if (OUT/'metrics.json').exists(): raise SystemExit('Run already exists; preserve it and choose a new run name.')
    OUT.mkdir(parents=True,exist_ok=True)
    torch.set_num_threads(4); torch.manual_seed(17); np.random.seed(17)
    device='cuda' if torch.cuda.is_available() else 'cpu'
    groups=[]; excluded=[]
    for split in ['train','val']:
        paths=[Path(s) for s in (ROOT/f'data/cloth_capture_split/{split}.txt').read_text(encoding='utf-8-sig').splitlines() if s]
        excluded.extend(str(p) for p in paths if int(p.name[5])==0)
        for old in range(1,5): groups.append([(p,old-1) for p in paths if int(p.name[5])==old])
    training=[];validation=[]
    for group in groups:
        nv=max(1,round(len(group)*.2));training.extend(group[:-nv]);validation.extend(group[-nv:])
    # Select checkpoints with an internal, per-class holdout, never the final test.
    rng=np.random.default_rng(17);selection=[];optimization=[]
    for cls in range(4):
        group=[p for p in training if p[1]==cls];order=rng.permutation(len(group))
        selection.extend(group[i] for i in order[:10]);optimization.extend(group[i] for i in order[10:])
    bg=sorted(BACKGROUND.glob('*.jpg'))
    if len(bg)!=6:raise ValueError('Expected the six reviewed empty-cloth photographs')
    optimization.extend((p,4) for p in bg[:4]);selection.append((bg[4],4));validation.append((bg[5],4))
    def rows(seq):return [{'path':str(p),'class_id':c,'name':NAMES[c]} for p,c in seq]
    split={'optimization':rows(optimization),'selection':rows(selection),'validation':rows(validation),
           'excluded_original_class0_water_c':excluded,'old_to_new_class_id':{'1':0,'2':1,'3':2,'4':3},
           'background_sources':[{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in bg],
           'note':'Four original classes only. Background source images split 4 optimization / 1 selection / 1 validation BEFORE augmentation. All six are similar captures, not independent deployment evidence. Beverage validation is the trailing 20% of each capture batch.'}
    all_active=[str(p) for p,c in optimization+selection+validation]
    assert len(all_active)==len(set(all_active)) and not set(all_active).intersection(excluded)
    (OUT/'split.json').write_text(json.dumps(split,ensure_ascii=False,indent=2),encoding='utf-8')
    catalog={'firmware_id_hex':'110303','beverage_classes':4,'background_id':4,'unknown_id':5,
             'classes':[{'id':i,'name':n,'price_cny':PRICES[i],'show_osd':i<4} for i,n in enumerate(NAMES)]}
    (OUT/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf-8')
    def tensors(seq):
        xx=np.stack([sample(p) for p,c in seq]);yy=[c for p,c in seq]
        return torch.tensor(xx,dtype=torch.float32,device=device).permute(0,3,1,2)/128-1,torch.tensor(yy,device=device)
    x,y=tensors(optimization);xs,ys=tensors(selection);xv,yv=tensors(validation)
    bg_ids=np.flatnonzero(y.cpu().numpy()==4); drink_ids=np.flatnonzero(y.cpu().numpy()<4)
    net=Net().to(device);opt=torch.optim.AdamW(net.parameters(),lr=.004,weight_decay=.001)
    best=-1;bestloss=float('inf');best_epoch=0;start=time.time()
    for epoch in range(600):
        net.train();losses=[]
        for chunk in np.array_split(rng.permutation(drink_ids),math.ceil(len(drink_ids)/40)):
            ids=np.concatenate((chunk,rng.choice(bg_ids,size=10,replace=True)))
            xx=x[ids].clone();yy=y[ids];n=len(ids)
            angle=(torch.rand(n,device=device)-.5)*6.2831853
            zoom=torch.rand(n,device=device)*.85+.35
            theta=torch.zeros(n,2,3,device=device)
            theta[:,0,0]=torch.cos(angle)*zoom;theta[:,0,1]=-torch.sin(angle)*zoom
            theta[:,1,0]=torch.sin(angle)*zoom;theta[:,1,1]=torch.cos(angle)*zoom
            theta[:,:,2]=(torch.rand(n,2,device=device)-.5)*.12
            xx=F.grid_sample(xx,F.affine_grid(theta,xx.size(),align_corners=False),align_corners=False,padding_mode='border')
            flip=torch.rand(n,device=device)>.5;xx[flip]=xx[flip].flip(3)
            xx=torch.clamp((xx+1)*(torch.rand(n,1,1,1,device=device)*.65+.65)*(torch.rand(n,3,1,1,device=device)*.20+.90)-1,-1,127/128)
            xx=torch.round(xx*128)/128
            opt.zero_grad();loss=F.cross_entropy(net(xx),yy);loss.backward();opt.step();losses.append(float(loss))
        net.eval()
        with torch.no_grad():
            logits=net(xs);pred=logits.argmax(1)
            macro=float(torch.stack([(pred[ys==c]==c).float().mean() for c in range(5)]).mean())
            vl=float(F.cross_entropy(logits,ys))
        if macro>best or (macro==best and vl<bestloss):
            best=macro;bestloss=vl;best_epoch=epoch+1;torch.save(net.state_dict(),OUT/'best.pt')
        for g in opt.param_groups:g['lr']=.004*(.2+.8*(1-epoch/600))
        if epoch%20==0:print(epoch+1,'loss',round(np.mean(losses),4),'selection_macro',round(macro,4),'seconds',round(time.time()-start,1),flush=True)
    net.load_state_dict(torch.load(OUT/'best.pt',weights_only=True));net.eval()
    with torch.no_grad():fpred=net(xv).argmax(1)
    v=torch.round(xv.cpu()*128).double();all_w=[];all_b=[];meta=[]
    for i,c in enumerate((net.c1,net.c2,net.c3)):
        w=c.weight.detach().cpu().double();b=c.bias.detach().cpu().double()
        shift=int(math.floor(math.log2(127/float(w.abs().max()))))
        qw=torch.round(w*2**shift).clamp(-127,127);qb=torch.round(b*128*2**shift)
        assert 0<=shift<=15 and float(qb.abs().max())<2**31
        v=torch.clamp(torch.floor(F.conv2d(v,qw,qb,2,1)/2**shift),0,127)
        meta.append({'layer':i,'shift':shift,'weight_offset':len(all_w),'bias_offset':len(all_b),'weight_shape':list(qw.shape)})
        all_w.extend(qw.int().reshape(-1).tolist());all_b.extend(qb.int().tolist())
    w=net.fc.weight.detach().cpu().double();b=net.fc.bias.detach().cpu().double()
    shift=int(math.floor(math.log2(127/float(w.abs().max()))))
    qw=torch.round(w*2**shift).clamp(-127,127);qb=torch.round(b*128*16*2**shift)
    scores=F.linear(v.sum((2,3)),qw,qb);pred=scores.argmax(1);truth=yv.cpu()
    meta.append({'layer':3,'shift':0,'weight_quantization_shift':shift,'weight_offset':len(all_w),'bias_offset':len(all_b),'weight_shape':list(qw.shape)})
    all_w.extend(qw.int().reshape(-1).tolist());all_b.extend(qb.int().tolist())
    cm=np.zeros((5,5),int)
    for a,b in zip(truth.tolist(),pred.tolist()):cm[a,b]+=1
    products=truth<4
    report={'model':'Tiny32 3->8->16->24 INT8 CNN: 4 beverages + explicit background (5 outputs)',
            'classes':NAMES,'background_id':4,'unknown_id':5,'selected_epoch':best_epoch,
            'optimization_images':len(optimization),'internal_selection_images':len(selection),
            'heldout_images':len(validation),'excluded_water_c_images':len(excluded),
            'beverage_counts_total':[sum(c==i for p,c in optimization+selection+validation) for i in range(4)],
            'float_classification_accuracy':float((fpred.cpu()==truth).float().mean()),
            'int8_classification_accuracy':float((pred==truth).double().mean()),
            'int8_beverage_correct':int((pred[products]==truth[products]).sum()),'heldout_beverage_images':int(products.sum()),
            'int8_background_correct':int((pred[~products]==4).sum()),'heldout_background_images':int((~products).sum()),
            'confusion_rows_true_columns_pred':cm.tolist(),'weights_bytes':len(all_w),'bias_bytes':4*len(all_b),'layers':meta,
            'limitations':['Fixed camera, one beverage, cloth background only; box is reference-background subtraction, not CNN detection.',
                          'Beverage validation shares capture sessions; the single background validation image shares a near-duplicate scene with training. Not a field accuracy estimate.',
                          'Removed water-C is excluded from all training and validation; it is not guaranteed to be rejected as an unknown object.',
                          'Actual FPGA camera, framing, background calibration and each remaining beverage need independent physical verification.']}
    (OUT/'metrics.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/'weights.hex').write_text(''.join(f'{w&255:02x}\n' for w in all_w),encoding='ascii')
    (OUT/'bias.hex').write_text(''.join(f'{b&0xffffffff:08x}\n' for b in all_b),encoding='ascii')
    np.savez(OUT/'integer_vectors.npz',inputs=torch.round(xv.cpu()*128).numpy().astype(np.int8),scores=scores.numpy().astype(np.int32),pred=pred.numpy(),truth=truth.numpy())
    (OUT/'validation_paths.json').write_text(json.dumps([str(p) for p,c in validation],ensure_ascii=False),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False,indent=2),flush=True)

if __name__=='__main__':main()
