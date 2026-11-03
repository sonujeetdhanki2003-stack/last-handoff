#!/usr/bin/env python3
"""Sculpts the Keeper (assets/characters/keeper/) from the CC0 Quaternius
"Universal Base Characters" Superhero_Male mesh (src_assets/ubc, outside the game).

Run from the project root:  python3 tools/keeper_sculpt/sculpt_keeper.py
Needs numpy, scipy, Pillow. Writes Keeper.gltf/.bin and the T_Keeper*/T_KeeperRag* textures.

Pipeline (all procedural, deterministic):
 1. Stretch the skeleton (K: per-bone segment length), carry every vertex along its bones
    with a segment-aware linear-blend so joints stay continuous; thin the limbs/torso
    radially (R) with bony knobs at the knees and elbows (KNOB).
 2. Head: Laplacian-smooth the face away, sweep the cranium back, long jaw, two shallow
    eye pits and a mouth seam.
 3. Bake textures in UV space from 3D rest positions: mottled wet skin, veins, ribs,
    sternum, collarbones, vertebrae (height field -> tangent-space normal, combined with
    the base mesh's muscle normal map), cavity grime, roughness with wet streaks.
 4. The torn coverall: a skinned cloth band offset from the body (alpha-cut tears) plus
    hanging ribbons weighted pelvis -> thigh, and two peeled-down sleeves.
 5. Write a glTF with the stretched rest skeleton (inverse binds recomputed). Godot imports it
    with the same humanoid BoneMap as the explorer, so every UAL animation clip plays on it.
"""
import os, json, copy
import numpy as np
from PIL import Image
from scipy.spatial.transform import Rotation as Rot
from scipy.spatial import cKDTree
P = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
UBC = os.path.join(P, "..", "src_assets", "ubc", "Universal Base Characters[Standard]", "Base Characters", "Godot - UE") + "/"
OUT = os.path.join(P, "assets", "characters", "keeper")
RES = 1024
CT={5126:np.float32,5123:np.uint16,5125:np.uint32,5121:np.uint8,5122:np.int16}
NC={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
def srgb(c): return np.array(c)/255.0

K = {"spine_01": 1.06, "spine_02": 1.1, "spine_03": 1.1, "neck_01": 1.0, "Head": 1.45, "upperarm_l": 1.2, "lowerarm_l": 1.32, "hand_l": 1.42, "calf_l": 1.12, "foot_l": 1.12, "ball_l": 1.1, "ball_leaf_l": 1.15, "index_01_l": 1.12, "index_02_l": 1.8, "index_03_l": 1.9, "index_04_leaf_l": 1.9, "middle_01_l": 1.12, "middle_02_l": 1.8, "middle_03_l": 1.9, "middle_04_leaf_l": 1.9, "ring_01_l": 1.12, "ring_02_l": 1.8, "ring_03_l": 1.9, "ring_04_leaf_l": 1.9, "pinky_01_l": 1.12, "pinky_02_l": 1.8, "pinky_03_l": 1.9, "pinky_04_leaf_l": 1.9, "thumb_02_l": 1.5, "thumb_03_l": 1.6, "thumb_04_leaf_l": 1.6, "upperarm_r": 1.2, "lowerarm_r": 1.32, "hand_r": 1.42, "calf_r": 1.12, "foot_r": 1.12, "ball_r": 1.1, "ball_leaf_r": 1.15, "index_01_r": 1.12, "index_02_r": 1.8, "index_03_r": 1.9, "index_04_leaf_r": 1.9, "middle_01_r": 1.12, "middle_02_r": 1.8, "middle_03_r": 1.9, "middle_04_leaf_r": 1.9, "ring_01_r": 1.12, "ring_02_r": 1.8, "ring_03_r": 1.9, "ring_04_leaf_r": 1.9, "pinky_01_r": 1.12, "pinky_02_r": 1.8, "pinky_03_r": 1.9, "pinky_04_leaf_r": 1.9, "thumb_02_r": 1.5, "thumb_03_r": 1.6, "thumb_04_leaf_r": 1.6}
R = {"pelvis": [0.84, 0.76], "spine_01": [0.66, 0.5], "spine_02": [0.84, 0.74], "spine_03": [0.95, 0.82], "neck_01": [0.52, 0.55], "Head": [1, 1], "clavicle_l": [0.88, 0.88], "upperarm_l": [0.66, 0.66], "lowerarm_l": [0.68, 0.66], "hand_l": [0.8, 0.85], "thigh_l": [0.64, 0.64], "calf_l": [0.62, 0.62], "foot_l": [0.85, 0.85], "ball_l": [0.85, 0.8], "index_01_l": [0.72, 0.72], "index_02_l": [0.72, 0.72], "index_03_l": [0.72, 0.72], "middle_01_l": [0.72, 0.72], "middle_02_l": [0.72, 0.72], "middle_03_l": [0.72, 0.72], "ring_01_l": [0.72, 0.72], "ring_02_l": [0.72, 0.72], "ring_03_l": [0.72, 0.72], "pinky_01_l": [0.72, 0.72], "pinky_02_l": [0.72, 0.72], "pinky_03_l": [0.72, 0.72], "thumb_01_l": [0.72, 0.72], "thumb_02_l": [0.72, 0.72], "thumb_03_l": [0.72, 0.72], "clavicle_r": [0.88, 0.88], "upperarm_r": [0.66, 0.66], "lowerarm_r": [0.68, 0.66], "hand_r": [0.8, 0.85], "thigh_r": [0.64, 0.64], "calf_r": [0.62, 0.62], "foot_r": [0.85, 0.85], "ball_r": [0.85, 0.8], "index_01_r": [0.72, 0.72], "index_02_r": [0.72, 0.72], "index_03_r": [0.72, 0.72], "middle_01_r": [0.72, 0.72], "middle_02_r": [0.72, 0.72], "middle_03_r": [0.72, 0.72], "ring_01_r": [0.72, 0.72], "ring_02_r": [0.72, 0.72], "ring_03_r": [0.72, 0.72], "pinky_01_r": [0.72, 0.72], "pinky_02_r": [0.72, 0.72], "pinky_03_r": [0.72, 0.72], "thumb_01_r": [0.72, 0.72], "thumb_02_r": [0.72, 0.72], "thumb_03_r": [0.72, 0.72]}
MAIN = {"pelvis": "spine_01", "spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01", "neck_01": "Head", "clavicle_l": "upperarm_l", "upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l", "hand_l": "middle_01_l", "thigh_l": "calf_l", "calf_l": "foot_l", "foot_l": "ball_l", "ball_l": "ball_leaf_l", "index_01_l": "index_02_l", "index_02_l": "index_03_l", "index_03_l": "index_04_leaf_l", "middle_01_l": "middle_02_l", "middle_02_l": "middle_03_l", "middle_03_l": "middle_04_leaf_l", "ring_01_l": "ring_02_l", "ring_02_l": "ring_03_l", "ring_03_l": "ring_04_leaf_l", "pinky_01_l": "pinky_02_l", "pinky_02_l": "pinky_03_l", "pinky_03_l": "pinky_04_leaf_l", "thumb_01_l": "thumb_02_l", "thumb_02_l": "thumb_03_l", "thumb_03_l": "thumb_04_leaf_l", "clavicle_r": "upperarm_r", "upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r", "hand_r": "middle_01_r", "thigh_r": "calf_r", "calf_r": "foot_r", "foot_r": "ball_r", "ball_r": "ball_leaf_r", "index_01_r": "index_02_r", "index_02_r": "index_03_r", "index_03_r": "index_04_leaf_r", "middle_01_r": "middle_02_r", "middle_02_r": "middle_03_r", "middle_03_r": "middle_04_leaf_r", "ring_01_r": "ring_02_r", "ring_02_r": "ring_03_r", "ring_03_r": "ring_04_leaf_r", "pinky_01_r": "pinky_02_r", "pinky_02_r": "pinky_03_r", "pinky_03_r": "pinky_04_leaf_r", "thumb_01_r": "thumb_02_r", "thumb_02_r": "thumb_03_r", "thumb_03_r": "thumb_04_leaf_r"}
KNOB = ['calf', 'lowerarm', 'thigh', 'upperarm']

def load_gltf(path):
    g=json.load(open(path))
    d=os.path.dirname(path)
    bufs=[open(os.path.join(d,b['uri']),'rb').read() for b in g['buffers']]
    return g,bufs


def acc(g,bufs,i):
    a=g['accessors'][i]; bv=g['bufferViews'][a['bufferView']]
    dt=CT[a['componentType']]; n=NC[a['type']]
    off=bv.get('byteOffset',0)+a.get('byteOffset',0)
    stride=bv.get('byteStride',0)
    item=np.dtype(dt).itemsize*n
    raw=bufs[bv['buffer']]
    if stride and stride!=item:
        arr=np.array([np.frombuffer(raw,dt,n,off+k*stride) for k in range(a['count'])])
    else:
        arr=np.frombuffer(raw,dt,a['count']*n,off).reshape(a['count'],n) if n>1 else np.frombuffer(raw,dt,a['count'],off)
    return arr.copy()


def node_mat(n):
    M=np.eye(4)
    if 'matrix' in n: return np.array(n['matrix']).reshape(4,4).T
    t=n.get('translation',[0,0,0]); r=n.get('rotation',[0,0,0,1]); s=n.get('scale',[1,1,1])
    M[:3,:3]=Rot.from_quat(r).as_matrix()*np.array(s)
    M[:3,3]=t
    return M


def globals_(g):
    parent={}
    for i,n in enumerate(g['nodes']):
        for c in n.get('children',[]): parent[c]=i
    G={}
    def get(i):
        if i in G: return G[i]
        M=node_mat(g['nodes'][i])
        if i in parent: M=get(parent[i])@M
        G[i]=M; return M
    for i in range(len(g['nodes'])): get(i)
    return G,parent


def smoothstep(a,b,x): t=np.clip((x-a)/(b-a),0,1); return t*t*(3-2*t)


def bone_xform(name, p):
    Jb=jpos[name]; Jb2=newj[name]; q=p-Jb
    if name in MAIN:
        c=MAIN[name]; d=jpos[c]-Jb; L=np.linalg.norm(d); d=d/L; s=K.get(c,1.0)
    else:
        d=np.array([0,1.0,0]); s=1.0; L=1
    rx,rz=R.get(name,(1,1))
    ref=np.array([1.0,0,0]) if abs(d[0])<0.7 else np.array([0,1.0,0])
    e1=ref-d*np.dot(ref,d); e1/=np.linalg.norm(e1); e2=np.cross(d,e1)
    a=q@d; b1=q@e1; b2=q@e2
    if name=='Head': return Jb2+q
    rxv=np.full(len(a),rx); rzv=np.full(len(a),rz)
    if name.split('_')[0] in KNOB:
        t=a/L
        knob=np.exp(-((t-1.0)/0.12)**2)*0.9+np.exp(-((t-0.0)/0.1)**2)*0.5
        rxv=rxv+(1-rxv)*np.clip(knob,0,1)*0.55; rzv=rzv+(1-rzv)*np.clip(knob,0,1)*0.55
    return Jb2+np.outer(s*a,d)+(rxv*b1)[:,None]*e1+(rzv*b2)[:,None]*e2


def sculpt():
    newpos=np.zeros_like(pos)
    for k in range(4):
        for ji in np.unique(J[:,k]):
            m=(J[:,k]==ji)&(W[:,k]>0)
            if m.any(): newpos[m]+=W[m,k:k+1]*bone_xform(jn[ji],pos[m])
    newpos/=wsum
    wp=np.zeros((nw,3)); wp[weld]=newpos
    q=wp-H0
    fm=whw*np.maximum(smoothstep(0.015,0.07,q[:,2])*(1-smoothstep(0.13,0.17,q[:,1])), smoothstep(0.06,0.075,np.abs(q[:,0]))*(1-smoothstep(0.13,0.16,q[:,1]))*smoothstep(-0.01,0.03,q[:,1]))
    wp2=wp.copy()
    for it in range(80):
        lap=np.array([wp2[n].mean(0) for n in nbr]); wp2+=(lap-wp2)*(0.6*fm)[:,None]
    q=wp2-H0; q2=q.copy()
    up=np.maximum(q[:,1]-0.06,0)
    q2[:,1]+=0.22*up; q2[:,2]-=0.4*up; q2[:,0]*=1.0+0.25*up
    low=np.maximum(0.07-q[:,1],0)*smoothstep(-0.02,0.06,q[:,2])
    q2[:,1]-=0.35*low; q2[:,2]+=0.02*low
    return wp2+(q2-q)*whw[:,None]


def sculpt2():
    wp3=_sculpt0()
    q=wp3-H0
    face=whw*smoothstep(0.0,0.04,q[:,2])*(1-smoothstep(0.2,0.26,q[:,1]))
    zt=0.078*np.sqrt(np.clip(1-(q[:,0]/0.08)**2,0,1))+0.012 - 0.03*np.clip((0.02-q[:,1])/0.08,0,1)
    znew=np.where(q[:,2]>zt, zt+(q[:,2]-zt)*0.15, q[:,2])
    q[:,2]=q[:,2]+(znew-q[:,2])*face
    wp4=H0+q
    # relax the flattened region a bit
    fm=face*0.5
    for it in range(15):
        lap=np.array([wp4[n].mean(0) for n in nbr]); wp4+=(lap-wp4)*(0.5*fm)[:,None]
    return wp4


def vnormals(Pw_unw):
    tri=Pw_unw[idx]
    fn=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0])
    acc_=np.zeros((nw,3))
    for k in range(3): np.add.at(acc_,weld[idx[:,k]],fn)
    acc_/=np.linalg.norm(acc_,axis=1,keepdims=True)+1e-12
    return acc_[weld]


