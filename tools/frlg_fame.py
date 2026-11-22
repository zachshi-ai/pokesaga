"""Project script sources of all 96 Fame Checker entries onto the runtime maps."""
import re



def extract(source, root, read, compact, blocks):
    global_scripts = blocks((source / 'data/scripts/fame_checker.inc').read_text())
    sources = {compact(f.parent.name): f for f in (source / 'data/maps').glob('*/map.json')}
    output = {}
    for region in ['kanto', 'sevii']:
        for path in sorted((root / 'content/regions' / region / 'maps').glob('*.json')):
            game_map = read(path)
            native = root / 'content/emerald_maps' / (game_map.get('emerald', '') + '.json')
            members = (read(native).get('member_maps', {}) if native.exists() else {}) or {game_map.get('emerald',path.stem): [0, 0]}
            entries = {}
            for member, (dx, dy) in members.items():
                orig_path = sources.get(compact(member)) or sources.get(compact(path.stem))
                if not orig_path:
                    continue
                m = read(orig_path)
                scripts = dict(global_scripts)
                if orig_path.with_name('scripts.inc').exists():
                    scripts.update(blocks(orig_path.with_name('scripts.inc').read_text()))
                for kind in ('object_events', 'bg_events'):
                    for obj in m.get(kind) or []:
                        label = obj.get('script', '')
                        if label not in scripts:
                            continue
                        todo = [label]
                        visited = set()
                        clues = set()
                        while todo:
                            node = todo.pop()
                            if node in visited:
                                continue
                            visited.add(node)
                            body = scripts[node]
                            clues.update(person + str(index) for person, index in
                                         re.findall(r'famechecker FAMECHECKER_(\w+), (\d+)\b', body))
                            todo.extend(l for l in re.findall(r'\b\w+_EventScript_\w+\b', body)
                                        if l in scripts and l not in visited)
                        if not clues:
                            continue
                        key = f"{dx + obj['x']},{dy + obj['y']}"
                        entries[key] = {'clues': sorted(clues), 'field': kind == 'bg_events' or obj.get('movement_type') == 'MOVEMENT_TYPE_INVISIBLE',
                                        'gfx': obj.get('graphics_id',''), 'flag': obj.get('flag','0'),
                                        'source':label}
            if entries:
                output[f'{region}/{path.stem}'] = entries
    return output
