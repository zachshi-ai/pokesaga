"""Draw the Sword/Shield story landmarks over 16-pixel Emerald field tiles."""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw
from kalos_gym_rooms import tile, sprite
from bake_emerald_field import pack
from galar_story_art import finish

ROOT=Path(__file__).resolve().parents[1]
MAPS=ROOT/"content/regions/galar/maps"
OUT=ROOT/"assets/galar/story"
OUT.mkdir(parents=True,exist_ok=True)
P=16
def read(mid):return json.loads((MAPS/(mid+'.json')).read_text())
def write(mid,content):(MAPS/(mid+'.json')).write_text(json.dumps(content,ensure_ascii=False,separators=(',',':'))+'\n')
def gate(at,mid,to):return {'at':list(at),'to':{'region':'galar','map':mid,'at':list(to)}}
class Site:
    def __init__(self,mid,title,size,kind,spawn):
        self.mid=mid;self.title=title;self.width,self.height=size;self.spawn=list(spawn)
        self.im=Image.new('RGB',(size[0]*P,size[1]*P));self.draw=ImageDraw.Draw(self.im)
        self.mask=np.zeros((size[1],size[0]),np.uint8)
        self.floor(0,0,*size,kind)
        self.mask[0,:]=self.mask[-1,:]=self.mask[:,0]=self.mask[:,-1]=1
        self.warps=[];self.signs=[]
    def floor(self,x,y,w,h,kind):
        surfaces={"galar_seafood":"arena_wood", "galar_circhester_grill":"arena_wood",
                  "galar_rose_suite":"office_tile","galar_rose_lift":"hall_tile",
                  "galar_energy_plant":"lab_tile","galar_tower_summit":"ruin_tile"}
        if kind in ("wood","floor","tiles") and self.mid in surfaces:
            ground=Image.open(ROOT/"assets/island_landmarks"/(surfaces[self.mid]+".png")).convert("RGB")
        else:
            ground=tile("grass" if kind=="verge" else kind)
        for j in range(y,y+h):
            for i in range(x,x+w):self.im.paste(ground,(i*P,j*P))
    def wall(self,kind='wall'):
        self.floor(0,0,self.width,2,kind);self.mask[:2,:]=1
    def piece(self,art,x,y,solid=True):
        a=sprite(art);dx=(x+.5)*P-a.width/2;dy=(y+1)*P-a.height
        self.im.paste(a,(int(dx),int(dy)),a)
        if solid:self.mask[y,x]=1
    def belt(self,x,y,w,h,color):
        r=(x*16,y*16,(x+w)*16-1,(y+h)*16-1);self.draw.rectangle(r,fill=color,outline='#5a504b',width=2)
        self.draw.rectangle((r[0]+4,r[1]+4,r[2]-4,r[3]-4),outline='#cbb17e',width=2)
    def door(self,at,dest,land,up=False):
        x,y=at;self.floor(x,y,1,1,'stairs')
        self.mask[y,x]=0;self.warps.append(dict(gate(at,dest,land),trigger='up' if up else 'down'))
    def sign(self,x,y,text):
        self.signs.append({'kind':'sign','at':[x,y],'text':text})
    def save(self,**kwargs):
        finish(self)
        self.im.save(OUT/(self.mid+'.png'),optimize=True)
        d=dict(name=self.title,size=[self.width,self.height],spawn=self.spawn,npcs=[],objects=self.signs,
            tiles=self.mask.tolist(),warps=self.warps,style='interior',biome='interior',galar_story_site=True,
            hoenn_art={'s':[self.width,self.height],'p':[],'t':pack(np.zeros(self.mask.shape,dtype='<u2')),'scene':['res://assets/galar/story/'+self.mid+'.png',0,0]})
        d.update(kwargs);write(self.mid,d)