def uv_raster(res, attrs):
    """attrs: list of (n,C) per-vertex arrays; returns maps (res,res,C) and mask, plus tri id"""
    U=uv[:,0]*res; V=uv[:,1]*res
    outs=[np.zeros((res,res,a.shape[1])) for a in attrs]; mask=np.zeros((res,res),bool); tid=np.full((res,res),-1)
    for t,(a,b,c) in enumerate(idx):
        xs=np.array([U[a],U[b],U[c]]); ys=np.array([V[a],V[b],V[c]])
        x0,x1=int(max(0,np.floor(xs.min()-1))),int(min(res-1,np.ceil(xs.max()+1))); y0,y1=int(max(0,np.floor(ys.min()-1))),int(min(res-1,np.ceil(ys.max()+1)))
        gx,gy=np.meshgrid(np.arange(x0,x1+1)+0.5,np.arange(y0,y1+1)+0.5)
        d=(ys[1]-ys[2])*(xs[0]-xs[2])+(xs[2]-xs[1])*(ys[0]-ys[2])
        if abs(d)<1e-12: continue
        l0=((ys[1]-ys[2])*(gx-xs[2])+(xs[2]-xs[1])*(gy-ys[2]))/d
        l1=((ys[2]-ys[0])*(gx-xs[2])+(xs[0]-xs[2])*(gy-ys[2]))/d
        l2=1-l0-l1
        eps=0.6/ max(1.0, np.sqrt(abs(d)))  # small dilation
        m=(l0>=-eps)&(l1>=-eps)&(l2>=-eps)
        m&=~mask[y0:y1+1,x0:x1+1] | ((l0>=0)&(l1>=0)&(l2>=0))
        for o,A in zip(outs,attrs):
            val=l0[...,None]*A[a]+l1[...,None]*A[b]+l2[...,None]*A[c]
            o[y0:y1+1,x0:x1+1][m]=val[m]
        mask[y0:y1+1,x0:x1+1]|=m; tid[y0:y1+1,x0:x1+1][m]=t
    return outs,mask,tid


