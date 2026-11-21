"""Walk and interact through Crystal's Johto campaign with a newly chosen Totodile."""

import johto_item_route as items


def earned(p, flag):
    return flag in p.state["flags"] or flag in p.state["badges"]


def talk(p, room, xy, flag):
    if not earned(p, flag):
        role = {"j_basement_key":"j_fake_director","j_radio_free":"j_broadcast_boss"}.get(flag)
        p.interact("johto_" + room, xy, role=role)
        p.milestone(flag)


def opening(p):
    talk(p,"elms_lab",(2,1),"johto_elm_told")
    if not earned(p,"johto_starter"):
        p.interact("johto_elms_lab",(3,2))
        choice = next((s for s in p.state["buttons"] if s.startswith("小锯鳄")),None)
        if choice: p.do("click",label=choice)
        p.milestone("johto_starter")
    talk(p,"elms_lab",(1,4),"j_potion")
    items.cherrygrove(p)
    talk(p,"mr_pokemons_house",(1,2),"j_mystery_egg")
    talk(p,"cherrygrove_city",(18,3),"j_rival1")
    talk(p,"elms_lab",(2,1),"j_egg_return")
    talk(p,"elms_lab",(1,4),"j_balls")
    p.train("johto_route_31",12)
    talk(p,"sprout_tower_3f",(5,1),"j_flash")
    talk(p,"violet_gym",(2,0),"飞翼徽章")
    talk(p,"violet_pokecenter_1f",(2,1),"j_egg_aide")


def azalea(p):
    items.route32(p)
    talk(p,"kurts_house",(1,1),"j_kurt_well")
    talk(p,"slowpoke_well_b1_f",(2,1),"j_well_clear")
    p.train("johto_route_33",18)
    if not earned(p,"昆虫徽章"):
        p.enter("johto_azalea_gym")
        if getattr(p.routes.fields["johto_azalea_gym"], "header", ""):
            azalea_rail(p,True)
        talk(p,"azalea_gym",(2,3),"昆虫徽章")
        if getattr(p.routes.fields["johto_azalea_gym"], "header", ""):
            azalea_rail(p,False)
    talk(p,"azalea_town",(3,6),"j_rival2")
    talk(p,"ilex_forest",(3,14),"j_bird_request")
    if not earned(p,"j_bird_home"):
        talk(p,"ilex_forest",(7,15),"j_bird_1")
        p.visit("johto_ilex_forest",(7,11),face="d")
        p.milestone("j_bird_2")
        p.visit("johto_ilex_forest",(7,13),face="d")
        p.visit("johto_ilex_forest",(6,17),face="l")
        p.milestone("j_bird_home")
    talk(p,"ilex_forest",(2,14),"j_cut")
    talk(p,"charcoal_kiln",(2,1),"j_charcoal")
    p.teach("居合斩",15)
    talk(p,"ilex_forest",(4,12),"j_forest_path_clear")


def azalea_rail(p, inbound):
    room="johto_azalea_gym"
    def ride(before, direction, stop):
        p.go({(room,*before)})
        p.do("walk",legs=[[direction,[room,*stop]]])
        assert p.pos == (room,*stop),("Spinarak journey",before,stop,p.state["obstruction"],p.pos)
    def switch_at(before, direction):
        p.go({(room,*before)})
        p.do("face",dir=direction)
    if inbound:
        ride((3,33),"u",(9,23))
        ride((9,18),"u",(3,8))
        switch_at((4,8),"u")
        ride((3,8),"d",(3,18))
        switch_at((3,18),"l")
        ride((3,18),"u",(9,8))
    else:
        ride((9,8),"d",(3,18))
        switch_at((3,18),"l")
        ride((3,18),"u",(3,8))
        switch_at((4,8),"u")
        ride((3,8),"d",(9,18))
        ride((9,23),"d",(3,33))


def goldenrod(p):
    items.goldenrod(p)
    p.train("johto_route_34",23)
    talk(p,"goldenrod_gym",(4,1),"j_gym3")
    talk(p,"goldenrod_gym",(4,3),"j_whitney_calm")
    talk(p,"goldenrod_gym",(4,1),"标准徽章")
    talk(p,"route_36",(16,6),"j_floria")
    talk(p,"goldenrod_flower_shop",(1,2),"j_squirt")
    p.do("mode",value="train")
    talk(p,"route_36",(17,4),"j_tree_clear")
    p.do("mode",value="travel")


