"""Read Platinum's separate floating-platform collision archive and moving lift definitions."""
import json
import re
import struct
import numpy as np

def narc(p):
    data=p.read_bytes(); base=data.index(b'GMIF')+8
    return [data[base+a:base+b] for i in range(struct.unpack_from('<H',data,24)[0])
            for a,b in [struct.unpack_from('<II',data,28+i*8)]]

def load(src, fields, samples):
    path=src/'res/prebuilt/fielddata/tornworld'
    maps=narc(path/'tw_arc.narc'); attrs=narc(path/'tw_arc_attr.narc')
    headers=(src/'generated/map_headers.txt').read_text().splitlines()
    records={}
    shapes=json.loads((samples/'distortion_platforms.json').read_text())
    kinds=['small_platform','floating_blue_rock','medium_elevator_platform_1','medium_elevator_platform_2','medium_elevator_platform_sw','medium_moving_platform_1','medium_moving_platform_2','medium_elevator_platform_3','large_elevator_platform_1','medium_elevator_platform_4','horizontal_platform_1','vertical_platform_1','vertical_platform_2','horizontal_platform_2','rotated_platform_east','rotated_platform_west','large_elevator_platform_2','large_elevator_platform_3','large_elevator_platform_4','medium_elevator_platform_5']
    def surface(model,x,z):
        return [[x+dx,z+dz] for dx,dz in shapes.get('distortion_world_'+model,[])]

    for hid,idx,ox,alt,oz in struct.iter_unpack('<IHhhh',maps[0][4:]):
        key=headers[hid];row=fields[key];row['land_offset']=[ox,oz]
        xs,ys=zip(*row['rows']);row['size']=[max(128,ox+32*int(max(xs)+1)),max(128,oz+32*int(max(ys)+1))]
        data=maps[idx+1];_,p,j,c,g=struct.unpack_from('<5I',data)
        platforms=[];jumps=[]
        if p:
            for i in range(struct.unpack_from('<I',data,20)[0]):
                kind,at,x,y,z,sx,sy,sz,w,h=struct.unpack_from('<hH6h2H',data,24+i*20)
                platforms.append((kind,x,y,z,sx,sy,sz,np.frombuffer(attrs[at],'<u2').reshape(h,w)))
        if j:
            for i in range(struct.unpack_from('<I',data,20+p)[0]):
                handler,direction,_,x,y,z,sx,sy,sz,dx,dy,dz,*rest=struct.unpack_from('<Hhi6h10h',data,24+p+i*40)
                jumps.append((direction,x,y,z,sx,sz,dx,dy,dz))
        row['platform_cells']=[]
        if g:
            start=20+p+j+c; count=struct.unpack_from('<I',data,start)[0]
            for group,kind,x,y,z in struct.iter_unpack('<IHhhh',data[start+12:start+12+count*12]):
                if kind<len(kinds):row['platform_cells']+=surface(kinds[kind],x,z)
        records[key]=(platforms,jumps,[])
    overlay=(src/'src/overlay009/ov9_02249960.c').read_text()
    for floor,num,body in re.findall(r'static const DistWorldMovingPlatformTemplate sMovingPlatformMapTemplate(\w+?)_(\d+) = \{(.*?)\};',overlay,re.S):
        def field(name):return re.search(r'\.'+name+r' = (\w+)',body).group(1)
        k='MAP_HEADER_DISTORTION_WORLD_'+floor
        fields[k]['platform_cells']+=surface(field('propKind').removeprefix('PROP_KIND_').lower(),int(field('tileX'),0),int(field('tileZ'),0))
        records[k][2].append((int(field('index'),0),int(field('tileX'),0),int(field('tileZ'),0),field('elevatorDir').split('_')[-1],int(field('destIndex'),0)))
    # B2F horizontal platforms run event commands rather than elevator paths.
    # A carried player moves by the scripted offset then jumps three tiles onto
    # the far platform. Each return trip has a separate original trigger.
    b2=fields['MAP_HEADER_DISTORTION_WORLD_B2F'];b2['rides']=[]
    events=overlay.split('static const DistWorldEvent sMapEventsB2F[] = {',1)[1].split('};',1)[0]
    for trigger in re.findall(r'\{([^{}]+)\}',events):
        found=re.search(r'\.cmds = sMapEventB2F_(P\w+)',trigger)
        if not found:continue
        cmd=found.group(1)
        def number(body,field):return int(re.search(r'\.'+field+r' = ([-\w]+)',body)[1],0)
        x,z=number(trigger,'tileX'),number(trigger,'tileZ')
        move=next(part for part in re.findall(r'CmdParamsMovePlatform sMapEventCmdParamsB2F_'+cmd+r'_\d+ = \{([^}]+)',overlay) if '.movePlayer = TRUE' in part)
        dx,dz,face={'N':(0,-1,'up'),'S':(0,1,'down'),'E':(1,0,'right'),'W':(-1,0,'left')}[cmd[-1]]
        tx=x+number(move,'finalTileXOffset')+3*dx;tz=z+number(move,'finalTileZOffset')+3*dz
        b2['rides'].append((x,z,tx,tz,face))
    return records

