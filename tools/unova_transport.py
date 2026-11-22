"""Versioned institutional floors, scheduled transport and non-roaming zone templates."""
from collections import defaultdict
import json
import numpy as np
from unova_art import ROOT

def annotate(src,data,append):
    floors=defaultdict(list)
    def nearest(a,pos,allow_water=False,unoccupied=False):
        cells=np.argwhere(~a['collision'])[:,::-1] if allow_water else a['coords']
        if unoccupied:
            used={tuple(w['at']) for w in a['warps']}|{tuple(x) for x in a['anchors'].values()}
            valid=cells[[tuple(pt) not in used for pt in cells]]
            if len(valid):cells=valid
        return cells[np.argmin(np.abs(cells-pos).sum(axis=1))]
    def pair(i,pa,j,pb,tag,gate=''):
        if i not in data or j not in data:return
        a,b=data[i],data[j]
        p=nearest(a,pa if pa is not None else a['spawn'],unoccupied=True);q=nearest(b,pb if pb is not None else b['spawn'],unoccupied=True)
        extra={'unova_requires':[gate],'unova_denied':'这里会在合众联盟的故事告一段落后开放。'} if gate else {}
        append(a,p,b,q,source=tag,**extra);append(b,q,a,p,source=tag)
    for i,a in data.items():
        z=a['z'];mid=z['mid'];reason=''
        if (src.era=='b2' and z['matrix']==44 and not z['warps'] and not z['triggers'] and (not z['npcs'] or i in (216,224,226))):reason='同一空置矩阵 / 未使用的旧版或测试场景'
        if i in (150,151,422):reason='本地联机接待区或通信对战房间'
        elif 279<=i<=316:reason='C-Gear 连入 / 无线造访其他玩家世界的专用矩阵'
        elif i in (147,148,149):reason='联合塔按网络交换国家生成访客楼层'
        elif i in (424,425,426):reason='白版与白2版时期的白色森林'
        elif src.era=='b2' and i in (478,480,482,485,487,492):reason='白2版的白色树洞设施'
        elif src.era=='b2' and i in (564,*range(526,531)):reason='白2版替换的船舱或四号道路建筑'
        elif src.era=='b2' and i in (*range(537,543),594,595):reason='白2版反转山或冠军之路的替换场景'
        elif src.era=='b2' and i in (597,598,599,600,601,603,606,607):reason='回忆连接专用的两年前过场布景'
        elif src.era=='b2' and i==139:reason='旧版联盟过场中庭副本'
        elif i==145:reason='登录名人堂的结尾演出场景'
        if reason:a['technical']=reason
        if not (i in range(44,62) or (src.era=='b2' and (i in range(543,551) or i==494 or i in range(96,107)))):continue
        # Shared global elevator scripts key the corresponding floor list; the
        # other sign in the same car calls the elevator's description.
        buttons=[v for v in z['bg'] if (10405<=int(v['script'])<=10411 or 10419<=int(v['script'])<=10422) and 'grid' in v]
        for v in buttons[:1]:
            p=(v['grid']['x'],v['grid']['y']+1)
            floors[v['script']].append((i,p))
    for i in (75,76):
        # Subway battle cars are loaded for an active challenge and unload after the bout.
        if i in data:data[i]['technical']='对战地铁挑战中的对战车厢实例'
    for rows in floors.values():
        rows.sort()
        for (i,p),(j,q) in zip(rows,rows[1:]):pair(i,p,j,q,'elevator')
    # The Musical's contest itself uses the stage as a performance scene.
    if 78 in data:data[78]['technical']='宝可梦音乐剧登台演出场景'
    pair(74,(16,14),418,None,'anville_train')
    pair(39,(19,16),52,(29,29),'royal_unova','u1_ghetsis' if src.era=='bw' else 'u2_champion')
    for row in json.loads((ROOT/'content/unova_side_events.json').read_text()):
        if row['era']!=src.era or 'destination' not in row:continue
        for a in data.values():
            if a['z']['mid']==row['map']:a.setdefault('script_links',[]).append(row['destination'])
    if src.era=='b2':
        # Clay Tunnel's miners drive the individual original minecart routes.
        # Endpoints are the player arrival cells in each worker's field script.
        for i,pa,j,pb in [(506,(27,38),507,(27,14)),(506,(16,7),508,(19,35)),
                          (506,(24,14),508,(56,84)),(508,(26,73),508,(58,90)),
                          (508,(26,48),508,(47,88))]:
            pair(i,pa,j,pb,'minecart')
        # Liberty Garden is an open scheduled ferry destination in the sequel.
        pair(36,None,235,None,'liberty_ferry')
        # Black Tower's lobby loads individual floor templates on demand.
        for i in (481,483,484,486,493):
            if i in data:data[i]['technical']='黑色摩天楼挑战加载的楼层实例'
        if 518 in data:data[518]['technical']='二十个隐藏洞穴入口共同加载的遭遇场景'
        # All three key chambers return to the same original antechamber.
        for i in (609,610,611,612,613):pair(565,(15+(i-611)*2,2),i,(15,61),'ruins_chamber','u2_champion')
        for p,j,q in [((15,21),554,(11,5)),((26,10),555,(7,14)),((4,10),557,(8,9))]:
            pair(561,p,j,q,'frigate_warp_pad')
    if 240 in data:
        # The four original surfacing scripts store the incoming surface tile
        # for the corresponding northern, western, eastern and southern shaft.
        bay=data[240]
        origins=((801,276),(786,290),(816,290),(801,308))
        for j,world_pos in enumerate(origins):
            pos=np.asarray(world_pos)-bay['origin']
            b=data.get(241+j)
            if b is None:continue
            p=nearest(bay,pos,True,True);q=nearest(b,b['spawn'],True,True)
            append(bay,p,b,q,source='dive',unova_requires=['u%d_hm_6'%(1 if src.era=='bw' else 2)],unova_denied='需要会潜水的伙伴才能进入海底遗迹。');append(b,q,bay,p,source='surface',surf_arrival=True)
    for i,pa,j,pb in [(245,(80,76),246,(30,32)),(246,(14,20),247,(42,24)),(247,(41,25),248,(13,22))]:
        pair(i,pa,j,pb,'abyssal_stairs')

