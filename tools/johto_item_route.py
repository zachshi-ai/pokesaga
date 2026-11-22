"""Collect and operate Crystal's key items on the campaign player's existing save."""


def collect(p, room, xy, flag, item, choices=()):
    if flag not in p.state["flags"]:
        p.interact("johto_"+room,xy)
        for choice in choices:
            p.do("click",label=choice)
        p.milestone(flag)
    assert p.state["bag"].get(item,0)>0, (room,item,p.state["dialog"])


def back_to_field(p):
    for _ in range(4):
        if not p.state["panels"]: return
        p.do("back")
    assert not p.state["panels"], p.state["buttons"]


def use(p, item, choices=()):
    p.key_item(item)
    for choice in choices:
        p.do("click",label=choice)
    back_to_field(p)


def cherrygrove(p):
    collect(p,"cherrygrove_city",(16,3),"j_map_card","地图卡",["好"])
    use(p,"宝可装置",["时钟"])
    use(p,"地图卡")


def cast(p, room, rod):
    from campaign_route import VECTORS
    mid="johto_"+room
    field=p.routes.fields[mid]
    shores={}
    for y in range(field.h):
        for x in range(field.w):
            if field.get("water",x,y) or field.get("collision",x,y) or (x,y) in field.doors: continue
            for key,(dx,dy,*_) in VECTORS.items():
                xx,yy=x+dx,y+dy
                if 0<=xx<field.w and 0<=yy<field.h and field.get("water",xx,yy):
                    shores[mid,x,y]=key
    p.go(set(shores))
    start=p.pos
    p.do("turn",dir=shores[start])
    assert p.pos==start,(start,p.pos)
    p.key_item(rod)
    assert p.state["fights"],(room,rod,p.state["dialog"])
    back_to_field(p)


def route32(p):
    collect(p,"route_32_pokecenter_1f",(0,2),"j_old_rod","破旧钓竿")
    cast(p,"route_32","破旧钓竿")


def goldenrod(p):
    collect(p,"goldenrod_bike_shop",(3,1),"j_bicycle","自行车")
    p.enter("johto_goldenrod_city")
    use(p,"自行车")
    use(p,"自行车")
    collect(p,"radio_tower_1f",(6,3),"j_radio_card","收音机卡",["参加","对","对","不对","对","不对"])
    use(p,"收音机卡",["8.5　幸运频道"])
    collect(p,"radio_tower_2f",(7,2),"j_blue_card","蓝卡")
    use(p,"蓝卡")
    collect(p,"goldenrod_underground",(3,12),"j_coin_case","代币盒")
    use(p,"代币盒")


def ecruteak(p):
    collect(p,"route_36",(22,4),"j_rock_smash","城都招式学习器 08")
    collect(p,"ecruteak_itemfinder_house",(1,1),"j_finder","探宝器")
    use(p,"探宝器")


def olivine(p):
    collect(p,"olivine_good_rod_house",(1,1),"j_good_rod","好钓竿")
    cast(p,"olivine_city","好钓竿")
    collect(p,"olivine_cafe",(2,1),"j_strength","秘传学习器 04")


def cianwood(p):
    collect(p,"cianwood_city",(5,23),"j_fly","秘传学习器 02")


def ice_path(p):
    collect(p,"ice_path_1f",(15,3),"j_waterfall","秘传学习器 07")


def scale(p):
    if "j_exp_share" not in p.state["flags"]:
        collect(p,"mr_pokemons_house",(1,2),"j_exp_share","学习装置",["交换"])
        assert not p.state["bag"].get("红色鳞片",0)


def kanto(p):
    collect(p,"route_12_super_rod_house",(2,1),"j_super_rod","厉害钓竿")
    cast(p,"route_12","厉害钓竿")
    collect(p,"pewter_city",(14,8),"j_silver_wing","银色之羽")
    use(p,"银色之羽")
