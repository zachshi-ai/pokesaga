"""Player actions in the Magma Hideout. Each boulder must be pushed before walking."""
from hoenn_field_route import cavern_plan, machine


def prepare(player, event):
    # Native collision starts with each Elite Four door closed. Mirror only the
    # metatiles the preceding victory actually opened before planning the walk.
    for field in player.routes.fields.values():
        door=field.data.get("mechanisms",{}).get("league_exit")
        if door and door["flag"] in player.state["flags"]:
            for x,y,_,_,blocked in door["open"]:
                field.grid["collision"][y*field.w+x]=blocked
    player.routes.edges.cache_clear()
    if event["id"] != "h_magma_tabitha":
        return
    machine(player,70)
    first="em_magma_hideout_1f"
    player.enter(first)
    field=player.routes.fields[first]
    goal=(25,34)
    path=cavern_plan(field,player.pos[1:],goal,player.routes.occupied.get(first,()))
    for kind,key,cell in path:
        if kind=="push":
            player.do("face",dir=key)
        player.do("walk",legs=[[key,(first,*cell)]])
        assert player.pos==(first,*cell),("Magma Hideout",kind,key,cell,player.pos,player.state["dialog"])
    door=field.doors[goal]["to"]
    player.do("walk",legs=[["d",(door["map"],*door["at"])]])
    assert player.pos[0]==door["map"],("Magma Hideout stairs",player.pos)
