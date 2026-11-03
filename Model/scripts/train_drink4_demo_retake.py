"""Retrain the isolated FPGA-sized drink CNN with the Nov 3 demo retake batch.

The newest chronological 25% per SKU stays untouched for final transfer testing.
No board or released model files are modified.
"""
import os
os.environ['OMP_NUM_THREADS']='4'
import json,math,time,hashlib
from pathlib import Path
import numpy as np
import torch
from torch import nn
from torch.nn import functional as F
from train_drink4_background import sample

ROOT=Path(__file__).resolve().parents[1]
DATA=ROOT/'data'
RETAKE=Path(os.environ.get('EDGEVISION_RETAKE_DIR', str(DATA/'demo_retake_20261103')))
BASE=ROOT/'runs/drink4_background_20261103'
OUT=ROOT/'runs/drink4_demo_retake_20261103_final'
NAMES=['乌苏啤酒','小可口可乐','小青柠','百事可乐','背景']
PRICES=[8.0,2.5,5.0,3.0,None]

class Net(nn.Module):
    def __init__(self):
        super().__init__()
        self.c1=nn.Conv2d(3,8,3,2,1);self.c2=nn.Conv2d(8,16,3,2,1)
        self.c3=nn.Conv2d(16,24,3,2,1);self.fc=nn.Linear(24,5)
    def forward(self,x):
        for c in (self.c1,self.c2,self.c3):x=torch.clamp(c(x),0,1)
        return self.fc(x.mean((2,3)))

def signed_hex(path,bits):
    raw=[int(s,16) for s in path.read_text(encoding='ascii').split()]
    sign=1<<(bits-1);mod=1<<bits
    return torch.tensor([x-mod if x&sign else x for x in raw],dtype=torch.float64)

def integer_scores(images,run,meta):
    w=signed_hex(run/'weights.hex',8);b=signed_hex(run/'bias.hex',32)
    v=torch.round(images.detach().cpu()*128).double()
    for layer in meta['layers'][:3]:
        shape=layer['weight_shape'];off=layer['weight_offset'];bo=layer['bias_offset']
        qw=w[off:off+int(np.prod(shape))].reshape(shape)
        qb=b[bo:bo+shape[0]]
        v=torch.clamp(torch.floor(F.conv2d(v,qw,qb,2,1)/(2**layer['shift'])),0,127)
    layer=meta['layers'][3];shape=layer['weight_shape'];off=layer['weight_offset'];bo=layer['bias_offset']
    qw=w[off:off+int(np.prod(shape))].reshape(shape)
    qb=b[bo:bo+shape[0]]
    return F.linear(v.sum((2,3)),qw,qb)

def tensors(rows,device):
    arr=np.stack([sample(path) for path,_ in rows])
    labels=torch.tensor([cls for _,cls in rows],dtype=torch.long,device=device)
    images=torch.tensor(arr,dtype=torch.float32,device=device).permute(0,3,1,2)/128-1
    return images,labels

def predict_rows(net,rows,device,weights_dir,meta):
    x,y=tensors(rows,device);net.eval()
    with torch.no_grad():float_pred=net(x).argmax(1).cpu().numpy()
    int_score=integer_scores(x,weights_dir,meta)
    return y.cpu().numpy(),float_pred,int_score.argmax(1).numpy(),int_score.numpy()

def metric(truth,pred,classes):
    if isinstance(truth,torch.Tensor):truth=truth.detach().cpu().numpy()
    if isinstance(pred,torch.Tensor):pred=pred.detach().cpu().numpy()
    truth=np.asarray(truth);pred=np.asarray(pred)
    cm=np.zeros((classes,classes),dtype=int)
    for a,b in zip(truth.tolist(),pred.tolist()):cm[int(a),int(b)]+=1
    return {'correct':int((truth==pred).sum()),'total':int(len(truth)),
            'accuracy':float((truth==pred).mean()) if len(truth) else None,
            'confusion_rows_true_columns_pred':cm.tolist()}

