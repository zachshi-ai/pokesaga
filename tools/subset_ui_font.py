"""Subset Noto Sans CJK SC to text used by the game. Pass the Sans2.004 Regular OTF."""
import argparse
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from asset_paths import project_path


def build(source):
    project = Path(project_path())
    chars = set(range(32, 127))
    for folder, pattern in [("core","*.gd"), ("scenes","*.gd"), ("content","*.json")]:
        for path in (project/folder).rglob(pattern):
            chars.update(map(ord, path.read_text()))
    opts = subset.Options()
    opts.recalc_timestamp = False
    font = TTFont(source, recalcTimestamp=False)
    comp = subset.Subsetter(options=opts)
    comp.populate(unicodes=sorted(chars))
    comp.subset(font)
    for record in font["name"].names:
        if record.nameID in (1, 3, 4, 6, 16):
            name = "PokeSagaFieldSans" if record.nameID in (3,6) else "PokeSaga Field Sans"
            record.string = name.encode(record.getEncoding())
    out = project/"assets/fonts/field-sans.otf"
    out.parent.mkdir(parents=True, exist_ok=True)
    font.save(out)
    print(f"{len(font.getBestCmap())} glyph mappings, {out.stat().st_size} bytes")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source",type=Path)
    build(parser.parse_args().source)
