"""Project the X/Y interior's floor and furniture separately from its collision grid."""
import re

import numpy as np
from scipy import ndimage

from kalos_surfaces import paint, put


GROUND = re.compile(r'yuka|floor|tairu|ground|flr|stairs|kaidan|step|carpet|carp0|kitchenmat|_jimen')
FURNITURE = [
    (r'counter|_count0', 'officecounter'),
    (r'shelf|bookcase|_tana', 'bookshelf'),
    (r'bed', 'ceilingbed'),
    (r'_desk|table', 'desk'),
    (r'sofa|bench', 'carebench'),
    (r'_sink|stove', 'kalos_stove'),
    (r'plant|ueki', 'plant_indoor'),
    (r'television|_tv', 'pc'),
]


def room_surfaces(room, parts, free, pixels):
    """Keep the floor under chairs, shelves and walls at its native model position."""
    height, width = free.shape
    origin = room['kalos_origin']
    materials = np.zeros((height, width), np.int16)
    heights = np.full(free.shape, -1e6, np.float32)
    footprints = {}
    carpet = np.zeros((height*pixels,width*pixels,4), np.uint8)
    stairs = np.zeros_like(materials)
    tread_heights = np.full_like(heights, -1e6)
    carpet_heights = np.full(carpet.shape[:2], -1e6, np.float32)
    for _, material, vertices, uv, triangles, texture, _ in parts:
        name = material.lower()
        if GROUND.search(name):
            put(heights, materials, vertices, triangles, 1, origin)
        if re.search(r'carpet|_carp|jutan|_mat[0-9]', name):
            # The X/Y textile carries its own border and central motifs. Project
            # its UVs onto the original floor, at native GBA pixel density.
            coords = np.column_stack(((vertices[:,0]/18-origin[0])*pixels,
                                      (vertices[:,2]/18-origin[1])*pixels, vertices[:,1], uv))
            cloth = np.array(texture, copy=True)
            # Compress the thread colours to a small, warm field palette.
            rgb = cloth[:,:,:3].astype(float)
            rgb = np.clip(24 + rgb * .84, 0, 255)
            cloth[:,:,:3] = (np.rint(rgb / 12) * 12).astype(np.uint8)
            paint(carpet, carpet_heights, coords, triangles, cloth)
        if re.search(r'stair|kaidan', name):
            put(tread_heights, stairs, vertices, triangles, 1, origin)
        if 'shadow' in name or 'kage' in name:
            continue
        furniture = next((sprite for tokens, sprite in FURNITURE if re.search(tokens, name)), '')
        if furniture:
            if furniture not in footprints:
                footprints[furniture] = (np.zeros_like(materials), np.full_like(heights, -1e6))
            mark, depth = footprints[furniture]
            put(depth, mark, vertices, triangles, 1, origin)

    # A stair landing may reach a walkable floor above the first ground mesh.
    # Retain the complete visible deck beneath the player's connected floor.
    x, y = room['spawn']
    groups, _ = ndimage.label(free)
    standing = groups == groups[y, x]
    deck = materials.astype(bool) | standing
    groups, _ = ndimage.label(deck)
    deck = groups == groups[y, x]
    fitted = room.get('kalos_furnishings', [])
    reserved = {(x, y) for _, x, y, _ in fitted}
    reserved.update(tuple(point) for point in room['kalos_anchors'].values())
    reserved.update(tuple(warp['at']) for warp in room['warps'])
    objects = []
    for sprite, (mark, _) in footprints.items():
        groups, count = ndimage.label((mark != 0) & deck & ~free)
        for label in range(1, count + 1):
            component = groups == label
            yy, xx = np.where(component)
            if not len(xx):
                continue
            # Place each sprite on its physical base, nearest the visible side.
            row = int(yy.max())
            xs = xx[yy == row]
            col = int(xs[np.argmin(np.abs(xs - np.median(xx)))])
            if any(abs(a-col)+abs(b-row) <= 2 for a,b in reserved):
                continue
            # A chair-sized mesh or a narrow portion of a shelf needs a small sprite.
            scale = .75 if int(xs.max()-xs.min()) < 1 else 1
            objects.append((sprite, col, row, scale))
            reserved.add((col, row))
    carpet[:,:,3] *= deck.repeat(pixels,0).repeat(pixels,1)
    return deck, carpet, stairs.astype(bool) & deck, tread_heights, objects
