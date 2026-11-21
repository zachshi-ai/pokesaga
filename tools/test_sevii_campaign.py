#!/usr/bin/env python3
"""Play the first badge and continue an isolated copy through the Sevii network repair."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--godot", default="godot")
parser.add_argument("--pack", type=Path)
parser.add_argument("--entry-save", type=Path, help="reuse a save that earned the first badge")
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix="pokesaga-sevii-") as folder:
    source = ["--main-pack", str(args.pack.resolve())] if args.pack else ["--path", str(ROOT)]
    command = [args.godot, "--headless", "--fixed-fps", "60", *source, "--script"]
    env = dict(os.environ, POKESAGA_CHAPTER_TEST_DIR=folder)
    if args.entry_save:
        entry = args.entry_save.resolve()
    else:
        subprocess.run([*command, str(ROOT / "tools/test_first_chapter.gd"), "--", "play"],
                       cwd=folder, env=env, check=True)
        entry = Path(folder) / "save.json"
    env["POKESAGA_SEVII_ENTRY_SAVE"] = str(entry)
    subprocess.run([*command, str(ROOT / "tools/test_sevii_campaign.gd")], cwd=folder, env=env, check=True)