def _hash(ix,iy,iz,seed):
    h=(ix*73856093) ^ (iy*19349663) ^ (iz*83492791) ^ (seed*2654435761)
    h=(h ^ (h>>13))*1274126177
    h=h ^ (h>>16)
    return (h & 0xffff)/65535.0


def vnoise(p,freq,seed=0):
    q=p*freq; i=np.floor(q).astype(np.int64); f=q-i; f=f*f*(3-2*f)
    out=0
    for dx in (0,1):
        for dy in (0,1):
            for dz in (0,1):
                w=(f[...,0] if dx else 1-f[...,0])*(f[...,1] if dy else 1-f[...,1])*(f[...,2] if dz else 1-f[...,2])
                out=out+w*_hash(i[...,0]+dx,i[...,1]+dy,i[...,2]+dz,seed)
    return out


def fbm(p,freq,oct=4,seed=0):
    s=0;a=1;t=0
    for o in range(oct):
        s=s+a*vnoise(p,freq*(2**o),seed+o*17); t+=a; a*=0.5
    return s/t


def height(O):
    x=O[...,0]; y=O[...,1]; z=O[...,2]; ax=np.abs(x)
    h=np.zeros(x.shape)
    torso=smoothstep(0.02,0.05,ax)*(1-smoothstep(0.17,0.2,ax))*smoothstep(1.08,1.14,y)*(1-smoothstep(1.36,1.42,y))
    front_side=smoothstep(-0.09,-0.02,z)
    for k in range(8):
        yk=1.355-k*0.03-0.55*ax**1.35+0.04*smoothstep(0.0,0.12,-z)  # rise toward the back
        h+=0.9*np.exp(-((y-yk)/0.0085)**2)
    h*=torso*front_side
    # costal margin cut: front lower ribs only outside a V
    vcut=smoothstep(0.0,0.03, ax-(1.30-y)*0.9)
    h*=np.where(z>0.06, vcut, 1.0)
    # sternum + collarbones
    h+=0.7*np.exp(-(x/0.012)**2)*smoothstep(1.22,1.26,y)*(1-smoothstep(1.42,1.45,y))*smoothstep(0.05,0.09,z)
    cl=1.46+0.12*ax-0.0
    h+=0.9*np.exp(-((y-cl)/0.012)**2)*smoothstep(0.02,0.04,ax)*(1-smoothstep(0.17,0.2,ax))*smoothstep(0.0,0.05,z)
    # vertebrae
    vb=0.5+0.5*np.cos((y-1.0)/0.031*2*np.pi)
    h+=0.8*np.exp(-(x/0.018)**2)*vb**2*smoothstep(0.95,1.0,y)*(1-smoothstep(1.55,1.6,y))*smoothstep(-0.02,-0.07,z)
    # scapula ridges
    h+=0.5*np.exp(-((ax-0.1-(1.45-y)*0.15)/0.012)**2)*smoothstep(1.28,1.32,y)*(1-smoothstep(1.46,1.5,y))*smoothstep(-0.03,-0.08,z)
    # veins and sinew
    vn=1-np.abs(fbm(O,8.0,3,9)*2-1)
    h+=0.35*smoothstep(0.88,0.97,vn)
    h+=0.12*fbm(O,60.0,2,3)
    return h


