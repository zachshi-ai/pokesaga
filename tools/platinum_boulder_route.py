"""Replay the six original Distortion World rock pushes via ordinary controller input."""
from campaign_route import VECTORS

PUSHES = {
    's_drop_uxie': 'd', 's_drop_mesprit': 'r', 's_drop_azelf': 'l',
    's_boulder_uxie': 'ddddl', 's_boulder_mesprit': 'lllllllu', 's_boulder_azelf': 'lld',
}


def push(player, event):
    key = event['id']
    mid = player.registry[event['map']]
    actor = event['trigger']['actor']
    start_x, start_y = player.local(mid, *event['trigger']['at'])
    player.enter(mid)
    # Precompute the exact footprint of the original solution so a saved partial
    # puzzle can continue from the position reported by the live field engine.
    x, y = start_x, start_y
    moves = {}
    for direction in PUSHES[key]:
        moves[x,y] = direction
        dx,dy,*_ = VECTORS[direction]
        x += dx
        y += dy
    for _ in range(len(moves)):
        if key in player.state['flags']:
            return
        row = next(r for r in player.state['actors'] if r[8] == actor)
        at = tuple(map(int, row[0]))
        direction = moves[at]
        dx,dy,*_ = VECTORS[direction]
        player.visit(mid, (at[0]-dx,at[1]-dy), direction)
    assert key in player.state['flags'], (key,player.pos,player.state['dialog'])