def ecruteak(p):
    items.ecruteak(p)
    talk(p,"burned_tower_1f",(4,4),"j_rival3")
    if not earned(p,"j_beasts"):
        p.visit("johto_burned_tower_b1_f",(5,2))
        p.milestone("j_beasts")
    p.train("johto_route_38",28)
    talk(p,"ecruteak_gym",(2,0),"魅影徽章")
    for i, xy in enumerate([(0,1),(1,0),(3,1),(4,0),(5,1)]):
        talk(p,"dance_theater",xy,"j_dance"+str(i))
    talk(p,"dance_theater",(3,5),"j_surf")
    p.teach("冲浪",57)


def coast(p):
    if not earned(p,"j_harbor_rival"):
        p.visit("johto_olivine_city",(6,6))
        p.milestone("j_harbor_rival")
    items.olivine(p)
    p.teach("怪力",70)
    talk(p,"olivine_lighthouse_6f",(4,4),"j_sick_amphy")
    p.train("johto_route_38",34)
    talk(p,"cianwood_pharmacy",(1,1),"j_medicine")
    talk(p,"cianwood_city",(5,7),"j_eusine_battle")
    talk(p,"cianwood_gym",(2,0),"打击徽章")
    items.cianwood(p)
    talk(p,"olivine_lighthouse_6f",(4,4),"j_lighthouse_cured")
    talk(p,"olivine_gym",(2,1),"矿物徽章")


def mahogany(p):
    p.do("mode",value="train")
    if not earned(p,"j_red_scale"):
        p.visit("johto_lake_of_rage",(9,12),face="u")
        p.milestone("j_red_scale")
    p.do("mode",value="travel")
    talk(p,"lake_of_rage",(10,14),"j_lance_lake")
    items.scale(p)
    p.enter("johto_mahogany_mart_1f")
    talk(p,"mahogany_mart_1f",(1,2),"j_base_open")
    for xy, flag in [((10,3),"j_slowtail"), ((2,7),"j_rattail"), ((4,1),"j_base_executive"), ((3,1),"j_voice")]:
        talk(p,"team_rocket_base_b3_f",xy,flag)
    talk(p,"team_rocket_base_b2_f",(9,7),"j_engine_boss")
    p.do("mode",value="train")
    for i in range(3):
        talk(p,"team_rocket_base_b2_f",(3,2+i),"j_electrode"+str(i))
    p.do("mode",value="travel")
    talk(p,"team_rocket_base_b2_f",(2,6),"j_plant_clear")
    talk(p,"mahogany_gym",(2,1),"冰川徽章")


def radio(p):
    talk(p,"radio_tower_5f",(1,3),"j_basement_key")
    talk(p,"goldenrod_underground",(9,3),"j_basement_open")
    talk(p,"goldenrod_underground_switch_room_entrances",(10,2),"j_rival4")
    if not earned(p,"j_switches"):
        for sid,x in [(2,0),(1,4),(0,7)]:
            if not earned(p,"j_switch_"+str(sid)):
                p.visit("johto_goldenrod_underground_switch_room_entrances",(x,2),face="u")
        p.milestone("j_switches")
    talk(p,"goldenrod_underground_warehouse",(6,4),"j_card_key")
    talk(p,"radio_tower_3f",(7,1),"j_radio_door")
    talk(p,"radio_tower_5f",(6,2),"j_radio_free")


def dragons_den(p):
    p.train("johto_route_44",45)
    items.ice_path(p)
    talk(p,"blackthorn_gym_1f",(2,1),"j_gym8")
    p.teach("潮旋",250)
    if not earned(p,"j_shrine_pass"):
        p.interact("johto_dragon_shrine",(2,0))
        for answer in ["伙伴","战术","强大的人","爱心","没有差别"]:
            p.do("click",label=answer)
        p.milestone("升龙徽章")
    p.teach("攀瀑",127)
    talk(p,"dragons_den_b1_f",(7,15),"j_den_tm")
    talk(p,"dragon_shrine",(2,0),"j_dratini")
    talk(p,"elms_lab",(2,1),"j_master_ball")


def main_story(p):
    stages = [(opening,"j_egg_aide"), (azalea,"j_forest_path_clear"),
              (goldenrod,"j_tree_clear"), (ecruteak,"j_surf"), (coast,"j_gym6"),
              (mahogany,"j_gym7"), (radio,"j_radio_free"), (dragons_den,"j_master_ball")]
    for play_stage, completed in stages:
        if not earned(p,completed):
            play_stage(p)