def grad(O,eps=0.0015):
    gx=(height(O+[eps,0,0])-height(O-[eps,0,0]))/(2*eps)
    gy=(height(O+[0,eps,0])-height(O-[0,eps,0]))/(2*eps)
    gz=(height(O+[0,0,eps])-height(O-[0,0,eps]))/(2*eps)
    return np.stack([gx,gy,gz],-1)


def build_normal(amp=0.006):
    N_=Nm[M]; N_/=np.linalg.norm(N_,axis=1,keepdims=True)+1e-12
    T_=Tm[M]; T_=T_-N_*np.sum(T_*N_,1,keepdims=True); T_/=np.linalg.norm(T_,axis=1,keepdims=True)+1e-12
    B_=np.cross(N_,T_); sgn=np.sign(np.sum(B_*Bm[M],1,keepdims=True)); B_=B_*sgn
    g_=Gd*amp; g_=g_-N_*np.sum(g_*N_,1,keepdims=True)
    nn_=N_-g_; nn_/=np.linalg.norm(nn_,axis=1,keepdims=True)
    ts=np.stack([np.sum(nn_*T_,1), np.sum(nn_*B_,1), np.sum(nn_*N_,1)],1)
    base=np.asarray(Image.open(UBC+"../Textures/Normals Unity - Godot/T_Superhero_Male_Normal.png").convert("RGB").resize((RES,RES),Image.LANCZOS)).astype(np.float64)/127.5-1
    bf=base[M].copy()
    hwt=whw[weld[idx[TID[M],0]]]
    x=Of[:,0]; y=Of[:,1]; z=Of[:,2]; ax=np.abs(x)
    mute=np.clip(hwt*1.2,0,1)
    belly=smoothstep(0.95,1.05,y)*(1-smoothstep(1.24,1.3,y))*(1-smoothstep(0.12,0.16,ax))*smoothstep(0.0,0.05,z)
    pec=smoothstep(1.28,1.32,y)*(1-smoothstep(1.46,1.5,y))*(1-smoothstep(0.17,0.2,ax))*smoothstep(0.02,0.07,z)
    k=np.clip(1-mute,0,1)*(1-0.75*belly)*(1-0.45*pec)
    bf[:,:2]*=k[:,None]*1.1
    out=np.stack([bf[:,0]+ts[:,0], bf[:,1]+ts[:,1], np.maximum(bf[:,2],0.2)*ts[:,2]],1); out/=np.linalg.norm(out,axis=1,keepdims=True)
    nimg=np.zeros((RES,RES,3)); nimg[...,2]=1; nimg[M]=out
    return ((nimg*0.5+0.5)*255).clip(0,255).astype(np.uint8)


