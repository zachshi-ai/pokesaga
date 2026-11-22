"""Read Black's rail graph and Black 2's equivalent zone bindings."""
import struct
from unova_source import archive, read
BW_IDS={28:0,30:1,36:2,66:3,114:4,121:5,137:6,209:7,211:8,214:9,241:10,242:10,243:10,244:10,249:11,255:12,338:13,339:14,340:15,341:16}

def black_rails(src):
    members=archive(src.bw,'0/7/9');headers=archive(src.bw,'1/0/9')
    rails=[]
    for h in headers:
        i=struct.unpack('<HH',h)[0];raw=members[i];attr=members[i+len(headers)];_,start,end,lines_end,_,_=struct.unpack_from('<6I',raw,4)
        points=[]
        for row in struct.iter_unpack('<4I4I4i3iI48s',raw[start:end]):
            points.append({'position':dict(zip(('x','y','z'),row[12:15]))})
        lines=[];offset=4
        for row in struct.iter_unpack('<6I48s',raw[end:lines_end]):
            width,length=struct.unpack_from('<HH',attr,offset);offset+=4
            cells=struct.unpack_from('<%dI'%(width*length),attr,offset);offset+=width*length*4
            tiles=[[hex(v) for v in cells[j*width:(j+1)*width]] for j in range(length)]
            lines.append(dict(point_a=row[0],point_b=row[1],length=row[5],tiles=tiles))
        rails.append(dict(points=points,lines=lines))
    return rails