def install(key,row,fields,all_records):
    platforms,jumps,lifts=all_records[key];phys=row['words'];warps=[]
    wall=next(((x,y,z,sy,sz) for kind,x,y,z,sx,sy,sz,grid in platforms if kind==2),None) if key.endswith('_B4F') else None
    for kind,x,y,z,sx,sy,sz,grid in platforms:
        if wall and kind==2:
            # Unfold this vertical wall into the unused space immediately to its
            # east. The player climbs nine elevations along its real 10x10 mask
            # before rotating onto the opposite plane above the inverted waterfall.
            for dz in range(sz+1):
                for dy in range(sy+1):
                    cell=int(grid[dz,dy]);phys[z+dz,x+1+dy]=cell
            continue
        for dz in range(sz+1):
            for dx in range(sx+1):
                i=dx if kind==0 else sx-dx if kind==3 else 0
                value=int(grid[dz,i])
                if kind in (1,2):
                    # A vertical walkable face is projected onto its XZ footprint.
                    walk=grid[dz,:sy+1];ok=walk[(walk&32768)==0]
                    if len(ok): value=int(ok[0])
                if not value&32768:phys[z+dz,x+dx]=value
    for x,z in row['platform_cells']:
        if 0<=x<phys.shape[1] and 0<=z<phys.shape[0]:phys[z,x]&=32767
    dirs=['up','down','left','right']
    def transfer(x,y,to,tx,ty,trigger,kind):
        phys[y,x]&=32767
        return {'at':[x,y],'trigger':trigger,'mechanism':kind,'to':{'region':'sinnoh','map':fields[to]['id'],'at':[tx,ty],'platinum_native':True}}
    def projected(x,y,z,on_wall):
        if wall and on_wall and x==wall[0]:return x+1+y-wall[1],z
        return x,z
    for d,x,y,z,sx,sz,dx,dy,dz in jumps:
        if not dx and not dz and not (wall and dy):continue
        for iz in range(sz+1):
            for ix in range(sx+1):
                px,pz=projected(x+ix,y,z+iz,wall and (dx==-1 or dy==1))
                tx,tz=projected(x+ix+dx,y+dy,z+iz+dz,wall and (dx==1 or dy==-1))
                if 0<=tx<phys.shape[1] and 0<=tz<phys.shape[0]:
                    warps.append(transfer(px,pz,key,tx,tz,dirs[d],'floating_jump'))
                    phys[tz,tx]&=32767
    for x,z,tx,tz,direction in row.get('rides',[]):
        warps.append(transfer(x,z,key,tx,tz,direction,'floating_ride'))
        phys[tz,tx]&=32767
    floor=key.split('_')[-1]
    for i,x,z,direction,dest in lifts:
        phys[z-1:z+2,x-1:x+2]=0
        if direction=='NONE':continue
        # One long elevator passes B4F on its way to B5F. Match the physical
        # shaft and the original destination platform index instead of floor arithmetic.
        opposite='UP' if direction=='DOWN' else 'DOWN'
        target,landing=next((k,lift) for k,(_,__,floor_lifts) in all_records.items() for lift in floor_lifts
                            if k!=key and lift[0]==dest and lift[1:3]==(x,z) and lift[3]==opposite)
        _,tx,tz,*_=landing
        warps.append(transfer(x,z,target,tx,tz,'panel','distortion_lift'))
    # The cartridge jumps across a gap of two cells instead of treating these as
    # a regular downhill ledge. The canonical source marks the facing lip.
    for z,x in zip(*np.nonzero(np.isin(phys&255,[90,91,92,93]))):
        dx,dz,face={90:(0,-1,'up'),91:(0,1,'down'),92:(-1,0,'left'),93:(1,0,'right')}[int(phys[z,x]&255)]
        sx,sz=int(x-dx),int(z-dz)
        for length in [2,3]:
            tx,tz=int(x+length*dx),int(z+length*dz)
            if 0<=tx<phys.shape[1] and 0<=tz<phys.shape[0] and not phys[tz,tx]&32768 and not phys[sz,sx]&32768:
                warps.append(transfer(sx,sz,key,tx,tz,face,'distortion_jump'));break
    # The inverted waterfall is a lateral input across two physical floors, not
    # an HM07 ascent. FieldSystem's movement handler starts it only while surfing.
    if floor in ('B4F','B5F'):
        target='MAP_HEADER_DISTORTION_WORLD_'+('B5F' if floor=='B4F' else 'B4F')
        for z in range(76,80):
            w=transfer(104,z,target,104,z,'right','reversed_waterfall')
            w['to']['surf_arrival']=True;warps.append(w);phys[z,104]=16
    if floor=='B7F':
        warps.append(transfer(89,57,'MAP_HEADER_DISTORTION_WORLD_GIRATINA_ROOM',15,25,'up','giratina_passage'))
        warps[-1]['to']['facing']='up'
    if key.endswith('GIRATINA_ROOM'):
        warps.append(transfer(15,25,'MAP_HEADER_DISTORTION_WORLD_B7F',89,57,'down','giratina_passage'))
        warps[-1]['to']['facing']='down'
    return warps