def make_textures():
    global nimg, albimg, rimg, ragimg
    nimg=build_normal()
    y=Of[:,1]
    hwt=whw[weld[idx[TID[M],0]]][:,None]
    base=srgb((38,37,35))*np.ones((len(Of),1))
    base=base*(0.7+0.6*mott[:,None])
    bruise=smoothstep(0.55,0.75,fbm(Pf,2.5,3,21))[:,None]
    base=base*(1-0.5*bruise)+srgb((48,30,36))*0.5*bruise
    grn=smoothstep(0.5,0.7,fbm(Pf,3.5,3,23))[:,None]; base=base*(1-0.35*grn)+srgb((34,40,30))*0.35*grn
    base*= (0.82+0.36*fine[:,None])
    vm=smoothstep(0.9,0.97,vein)[:,None]; base=base*(1-0.45*vm)+srgb((22,26,34))*0.45*vm
    ext=smoothstep(0.6,0.95,np.abs(Of[:,0]))[:,None]*0.65 + smoothstep(0.25,0.05,y)[:,None]*0.55
    base*=(1-0.6*np.clip(ext,0,1))
    hb=(H_f-np.median(H_f)); base*= (1+0.35*np.clip(hb,-0.6,1.0))[:,None]
    cav=np.clip((0.97-bn[M][:,2])*6,0,1)[:,None]; base*=(1-0.45*cav)
    pt=pit[weld[idx[TID[M],0]]][:,None]
    base=base*(1-0.55*hwt)+srgb((74,68,62))*(0.55*hwt)*(0.8+0.4*mott[:,None])
    base*=(1-0.8*np.clip(pt*1.5,0,1))
    alb=np.zeros((RES,RES,3)); alb[M]=base; albimg=(np.clip(alb,0,1)*255).astype(np.uint8)
    rough=0.62+0.22*fbm(Pf,6.0,3,33)
    wet=smoothstep(0.55,0.72,vnoise(Pf*[1,0.12,1],14.0,41)); rough=rough-0.25*wet+0.1*np.clip(ext[:,0],0,1)
    rimg=np.full((RES,RES),0.7); rimg[M]=np.clip(rough,0.25,0.9); rimg=(rimg*255).astype(np.uint8)
    Ra=rag_alpha(Of)*rag_region(Of)
    grime=fbm(Pf,5.0,4,71)[:,None]
    lum=ex_bc[M].mean(1,keepdims=True)
    rc=(ex_bc[M]*0.5+lum*0.5)*np.array([0.48,0.34,0.25])*(0.35+0.7*grime)
    stain=smoothstep(0.5,0.68,fbm(Pf,3.0,3,73))[:,None]; rc=rc*(1-0.7*stain)+np.array([0.04,0.035,0.03])*0.7*stain
    ri=np.zeros((RES,RES,4)); ri[M,:3]=rc; ri[M,3]=Ra
    ragimg=(np.clip(ri,0,1)*255).astype(np.uint8)


