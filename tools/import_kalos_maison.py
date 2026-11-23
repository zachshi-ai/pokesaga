"""Build the X/Y Maison roster from Altissimo's transcribed battle tables.

Pass downloaded battle-maison-pokemon.html, battle-maison-trainers.html and
Kalos-Locations/battle-maison.html in that order. Requires beautifulsoup4.
"""
import argparse
import csv
import json
import re
import unicodedata
from pathlib import Path

from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / "content"


def slug(value):
    value = value.replace("♀", "-f").replace("♂", "-m").replace("’", "").replace("'", "")
    return re.sub("[^a-z0-9]", "", unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode().lower())


def cells(row):
    return [td.get_text(" ", strip=True) for td in row.find_all(["td", "th"], recursive=False)]


def tables(path):
    return BeautifulSoup(path.read_bytes(), "html.parser").find_all("table")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sets", type=Path)
    parser.add_argument("trainers", type=Path)
    parser.add_argument("facility", type=Path)
    parser.add_argument("--species-csv", type=Path, required=True, help="PokéAPI pokemon_species.csv")
    args = parser.parse_args()
    species = {slug(row["key"]): row["id"] for row in json.loads((CONTENT / "species.json").read_text())}
    with args.species_csv.open() as reader:
        species.update({slug(r["identifier"]):int(r["id"]) for r in csv.DictReader(reader)})
    moves = {slug(row["key"]): row["id"] for row in json.loads((CONTENT / "moves.json").read_text())}
    species.update(wormadamtrash=413, wormadamsandy=413, wormadamplant=413, meowsticm=678, meowsticf=678,
                   gourgeistsmall=711, gourgeistlarge=711, gourgeistsuper=711, gourgeistaverage=711)
    keys = {}
    sets = []
    rosters = []
    bosses = []
    points = []

    def build_set(row, boss=False):
        label, nature, item = row[1:4]
        mon = re.sub(r"-[1-4]$", "", label)
        form = ""
        if slug(mon) not in species:
            base = next((s for s in ["Rotom", "Wormadam", "Gourgeist", "Meowstic", "Basculin", "Gastrodon", "Pumpkaboo"] if mon.startswith(s)), "")
            if not base:
                raise ValueError(mon)
            form = mon
            mon = base
        result=[species[slug(mon)], [moves[slug(move)] for move in row[4:8] if slug(move) not in ("na","")], item_key(item), nature, form]
        if not boss:
            result.append([int(v) for v in row[8:14]])
        return result

    def item_key(item):
        return item.replace(" ", "_").replace("-", "_").replace("’", "").replace("'", "").upper()

    for table in tables(args.sets):
        for tr in table.select("tr")[1:]:
            row = cells(tr)
            if len(row) != 14 or not row[1]:
                continue
            if row[1] in keys:
                continue
            keys[row[1]] = len(sets)
            sets.append(build_set(row))
    trainer_tables=tables(args.trainers)
    for table in trainer_tables[2:]:
        heading = table.find_previous("h4")
        if not heading or not heading.get_text(strip=True).startswith("Roster "):
            continue
        trainers = [li.get_text(" ", strip=True).split(" (XY)")[0] for li in table.find_next_sibling("ul").select("li")]
        refs = []
        for tr in table.select("tr"):
            for cell in cells(tr):
                raw=re.fullmatch(r"(.+?)-([1-4](?:,\s*[1-4])*)", cell)
                if raw:
                    refs.extend(keys[f"{raw[1]}-{n.strip()}"] for n in raw[2].split(","))
        if trainers and refs:
            lower, upper = map(int,re.findall(r"\d+",table.find_previous("h3").get_text())[:2])
            rosters.append([trainers, refs, lower, upper])
    partners=[]
    for table in trainer_tables[68:71]:
        roster=[]
        for tr in table.select("tr"):
            row=cells(tr)
            if len(row)<15 or not row[1]:
                continue
            label=row[1].replace(" ♀","").replace(" ♂","")
            roster.append(build_set(["",label,row[3],row[4],*row[5:9],*row[9:15]],boss=True))
        partners.append(roster)
    info = tables(args.facility)
    for table in info[10:18]:
        bosses.append([build_set(cells(tr),boss=True) for tr in table.select("tr")[1:] if len(cells(tr)) == 14])
    for table in info[2:4]:
        for row in table.select("tr")[1:]:
            values = cells(row)
            if len(values)==2 and "BP" in values[1]:
                points.append([item_key(values[0]) if not values[0].startswith("TM") else values[0].split()[0], int(values[1].split()[0])])
    payload = {"sets": sets, "rosters": rosters, "bosses": bosses, "shop": points,"partners":partners}
    assert len(sets)>850 and len(rosters)>60 and len(bosses)==8,(len(sets),len(rosters),len(bosses))
    (CONTENT / "kalos_maison.json").write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":"))+"\n")
    print(len(sets), "sets,", len(rosters), "rosters,", len(points), "prizes")


if __name__ == "__main__":
    main()
