"""Plan walking inputs through the eight original Trick House puzzle rooms."""
from hoenn_gym_route import DIRS,search
from hoenn_field_route import cavern_plan

def button_path(p,target):
 f=p.routes.fields[p.pos[0]];m=f.data['mechanisms'];base=f.data['physics']['collision'];n=int(p.pos[0][-1])
 states=m.get('trick_shutters',[]);local=p.state['gym_local'];pressed=local.get('trick_buttons',{})
 first=int(local.get('shutter',0));mask=sum(1<<(int(i)-1) for i in pressed)
 buts={tuple(map(int,xy.split(','))):num for xy,num in m['trick_buttons'].items()}
 covers=[{(x,y):b for x,y,_,_,b in rows} for rows in states]
 changes={int(i):{(x,y):b for x,y,_,_,b in rows} for i,rows in m['button_tiles'].items()}
 actors={tuple(a[0]) for a in p.state['actors']}
 def edges(st):
  x,y,sh,buttons=st
  for k,(dx,dy) in DIRS.items():
   a,b=x+dx,y+dy
   if not(0<=a<f.w and 0<=b<f.h) or (a,b) in actors or (a,b) in ((0,21),(1,21)) and k=='d':continue
   blocked=base[b][a]
   for i,tiles in changes.items():
    if buttons & 1<<(i-1):blocked=tiles.get((a,b),blocked)
   if covers:blocked=covers[sh].get((a,b),blocked)
   if blocked:continue
   key=buts.get((a,b));newbuttons=buttons;newsh=sh
   if key and not (buttons & 1<<(key-1)):
    if n==3:newbuttons=1<<(key-1);newsh=1-sh
    else:newbuttons|=1<<(key-1)
   yield k,(a,b,newsh,newbuttons)
 route=search((*p.pos[1:],first,mask),lambda s:tuple(s[:2]) in target,edges)
 rocks={tuple(o['at']) for o in f.data['objects'] if o['kind']=='rock'}
 for k,xy in route:
  if xy in rocks:p.do('face',dir=k)
  p.do('walk',legs=[[k,[p.pos[0],*xy]]])
  assert p.pos[1:]==xy,('press route',n,k,xy,p.pos,p.state['dialog'])

def goal(p,target):
 m=p.pos[0]; f=p.routes.fields[m];n=int(m[-1])
 if n in (2,3):return button_path(p,target)
 if n in (6,7):
  from hoenn_gym_route import fortree,mossdeep
  for xy in sorted(target):
   if 0<=xy[0]<f.w and 0<=xy[1]<f.h and not f.get('collision',*xy):
    try:(fortree if n==6 else mossdeep)(p,xy);return
    except ValueError:continue
  raise ValueError((m,target,'puzzle goal'))
 if n==4:
  # Use the current positions, including stones pushed on the way to the scroll.
  from copy import copy
  f2=copy(f);f2.data=dict(f.data);f2.data['objects']=[dict(o) for o in f.data['objects']]
  displaced=getattr(p,'trick_rocks',{})
  for ob in f2.data['objects']:
   if ob['kind']=='boulder':ob['at']=displaced.get(tuple(ob['at']),ob['at'])
  candidates=[xy for xy in target if 0<=xy[0]<f.w and 0<=xy[1]<f.h and not f.get('collision',*xy)]
  for xy in candidates:
   try:plan=cavern_plan(f2,p.pos[1:],xy,{tuple(a[0]) for a in p.state['actors']});break
   except ValueError:continue
  else:raise ValueError(('no push solution',p.pos,target))
  for kind,k,pos in plan:
   if kind=='push':
    p.do('face',dir=k)
    origin=next((o for o,loc in displaced.items() if tuple(loc)==pos),pos)
    dx,dy=DIRS[k];displaced[origin]=(pos[0]+dx,pos[1]+dy)
   p.do('walk',legs=[[k,[m,*pos]]])
   assert p.pos[1:]==pos,('push',kind,k,pos,p.pos)
  p.trick_rocks=displaced;return
 return p.go({(m,*xy) for xy in target})