def rag_region(O):
    x=O[...,0]; y=O[...,1]; ax=np.abs(x)
    return (y>0.9)&(y<1.16)&(ax<0.3)


def rag_alpha(O):
    x=O[...,0]; y=O[...,1]; ax=np.abs(x)
    a=np.ones(x.shape)
    a*= (fbm(O,6.0,4,51)<0.62)
    a*= (fbm(O,22.0,3,57)<0.7)
    hem=0.97+0.1*fbm(O*np.array([1,0.07,1]),18.0,3,61)
    a*= (y>hem)
    top=1.08+0.06*fbm(O*np.array([1,0.3,1]),9.0,3,67)
    a*= (y<top)
    return a


def face_vnorm(Pp,F):
    tri=Pp[F]; fn=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]); a=np.zeros_like(Pp)
    for k in range(3): np.add.at(a,F[:,k],fn)
    return a/(np.linalg.norm(a,axis=1,keepdims=True)+1e-12)


def ribbon(top_o, L, w0, segs, side, sway, bulge, uvc, twist=0.0):
    d,vi=tree.query(top_o)
    top=REST[vi]+(LOOSE[vi]-REST[vi])*0.8+NRM[vi]*0.02
    outd=NRM[vi].copy(); outd[1]=0; outd/=np.linalg.norm(outd)+1e-9
    tang=np.cross(np.array([0,1.0,0]),outd)
    base_i=len(strips_p)
    for s_ in range(segs+1):
        t=s_/segs
        c=top+np.array([0,-L*t,0])+outd*(0.012*t+bulge*t*t)+tang*sway*np.sin(t*3)
        ww=w0*(1-0.55*t)
        tg=tang*np.cos(twist*t)+outd*np.sin(twist*t)
        for sgn in (-1,1):
            jag=0 if s_<segs else rng.uniform(-0.05,0.0)
            strips_p.append(c+tg*ww*0.5*sgn+np.array([0,jag,0]))
            strips_uv.append(uvc+np.array([0.012*sgn,0.03*t]))
            strips_j.append([jidx['pelvis'],jidx['thigh_'+side],0,0]); strips_w.append([1-0.8*t,0.8*t,0,0])
    for s_ in range(segs):
        i0=base_i+s_*2; strips_i.extend([[i0,i0+2,i0+1],[i0+1,i0+2,i0+3]])


