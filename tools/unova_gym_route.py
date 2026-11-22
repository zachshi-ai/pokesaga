"""Operate the original Unova floor and book switches and challenge required Gym Trainers."""
def prepare(player,key):
    if key=='u1_badge_1':
        mid='unova_bw_gym_striaton'
        for xy in ((15,36),(9,26),(12,16)):
            player.go({(mid,*xy)})
    if key=='u1_badge_2':
        mid='unova_bw_gym_nacrene'
        player.enter(mid)
        for i,at in enumerate(((6,18),(5,10),(6,2),(12,18),(12,10))):
            flag={2:'u1_trainer_88',4:'u1_trainer_87'}.get(i)
            if flag and flag not in player.state['flags']:
                reader=next(r for r in player.state['actors'] if len(r)>10 and r[10]==flag)
                player.use_at(mid,reader[0])
                assert flag in player.state['flags'],(flag,player.state['dialog'])
            player.use_at(mid,at)
    students={'u2_badge_1':('aspertia',(171,172)), 'u2_badge_2':('virbank',(178,179)), 'u2_badge_4':('nimbasa',(207,208,209))}
    if key in students:
        city,ids=students[key];mid='unova_b2_gym_'+city
        player.enter(mid)
        for tid in ids:
            flag='u2_trainer_%d'%tid
            if flag in player.state['flags']:continue
            actor=next((r for r in player.state['actors'] if len(r)>10 and r[10]==flag),None)
            if not actor:raise RuntimeError(('gym trainer missing',key,tid,player.state['actors']))
            player.use_at(mid,actor[0])
            if flag not in player.state['flags']:raise RuntimeError(('gym trainer',tid,player.pos,player.state['dialog']))
