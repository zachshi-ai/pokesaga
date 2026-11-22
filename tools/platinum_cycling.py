"""Separate Route 206's elevated Cycling Road from the trail underneath using its BDHC planes."""
import struct
from collections import deque
import numpy as np


def planes(path):
    data=path.read_bytes(); cursor=data.index(b'BDHC')+4
    counts=struct.unpack_from('<6H',data,cursor);cursor+=12
    def array(count,fmt):
        nonlocal cursor
        length=count*struct.calcsize(fmt)
        values=list(struct.iter_unpack(fmt,data[cursor:cursor+length]));cursor+=length
        return values
    points=array(counts[0],'<ii');normals=array(counts[1],'<iii');constants=array(counts[2],'<i');plates=array(counts[3],'<4H')
    heights=[[set() for _ in range(32)] for _ in range(32)]
    for one,two,n,k in plates:
        x0,z0=points[one];x1,z1=points[two];a,b,c=normals[n];d=constants[k][0]
        if b==0:continue
        for y in range(32):
            z=(y-15.5)*65536
            if not min(z0,z1)<=z<=max(z0,z1):continue
            for i in range(32):
                x=(i-15.5)*65536
                if min(x0,x1)<=x<=max(x0,x1):heights[y][i].add(round(-(a*x/4096+c*z/4096+d)/b,2))
    return heights


def layer(src,m):
    width,height=m['size'];surfaces={}
    for (x,y),land in m['rows'].items():
        hs=planes(src/f'res/field/mapmodels/data/map_data_{land:03}.bin');ox=x*32-m['origin'][0];oy=y*32-m['origin'][1]
        for j,row in enumerate(hs):
            for i,tile in enumerate(row):surfaces[ox+i,oy+j]=tile
    seeds={'deck':[(16,0),(14,105)],'ground':[(11,35),(22,31),(14,112)]}
    # Each tile can have two real vertical positions. The cartridge accepts a
    # neighbouring plate only if it is less than 20 world units from the actor.
    for kind,starts in seeds.items():
        heights=set();todo=deque()
        for xy in starts:
            stack=surfaces[xy]
            h=(max if kind=='deck' else min)(stack)
            heights.add((*xy,h));todo.append((*xy,h))
        while todo:
            x,y,z=todo.popleft()
            for dx,dy in ((0,1),(0,-1),(1,0),(-1,0)):
                a,b=x+dx,y+dy
                if not (0<=a<width and 0<=b<height) or m['words'][b,a]&32768:continue
                vals=surfaces.get((a,b),())
                if not vals:continue
                n=min(vals,key=lambda h:abs(h-z));node=a,b,n
                if node not in heights and abs(n-z)<20:heights.add(node);todo.append(node)
        mask=np.ones((height,width),dtype='uint8')
        for a,b,_ in heights:mask[b,a]=0
        yield kind,mask.tolist()