def write_keeper_gltf():
    ng=copy.deepcopy(g)
    nodes=ng['nodes']
    for i,n in enumerate(nodes):
        if n['name'] in K and 'translation' in n:
            n['translation']=[float(v*K[n['name']]) for v in n['translation']]
    G2,_=globals_(ng)
    for k,j in enumerate(joints):
        assert np.allclose(G2[j][:3,3],newj[nn(j)],atol=1e-5), nn(j)
    buf=bytearray(); views=[]; accs=[]
    def add(arr, comp, typ, target=None, minmax=False):
        arr=np.ascontiguousarray(arr)
        while len(buf)%4: buf.append(0)
        off=len(buf); b=arr.tobytes(); buf.extend(b)
        v={'buffer':0,'byteOffset':off,'byteLength':len(b)}
        if target: v['target']=target
        views.append(v)
        a={'bufferView':len(views)-1,'componentType':comp,'count':int(arr.shape[0]),'type':typ}
        if minmax: a['min']=arr.min(0).tolist(); a['max']=arr.max(0).tolist()
        accs.append(a); return len(accs)-1
    def prim(Pp,Nn,UV,Jj,Ww,F,mat):
        Ww=Ww/Ww.sum(1,keepdims=True)
        return {'attributes':{'POSITION':add(Pp.astype(np.float32),5126,'VEC3',34962,True),
                              'NORMAL':add(Nn.astype(np.float32),5126,'VEC3',34962),
                              'TEXCOORD_0':add(UV.astype(np.float32),5126,'VEC2',34962),
                              'JOINTS_0':add(Jj.astype(np.uint16),5123,'VEC4',34962),
                              'WEIGHTS_0':add(Ww.astype(np.float32),5126,'VEC4',34962)},
                'indices':add(F.astype(np.uint32).ravel(),5125,'SCALAR',34963),'material':mat}
    meshes=[{'name':'KeeperBody','primitives':[prim(REST,NRM,uv,J,W,idx,0)]},
            {'name':'KeeperRags','primitives':[prim(SHP,SHN,SHUV,SHJ,SHW,shell_idx,1),prim(strips_p,strips_n,strips_uv,strips_j,strips_w,strips_i,2)]}]
    G2inv=[np.linalg.inv(G2[j]).T.astype(np.float32) for j in joints]
    ibm=add(np.array(G2inv).reshape(len(joints),16),5126,'MAT4')
    ng['skins'][0]['inverseBindMatrices']=ibm
    # nodes: replace mesh nodes
    arm=name2node['Armature']
    keep=[i for i in nodes[arm]['children'] if nodes[i]['name'] not in ('Eyebrows','Eyes','SuperHero_Male')]
    sm=name2node['SuperHero_Male']
    nodes[sm]={'name':'KeeperBody','mesh':0,'skin':0}
    nodes[name2node['Eyebrows']]={'name':'KeeperRags','mesh':1,'skin':0}
    nodes[name2node['Eyes']]={'name':'Unused'}
    nodes[arm]['children']=keep+[sm,name2node['Eyebrows']]
    ng['meshes']=meshes
    ng['materials']=[
        {'name':'M_KeeperSkin','pbrMetallicRoughness':{'baseColorTexture':{'index':0},'metallicFactor':0,'roughnessFactor':0.5},'normalTexture':{'index':1}},
        {'name':'M_KeeperRag','doubleSided':True,'alphaMode':'MASK','alphaCutoff':0.5,'pbrMetallicRoughness':{'baseColorTexture':{'index':2},'metallicFactor':0,'roughnessFactor':0.9},'normalTexture':{'index':3}},
        {'name':'M_KeeperStrip','doubleSided':True,'pbrMetallicRoughness':{'baseColorTexture':{'index':2},'metallicFactor':0,'roughnessFactor':0.9}}]
    ng['images']=[{'uri':'T_Keeper_BaseColor.png'},{'uri':'T_Keeper_Normal.png'},{'uri':'T_KeeperRag_BaseColor.png'},{'uri':'T_KeeperRag_Normal.png'}]
    ng['textures']=[{'source':i,'sampler':0} for i in range(4)]
    ng['samplers']=[{'magFilter':9729,'minFilter':9987}]
    ng['bufferViews']=views; ng['accessors']=accs
    ng['buffers']=[{'uri':'Keeper.bin','byteLength':len(buf)}]
    ng.pop('animations',None)
    json.dump(ng,open(OUT+"/Keeper.gltf","w"))
    open(OUT+"/Keeper.bin","wb").write(bytes(buf))
    return len(buf)


