"""Select native Emerald metatiles and architectural strips at their original pixel scale."""

from functools import lru_cache
from pathlib import Path
import argparse

from PIL import Image

from bake_emerald_field import Emerald

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/island_landmarks"
# Source layout, upper-left tile, width, height. Ground swatches contain only walkable floor.
PICK = {
    "arena_wood": ("BattleFrontier_BattleArenaBattleRoom", 3, 5, 1, 1),
    "arena_clay": ("EverGrandeCity_SidneysRoom", 2, 5, 1, 1),
    "arena_mauve": ("EverGrandeCity_PhoebesRoom", 2, 5, 1, 1),
    "arena_ice": ("EverGrandeCity_GlaciasRoom", 2, 5, 1, 1),
    "arena_mint": ("EverGrandeCity_ChampionsRoom", 6, 6, 1, 1),
    "arena_brown": ("BattleFrontier_BattleDomeBattleRoom", 0, 5, 1, 1),
    "lab_tile": ("Route119_WeatherInstitute_1F", 8, 4, 1, 1),
    "hall_tile": ("SlateportCity_OceanicMuseum_1F", 3, 3, 1, 1),
    "office_tile": ("RustboroCity_DevonCorp_2F", 4, 7, 1, 1),
    "ruin_tile": ("DesertRuins", 5, 5, 1, 1),
    "scarp_base": ("DesertRuins", 4, 2, 1, 1),
    "scarp_top": ("DesertRuins", 4, 1, 1, 1),
    "scarp_left": ("DesertRuins", 2, 6, 1, 1),
    "scarp_right": ("DesertRuins", 13, 6, 1, 1),
    "dojo_wall": ("BattleFrontier_BattleArenaBattleRoom", 1, 0, 5, 3),
    "medal_wall": ("EverGrandeCity_SidneysRoom", 4, 0, 5, 3),
    "prism_wall": ("EverGrandeCity_ChampionsRoom", 4, 0, 5, 3),
    "dome_seats": ("BattleFrontier_BattleDomeBattleRoom", 4, 0, 6, 2),
    "museum_wall": ("SlateportCity_OceanicMuseum_1F", 6, 0, 3, 2),
    "office_wall": ("RustboroCity_DevonCorp_2F", 4, 0, 4, 2),
    "dome_mat": ("BattleFrontier_BattleDomeBattleRoom", 2, 4, 14, 5),
    "dojo_mat": ("BattleFrontier_BattleArenaBattleRoom", 4, 4, 8, 5),
    "temple_mat": ("BattleFrontier_BattlePalaceBattleRoom", 4, 3, 7, 5),
    "champ_stairs": ("EverGrandeCity_ChampionsRoom", 5, 10, 3, 3),
}


def generate(source):
    em = Emerald(source)
    OUT.mkdir(exist_ok=True)
    for key, (loc, x, y, w, h) in PICK.items():
        img = em.patch(loc, x, y, w, h)
        img.convert("RGB").save(OUT / (key + ".png"), optimize=True)


@lru_cache(None)
def piece(key):
    return Image.open(OUT / (key + ".png")).convert("RGB")


if __name__ == "__main__":
    a = argparse.ArgumentParser(description=__doc__)
    a.add_argument("emerald", type=Path)
    generate(a.parse_args().emerald)
