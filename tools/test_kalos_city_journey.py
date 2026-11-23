#!/usr/bin/env python3
"""Walk an earned Kalos champion save through the restaurants, hotel, research institute and wild habitats."""
import argparse
import os
from pathlib import Path
import shutil
import tempfile

from campaign_collection import Habitat, pace
from campaign_route import ROOT, VECTORS, read
from test_kalos_journey import KalosPlayer, KalosRoutes


class CityPlayer(KalosPlayer):
    def counter(self, mid, name):
        self.enter(mid)
        resident = next(actor for actor in self.state["actors"] if name in actor[2])
        self.use_at(mid, resident[0])

    def choose(self, label):
        assert self.select(label), (label, self.state["buttons"], self.state["dialog"])

    def record(self):
        self.do("save")
        return read(self.save_slot)

    def services(self):
        self.nurse("kalos_lumiose_center_magenta")
        mid = next(mid for mid, field in self.routes.fields.items() if field.data["kalos_zone"] == 141)
        self.counter(mid, "领班")
        self.choose("双打")
        for _ in range(3):
            self.choose("开始对战")
        slot = self.record()
        assert "lenah" in slot["kalos_restaurant_records"]
        assert self.state["bag"].get("小蘑菇", 0) > 0

        self.counter("kalos_hotel", "经理")
        self.choose("客房送餐")
        order = " ".join(self.state["dialog"])
        for _ in range(4):
            self.choose(next(word for word in self.state["buttons"] if word in order))
        assert self.record()["kalos_hotel_perfect"] > 0
        for task, goal in [("整理床铺", [10,15]), ("寻找失物", [21,7])]:
            self.counter("kalos_hotel", "经理")
            self.choose(task)
            shift = self.record()["kalos_hotel_shift"]
            floor = "kalos_zone_" + str(136 + int(shift["floor"]))
            self.use_at(floor, goal)
            assert not self.record().get("kalos_hotel_shift"), (task, floor, goal)

        self.nurse("kalos_lumiose_center_magenta")
        mid = next(mid for mid, field in self.routes.fields.items() if field.data["kalos_zone"] == 110)
        self.counter(mid, "考官")
        self.choose("单打测验")
        for _ in range(3):
            self.choose(next(b for b in self.state["buttons"] if b not in ("取消","返回")))
        for _ in range(5):
            self.choose("进入对战")
        slot = self.record()
        assert "kalos_institute_best" in slot and not slot.get("kalos_institute")
        print("KALOS SERVICES PASS", slot["kalos_restaurant_records"], slot["kalos_hotel_perfect"], slot["kalos_institute_best"])

    def wild_patch(self, mid, kind):
        self.enter(mid)
        field = self.routes.fields[mid]
        land = {(x,y) for y,row in enumerate(field.data["physics"][kind]) for x,value in enumerate(row)
                if value and not field.get("collision",x,y) and not field.get("water",x,y) and (x,y) not in field.doors}
        cells = {(x,y) for x,y in land if any((x+dx,y+dy) in land for dx,dy,*_ in VECTORS.values())}
        self.go({(mid,*xy) for xy in cells})
        for _ in range(40):
            pace(self, Habitat(mid,mid,cells,{},1), "wild-survey", 8)
            foes = [fight for fight in self.state["fights"] if not fight[0]]
            if foes:
                print("KALOS HABITAT PASS", mid, kind, self.pos, foes)
                return
        raise AssertionError((mid,kind,"no wild encounter"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resume", type=Path, required=True, help="A champion save before today's hotel jobs")
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--pack", type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="kalos-city-") as tmp:
        folder = Path(tmp)
        shutil.copy2(args.resume, folder/"save.json")
        source = ["--main-pack",str(args.pack.resolve())] if args.pack else ["--path",str(ROOT)]
        cmd = [args.godot, "--headless", "--fixed-fps", "60", *source]
        player = CityPlayer(KalosRoutes(),cmd,dict(os.environ,POKESAGA_CHAPTER_TEST_DIR=tmp),folder)
        player.save_slot = folder/"save.json"
        try:
            player.services()
            for mid,kind in [("kalos_13","rough_terrain"),("kalos_21","red_flowers"),("kalos_21","purple_flowers")]:
                player.wild_patch(mid,kind)
        finally:
            player.do("quit")
            player.process.wait(timeout=10)


if __name__ == "__main__":
    main()
