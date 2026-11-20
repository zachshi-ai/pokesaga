#!/usr/bin/env python3
"""Play the first badge route in a fresh save, then verify it in a second process."""
import argparse
import os
import subprocess
import tempfile
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--godot", default="godot")
parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
parser.add_argument("--pack", type=Path, help="exercise this exported resource pack in place of the source project")
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix="pokesaga-chapter-") as directory:
    env = dict(os.environ, POKESAGA_CHAPTER_TEST_DIR=directory)
    source = ["--main-pack", str(args.pack.resolve())] if args.pack else ["--path", str(args.project.resolve())]
    for phase in ["play", "reload"]:
        subprocess.run([args.godot, "--headless", "--fixed-fps", "60", *source,
                        "--script", str(Path(__file__).with_suffix(".gd").resolve()), "--", phase],
                       cwd=directory, env=env, check=True)