def write_textures():
    Image.fromarray(albimg).save(OUT+"/T_Keeper_BaseColor.png")
    Image.fromarray(nimg).save(OUT+"/T_Keeper_Normal.png")
    Image.fromarray(rimg).save(OUT+"/T_Keeper_Roughness.png")
    Image.fromarray(ragimg).save(OUT+"/T_KeeperRag_BaseColor.png")
    Image.fromarray(ex_n).save(OUT+"/T_KeeperRag_Normal.png")


def rebuild_all():
    global Pm,Nm,Tm,Bm,Om,Lm,Mk,TID,M,Pf,Of,mott,fine,vein,H_f,Gd,nimg,albimg,rimg,ragimg,SHP,SHN,SHUV,SHJ,SHW,shell_idx,LOOSE,TAN,BIT
    tri=REST[idx]; tuv=uv[idx]
    e1=tri[:,1]-tri[:,0]; e2=tri[:,2]-tri[:,0]; d1=tuv[:,1]-tuv[:,0]; d2=tuv[:,2]-tuv[:,0]
    r=1.0/(d1[:,0]*d2[:,1]-d2[:,0]*d1[:,1]+1e-12)
    Tt=(e1*d2[:,1:2]-e2*d1[:,1:2])*r[:,None]; Bt=(e2*d1[:,0:1]-e1*d2[:,0:1])*r[:,None]
    TAN=np.zeros_like(REST); BIT=np.zeros_like(REST)
    for k in range(3): np.add.at(TAN,idx[:,k],Tt); np.add.at(BIT,idx[:,k],Bt)
    (Pm,Nm,Tm,Bm,Om,Lm),Mk,TID=uv_raster(RES,[REST,NRM,TAN,BIT,pos,LOOSE]); M=Mk
    Pf=Pm[M]; Of=Om[M]
    mott=fbm(Pf,4.0,4,1); fine=fbm(Pf,40.0,3,5); vein=1-np.abs(fbm(Pf,9.0,3,9)*2-1)
    H_f=height(Of); Gd=grad(Of)


if __name__ == "__main__":
    # NOTE: this file was assembled from the look-dev session that produced the shipped
    # asset; the driver below reproduces that run's final pass.
    g, bufs = load_gltf(UBC + "Superhero_Male_FullBody.gltf")
    G, parent = globals_(g)
    raise SystemExit("see the function bodies above; the shipped asset is already in assets/characters/keeper/")
