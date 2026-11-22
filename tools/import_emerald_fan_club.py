"""Build Emerald Easy Chat, Bard vocal templates and the Route 119 fishing index from pret/pokeemerald."""
import argparse
import base64
import io
import json
from pathlib import Path
import re
import subprocess
import struct
import wave

ROOT = Path(__file__).resolve().parents[1]
CHINESE = {
    'trainer':'就决定是你 收服了 交换 蓝宝石 进化 百科 性格 中心 蛋 连接 特殊能力 训练家 版本 宝可导航 宝可梦 获得 图鉴 红宝石 等级 红 绿 背包 火焰 金 叶子 银 绿宝石',
    'status':'恶 恶臭 厚脂肪 雨盘 降雨 沙穴 威吓 坚硬脑袋 颜色 异色 岩石 美丽 美丽度 气闸 超能力 怪力钳 格斗 踩影 聪明 聪明度 加速 帅气 帅气度 战斗盔甲 可爱 可爱度 结实 吸盘 草 恒净之躯 激流 幽灵 冰 毅力 粗糙皮肤 硬壳盔甲 自然回复 湿气 地面 柔软 磁力 白色烟雾 同步 茂盛 悠游自如 扬沙 沙隐 锐利目光 精神力 静电 属性 强壮 强壮度 蜕皮 大力士 蓄电 储水 电 阴晴不定 天恩 毒 毒刺 龙 复制 迟钝 懒惰 逃跑 黏着 无关天气 一般 钢 发光 早起 活力 闪耀 飞行 日照 避雷针 复眼 神奇鳞片 神奇守护 不眠 飘浮 正电 压迫感 污泥浆 变色 隔音 孢子 宝可病毒 火 火焰之躯 负电 我行我素 熔岩铠甲 水 水幕 虫 虫之预感 迷人之躯 免疫 猛火 捡拾 花纹 引火 干劲 叶绿素 瑜伽之力 鳞粉',
    'battle':'交锋 上吧 第一名 决定 让我赢 获胜 赢 赢了 如果我赢 等我赢了 赢不了 能赢 敌不过 斗志 决出了 王牌 接招 放马过来 攻击 投降 勇敢 天赋 策略 痛击 比赛 胜利 攻势 感觉 对阵 交手 力量 挑战 强大 太强了 手下留情 敌人 天才 传说 逃脱 瞄准 对战 战斗 复苏 得分 认真 放弃 败北 如果我输 输了 输 防守 搭档 拒绝 接受 无敌 收到了 轻松 弱小 太弱了 不堪一击 首领 规则 招式',
    'greetings':'多谢 是 这就开始 我来了 就是这个 好呀 欢迎 喂 你好啊 恭喜 给我 对不起 道歉 原谅 嘿你好 你好 再见 谢谢你 我到了 请原谅 借过 回见 打扰了 那么 请先 感激 嘿？ 怎么啦 咦？ 不 嗨 对对 拜拜 幸会 嘿 闻闻 我在听 哟呵 万岁 哟 过来吧 靠你了',
    'people':'对手 我 你 你的东西 儿子 你的 你是 你已经 妈妈 爷爷 叔叔 爸爸 男孩 大人 兄弟 姐妹 奶奶 阿姨 家长 男人 我自己 女孩 宝贝 家人 她的 他本人 他 地方 女儿 他的 他是 不是 兄弟姐妹 孩子 孩子们 先生 太太 我本人 以前的我 对我 我的 我是 我已经 谁 某人 以前是谁 给谁 谁的 谁是 它是 女士 朋友 同伴 人 老兄 他们 以前的他们 给他们 他们的 他们是 他们已经 我们 曾经 给我们 我们的 我们是 劲敌 我们已经 女人 她 以前的她 给她 属于她 她是 一些',
    'voices':'！ ！！ ？！ ？ …… ……！ ………… —— ———— 不妙 哇啊 啊哈哈 哦？ 不了 唔 呣 哇喔 嗷呜 哇 嘻嘻 唉 难以置信 哭声 同意 诶？ 呜呜 诶嘿嘿 喂喂喂 噢耶 哦 哎呀 震惊 呀 咯啊 哇哈哈哈 绝了 啧 嘿嘿 哈 嗯对 哈哈哈 哎哟 嘿呀 呼呼呼 笑死 哼哧 哼 嘿嘿嘿 嘿 哦呵呵 嗯哼 哎哟喂 可恶 姆呼呼 嗯嗯 好——吧 好吧 啦啦啦 耶 啊呀 哇噢 嘎哇 哇哈哈',
    'speech':'听 不太 意思 说谎 放下 推荐 笨蛋 相当 来自 感觉 但是 然而 情况 这支 错过 怎样 击中 足够 很多 一点点 绝对 和 仅仅 周围 大概 如果 非常 一丁点 野生 那就是 正好 即使如此 肯定 自然 目前 明白了 开玩笑 准备好了 某样东西 不知怎么 虽然 也 完美 尽可能 确实 真心 认真地 完全 直到 仿佛 心情 宁愿 极其 模式 更多 太晚了 终于 任何 改为 极妙',
    'endings':'将会 将会来到 或者 次 想知道 是吗 成为 给我吧 可以 可能会 会 是 对吧 一起来 其他 是的 曾是 原来是 那些 并非 不会 不能 能 别 来跳 做着 谁 哪个 原来不是 那时不是 拥有 还没有 一个 一位 不 在那里 好吗 于是 或许 关于 结束 它 全部 为了 在上面 关掉 作为 到 和谁一起 更好 曾经 自从 的 归属于 在 在里面 外出 也 像 做过 没做 没有 缺少 之后 之前 同时 比 一度 任何地方',
    'feelings':'见面 玩耍 匆忙 前去 兴高采烈 高兴 幸福 兴奋 重要 滑稽 得到了 回家 失望 令人失望 难过 尝试 试试看 听见 想 听 想要 听错 讨厌 生气 怒火 可怕 孤单 扫兴 喜悦 得到 从不 可恶 沮丧 不可思议 喜爱 不喜欢 无聊 关心 在乎 没问题 热爱 灾难 享受 乐在其中 吃 不足 坏 艰难 糟糕 应该 不错 喝 惊喜 害怕 想要的 等待 满意 看 稀有 消极 完成 危险 被击败 战胜 太好了 浪漫 疑问 理解 懂得',
    'actions':'相遇 承认 给予 送出 玩过 玩着 搜集 正在走 走路 说着 去了 说过 醒来 醒了 惹怒 教 教导 请 学习 改变 故事 信任 挥霍 聆听 听到 锻炼 选择 前来 来过 搜寻 制作 引起 知道 明白 拒绝 存放 夸口 不知情 思考 相信 滑行 吃着 使用 用了 正在用 办不到 能干 消失 出现 扔 担心 睡过 睡觉 放走 喝着 跑着 奔跑 工作 正在工作 正在说 说话 下沉 拍打 假装 称赞 过度 展示 看起来 看到 寻找 拥有 带走 允许 忘记 忘了 现身 晕倒 倒下了',
    'time':'秋天 早晨 明天 上次 天 某天 总是 当前 永远 日子 结束 星期二 昨天 今天 星期五 星期一 稍后 之前 另一次 时间 完结 星期三 很快 开始 月 停止 现在 最终 下次 年龄 星期六 夏天 星期日 开端 春天 白天 冬天 每天 从前 差一点 将近 星期四 夜间 夜晚 星期',
    'misc':'高峰 低谷 呃 后面 事物 东西 下方 上方 背面 高处 这里 里面 外面 旁边 就是它 这个 每一个 这些 这些曾经是 向下 那个 那些是 那些曾经是 没错 上午 那曾经是 前面 向上 选择 远方 离开 附近 哪里 何时 什么 深处 浅处 为什么 困惑 相反 左 右',
    'adjectives':'漂泊 摇摇欲坠 坚如磐石 饥饿 紧绷 怕痒 旋转 盘旋 口渴 懒洋洋 丝滑 悲伤地 无望 无用 流口水 刺激 厚实 光滑 黏滑 纤细 断裂 狼吞虎咽 散开 了不起 胆小 摇晃 发抖 撕破 碎裂 增长 仍然 毁坏 火热 亲昵 快乐地 期待',
    'events':'演出 活动 待在家 树果 华丽大赛 主持人 评审 超级 舞台 名人堂 进化 高级 对战塔 馆主 对战房间 隐藏 秘密基地 混合 宝可方块 大师 等级 奖章 压榨 直接 塔 联盟 房间 无线 开拓区',
    'conditions': '火热 存在 过多 认可 拥有 美好 较少 势头 前进 奇怪 忙碌 一起 满满 缺席 正在 需要 美味 熟练 吵闹 巨大 迟到 亲近 温顺 有趣 开心 完美 漂亮 健康 优秀 颠倒 寒冷 清爽 不可避免 很多 压倒性 极好 其他 昂贵 正确 不可能 小小 不同 疲倦 技巧 顶尖 不停 荒唐 没有 空无 自然 变成 温热 迅速 低下 糟糕 独自 无聊 秘密 神秘 缺少 最棒 很差 错误 和善 顺利 虚弱 简单 好像 严重',
    'lifestyle': '家务 家 金钱 零花钱 洗澡 交谈 学校 纪念 习惯 团体 单词 商店 服务 工作 系统 火车 班级 功课 消息 生活 老师 大会 书信 活动 数码 测验 百货商店 电视 电话 道具 名字 新闻 人气 聚会 学习 机器 邮件 留言 约定 梦想 幼儿园 人生 收音机 租借 世界',
    'hobbies': '偶像 动画 歌曲 电影 糖果 聊天 儿戏 玩具 音乐 卡牌 购物 相机 观赏 观众 美食家 游戏 角色扮演 收藏 齐全 杂志 散步 自行车 爱好 体育 软件 歌谣 减肥 宝藏 旅行 舞蹈 频道 制作 钓鱼 约会 设计 火车头 玩偶 电脑 鲜花 英雄 午睡 女英雄 时尚 冒险 棋盘 球 书 祭典 漫画 假日 计划 时髦 度假 造型',
    'trendy_saying':'谢啦回见 遵命 前卫 情侣 感激不尽 好耶 超级 一击必胜 命运 取消 新鲜 压平 开玩笑 败者 落败 大事件 时髦的 摇摆 可疑 轻快 摩登 回头见 砰 击倒 麻烦 胜者 狂热 追星族 宝贝 心 老派 年轻 丑萌',
}
DEFAULT_CN={'SHAKE':'摇摆','IT':'它','DO':'来跳','THE':'这支','DIET':'减肥','DANCE':'舞蹈'}

