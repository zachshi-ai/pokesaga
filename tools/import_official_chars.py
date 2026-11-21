"""Build Emerald overworld sprites. Kanto-only characters use their GBA FireRed art."""
from pathlib import Path

from PIL import Image

from asset_paths import project_path, source_path


EMERALD = {
    "aroma_lady":"woman_4", "battle_girl":"running_triathlete_f", "beauty":"beauty",
    "bird_keeper":"boy_2", "blackbelt":"black_belt", "breeder":"woman_3",
    "bug_catcher":"bug_catcher", "camper":"camper", "clerk":"mart_employee",
    "expert_m":"expert_m", "fisherman":"fisherman", "gentleman":"gentleman",
    "hiker":"hiker", "kindler":"man_3", "lass":"lass", "man":"man_1",
    "mom":"mom", "navigator":"frontier_brains/brandon", "nurse":"nurse",
    "old_expert":"expert_m", "old_man":"old_man", "old_woman":"old_woman",
    "picnicker":"picnicker", "pokefan_f":"pokefan_f", "pokefan_m":"pokefan_m",
    "pokemaniac":"maniac", "ranger":"boy_3", "ruin_maniac":"man_5",
    "sailor":"sailor", "schoolkid":"school_kid_m", "scientist":"scientist_1",
    "swimmer_f":"swimmer_f", "swimmer_m":"swimmer_m", "teala":"teala",
    "tuber":"tuber_f", "woman":"woman_1", "youngster":"youngster",
}
FIRERED = {
    "blaine":"blaine", "brock":"brock", "cooltrainer_m":"cooltrainer_m",
    "erika":"erika", "giovanni":"giovanni", "koga":"koga", "misty":"misty",
    "oak":"prof_oak", "rocker":"rocker", "sabrina":"sabrina", "surge":"lt_surge",
    "team_rocket_f":"rocket_f", "team_rocket_m":"rocket_m",
}


def indexed_sprite(path):
    with Image.open(path) as image:
        if image.mode != "P":
            raise ValueError(f"Expected indexed GBA artwork in {path}")
        image.info["transparency"] = 0
        return image.convert("RGBA")


if __name__ == "__main__":
    people = "graphics/object_events/pics/people"
    output = Path(project_path("assets"))
    (output/"npc").mkdir(parents=True, exist_ok=True)
    emerald = Path(source_path("emerald_original", people))
    firered = Path(source_path("firered", people))
    indexed_sprite(emerald/"brendan"/"walking.png").save(output/"player_emerald.png")
    for root, mappings in [(emerald, EMERALD), (firered, FIRERED)]:
        for role, source in mappings.items():
            image = indexed_sprite(root / (source + ".png"))
            image.crop((0, 0, 16, 32)).save(output / "npc" / (role + ".png"))
