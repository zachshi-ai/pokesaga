"""Audit the native DS field registries and replay old offstage arrivals in Godot."""

import argparse
import base64
from collections import Counter
from functools import lru_cache
import json
import os
from pathlib import Path
import tempfile
import zlib

import numpy as np
from PIL import Image

from campaign_route import ROOT, Routes
from test_kanto_journey import Player
from unova_first_routes import OPENING
from unova_transit_art import INDEX, PLACES


@lru_cache(96)
def image(uri):
    with Image.open(ROOT / uri.removeprefix("res://")) as f:
        im = f.convert("RGBA")
    assert max(im.size) <= 4096, (uri, im.size)
    return im


def audit():
    counts = Counter()
    for folder in ("platinum_native/maps", "platinum_native/flower", "unova_native/bw", "unova_native/b2"):
        for path in sorted((ROOT / "content" / folder).glob("*.json")):
            doc = json.loads(path.read_bytes())
            name = doc["id"]
            art = doc["hoenn_art"]
            w, h = doc["size"]
            assert art["s"] == doc["size"]
            tiles = np.frombuffer(zlib.decompress(base64.b64decode(art["t"])), dtype="<u2").reshape(h, w)
            atlas = Image.open(
                ROOT
                / (
                    "assets/unova/tiles.png"
                    if folder.startswith("unova")
                    else "assets/platinum_native/tiles.png"
                )
            )
            assert tiles.max() < atlas.width * atlas.height // 256, (folder, name, tiles.max())
            atlas.close()
            scene = art.get("scene", [])
            if scene:
                uri, ox, oy = scene
                img = image(uri)
                assert ox < img.width + w * 16 and oy < img.height + h * 16 and img.getbbox(), (name, scene)
                # These DS lifts and unlit platforms used to put the avatar on a
                # completely black patch of the source model at a legitimate door.
                landing = {
                    "sinnoh_hearthome_city_dp_gym_leader_room": (9, 12),
                    "unova_b2_zone_596": (4, 22),
                }.get(name)
                if landing:
                    x, y = landing
                    sample = img.crop((x * 16 + 4 - ox, y * 16 + 4 - oy, x * 16 + 12 - ox, y * 16 + 12 - oy))
                    rgb = np.array(sample)
                    assert rgb[:, :, 3].min() == 255 and rgb[:, :, :3].max(2).min() > 24, name
                if folder.startswith("unova") and name in OPENING[path.parent.name]:
                    assert "/landmarks/" in uri
            elif folder.startswith("unova"):
                assert name in PLACES, (folder, name, "missing scene")
                walk = np.asarray(doc["physics"]["collision"]) == 0
                assert np.isin(tiles[walk], list(INDEX.values())).all(), (folder, name, "unpainted walkway")
            elif name == "sinnoh_underground":
                assert len(np.unique(tiles)) >= 300 and doc["size"] == [480, 480]
            else:
                assert (
                    name in ("sinnoh_206", "sinnoh_villa")
                    or name.startswith("sinnoh_pokemon_league_")
                    or doc.get("platinum_gym")
                    or doc.get("platinum_ride_tile")
                ), (folder, name, "missing scene")
            for p in art["p"]:
                if p[0].startswith("res://"):
                    assert (ROOT / p[0][6:]).is_file() and len(p) == 4, (name, p)
            migrated = doc.get("platinum_previous_spawn", doc.get("unova_previous_spawn"))
            if migrated:
                assert migrated != doc["spawn"], (name, migrated)
                x, y = doc["spawn"]
                assert not doc["physics"]["collision"][y][x] and not any(
                    a["at"] == [x, y] for a in [*doc["warps"], *doc["npcs"]]
                ), (folder, name, doc["spawn"])
                if scene:
                    assert img.getpixel((x * 16 + 8 - ox, y * 16 + 8 - oy))[3] > 128, (
                        folder,
                        name,
                        "offstage spawn",
                    )
                else:
                    assert tiles[y, x] != 0, (folder, name, "offstage tile spawn")
                counts["fixed arrivals"] += 1
            counts[folder] += 1
    assert [
        counts[x]
        for x in ("platinum_native/maps", "platinum_native/flower", "unova_native/bw", "unova_native/b2")
    ] == [551, 3, 426, 616], counts
    print("DS REGISTRY PASS", dict(counts))


def migration(godot, pack):
    args = [godot, "--headless", "--fixed-fps", "60"] + (
        ["--main-pack", str(pack.resolve())] if pack else ["--path", str(ROOT)]
    )
    routes = Routes(())
    with tempfile.TemporaryDirectory(prefix="ds-map-migration-") as temp:
        folder = Path(temp)
        save = folder / "save.json"
        env = dict(os.environ, POKESAGA_CHAPTER_TEST_DIR=temp)

        def launch(startup=()):
            return Player(routes, args, env, folder, startup)

        def close(player):
            player.do("quit")
            assert player.process.wait(timeout=20) == 0

        p = launch(["--", "new-sinnoh"])
        try:
            p.do("save")
            template = json.loads(save.read_bytes())
        finally:
            close(p)
        # A legitimate Unova old save has already accepted its chapter. Start through
        # the regular starter selection to retain that prerequisite during load testing.
        from test_unova_journey import UnovaPlayer, UnovaRoutes

        unova_folder = folder / "unova"
        unova_folder.mkdir()
        unova_env = dict(os.environ, POKESAGA_CHAPTER_TEST_DIR=str(unova_folder))
        unova = UnovaPlayer(UnovaRoutes(), args, unova_env, unova_folder, ["--", "new-unova", "unova-boxed"])
        step = argparse.Namespace(
            result_save=None,
            checkpoints=None,
            stop_at="u1_first_battle",
            transfer="boxed",
            with_alder=False,
            verify_memory=False,
        )
        try:
            unova.run(unova_folder, step)
            unova_template = json.loads((unova_folder / "save.json").read_bytes())
        finally:
            unova.finish()
        for file in (
            "platinum_native/maps/sinnoh_contest_hall_lobby",
            "platinum_native/maps/sinnoh_library",
            "platinum_native/maps/sinnoh_old_chateau_dining_area",
            "unova_native/bw/unova_bw_zone_92",
        ):
            doc = json.loads((ROOT / "content" / (file + ".json")).read_bytes())
            old = doc.get("platinum_previous_spawn", doc.get("unova_previous_spawn"))
            fixture = dict(
                unova_template if doc["region"] == "unova" else template,
                region=doc["region"],
                map=doc["id"],
                pos=old,
            )
            save.write_text(json.dumps(fixture, ensure_ascii=False))
            for _ in range(2):
                p = launch()
                try:
                    assert p.pos == (doc["id"], *doc["spawn"]), (file, p.pos, doc["spawn"])
                    p.do("save")
                    record = json.loads(save.read_bytes())
                    assert record["pos"] == doc["spawn"] and record["party"] == fixture["party"]
                finally:
                    close(p)
        print(
            "DS OLD SAVE PASS four historical arrivals written, reloaded twice and checked on the new floor"
        )


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--godot")
    ap.add_argument("--pack", type=Path)
    args = ap.parse_args()
    audit()
    if args.godot:
        migration(args.godot, args.pack)