def scheduled_exits(era,data):
    def destination(name,point):return dict(map=name,at=point)
    def remember(a,names):
        a['dynamic_exits']=True
        a['script_links']=sorted(set(a.get('script_links',[]))|set(names))
    # Big Stadium and Small Court share a single pad per lobby. The RTC changes
    # the active sport (and thus the room and arrival coordinates) each day.
    for lobby,row in [(79,[82,82,83,81,82,83,81]),(84,[86,86,87,86,87,86,87])]:
        a=data[lobby]
        fields={data[i]['z']['mid'] for i in row}
        doors=[w for w in a['warps'] if w['source_warp'].startswith('native_return_') and w['to']['map'] in fields]
        bymap={w['to']['map']:w['to'] for w in doors}
        if not all(data[i]['z']['mid'] in bymap for i in row):continue
        choices=[bymap[data[i]['z']['mid']] for i in row]
        doors[0]['to']=dict(doors[0]['to'],unova_stadium_days=[destination(t['map'],t['at']) for t in choices])
        a['warps']=[w for w in a['warps'] if w not in doors[1:]]
        remember(a,bymap)
    if era!='b2':return
    decks=[data[i]['z']['mid'] for i in (552,1001,562,1002)]
    abroad={data[i]['z']['mid'] for i in (191,463,233,238)}
    for i,port in ((552,191),(1001,463),(562,233),(1002,238)):
        a=data[i];portname=data[port]['z']['mid']
        a['warps']=[w for w in a['warps'] if (w['to']['map'] not in abroad or w['to']['map']==portname) and w['to']['map']!=data[563]['z']['mid']]
    # The left/right Frigate layout is version-dependent. The alternate front
    # room is not entered on the Black 2 (switches, then password) branch.
    if 563 in data:data[563]['technical']='白2版等离子驱逐舰的替换前舱'
    for i in (553,554,558,563):
        a=data[i];groups=defaultdict(list)
        for w in a['warps']:
            if w['to']['map'] in decks:groups[tuple(w['at'])].append(w)
        for warps in groups.values():
            bymap={w['to']['map']:w['to']['at'] for w in warps}
            standard=bymap.get(decks[0],warps[0]['to']['at'])
            frozen=bymap.get(decks[2],[32,15] if standard[1]<30 else [32,48])
            points=[standard,standard,frozen,standard]
            choices={str(k):destination(name,points[k]) for k,name in enumerate(decks)}
            warps[0]['to']=dict(warps[0]['to'],unova_dock_returns=choices)
            a['warps']=[w for w in a['warps'] if w not in warps[1:]]
            remember(a,decks)
    # Black 2's shared bridge/engine room always returns to its Black entrance.
    data[556]['warps']=[w for w in data[556]['warps'] if w['to']['map']!=data[563]['z']['mid']]