def restaurant(mid,title,parent,back,maritime):
    s=Site(mid,title,(23,16),'wood',(11,13));s.wall()
    s.belt(8,3,7,10,'#346478' if maritime else '#a05e4e')
    for y in [5,10]:
        for x in [4,18]:
            s.piece('desk',x,y);s.piece('carebench',x,y+1)
    for x in [2,20]:s.piece('plant_indoor',x,3)
    s.piece('officecounter',11,3);s.piece('bookshelf',3,2);s.piece('bookshelf',19,2)
    # The fourth Hero tapestry in Bob's Your Uncle, port windows at the Captain's Table.
    for x in [7,13]:
        c=(x*16,11,x*16+45,44);s.draw.rectangle(c,fill='#5687a3' if maritime else '#866047',outline='#594444',width=3)
        if maritime:
            s.draw.rectangle((c[0]+3,30,c[2]-3,40),fill='#69a8b4')
            s.draw.line((c[0]+23,14,c[0]+23,41),fill='#d5cba5',width=2)
        else:
            s.draw.polygon([(c[0]+5,34),(c[0]+14,21),(c[0]+20,33)],fill='#cdab71')
            s.draw.line((c[0]+27,32,c[0]+36,19),fill='#e7c998',width=2)
    s.door((11,15),parent,back);s.save()
def lift():
    s=Site('galar_rose_lift','洛兹大厦・观景电梯',(19,15),'tiles',(9,12));s.wall()
    for x in [2,6,10,14]:
        s.draw.rectangle((x*16,8,(x+3)*16-2,49),fill='#486078',outline='#303e53',width=3)
        for j in range(5):s.draw.rectangle((x*16+4+j*7,36-j%3*5,x*16+8+j*7,46),fill='#263e59')
    s.belt(4,5,11,6,'#7c515d')
    for x in [2,16]:s.piece('console',x,6);s.piece('streetlamp_compact',x,10)
    s.door((9,14),'galar_rose',[11,3]);s.door((9,2),'galar_rose_suite',[11,14],True);s.save()
    s=Site('galar_rose_suite','洛兹大厦・会长办公室',(25,17),'floor',(11,14));s.wall()
    s.belt(8,5,9,10,'#865960')
    for x in range(2,23,3):
        s.draw.rectangle((x*16,4,x*16+30,42),fill='#667e93',outline='#364254',width=3)
        s.draw.line((x*16+5,10,x*16+22,10),fill='#a1b0b1',width=2)
    for x in [3,21]:s.piece('bookshelf',x,5);s.piece('plant_indoor',x,13)
    s.piece('officecounter',12,4);s.piece('carebench',5,10);s.piece('carebench',19,10)
    s.door((11,16),'galar_rose_lift',[9,3]);s.save()
def plant():
    s=Site('galar_energy_plant','拳关市・能源工厂',(33,24),'tiles',(16,21));s.wall('stone')
    s.belt(13,5,7,16,'#657675')
    for x in [4,25]:
        for y in [6,14]:
            xx=x*16;yy=y*16
            s.draw.rectangle((xx-3,yy-27,xx+52,yy+12),fill='#586371',outline='#313e4d',width=3)
            s.draw.ellipse((xx,yy-37,xx+48,yy-10),fill='#708493',outline='#35434c',width=3)
            for j in [4,11,18,25,32,39]:s.draw.line((xx+j,yy-17,xx+j,yy+7),fill='#bcc4bb',width=2)
            s.draw.ellipse((xx+10,yy-31,xx+37,yy-17),fill='#a95779',outline='#de91a3',width=2)
            s.mask[y-1:y+1,x:x+3]=1
        for y in range(4,20):
            s.draw.rectangle((x*16+16,y*16,x*16+21,y*16+15),fill='#657c82',outline='#344651')
    for x in [9,22]:s.piece('console',x,8);s.piece('console',x,16)
    s.door((16,23),'galar_hammerlocke_castle_room',[17,4]);s.door((16,2),'galar_tower_summit',[14,15],True)
    s.sign(22,16,'能源流向　反应炉 → 塔顶');s.save(galar_power_spot=True)
    s=Site('galar_tower_summit','拳关竞技场・塔顶',(29,21),'stone',(14,15))
    s.floor(2,3,25,15,'tiles');s.belt(7,6,15,9,'#71737c')
    for x in [3,7,11,17,21,25]:
        for y in [3,17]:s.piece('statue',x,y)
    for x in range(1,28):
        s.draw.rectangle((x*16,20,x*16+15,32),fill='#57616d',outline='#9095a0')
    s.door((14,20),'galar_energy_plant',[16,3]);s.save(galar_power_spot=True,biome='mountain',style='ruins')
