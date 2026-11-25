"""The six field cells inserted by HeartGold's PlaceSafariZoneAreas (default set zero)."""
import re

AREA = re.compile(r"^MAP_SAFARI_ZONE_(0[1-9]|1[0-2])$")
ENTRY = "MAP_SAFARI_ZONE_ENTRANCE_EXTERIOR"
# src/safari_zone.c sSafariZoneDefaultAreaSets[0], ordered like map_matrix.c.
# Keeping map IDs per area also preserves the terrain and field saves for each template.
DEFAULT = ((1,8,2),(6,4,7))


def outdoors(hid):
    return hid == ENTRY or AREA.fullmatch(hid) is not None


def passages(hid, names, walkable):
    cells = {(x,y):f"MAP_SAFARI_ZONE_{num:02}" for y,row in enumerate(DEFAULT) for x,num in enumerate(row)}
    cells[1,2] = ENTRY
    zone = next((pos for pos,key in cells.items() if key==hid),None)
    if zone is None:
        return {}
    result = {}
    for dx,dy,direction in ((0,-1,"up"),(0,1,"down"),(-1,0,"left"),(1,0,"right")):
        other=cells.get((zone[0]+dx,zone[1]+dy))
        if not other:continue
        for n in range(32):
            x=0 if dx==-1 else 31 if dx==1 else n
            y=0 if dy==-1 else 31 if dy==1 else n
            tx=(x+dx)%32;ty=(y+dy)%32
            if not (walkable(hid,x,y) and walkable(other,tx,ty)):continue
            result[x,y]={"at":[x,y],"trigger":direction,"edge":True,
                         "to":{"region":"johto","map":names[other],"at":[tx,ty],"hgss":True}}
    return result


def install_counter(fields):
    lobby=fields["hgss_safari_zone_entrance_interior"]
    exterior=fields["hgss_safari_zone_entrance_exterior"]
    for x in (5,19):
        # D47R0101_001 asks for 500 at the counter, then scripts a walk past
        # the closed barrier and warps to global (79,100) in matrix 212.
        lobby["warps"].append({"at":[x,6],"trigger":"up","to":{
            "region":"johto","map":"hgss_safari_zone_entrance_exterior",
            "at":[15,4],"facing":"up","hgss":True,"johto_safari_admission":True}})
    for w in exterior["warps"]:
        if w["to"]["map"]=="hgss_safari_zone_entrance_interior":
            # The exit script walks through the staff gate, back to the public lobby.
            w["to"].pop("recall_passage",None)
            w["to"]["at"]=[5,6]
