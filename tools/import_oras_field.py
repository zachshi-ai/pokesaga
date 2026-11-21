#!/usr/bin/env python3
"""Bake ORAS terrain and object drawings from the pinned models and gameplay captures.

Requires Python 3, NumPy and Pillow. External assets are cached outside the project.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import urllib.request

import numpy as np
from PIL import Image, ImageDraw, ImageOps
from oras_mesh import collada, obj, render

ROOT = Path(__file__).resolve().parents[1]
SOURCE = json.loads((ROOT / "tools/oras_field_sources.json").read_text())
TARGET = ROOT / "assets/oras/field"
TERRAIN = ("grass", "woodland", "water", "trail", "flower", "mountain", "cliff",
           "roof", "door", "fence", "sand", "tall", "pave", "floor", "rug", "wall",
           "rockfloor", "ice", "lava", "bridge", "ash", "meadow", "deep", "marsh",
           "dune", "snow", "ruin", "gym", "surf", "stair", "empty", "urban", "marble", "civic", "clinic", "astral", "snowcliff")
TILE = 32


def resources(cache, local):
    models = {}
    for key, rec in SOURCE["models"].items():
        root = local.get(key) or cache / key
        if not (root / ".git").exists():
            subprocess.run(["git","clone","--filter=blob:none","--no-checkout",rec["repo"],str(root)],check=True)
            subprocess.run(["git","-C",str(root),"sparse-checkout","set",rec["path"]],check=True)
            subprocess.run(["git","-C",str(root),"checkout","--detach",rec["rev"]],check=True)
        actual = subprocess.check_output(["git","-C",str(root),"rev-parse","HEAD"],text=True).strip()
        if actual != rec["rev"]:
            raise ValueError(f"{root}: expected {rec['rev']}")
        models[key] = root / rec["path"]
    photos = {}
    for key, rec in SOURCE["captures"].items():
        fp = cache / "photos" / (key + ".jpg")
        fp.parent.mkdir(parents=True,exist_ok=True)
        if not fp.is_file():
            fp.write_bytes(urllib.request.urlopen(rec["url"],timeout=30).read())
        if hashlib.sha256(fp.read_bytes()).hexdigest() != rec["sha256"]:
            raise ValueError(f"Capture changed: {fp}")
        photos[key] = Image.open(fp).convert("RGB").resize((400,240),Image.Resampling.LANCZOS)
    return models, photos


def cut(image, polygon):
    mask = Image.new("L",image.size)
    ImageDraw.Draw(mask).polygon(polygon,fill=255)
    layer = image.convert("RGBA")
    layer.putalpha(mask)
    return layer.crop(mask.getbbox())


def wall_house(photo):
    # Assemble the photographed original facade around its actual front door.
    body = photo.crop((227,56,392,120)).resize((140,58),Image.Resampling.LANCZOS)
    roof = photo.crop((232,0,386,57)).resize((156,56),Image.Resampling.LANCZOS)
    im=Image.new("RGBA",(156,113))
    mask=Image.new("L",roof.size)
    ImageDraw.Draw(mask).polygon([(14,0),(142,0),(155,45),(155,55),(0,55),(0,45)],fill=255)
    im.paste(body,(8,55));im.paste(roof,(0,0),mask)
    return im


def room_ground(photo, size=(384,288)):
    # Use a single perspective wall and a continuous wooden floor, independent of collision.
    w,h=size
    out=Image.new("RGB",size,(41,29,20))
    plank=photo.crop((215,185,324,235))
    for y in range(70,h,plank.height):
        for col,x in enumerate(range(-42,w,plank.width)):
            out.paste(ImageOps.mirror(plank) if col%2 else plank,(x,y))
    # Cream plaster, continuous top timber and skirting are sampled from the original room.
    wall=photo.crop((71,26,131,90)).resize((w-20,52),Image.Resampling.LANCZOS)
    skirting=photo.crop((66,90,130,105)).resize((w-20,10),Image.Resampling.LANCZOS)
    out.paste(wall,(10,16));out.paste(skirting,(10,68))
    trim=photo.crop((44,5,130,27)).resize((w,19),Image.Resampling.LANCZOS)
    out.paste(trim,(0,0))
    beam=photo.crop((132,27,143,98)).resize((7,55),Image.Resampling.LANCZOS)
    for x in (10,w//2-28,w-18):out.paste(beam,(x,17))
    # Narrow side walls keep the floor continuous from the bed to the upstairs landing.
    rail=photo.crop((137,26,143,95)).resize((5,h-11),Image.Resampling.LANCZOS)
    out.paste(rail,(0,12));out.paste(ImageOps.mirror(rail),(w-5,12))
    # The player's rug is woven from the original bedroom carpet; retain its cream border.
    rug=photo.crop((71,188,121,231)).resize((117,65),Image.Resampling.LANCZOS)
    edge=Image.new("RGB",(125,73),(124,50,43))
    ImageDraw.Draw(edge).rounded_rectangle((1,1,123,71),5,fill=(227,172,141))
    edge.paste(rug,(4,4));out.paste(edge,(w//2-38,h//2+3))
    return out


def clinic_ground(photos):
    # The medical hall retains the warm honeycomb floor and red cornice seen in Lavaridge.
    photo=photos["lavaridge-center"]
    out=Image.new("RGB",(480,340),(122,92,67));w,h=out.size
    motif=photo.crop((105,139,155,170)).resize((55,33),Image.Resampling.LANCZOS)
    for row,y in enumerate(range(50,h,32)):
        for col,x in enumerate(range(-25,w,54)):
            patch=ImageOps.mirror(motif) if col%2 else motif
            out.paste(ImageOps.flip(patch) if row%2 else patch,(x,y))
    wall=photo.crop((203,33,239,65)).resize((w,44),Image.Resampling.LANCZOS)
    out.paste(wall,(0,15))
    cap=photo.crop((29,1,126,16)).resize((w,18),Image.Resampling.LANCZOS);out.paste(cap,(0,0))
    plaster=photo.crop((204,79,221,87)).resize((w,7),Image.Resampling.LANCZOS);out.paste(plaster,(0,58))
    return out


def spa(photos):
    # A plaza water basin assembled from Lavaridge's original carved rocks and spring.
    result=Image.new("RGBA",(136,80))
    basin=photos["lavaridgetown"].crop((31,46,184,87)).resize((136,60),Image.Resampling.LANCZOS)
    edge=Image.new("L",basin.size);ImageDraw.Draw(edge).ellipse((0,0,135,59),fill=255)
    result.paste(basin,(0,20),edge)
    water=photos["lavaridgetown"].crop((61,9,159,43)).resize((109,39),Image.Resampling.LANCZOS)
    mask=Image.new("L",water.size);ImageDraw.Draw(mask).ellipse((0,0,108,38),fill=255)
    result.paste(water,(14,23),mask)
    # Original Meteor Falls waterfall column, alpha keyed to the bright falling water.
    fall=photos["meteorfalls"].crop((165,3,235,72)).resize((34,45),Image.Resampling.LANCZOS).convert("RGBA")
    arr=np.array(fall);yy,xx=np.mgrid[:45,:34]
    alpha=np.zeros((45,34),float)
    for offset,curve,top,alpha0 in [(15,-.08,2,158),(18,.14,9,135),(12,-.22,18,110),(19,.26,24,100)]:
        dist=(xx-offset-curve*yy)/(1+yy*.028)
        alpha += alpha0*np.exp(-dist*dist)*np.clip((yy-top)/3,0,1)
    alpha *= np.clip((45-yy)/8,0,1)
    arr[:,:,3]=np.uint8(np.clip(alpha,0,222));result.alpha_composite(Image.fromarray(arr),(51,5))
    return result


def bake(cache, local):
    models, photos = resources(cache,local)
    TARGET.mkdir(parents=True,exist_ok=True)
    field=models["route111"]
    def tex(name):
        return Image.open(field/(name+".png")).convert("RGB")
    def shot(name, box):
        return photos[name].crop(box)
    # Cut terrain only from exposed, actor-free regions of each confirmed ORAS image.
    grass=tex("chip_kusa_b")
    terrain = {
        "grass":grass, "woodland":Image.blend(grass.resize((128,128)),tex("chip_kusa").resize((128,128)),.22), "trail":tex("chip_soil_a"),
        "water":shot("route105",(8,135,73,204)), "deep":shot("shoalcave",(247,19,343,61)),
        "flower":grass.copy(), "mountain":tex("r111_top01"), "cliff":tex("chip_gake01"),
        "roof":shot("rival-house",(240,0,369,42)), "door":tex("chip_soil_a"),
        "fence":shot("lavaridgetown",(47,103,154,118)), "sand":tex("chip_des_01"),
        "tall":shot("route101",(14,8,119,59)), "pave":shot("slateportcity",(172,4,226,67)),
        "floor":shot("bedroom",(218,174,316,230)), "rug":shot("bedroom",(49,184,117,226)),
        "wall":shot("bedroom",(67,26,136,91)), "rockfloor":shot("granitecave",(117,118,159,152)),
        "ice":shot("shoal-ice",(273,113,386,179)), "lava":shot("seafloorcavern",(110,70,187,89)),
        "bridge":shot("pacifidlogtown",(39,22,89,39)),
        "ash":shot("fallarbortown",(247,162,300,221)), "meadow":tex("chip_kusa"),
        "marsh":shot("petalburgwoods",(14,164,89,218)), "dune":tex("sabak_ground1"),
        "snow":shot("shoal-ice",(317,136,385,204)), "ruin":tex("sabak_ground2"),
        "gym":shot("mauvillecity",(82,170,158,190)), "surf":shot("route105",(6,115,59,181)),
        "stair":shot("granitecave",(164,175,232,193)), "empty":Image.new("RGB",(128,128),(24,40,43)),
        "urban":shot("stone-city",(215,151,312,228)), "marble":shot("marble",(233,149,293,223)),
        "civic":shot("mall",(246,100,297,146)), "clinic":shot("clinic",(141,132,181,166)),
        "astral":shot("observatory",(15,23,95,46)), "snowcliff":shot("shoal-ice",(14,155,62,203)),
    }
    # Match city paving scale to the reference scenes. Reflect neighboring samples to avoid visible seams.
    for name in ("pave","urban","marble","civic","clinic","rockfloor","stair","wall","floor","rug"):
        raw=terrain[name];tile=Image.new("RGB",(raw.width*2,raw.height*2));tile.paste(raw,(0,0))
        tile.paste(ImageOps.mirror(raw),(raw.width,0));tile.paste(ImageOps.flip(tile.crop((0,0,tile.width,raw.height))),(0,raw.height));terrain[name]=tile
    # The field's own flower/leaf alpha texture preserves the original silhouettes.
    flowers=Image.open(field/'alpha.png').convert("RGBA").crop((67,9,119,45))
    for x,y,sz in [(10,21,20),(71,49,29),(30,95,24),(108,102,15)]:
        patch=flowers.resize((sz,int(sz*.73)),Image.Resampling.LANCZOS);terrain["flower"].paste(patch,(x,y),patch)
    clinic_ground(photos).save(TARGET/"clinic_ground.png",optimize=True)
    room_ground(photos["bedroom"]).save(TARGET/"room_ground.png",optimize=True)
    atlas=Image.new("RGBA",(16*TILE,len(TERRAIN)*TILE))
    for row, name in enumerate(TERRAIN):
        base=terrain[name].resize((4*TILE,4*TILE),Image.Resampling.LANCZOS)
        for variant in range(16):
            x=variant%4*TILE;y=variant//4*TILE
            atlas.paste(base.crop((x,y,x+TILE,y+TILE)),(variant*TILE,row*TILE))
    atlas.save(TARGET/"terrain.png")
    # Edge tiles overlay a flexible shoreline, road margin or indoor wall skirting.
    edges=Image.new("RGBA",(16*TILE,4*TILE))
    for row,name in enumerate(("shore","path","wall","ledge")):
        for mask in range(16):
            cell=Image.new("RGBA",(TILE,TILE));dr=ImageDraw.Draw(cell)
            for direction in range(4):
                if not mask&(1<<direction): continue
                strip=Image.new("RGBA",cell.size);pen=ImageDraw.Draw(strip)
                for x in range(TILE):
                    v=(0,0,1,1,1,2,1,1,0,0,1,0,0,1,0,0)[x%16]
                    if name=="shore":
                        pen.line((x,0,x,2+v),fill=(159,152,104,255));pen.point((x,3+v),fill=(192,220,190,235));pen.point((x,4+v),fill=(138,199,203,164))
                    elif name=="path":
                        pen.line((x,0,x,v+1),fill=(84,143,71,192));pen.point((x,v+2),fill=(135,161,81,132))
                    elif name=="wall":
                        pen.line((x,0,x,3),fill=(77,60,48,180));pen.point((x,4),fill=(156,131,100,180))
                    else:
                        px=terrain["cliff"].getpixel((x%terrain["cliff"].width,35));pen.line((x,0,x,5+v),fill=(*px,255));pen.point((x,6+v),fill=(91,77,56,230))
                cell.alpha_composite(strip.rotate(-90*direction))
            edges.paste(cell,(mask*TILE,row*TILE))
    edges.save(TARGET/"edges.png")
    scene=collada(field/'r111a_00_00.dae')
    tree=[]
    for part in scene:
        if part["name"] not in ("chip_wood_a","chip_wood_b"): continue
        center=part["VERTEX"].mean(1)
        mask=(abs(center[:,0]+330)<39)&(abs(center[:,2]-260)<38)
        tree.append({**part,**{k:v[mask] for k,v in part.items() if isinstance(v,np.ndarray)}})
    objects={"tree":render(tree,(140,155),42),"rock":render([p for p in scene if p["name"]=="sabak_iwa"],(82,84),45),
             "ruin":render(collada(field/'r111_bm_regiruin01.dae'),(180,135),39),
             "center":render(obj(models["center"]/'PokeCenter.obj'),(180,160),37),
             "home":wall_house(photos["rival-house"]),"fountain":spa(photos)}
    polygons={
      "clock":("bedroom",[(215,38),(223,33),(231,34),(239,41),(240,50),(235,59),(225,62),(217,59),(211,52),(211,45)]),
      "ceilingbed":("room-bed",[(57,114),(63,103),(72,100),(77,112),(154,111),(156,115),(157,141),(152,154),(143,154),(143,150),(72,150),(71,154),(60,152),(59,138)]),
      "woodstairs":("home-stairs",[(131,38),(183,38),(186,88),(132,88)]),
      "pc":("birch-office",[(115,73),(121,71),(127,72),(128,79),(130,78),(153,78),(156,80),(156,91),(159,92),(159,95),(143,96),(129,96),(129,95),(116,97),(115,94)]),
      "statue":("monument",[(63,106),(70,105),(88,108),(96,150),(100,154),(101,185),(94,194),(68,194),(64,188),(62,157),(67,148)]),
      "streetlamp":("plaza",[(149,19),(154,18),(158,23),(161,27),(160,34),(156,38),(156,72),(162,77),(162,82),(150,82),(150,76),(153,73),(153,37),(148,34),(147,29)]),
      "planter":("mall",[(341,94),(350,88),(354,94),(359,94),(364,98),(361,112),(340,112),(336,101)]),
      "banner":("lavaridge-center",[(110,28),(168,28),(168,31),(165,32),(163,68),(142,72),(138,65),(137,72),(113,69),(112,32),(110,31)]),
      "officecounter":("lavaridge-center",[(252,113),(262,112),(264,109),(273,105),(285,111),(291,116),(291,128),(314,128),(315,112),(301,111),(302,100),(311,96),(339,96),(344,102),(345,113),(341,122),(341,128),(399,127),(399,158),(397,171),(263,171),(257,167),(253,156)]),
      "carebench":("mall",[(208,72),(247,72),(247,78),(242,79),(242,85),(248,85),(250,89),(248,96),(243,96),(240,92),(215,92),(211,96),(207,95),(207,89),(208,85)]),
      "academy":("wharf",[(36,0),(345,0),(354,9),(364,31),(355,39),(346,100),(209,120),(209,93),(191,92),(189,123),(38,140),(30,71),(28,43)]),
      "desk":("bedroom",[(270,49),(340,49),(342,55),(342,79),(347,86),(352,92),(351,99),(345,101),(344,111),(338,111),(335,103),(317,104),(316,116),(306,120),(300,117),(300,107),(297,107),(296,118),(290,116),(291,105),(274,105),(272,112),(267,111),(266,95),(264,91),(264,85),(267,80)]),
      "tv":("bedroom",[(4,87),(62,86),(69,122),(80,127),(84,143),(79,151),(0,151),(0,126),(11,123)]),
      "bed":("bedroom",[(331,157),(335,146),(344,144),(349,148),(351,153),(383,152),(386,147),(393,148),(397,153),(399,158),(399,237),(360,237),(355,216),(341,197),(332,178),(328,168)]),
      "map":("bedroom",[(145,40),(197,40),(198,76),(147,77)]),
      "bookshelf":("bedroom",[(266,45),(342,45),(348,73),(268,74)]),
      "mart":("mauvillecity",[(239,30),(390,30),(394,112),(242,114)]),
      "gym":("mauvillecity",[(8,16),(150,16),(154,110),(7,112)]),
      "lab":("verdanturftown",[(0,45),(149,46),(147,96),(143,222),(0,223)]),
      "treehouse":("fortreecity",[(243,50),(251,28),(271,15),(302,9),(325,12),(345,24),(360,46),(359,65),(350,81),(343,123),(322,128),(319,202),(309,204),(309,131),(258,125),(245,116)]),
      "flowers":("oldaletown",[(145,35),(248,35),(258,64),(218,68),(218,83),(139,85),(136,71)]),
      "stairs":("granitecave",[(165,157),(232,157),(244,201),(152,201)]),
      "sign":("mauvillecity",[(299,136),(333,136),(334,163),(328,164),(328,173),(325,173),(325,164),(303,164),(303,173),(299,173)]),
      "fence":("lavaridgetown",[(36,92),(46,96),(80,96),(85,91),(95,92),(99,100),(142,100),(146,91),(155,92),(160,100),(160,126),(145,126),(141,118),(99,118),(97,126),(86,126),(82,118),(48,117),(47,124),(37,124)]),
      "shrine":("granitecave",[(53,59),(147,62),(152,103),(146,111),(53,109)]),
    }
    for name,(src,polygon) in polygons.items():objects[name]=cut(photos[src],polygon)
    # A full lab facade uses the ORAS Birch laboratory photograph. Replace the occupied door
    # with the matching Littleroot door so the player can approach an empty entrance.
    lab=cut(photos["birch-lab"],[(85,0),(315,0),(337,53),(337,69),(319,76),(316,140),(88,140),(84,72),(61,68),(61,55)])
    door=photos["rival-house"].crop((264,62,311,119)).resize((46,67),Image.Resampling.LANCZOS)
    lab.paste(door,(114,72));objects["birch_lab"]=lab
    # A picnic banner on its field pole retains the actual Lavaridge Pokemon Center emblem.
    banner=Image.new("RGBA",(54,88));post=photos["lavaridgetown"].crop((146,98,152,124)).resize((5,80))
    banner.paste(post,(4,7));banner.alpha_composite(objects["banner"].resize((47,35),Image.Resampling.LANCZOS),(4,7))
    objects["banner"]=banner
    # Keep the full pixel resolution of the orchard photograph for this small 3DS field object.
    orchard=Image.open(cache/"photos/berry-orchard.jpg").convert("RGB")
    outline=[(216.5,83.8),(218.1,84.8),(220.2,84.8),(224.1,83.7),(224.7,85.5),
             (227.2,87.4),(226.7,90.8),(228.2,93.4),(228.2,96.7),(229,98.3),(228,99.3),
             (227.3,102.4),(224.3,103.5),(222.1,104.5),(221.7,106.3),(222.2,108.1),
             (219.6,109.1),(217.5,108.3),(218.4,105.8),(218.6,104.6),(215,103.7),
             (211.7,102.1),(211.8,99.6),(211.2,98.6),(212.3,96.2),(212,95.0),(212.6,91.8),
             (213.3,90.2),(212.5,88.7),(213.1,87.2),(215.5,86.7)]
    objects["berry_tree"]=cut(orchard,[(round(x*orchard.width/400),round(y*orchard.height/240)) for x,y in outline])
    thorn=Image.open(cache/"photos/cut-tree.jpg").convert("RGB")
    body=[(158,53),(165,52),(166,43),(172,50),(172,45),(177,53),(181,50),(184,52),
          (188,47),(191,49),(197,45),(198,48),(195,54),(200,55),(199,60),(204,63),
          (203,68),(201,74),(200,79),(201,85),(196,83),(195,89),(189,92),(186,98),
          (181,98),(176,95),(172,93),(173,82),(173,70),(169,67),(167,69),(162,64)]
    bush=cut(thorn,[(round(x*thorn.width/400),round(y*thorn.height/240)) for x,y in body])
    rgba=np.array(bush);r,g,b=[rgba[:,:,i].astype(int) for i in range(3)]
    keep=(r>g*.46)&(r>b*1.24)
    rgba[:,:,3]=np.where(keep,rgba[:,:,3],0);objects["cut_tree"]=Image.fromarray(rgba)
    # For Strength and Rock Smash the same genuine rock data is projected at different
    # angles so the push-block stays distinguishable from a smaller breakable rock.
    objects["boulder"]=render([p for p in scene if p["name"]=="sabak_iwa"],(95,95),32,29)
    patch=tex("chip_soil_a").resize((72,42),Image.Resampling.LANCZOS).convert("RGBA")
    mask=Image.new("L",patch.size);ImageDraw.Draw(mask).ellipse((0,0,71,41),fill=255)
    patch.putalpha(mask);objects["soil"]=patch
    pickup=Image.open(cache/"photos/field-item.jpg").convert("RGB")
    points=[(169.4,117.4),(170.8,115.6),(173.3,114.7),(176.2,114.7),(178.3,116.1),
            (179.6,118.2),(179.7,121.4),(178.2,124.1),(176.8,126.0),(173.7,126.5),
            (170.6,125.3),(168.8,123),(168.6,119.7)]
    objects["pickup"]=cut(pickup,[(round(x*pickup.width/400),round(y*pickup.height/240)) for x,y in points])
    for name,image in objects.items():
        image.save(TARGET/(name+".png"),optimize=True)
    print(f"Baked {len(TERRAIN)} ORAS terrain materials and {len(objects)} field objects")


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--cache",type=Path,default=Path.home()/".cache/pokesaga/oras")
    p.add_argument("--route111",type=Path);p.add_argument("--center",type=Path)
    a=p.parse_args();bake(a.cache,{"route111":a.route111,"center":a.center})
