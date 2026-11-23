#!/usr/bin/env python3
"""Check the shipped Unova opening streets, model footprints and door positions.

Run from the project root: python3 tools/test_unova_facades.py
"""
import json
import sys
from functools import lru_cache
from pathlib import Path

from PIL import Image

from unova_first_routes import OPENING

ROOT = Path(__file__).resolve().parents[1]
CELL = 16

# These native step triggers connect an outdoor location, transport, or a gatehouse
# whose body lies outside this map. All other interior entries must meet a facade.
PASSAGES = {
    'unova_accumula': {(0, 7): 'western gate at the map edge'},
    'unova_nacrene': {(63, 22): 'eastern gate at the map edge'},
    'unova_striaton': {(69, 4): 'Dreamyard path'},
    'unova_19': {(20, 31): 'Aspertia gate at the southern edge'},
    'unova_20': {(9, 53): 'Cave of Being'},
    'unova_aspertia': {(6, 9): 'outdoor lookout'},
    'unova_floccesy': {(21, 2): 'Pledge Grove path'},
    'unova_virbank': {(24, 0): 'northern gate at the map edge', (20, 10): 'ferry'},
}


@lru_cache(None)
def image_alpha(resource):
    if not resource.startswith('res://'):
        raise ValueError(f'Invalid resource path {resource}')
    with Image.open(ROOT / resource[6:]) as image:
        return image.convert('RGBA').getchannel('A')


def check_wall(prop, physics):
    resource, x, y, (anchor_x, anchor_y) = prop
    alpha = image_alpha(resource)
    if anchor_y != alpha.height or not 0 < anchor_x < alpha.width:
        return [f'{resource} has invalid doorstep anchor {(anchor_x, anchor_y)}']
    width, height = physics['size']
    if not (0 <= x < width and 0 <= y < height):
        return [f'{resource} has base outside map at {(x, y)}']
    left = x * CELL + CELL // 2 - anchor_x
    right = left + alpha.width
    errors = []
    # EmeraldField places the sprite's last row at the foot of grid cell (x,y).
    # Only the lowest half-cell is a wall. Roofs legitimately overhang actors who
    # pass behind the building, because World draws actors in increasing Y order.
    for col in range(max(0, left // CELL), min(width, (right + CELL - 1) // CELL)):
        x0 = max(0, col * CELL - left)
        x1 = min(alpha.width, (col + 1) * CELL - left)
        strip = alpha.crop((x0, max(0, alpha.height - CELL // 2), x1, alpha.height))
        # Ignore a few outline/shadow pixels; a real wall covers at least 40 of 128 pixels.
        if sum(strip.histogram()[128:]) < 40:
            continue
        water = physics.get('water')
        if water and water[y][col]:
            errors.append(f'{resource} has a wall on water at {(col, y)}')
        if not physics['collision'][y][col]:
            errors.append(f'{resource} has a wall on walkable ground at {(col, y)}')
    return errors


def check_map(era, mid):
    data = json.loads((ROOT / 'content/unova_native' / era / (mid + '.json')).read_text())
    art = data['hoenn_art']
    physics = data['physics']
    scene, offset_x, offset_y = art['scene']
    expected_size = tuple(n * CELL for n in data['size'])
    errors = []
    if (offset_x, offset_y) != (0, 0) or image_alpha(scene).size != expected_size:
        errors.append('scenery canvas and native walking grid are misaligned')

    facades = [p for p in art['p'] if p[0].startswith('res://assets/unova/facades/')]
    entries = {(p[1], p[2] + 1) for p in facades}
    for prop in facades:
        errors.extend(check_wall(prop, physics))
    doors = {
        tuple(w['at']) for w in data['warps']
        if w['trigger'] == 'step' and not w.get('atlas') and w['to']['map'] != mid
    }
    required = doors - PASSAGES.get(mid, {}).keys()
    for point in sorted(required - entries):
        errors.append(f'interior entrance {point} has no facade on the tile behind it')
    for x, y in required:
        water = physics.get('water')
        if water and water[y][x]:
            errors.append(f'front step {(x, y)} is in water')
    return len(facades), len(required), errors


def main():
    failures = []
    facades = doors = maps = 0
    for era, itinerary in OPENING.items():
        for mid in sorted(itinerary):
            maps += 1
            try:
                count, entries, errors = check_map(era, mid)
            except (KeyError, IndexError, ValueError, OSError) as exc:
                failures.append(f'{era}/{mid}: {exc}')
                continue
            facades += count
            doors += entries
            failures.extend(f'{era}/{mid}: {error}' for error in errors)
    for failure in failures:
        print(failure, file=sys.stderr)
    print(f'Unova facades {"FAIL" if failures else "PASS"} '
          f'maps={maps} facades={facades} interior_entries={doors} failures={len(failures)}')
    return int(bool(failures))


if __name__ == '__main__':
    sys.exit(main())
