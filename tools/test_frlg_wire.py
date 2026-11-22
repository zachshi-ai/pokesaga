"""Two independent Godot processes share the Two Island games over real ENet."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def play(godot, mode, pack=None):
    project = ['--main-pack', str(pack.resolve())] if pack else ['--path', str(ROOT)]
    with tempfile.TemporaryDirectory() as tmp:
        peers = []
        for role in ('host', 'client'):
            path = Path(tmp) / role
            path.mkdir()
            peers.append(subprocess.Popen([godot, '--headless', '--fixed-fps', '60', *project,
                        '--script', str(ROOT/'tools/test_frlg_wire.gd'), '--', mode, role], stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT, text=True, cwd=tmp if pack else ROOT, env=dict(os.environ, POKESAGA_CHAPTER_TEST_DIR=str(path))))
            if role == 'host':
                time.sleep(1)
        results = []
        try:
            for peer in peers:
                out = peer.communicate(timeout=150)[0]
                print(out, flush=True)
                assert peer.returncode == 0 and 'ERROR:' not in out, out
                results.append(json.loads(next(l[12:] for l in out.splitlines() if l.startswith('WIRE RESULT '))))
        finally:
            for peer in peers:
                if peer.poll() is None:
                    peer.kill()
                    peer.wait()
        if mode == 'jump':
            assert results[0] == results[1] and results[0]['amount'] == 1 and results[0]['points'] >= 5000, results
        elif mode == 'battle':
            assert [r['wins'] for r in results] == [1, 0], results
        else:
            assert max(r['points'] for r in results) >= 3000 and sum(r['amount'] for r in results) >= 1, results


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--godot', default='godot')
    ap.add_argument('--pack', type=Path)
    ap.add_argument('--mode', choices=['jump','dodrio','battle'])
    args = ap.parse_args()
    for game in ([args.mode] if args.mode else ('jump', 'dodrio', 'battle')):
        play(args.godot, game, args.pack)
    print('TWO ISLAND WIRE PASS')
