"""Rebuild selected production assets in an existing checkout, preserving authored maps and saves."""
import argparse
import os
import subprocess
import sys
from pathlib import Path

from asset_paths import REPO, project_path, source_path
from sevii_connections import rebuild as rebuild_islands

STAGES = ["maps", "icons", "dex", "font", "audio"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stages", choices=STAGES + ["all"], nargs="+")
    parser.add_argument("--project", type=Path, default=Path(project_path()))
    args = parser.parse_args()
    root = args.project.resolve()
    if not (root/"project.godot").is_file():
        parser.error("--project needs an existing editable Godot project")
    os.environ["POKESAGA_PROJECT"] = str(root)

    def run(tool, *extra):
        subprocess.run([sys.executable, str(REPO/"tools"/tool), *map(str, extra)], check=True)

    stages = STAGES if "all" in args.stages else args.stages
    if "maps" in stages:
        run("render_crystal_maps.py", "--active-art")
        run("import_crystal_story_tiles.py")
        run("repair_johto_warps.py")
        run("johto_bg_events.py")
        run("import_crystal_items.py",source_path("crystal"),"--project",root)
        run("import_johto_supplies.py")
        run("import_johto_encounters.py")
        run("hoenn_ferry.py")
        run("build_world_routes.py","--project",root)
        run("bake_emerald_field.py")
        rebuild_islands(root/"content/regions/sevii/maps", root/"content/emerald_maps",
                        source_path("firered","data/maps"))
        run("import_firered_warps.py","--project",root)
        run("import_frlg_services.py", "--source", source_path("firered"), "--project", root)
        run("rebuild_frlg_grass.py", source_path("firered"), "--project", root)
        run("import_kanto_puzzles.py", source_path("firered"), "--project", root)
        run("world/render_charts.py","--project",root)
        run("import_emerald_ui.py")
        run("import_official_chars.py")
        run("import_frlg_actors.py")
        run("import_emerald_battle.py")
    if "icons" in stages:
        run("import_bag_icons.py")
    if "dex" in stages:
        run("build_dex_catalog.py", "--csv-dir", source_path("pokeapi","data/v2/csv"))
        run("import_dex_art.py")
    if "font" in stages:
        run("subset_ui_font.py", source_path("noto","Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf"))
    if "audio" in stages:
        run("make_audio.py")


if __name__ == "__main__":
    main()