def main():
    if OUT.exists():raise SystemExit(f'Run already exists; refusing to overwrite: {OUT}')
    if not RETAKE.is_dir() or not BASE.is_dir():raise SystemExit('Missing staged retake batch or baseline model.')
    torch.set_num_threads(4);torch.manual_seed(17);rng=np.random.default_rng(17)
    device='cuda' if torch.cuda.is_available() else 'cpu'
    old_groups=[];excluded=[]
    for split in ('train','val'):
        paths=[Path(s) for s in (DATA/f'cloth_capture_split/{split}.txt').read_text(encoding='utf-8-sig').splitlines() if s]
        excluded.extend(str(p) for p in paths if int(p.name[5])==0)
        for old_cls in range(1,5):old_groups.append([(p,old_cls-1) for p in paths if int(p.name[5])==old_cls])
    old_opt=[];old_final=[]
    for group in old_groups:
        nv=max(1,round(len(group)*.2));old_opt.extend(group[:-nv]);old_final.extend(group[-nv:])
    bg_dir=Path(os.environ.get('EDGEVISION_BACKGROUND_DIR', str(DATA / 'background')))
    bg=sorted(bg_dir.glob('*.jpg'))
    if len(bg)!=6:raise SystemExit('Expected six reviewed baseline empty-cloth photographs.')
    by_cls={c:sorted((RETAKE/f'class{c}_{name}').glob('*.jpg'),key=lambda p:p.name) for c,name in enumerate(NAMES[:4])}
    if [len(by_cls[c]) for c in range(4)]!=[12,12,14,21]:raise SystemExit('Retake inventory changed; inspect before training.')
    new_opt=[];new_selection=[];new_final=[];new_splits={}
    for cls,paths in by_cls.items():
        ntest=max(1,round(len(paths)*.25));pre=paths[:-ntest];test=paths[-ntest:]
        nsel=max(1,round(len(pre)*.2));order=rng.permutation(len(pre));sel_ids=set(order[:nsel].tolist())
        sel=[(pre[i],cls) for i in sorted(sel_ids)]
        opt=[(pre[i],cls) for i in range(len(pre)) if i not in sel_ids]
        new_opt.extend(opt);new_selection.extend(sel);new_final.extend((p,cls) for p in test)
        new_splits[str(cls)]={'class_name':NAMES[cls],'optimization':[str(p) for p,c in opt],
                              'selection':[str(p) for p,c in sel],'heldout':[str(p) for p in test]}
    selection=list(new_selection)
    old_selection=[]
    # Preserve the existing model's deterministic 10-image/class checkpoint-selection subset.
    for cls in range(4):
        group=[row for row in old_opt if row[1]==cls]
        order=rng.permutation(len(group));old_selection.extend(group[i] for i in order[:10])
    selection.extend(old_selection)
    old_opt_selected={p for p,c in old_selection}
    optimization=[row for row in old_opt if row[0] not in old_opt_selected]+new_opt+[(p,4) for p in bg[:4]]
    selection.append((bg[4],4))
    old_test=list(old_final)+[(bg[5],4)]
    final_test=old_test+new_final
    all_paths=[p for group in (optimization,selection,final_test) for p,c in group]
    duplicates=sorted({str(p) for p in all_paths if all_paths.count(p)>1})
    if duplicates:raise AssertionError('Train/selection/final-test leakage: '+json.dumps(duplicates,ensure_ascii=False))
    assert not set(all_paths).intersection(Path(p) for p in excluded),'Removed water-C leaked into active model.'
    for rows in (optimization,selection,final_test):
        assert set(c for p,c in rows)==set(range(5))
    split={'optimization':[{'path':str(p),'class_id':c,'name':NAMES[c]} for p,c in optimization],
           'selection':[{'path':str(p),'class_id':c,'name':NAMES[c]} for p,c in selection],
           'final_test':[{'path':str(p),'class_id':c,'name':NAMES[c]} for p,c in final_test],
           'retake':new_splits,'excluded_water_c':excluded,
           'protocol':'Original and earlier cloth batches retain their prior suffix-block partition. For each retake class, newest chronological 25% is final test; 20% of the preceding frames is checkpoint selection; other retake frames train. Near-adjacent frames can still correlate.',
           'background':'Four original empty-cloth photos optimize, one selects, one tests; not independent backgrounds.'}
    OUT.mkdir(parents=True)
    (OUT/'split.json').write_text(json.dumps(split,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/'catalog.json').write_text(json.dumps({'beverage_classes':4,'background_id':4,'unknown_id':5,
      'classes':[{'id':i,'name':n,'price_cny':PRICES[i],'show_osd':i<4} for i,n in enumerate(NAMES)],
      'note':'Candidate weights only; active firmware is unchanged.'},ensure_ascii=False,indent=2),encoding='utf-8')
    x,y=tensors(optimization,device);xs,ys=tensors(selection,device);xv,yv=tensors(final_test,device)
    select_ids=np.arange(len(selection));net=Net().to(device);opt=torch.optim.AdamW(net.parameters(),lr=.004,weight_decay=.001)
    best=-1.;bestloss=float('inf');best_epoch=0;start=time.time()
    print(json.dumps({'device':device,'optimization':len(optimization),'selection':len(selection),
      'final_test':len(final_test),'retake_final_test':[sum(c==i for p,c in final_test) for i in range(4)]},ensure_ascii=False),flush=True)
    for epoch in range(600):
        net.train();losses=[]
        for chunk in np.array_split(rng.permutation(len(x)),math.ceil(len(x)/40)):
            ids=torch.tensor(chunk,device=device);xx=x[ids].clone();yy=y[ids];n=len(ids)
            angle=(torch.rand(n,device=device)-.5)*6.2831853;zoom=torch.rand(n,device=device)*.85+.35
            theta=torch.zeros(n,2,3,device=device);theta[:,0,0]=torch.cos(angle)*zoom;theta[:,0,1]=-torch.sin(angle)*zoom
            theta[:,1,0]=torch.sin(angle)*zoom;theta[:,1,1]=torch.cos(angle)*zoom
            theta[:,:,2]=(torch.rand(n,2,device=device)-.5)*.12
            xx=F.grid_sample(xx,F.affine_grid(theta,xx.size(),align_corners=False),align_corners=False,padding_mode='border')
            flip=torch.rand(n,device=device)>.5;xx[flip]=xx[flip].flip(3)
            xx=torch.clamp((xx+1)*(torch.rand(n,1,1,1,device=device)*.65+.65)*
                           (torch.rand(n,3,1,1,device=device)*.20+.90)-1,-1,127/128)
            xx=torch.round(xx*128)/128
            opt.zero_grad();loss=F.cross_entropy(net(xx),yy);loss.backward();opt.step();losses.append(float(loss.detach()))
        net.eval()
        with torch.no_grad():logits=net(xs);pred=logits.argmax(1);macro=float(torch.stack([(pred[ys==c]==c).float().mean() for c in range(5)]).mean());vl=float(F.cross_entropy(logits,ys))
        if macro>best or (macro==best and vl<bestloss):
            best=macro;bestloss=vl;best_epoch=epoch+1;torch.save(net.state_dict(),OUT/'best.pt')
        for g in opt.param_groups:g['lr']=.004*(.2+.8*(1-epoch/600))
        if epoch%20==0:print(epoch+1,'loss',round(float(np.mean(losses)),4),'selection_macro',round(macro,4),'seconds',round(time.time()-start,1),flush=True)
    net.load_state_dict(torch.load(OUT/'best.pt',weights_only=True,map_location=device));net.eval()
    with torch.no_grad():float_scores=net(xv)
    v=torch.round(xv.detach().cpu()*128).double();all_w=[];all_b=[];layers=[]
    for i,c in enumerate((net.c1,net.c2,net.c3)):
        w=c.weight.detach().cpu().double();bias=c.bias.detach().cpu().double();shift=int(math.floor(math.log2(127/float(w.abs().max()))))
        qw=torch.round(w*2**shift).clamp(-127,127);qb=torch.round(bias*128*2**shift)
        if not 0<=shift<=15 or float(qb.abs().max())>=2**31:raise ValueError('Quantized layer range exceeded.')
        v=torch.clamp(torch.floor(F.conv2d(v,qw,qb,2,1)/(2**shift)),0,127)
        layers.append({'layer':i,'shift':shift,'weight_offset':len(all_w),'bias_offset':len(all_b),'weight_shape':list(qw.shape)})
        all_w.extend(qw.int().reshape(-1).tolist());all_b.extend(qb.int().tolist())
    w=net.fc.weight.detach().cpu().double();bias=net.fc.bias.detach().cpu().double();shift=int(math.floor(math.log2(127/float(w.abs().max()))))
    qw=torch.round(w*2**shift).clamp(-127,127);qb=torch.round(bias*128*16*2**shift)
    scores=F.linear(v.sum((2,3)),qw,qb);pred=scores.argmax(1);all_w.extend(qw.int().reshape(-1).tolist());all_b.extend(qb.int().tolist())
    layers.append({'layer':3,'shift':0,'weight_quantization_shift':shift,'weight_offset':len(all_w)-int(np.prod(qw.shape)),'bias_offset':len(all_b)-qw.shape[0],'weight_shape':list(qw.shape)})
    truth=yv.cpu();ints=pred.cpu();float_pred=float_scores.argmax(1).cpu();cm=np.zeros((5,5),int)
    for a,b in zip(truth.tolist(),ints.tolist()):cm[a,b]+=1
    beverage=truth<4;retake_mask=torch.tensor([Path(p).resolve().is_relative_to(RETAKE.resolve()) for p,c in final_test],dtype=torch.bool)
    retake_beverage=retake_mask & beverage
    oldmeta=json.loads((BASE/'metrics.json').read_text(encoding='utf-8'))
    oldnet=Net().to(device);oldnet.load_state_dict(torch.load(BASE/'best.pt',map_location=device,weights_only=True));oldnet.eval()
    with torch.no_grad():baseline_float=oldnet(xv).argmax(1).cpu()
    baseline_int=integer_scores(xv,BASE,oldmeta).argmax(1).cpu()
    report={'model':'Tiny32 3->8->16->24 INT8 CNN: four beverages plus explicit background',
      'run':'drink4_demo_retake_20261103','selected_epoch':best_epoch,'optimization_images':len(optimization),
      'internal_selection_images':len(selection),'final_test_images':len(final_test),
      'retake_test_images':int(retake_mask.sum()),'retake_test_per_class':[int((retake_mask&(yv.cpu()==c)).sum()) for c in range(4)],
      'excluded_water_c_images':len(excluded),'baseline_retake_int8':metric(yv.cpu()[retake_mask],baseline_int[retake_mask],5),
      'candidate_retake_float':metric(yv.cpu()[retake_mask],float_pred[retake_mask],5),
      'candidate_retake_int8':metric(yv.cpu()[retake_mask],ints[retake_mask],5),
      'baseline_all_final_int8':metric(truth,baseline_int,5),'candidate_all_final_float':metric(truth,float_pred,5),
      'candidate_all_final_int8':metric(truth,ints,5),'confusion_rows_true_columns_pred':cm.tolist(),
      'int8_vs_float_disagreements':int((ints!=float_pred).sum()),'weights_bytes':len(all_w),'bias_bytes':4*len(all_b),
      'layers':layers,'retake_source_counts':[len(by_cls[c]) for c in range(4)],
      'limitations':['The 15 retake test images are a small chronological suffix of the supplied capture sequences; adjacent video-like frames may correlate.',
                     'Scene-level component box remains reference-background subtraction, not CNN localization.',
                     'Successful offline evaluation does not prove the model is deployed or accurate on the FPGA camera.']}
    (OUT/'metrics.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/'weights.hex').write_text(''.join(f'{z&255:02x}\n' for z in all_w),encoding='ascii')
    (OUT/'bias.hex').write_text(''.join(f'{z&0xffffffff:08x}\n' for z in all_b),encoding='ascii')
    np.savez(OUT/'integer_vectors.npz',inputs=torch.round(xv.cpu()*128).numpy().astype(np.int8),
       scores=scores.numpy().astype(np.int32),pred=ints.numpy(),truth=truth.numpy(),float_pred=float_pred.numpy(),
       retake=retake_mask.numpy(),baseline_pred=baseline_int.numpy(),baseline_float_pred=baseline_float.numpy())
    (OUT/'validation_paths.json').write_text(json.dumps([{'path':str(p),'class_id':c} for p,c in final_test],ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False,indent=2),flush=True)

if __name__=='__main__':main()
