"""Orthographic renderer for the original ORAS map objects used by the Godot field."""
from pathlib import Path
import math
import xml.etree.ElementTree as ET
import numpy as np
from PIL import Image


def collada(path):
    root = ET.parse(path).getroot()
    ns = "{http://www.collada.org/2005/11/COLLADASchema}"
    meshes = []
    for g in root.iter(ns + "geometry"):
        mesh = g.find(ns + "mesh")
        arrays = {}
        for source in mesh.findall(ns + "source"):
            stride = int(source.find(".//" + ns + "accessor").get("stride"))
            arrays[source.get("id")] = np.fromstring(source.findtext(ns + "float_array"), sep=" ").reshape(-1, stride)
        position = mesh.find(ns + "vertices").find(ns + "input").get("source")[1:]
        for triangles in mesh.findall(ns + "triangles"):
            inputs = triangles.findall(ns + "input")
            n = max(int(i.get("offset")) for i in inputs) + 1
            lookup = np.fromstring(triangles.findtext(ns + "p"), sep=" ", dtype=int).reshape(-1, 3, n)
            data = {}
            for i in inputs:
                name = i.get("semantic")
                source = position if name == "VERTEX" else i.get("source")[1:]
                data[name] = arrays[source][lookup[:, :, int(i.get("offset"))]]
            data["image"] = Image.open(path.parent / (triangles.get("material").split("_png-")[0] + ".png")).convert("RGBA")
            data["name"] = triangles.get("material").split("_png-")[0]
            meshes.append(data)
    return meshes


def obj(path):
    pos, uv, groups = [], [], {}
    material = None
    for line in path.read_text().splitlines():
        words = line.split()
        if not words:
            continue
        if words[0] == "v":
            pos.append(list(map(float, words[1:4])))
        elif words[0] == "vt":
            uv.append(list(map(float, words[1:3])))
        elif words[0] == "usemtl":
            material = words[1]
        elif words[0] == "f":
            points = [tuple(int(i)-1 for i in token.split("/")[:2]) for token in words[1:]]
            for j in range(1, len(points)-1):
                groups.setdefault(material, []).append([points[0], points[j], points[j+1]])
    images = {}
    for line in path.with_suffix(".mtl").read_text().splitlines():
        if line.startswith("newmtl "):
            material = line.split(maxsplit=1)[1]
        if line.startswith("map_Kd "):
            texture = line.split(maxsplit=1)[1].replace("\\", "/")
            images[material] = Image.open(path.parent / texture).convert("RGBA")
    return [{"name": key, "VERTEX": np.asarray(pos)[np.asarray(tris)[:,:,0]],
             "TEXCOORD": np.asarray(uv)[np.asarray(tris)[:,:,1]], "image": images[key]}
            for key,tris in groups.items() if key in images]


def render(parts, size=(192, 192), elevation=46, azimuth=0):
    # Native exported meshes use Y for height and Z towards the camera.
    a, e = np.radians([azimuth, elevation])
    right = np.array([math.cos(a), 0, -math.sin(a)])
    forward = np.array([math.sin(a)*math.cos(e), math.sin(e), math.cos(a)*math.cos(e)])
    up = np.cross(forward, right)
    axes = np.vstack([right, -up, forward]).T
    sets = [(p, p["VERTEX"] @ axes) for p in parts]
    xyz = np.concatenate([pts.reshape(-1,3) for _,pts in sets])
    low, high = xyz.min(0), xyz.max(0)
    factor = min((size[0]-4)/max(1,high[0]-low[0]), (size[1]-4)/max(1,high[1]-low[1]))
    rgba = np.zeros((size[1],size[0],4),dtype=np.uint8)
    depth = np.full((size[1],size[0]),-np.inf)
    for p, faces in sets:
        tex = np.asarray(p["image"])
        for num, points in enumerate(faces):
            coords = (points[:,:2] - (low[:2] + high[:2])/2) * factor + np.array(size)/2
            x0,y0 = np.maximum(np.floor(coords.min(0)).astype(int),0)
            x1,y1 = np.minimum(np.ceil(coords.max(0)).astype(int)+1,size)
            if x0 >= x1 or y0 >= y1:
                continue
            d1, d2 = coords[1:] - coords[0]
            det = d1[0]*d2[1]-d1[1]*d2[0]
            if abs(det) < 1e-7:
                continue
            yy,xx=np.mgrid[y0:y1,x0:x1]
            xx=xx+.5-coords[0,0]; yy=yy+.5-coords[0,1]
            w1=(xx*d2[1]-yy*d2[0])/det
            w2=(d1[0]*yy-d1[1]*xx)/det
            w0=1-w1-w2
            weights=np.stack([w0,w1,w2],axis=-1)
            z = weights @ points[:,2]
            current=depth[y0:y1,x0:x1]
            visible=(w0>=-1e-6)&(w1>=-1e-6)&(w2>=-1e-6)&(z>=current)
            if not visible.any():
                continue
            texcoord=weights @ p["TEXCOORD"][num,:,:2]
            tx=(np.floor(texcoord[:,:,0]*tex.shape[1]).astype(int))%tex.shape[1]
            ty=(np.floor((1-texcoord[:,:,1])*tex.shape[0]).astype(int))%tex.shape[0]
            pixels=tex[ty,tx].copy()
            visible &= pixels[:,:,3] > 90
            if "COLOR" in p:
                # Vertex colors supply the original canopy shadows and stone gradients.
                pixels[:,:,:3]=(pixels[:,:,:3]*(.42+.58*np.clip(weights@p["COLOR"][num,:,:3],0,1))).astype('uint8')
            rgba[y0:y1,x0:x1][visible]=pixels[visible]
            current[visible]=z[visible]
    im=Image.fromarray(rgba)
    return im.crop(im.getbbox()) if im.getbbox() else im
