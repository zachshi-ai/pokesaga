"""Pose the ORAS field mesh in model space and bake nine orthographic walk frames."""
import argparse
import re
from math import cos, sin, radians
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
FRAME = 72
OVERSAMPLE = 3


def rotation(x=0., y=0., z=0.):
    rx = np.array([[1,0,0],[0,cos(x),-sin(x)],[0,sin(x),cos(x)]])
    ry = np.array([[cos(y),0,sin(y)],[0,1,0],[-sin(y),0,cos(y)]])
    rz = np.array([[cos(z),-sin(z),0],[sin(z),cos(z),0],[0,0,1]])
    return rz @ ry @ rx


def read_mesh(root):
    lines = (root/'BrendanOW.SMD').read_text().splitlines()
    nodes = []
    for line in lines[lines.index('nodes')+1:]:
        if line == 'end':
            break
        idx, name, parent = re.fullmatch(r'\s*(\d+) "(.*)"\s+(-?\d+)',line).groups()
        nodes.append((name,int(parent)))
    bind = []
    for line in lines[lines.index('time 0')+1:]:
        if line == 'end':
            break
        idx,x,y,z,rx,ry,rz = map(float,line.split())
        mat = np.eye(4)
        mat[:3,:3] = rotation(rx,ry,rz)
        mat[:3,3] = [x,y,z]
        parent = nodes[int(idx)][1]
        bind.append(bind[parent] @ mat if parent >= 0 else mat)
    textures, faces, xyz, normals, uv, weights = {}, [], [], [], [], []
    for model in ('BrendanOW.SMD','BrendanOW_ShoesA.SMD'):
        source = (root/model).read_text().splitlines()
        triangles = iter(source[source.index('triangles')+1:])
        for material in triangles:
            if material == 'end':
                break
            if material not in textures:
                textures[material] = np.asarray(Image.open(root/'images'/material).convert('RGBA'))
            faces.append(material)
            for _ in range(3):
                row = list(map(float,next(triangles).split()))
                xyz.append([*row[1:4],1])
                normals.append(row[4:7])
                uv.append(row[7:9])
                w = np.zeros(len(nodes))
                for bone, weight in zip(row[10::2],row[11::2]):
                    w[int(bone)] = weight
                if not w.any():
                    w[int(row[0])] = 1
                weights.append(w)
    return nodes,bind,textures,faces,np.array(xyz),np.array(normals),np.array(uv),np.array(weights)


def frame(mesh, yaw, step):
    nodes, bind, textures, faces, xyz, normals, uv, weights = mesh
    overrides = {}
    for sign, side in ((1,'L'),(-1,'R')):
        # Shoulder and hip swing in opposite phases.
        overrides[side+'ArmA'] = rotation(x=radians(sign*step*17)) @ rotation(y=radians(sign*70))
        overrides[side+'Thigh'] = rotation(x=radians(-sign*step*24))
        overrides[side+'Leg'] = rotation(x=radians(max(0, sign*step)*13))
    transforms = []
    posed = np.zeros((len(xyz),3))
    lighting = np.zeros_like(posed)
    for i,(name,parent) in enumerate(nodes):
        mat = np.eye(4)
        if name in overrides:
            rot = overrides[name]
            pivot = bind[i][:3,3]
            mat[:3,:3], mat[:3,3] = rot, pivot - rot @ pivot
        transforms.append(transforms[parent] @ mat if parent >= 0 else mat)
        used = weights[:,i] > 0
        if used.any():
            w = weights[used,i,None]
            posed[used] += np.einsum("ij,kj->ik", xyz[used], transforms[i][:3,:])*w
            lighting[used] += np.einsum("ij,kj->ik", normals[used], transforms[i][:3,:3])*w
    angle, pitch = radians(yaw), radians(19)
    right = np.array([cos(angle),sin(angle),0])
    toward = np.array([sin(angle)*cos(pitch),-cos(angle)*cos(pitch),sin(pitch)])
    up = np.cross(toward,right)
    side = FRAME*OVERSAMPLE
    scale = 1.84*OVERSAMPLE
    screen = np.stack([side*.5+np.sum(posed*right,axis=1)*scale,side*.92-np.sum(posed*up,axis=1)*scale,np.sum(posed*toward,axis=1)],axis=1)
    diffuse = np.clip(.86 + .19*np.sum(lighting*(toward*.66+up*.56-right*.33),axis=1),.70,1.08)
    output = np.zeros((side,side,4),dtype='uint8')
    depth = np.full((side,side),-np.inf)
    for i,material in enumerate(faces):
        tri = slice(3*i,3*i+3)
        a,b,c = screen[tri]
        x0,y0 = np.maximum(0,np.floor(np.min([a[:2],b[:2],c[:2]],axis=0)).astype(int))
        x1,y1 = np.minimum(side,np.ceil(np.max([a[:2],b[:2],c[:2]],axis=0)).astype(int)+1)
        denom = (b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
        if x0>=x1 or y0>=y1 or abs(denom)<1.e-6:
            continue
        yy,xx = np.mgrid[y0:y1,x0:x1]+.5
        u = ((b[1]-c[1])*(xx-c[0])+(c[0]-b[0])*(yy-c[1]))/denom
        v = ((c[1]-a[1])*(xx-c[0])+(a[0]-c[0])*(yy-c[1]))/denom
        w = 1-u-v
        z = u*a[2]+v*b[2]+w*c[2]
        dest_z = depth[y0:y1,x0:x1]
        keep = (u>=0)&(v>=0)&(w>=0)&(z>dest_z)
        if not keep.any():
            continue
        phi = np.stack([u[keep],v[keep],w[keep]],axis=1)
        tex = textures[material]
        coords = np.einsum("ij,jk->ik",phi,uv[tri])
        tx = np.floor((coords[:,0]%1)*tex.shape[1]).astype(int)%tex.shape[1]
        ty = np.floor((-coords[:,1]%1)*tex.shape[0]).astype(int)%tex.shape[0]
        pixels = tex[ty,tx].copy()
        pixels[:,:3] = np.clip(pixels[:,:3]*np.sum(phi*diffuse[tri],axis=1)[:,None],0,255)
        ys,xs = np.nonzero(keep)
        opaque = pixels[:,3]>100
        ys,xs = ys[opaque],xs[opaque]
        output[y0+ys,x0+xs] = pixels[opaque]
        dest_z[ys,xs] = z[ys,xs]
    return Image.fromarray(output).resize((FRAME,FRAME),Image.Resampling.LANCZOS)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path, help='BrendanOW directory with SMD files and images/')
    args = parser.parse_args()
    mesh = read_mesh(args.source)
    sheet = Image.new('RGBA',(FRAME*9,FRAME))
    for i,(direction,pose) in enumerate([(0,0),(180,0),(90,0),(0,-1),(0,1),(180,-1),(180,1),(90,-1),(90,1)]):
        sheet.paste(frame(mesh,direction,pose),(i*FRAME,0))
    dest = ROOT/'assets/oras/actors/brendan_walk.png'
    dest.parent.mkdir(exist_ok=True,parents=True)
    sheet.save(dest)


if __name__ == '__main__':
    main()