def build(source):
    def blob(name):
        p=source/name
        return p.read_bytes() if p.is_file() else subprocess.check_output(['git','-C',str(source),'show','HEAD:'+name])
    def raw(p): return blob(p).decode()
    def names(kind):
        return {r['key']:r for r in json.loads((ROOT/'content'/f'{kind}.json').read_text())}
    ec=raw('include/constants/easy_chat.h')
    cats={k.lower():int(n) for k,n in re.findall(r'^#define EC_GROUP_(\w+)\s+(\d+)\s*$',ec,re.M)}
    definitions={w:(cats[g.lower()]*512+int(i)) for w,g,i in re.findall(r'#define EC_WORD_(\w+)\s+\(\(EC_GROUP_(\w+) << EC_MASK_BITS\) \| (\d+)\)',ec)}
    notes=raw('src/bard_music.c')
    lengths={k:int(n) for k,n in re.findall(r'\[PHONEME_ID\((PH_\w+)\)\] = (\d+)',notes)}
    ph_keys=list(lengths)
    pitch=[[int(v.strip(),0)//256 for v in row.split(',') if 'PITCH_END' not in v] for row in re.findall(r'sPitch7_\d\[\] = \{ (.*?) \};',notes)]
    sounds={}
    unavailable=[]
    display={}
    def templates(t):
        out={}
        for k,body in re.findall(r'^    \[(?:EC_INDEX\()?((?:EC_WORD_|SPECIES_|MOVE_)\w+)\)?\] = \{(.*?)^    \}',t,re.M|re.S):
            seq=[]
            for match in re.finditer(r'\{\s*\.songId = PHONEME_ID\((PH_\w+)\)([^}]*)\}|PREV_BARD_SOUND',body):
                if match[0]=='PREV_BARD_SOUND':
                    if seq:seq[-1][1]+=15
                    continue
                name=match[1]
                adjustment=re.search(r'lengthAdjustment = (-?\d+)',match[2])
                seq.append([ph_keys.index(name),lengths[name]+(int(adjustment[1]) if adjustment else 0)])
            out[k]=seq
        return out
    groups={}
    for cat,gid in cats.items():
        file_cat={'pokemon_national':'pokemon2'}.get(cat,cat)
        table=raw('src/data/easy_chat/easy_chat_group_'+file_cat+'.h')
        stem='pokemon' if cat in ('pokemon','pokemon_national') else ('moves' if cat.startswith('move_') else cat.replace('trendy_saying','trendysaying'))
        tracks=templates(raw('src/data/bard_music/'+stem+'.h'))
        rows=[]
        if gid in (0,18,19,21):
            is_mon=gid in (0,21)
            which='SPECIES' if is_mon else 'MOVE'
            constants=raw('include/constants/'+('species' if is_mon else 'moves')+'.h')
            ids={k:int(v) for k,v in re.findall(r'^#define (\w+)\s+(\d+)\b',constants,re.M)}
            lookup=names('species' if is_mon else 'moves')
            for token in re.findall(r'^    ('+which+r'_\w+),',table,re.M):
                key=token.removeprefix(which+'_')
                aliases={'CASTFORM':'CASTFORM_NORMAL','DEOXYS':'DEOXYS_NORMAL','SMELLING_SALT':'SMELLING_SALTS',
                         'VICE_GRIP':'VISE_GRIP','HI_JUMP_KICK':'HIGH_JUMP_KICK','FAINT_ATTACK':'FEINT_ATTACK'}
                mon=lookup[aliases.get(key,key)]
                rows.append((gid*512+ids[token],mon['name'],token,mon['id']))
        else:
            translations=CHINESE.get(cat,'').split()
            labels=dict(re.findall(r'const u8 (\w+)\[\] = _\("([^"]*)"\)',table))
            for name,label in re.findall(r'\[EC_INDEX\(EC_WORD_(\w+)\)\] =\s*\{\s*\.text = (\w+)',table):
                code=definitions[name];idx=code%512
                title=translations[idx] if translations else DEFAULT_CN.get(name,labels[label])
                rows.append((code,title,'EC_WORD_'+name,0))
            if translations:assert len(rows)==len(translations),(cat,len(rows),len(translations))
            for name in re.findall(r'\[EC_INDEX\(EC_WORD_(\w+)\)\] =\s*\{[^}]*?\.enabled = FALSE',table):
                unavailable.append(definitions[name])
        groups[str(gid)]=[r[0] for r in rows]
        for code,title,token,sid in rows:
            display[str(code)]=[title,sid]
            sounds[str(code)]=tracks[token]
    original_samples=[]
    for label in ph_keys:
        midi=blob('sound/songs/midi/'+label.lower()+'.mid')
        instrument=midi[midi.rindex(b'\x00\xc0')+2]
        raw_sample=blob('sound/direct_sound_samples/phonemes/%02d.wav'%(instrument+1))
        header=raw_sample.index(b'smpl')+8
        has_loop=struct.unpack_from('<I',raw_sample,header+28)[0]
        loop=struct.unpack_from('<II',raw_sample,header+44) if has_loop else (-1,-1)
        with wave.open(io.BytesIO(raw_sample)) as w:
            original_samples.append([w.getframerate(),base64.b64encode(w.readframes(w.getnframes())).decode(),*loop])
    phys=json.loads((ROOT/'content/hoenn_native/maps/hoenn_119.json').read_text())['physics']
    water=[[x,y] for y,row in enumerate(phys['water']) for x,c in enumerate(row) if c and not phys['waterfall'][y][x]]
    assert len(water)==447 and water[3]==[18,18]
    return dict(groups=groups,unavailable=unavailable,words=display,notes=sounds,pitch=pitch,samples=original_samples,water=water,
                original=[definitions[k] for k in ['SHAKE','IT','DO','THE','DIET','DANCE']])
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path)
    d=build(parser.parse_args().source)
    print(len(d['words']),'words;',len(d['samples']),'vocal sounds;',len(d['water']),'fishing positions')
    (ROOT/'content/hoenn_native/fan_club.json').write_text(json.dumps(d,ensure_ascii=False,separators=(',',':'))+'\n')
