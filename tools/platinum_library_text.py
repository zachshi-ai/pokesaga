"""Extract the branching text at Canalave Library from matching Platinum message banks."""

import json
import re


def export(pt, texts, output):
    from import_platinum_people import pages, read

    def bank(floor):
        name = f"canalave_library_{floor}f"
        original = read(pt / "res/text" / (name + ".json"))["messages"]
        localized = read(texts / "Pt/zh_Hans" / f"c02r010{floor}.json")
        assert len(original) == len(localized)
        return {
            a["id"].split("_Text_")[1]: pages(re.sub(r"\[FF01,[0-9A-F]+\]", "", b["translation"]))
            for a, b in zip(original, localized)
        }

    t1, t2, t3 = [bank(n) for n in (1, 2, 3)]
    scripts = (pt / "res/field/maps/canalave_library_3f/scripts.s").read_text()
    books = {}
    for key, opening in t3.items():
        if not key.startswith("AskRead"):
            continue
        title = key.removeprefix("AskRead")
        block = re.search(
            rf"^CanalaveLibrary3F_Read{title}:\s*\n(.*?)(?=^\w+:)",
            scripts,
            re.MULTILINE | re.DOTALL,
        ).group(1)
        chapter_keys = re.findall(r"^\s*Message CanalaveLibrary3F_Text_(\w+)", block, re.MULTILINE)
        chapters = [t3[k] for k in chapter_keys]
        assert opening and chapters and all(chapters)
        books[title] = {"open": opening, "chapters": chapters, "back": t3["Put" + title + "Back"]}
    assert len(books) == 6
    folk = {
        "open": t3["SinnohFolkStories"],
        "question": t3["ReadWhichStory"][0],
        "stories": [t3[f"SinnohFolkStory{i}"] for i in (1, 2, 3)],
        "back": t3["PutSinnohFolkStoriesBack"],
    }
    book = {
        "books": books,
        "folk": folk,
        "reception": [t1["PleaseKeepQuiet"], t1["ThatWasntMeScreaming"]],
        "shelves_2f": t2["BookshelvesAreCrammed"],
    }
    assert all(book["reception"]) and all(folk["stories"]) and book["shelves_2f"]
    output.write_text(json.dumps(book, ensure_ascii=False, separators=(",", ":")) + "\n")