def altar():
    s=Site('galar_weald_altar','微寐森林・英雄的石台',(29,21),'verge',(14,18))
    s.floor(5,4,19,11,'stone');s.floor(12,10,5,9,'trail_11')
    for y in [3,7,11,15,18]:
        for x in [2,26]:s.piece('tree',x,y)
    for x,y in [(7,5),(10,4),(18,4),(21,5),(5,13),(23,12)]:s.piece('rock',x,y)
    s.piece('statue',14,5);s.belt(12,7,5,2,'#89938b');s.mask[7:9,13:16]=1
    s.door((14,20),'galar_weald',[12,7]);s.save(biome='forest',style='forest')
def bay():
    s=Site('galar_circhester_bay','九号道路・战竞湾',(33,23),'verge',(12,4))
    sea=Image.new('RGB',(16,16))
    d=s.draw
    for y in range(1,22):
        for x in range(1,32):
            north=7 if 6<=x<=17 else (6 if x%9<4 else 5)
            south=14 if 5<=x<=16 else (15 if x%10<6 else 16)
            if north<y<south:
                s.floor(x,y,1,1,'sea');s.mask[y,x]=2
                if (x*13+y*7)%17==3:
                    a=x*16+3;b=y*16+6;d.line((a,b,a+5,b),fill='#9acccc');d.point((a+7,b-1),fill='#a3d1cf')
            elif y==north or y==south:s.floor(x,y,1,1,'ground')
    for x,y in [(2,4),(5,3),(19,3),(26,5),(25,18),(22,19),(4,18),(9,17)]:s.piece('rock',x,y)
    for x,y in [(2,2),(28,3),(30,19),(3,20)]:s.piece('tree',x,y)
    s.floor(11,1,3,6,'trail_11');s.floor(17,17,3,5,'trail_11')
    s.door((12,0),'galar_9',[19,41],True);s.door((18,22),'galar_spikemuth',[21,1])
    for w in s.warps:w['atlas']='world'
    s.save(style='coast',biome='coast')
    atlas=ROOT/'content/world_destinations.json'
    catalog=json.loads(atlas.read_text());region=catalog['regions']['galar'];bay_id=s.mid
    if not any(location['map']==bay_id for location in region['locations']):
        region['locations'].append({'id':bay_id,'name':'战竞湾','kind':'route','map':bay_id,'at':s.spawn,'pos':[7,7]})
    old_edge={'galar_9','galar_spikemuth'}
    region['connections']=[e for e in region['connections'] if set(e)!=old_edge]
    for neighbour in sorted(old_edge):
        edge=sorted([neighbour,bay_id])
        if edge not in region['connections']:region['connections'].append(edge)
    atlas.write_text(json.dumps(catalog,ensure_ascii=False,separators=(',',':'))+'\n')
    for mid,target,arrival in [('galar_9','galar_spikemuth',[12,4]),('galar_spikemuth','galar_9',[18,20])]:
        m=read(mid)
        for w in m['warps']:
            if w['to']['map']==target:w['to'].update(map='galar_circhester_bay',at=arrival)
        write(mid,m)
def connect(mid,at,target,landing):
    d=read(mid)
    if any(w['to']['map']==target for w in d['warps']):return
    x,y=at;d['tiles'][y][x]=0;d['warps'].append(dict(gate(at,target,landing),trigger='up'))
    d['objects'].append(dict(kind='sign',at=[x+1,y],text=read(target)['name']))
    write(mid,d)
def main():
    restaurant('galar_seafood','水舟镇・防波亭海鲜餐厅','galar_hulbury_fishmarket_room',[7,4],True)
    restaurant('galar_circhester_grill','战竞镇・牛排之家','galar_circhester_hotel_room',[7,3],False)
    lift();plant();altar();bay()
    connect('galar_hulbury_fishmarket_room',(7,3),'galar_seafood',(11,13))
    connect('galar_circhester_hotel_room',(7,2),'galar_circhester_grill',(11,13))
    connect('galar_rose',(11,2),'galar_rose_lift',(9,12))
    connect('galar_hammerlocke_castle_room',(17,3),'galar_energy_plant',(16,21))
    connect('galar_weald',(12,6),'galar_weald_altar',(14,18))
    p=MAPS.parent/'region.json';r=json.loads(p.read_text())
    for img in sorted(OUT.glob('*.png')):
        if img.stem not in r['maps']:r['maps'].append(img.stem)
    p.write_text(json.dumps(r,ensure_ascii=False,separators=(',',':'))+'\n')
if __name__=='__main__':main()
