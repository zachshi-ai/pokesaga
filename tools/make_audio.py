#!/usr/bin/env python3
"""用火红原版曲谱（sound/songs/midi/*.mid）合成游戏 BGM 与音效。

曲谱本身是原版的（音符、速度、声部都从 .mid 读），这里只做一件事：
把 MIDI 用方波/锯齿/三角波 + 包络合成成 ogg，好让游戏有原版的旋律线条。
输出到 assets/audio/bgm/*.ogg、assets/audio/sfx/*.wav
用法: python3 tools/make_audio.py
"""
import json
import math
import os
import struct
import subprocess
import wave

import numpy as np

ROOT = "/root/build/pokeemerald-expansion-master/sound/songs/midi"
OUT = "/root/build/pokesaga/assets/audio"
SR = 22050

# 游戏里用到的曲子：键 -> 原版文件
BGM = {
    "town": "mus_rg_pallet",
    "city": "mus_rg_celadon",
    "route": "mus_rg_route1",
    "cave": "mus_rg_mt_moon",
    "gym": "mus_rg_gym",
    "center": "mus_rg_poke_center",
    "battle_trainer": "mus_rg_vs_trainer",
    "battle_wild": "mus_vs_wild",
    "victory": "mus_rg_victory_trainer",
    "surf": "mus_rg_surf",
    "sevii": "mus_rg_sevii_123",
    "tower": "mus_rg_poke_tower",
    "silph": "mus_rg_silph",
}


def read_varlen(data, i):
    v = 0
    while True:
        b = data[i]
        i += 1
        v = (v << 7) | (b & 0x7F)
        if not b & 0x80:
            return v, i


def parse_midi(path):
    """返回 (notes, tempo_map)。notes: [(开始秒, 时长秒, 音高, 力度, 轨道)]"""
    data = open(path, "rb").read()
    assert data[:4] == b"MThd", path
    hlen = struct.unpack(">I", data[4:8])[0]
    fmt, ntrk, div = struct.unpack(">HHH", data[8:14])
    i = 8 + hlen
    tracks = []
    for _ in range(ntrk):
        assert data[i:i + 4] == b"MTrk"
        tlen = struct.unpack(">I", data[i + 4:i + 8])[0]
        tracks.append(data[i + 8:i + 8 + tlen])
        i += 8 + tlen

    # 先扫一遍收集 tempo，构造 秒/拍 的时间换算
    tempos = []  # (tick, us_per_quarter)
    for tr in tracks:
        t = 0
        j = 0
        status = 0
        while j < len(tr):
            dt, j = read_varlen(tr, j)
            t += dt
            if j >= len(tr):
                break
            b = tr[j]
            if b & 0x80:
                status = b
                j += 1
            if status == 0xFF:
                meta = tr[j]
                j += 1
                ln, j = read_varlen(tr, j)
                payload = tr[j:j + ln]
                j += ln
                if meta == 0x51 and ln == 3:
                    us = (payload[0] << 16) | (payload[1] << 8) | payload[2]
                    tempos.append((t, us))
                elif meta == 0x2F:
                    break
                continue
            if status in (0xF0, 0xF7):
                ln, j = read_varlen(tr, j)
                j += ln
                continue
            high = status & 0xF0
            if high in (0xC0, 0xD0):
                j += 1
            else:
                j += 2
    tempos.sort()
    if not tempos:
        tempos = [(0, 500000)]

    def tick_to_sec(tick):
        sec = 0.0
        last_tick = 0
        us = tempos[0][1]
        for tk, u in tempos:
            if tk > tick:
                break
            sec += (tk - last_tick) * us / 1e6 / div
            last_tick = tk
            us = u
        sec += (tick - last_tick) * us / 1e6 / div
        return sec

    notes = []
    for ti, tr in enumerate(tracks):
        t = 0
        j = 0
        status = 0
        active = {}
        while j < len(tr):
            dt, j = read_varlen(tr, j)
            t += dt
            if j >= len(tr):
                break
            b = tr[j]
            if b & 0x80:
                status = b
                j += 1
            if status == 0xFF:
                meta = tr[j]
                j += 1
                ln, j = read_varlen(tr, j)
                j += ln
                if meta == 0x2F:
                    break
                continue
            if status in (0xF0, 0xF7):
                ln, j = read_varlen(tr, j)
                j += ln
                continue
            high = status & 0xF0
            ch = status & 0x0F
            if high in (0x80, 0x90):
                note = tr[j]
                vel = tr[j + 1]
                j += 2
                if high == 0x90 and vel > 0:
                    active[(ch, note)] = (t, vel)
                else:
                    st = active.pop((ch, note), None)
                    if st and ch != 9:
                        notes.append((tick_to_sec(st[0]), tick_to_sec(t) - tick_to_sec(st[0]),
                                      note, st[1], ch))
            elif high in (0xC0, 0xD0):
                j += 1
            else:
                j += 2
    notes.sort()
    return notes


# 波形
def wave_square(phase):
    return np.sign(np.sin(phase))


def wave_pulse(phase):
    return np.where((phase % (2 * np.pi)) < math.pi * 0.5, 1.0, -1.0)


def wave_tri(phase):
    p = (phase % (2 * np.pi)) / (2 * np.pi)
    return 4 * np.abs(p - 0.5) - 1


def synth_note(freq, dur, vel, kind):
    n = max(1, int(dur * SR))
    t = np.arange(n) / SR
    phase = 2 * np.pi * freq * t
    if kind == "tri":
        w = wave_tri(phase) * 0.55
    elif kind == "pulse":
        w = wave_pulse(phase) * 0.35
    else:
        w = wave_square(phase) * 0.30
    # ADSR：前 6ms 起音，之后衰减到 0.55 维持，末尾 60ms 释放
    env = np.ones(n)
    a = min(n, int(0.006 * SR))
    if a > 0:
        env[:a] = np.linspace(0, 1, a)
    d = min(n, int(0.10 * SR))
    if d > 0:
        env[:d] *= np.linspace(1, 0.75, d)
    r = min(n, int(0.06 * SR))
    if r > 0:
        env[-r:] *= np.linspace(1, 0, r)
    return w * env * (vel / 127.0)


def render(notes, max_sec=60.0):
    if not notes:
        return np.zeros(SR, dtype=np.float32)
    end = min(max_sec, max(n[0] + n[1] for n in notes))
    total = int(end * SR) + SR // 4
    buf = np.zeros(total, dtype=np.float32)
    for start, dur, pitch, vel, ch in notes:
        if start >= end:
            continue
        d = min(dur, 1.6)
        kind = "pulse" if pitch >= 76 else ("tri" if pitch <= 45 else "square")
        tone = synth_note(440.0 * 2 ** ((pitch - 69) / 12.0), max(d, 0.05), vel, kind)
        s = int(start * SR)
        e = min(total, s + len(tone))
        if e > s:
            buf[s:e] += tone[:e - s]
    peak = float(np.max(np.abs(buf))) or 1.0
    buf = buf / peak * 0.85
    # 轻微低通，去掉方波最刺的高频
    k = np.array([0.25, 0.5, 0.25], dtype=np.float32)
    buf = np.convolve(buf, k, mode="same").astype(np.float32)
    return buf


def write_wav(path, buf):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(buf, -1, 1) * 32767).astype("<i2").tobytes())


def beep(freqs, dur=0.09, kind="square", gap=0.0):
    out = []
    for f in freqs:
        out.append(synth_note(f, dur, 110, kind))
        if gap:
            out.append(np.zeros(int(gap * SR), dtype=np.float32))
    return np.concatenate(out) if out else np.zeros(1, dtype=np.float32)


def noise(dur=0.15, amp=0.5):
    n = int(dur * SR)
    rng = np.random.default_rng(7)
    x = rng.uniform(-1, 1, n).astype(np.float32)
    env = np.linspace(1, 0, n)
    return x * env * amp


def main():
    os.makedirs(os.path.join(OUT, "bgm"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "sfx"), exist_ok=True)
    made = []
    for key, name in BGM.items():
        src = os.path.join(ROOT, name + ".mid")
        if not os.path.exists(src):
            print("缺曲谱", name)
            continue
        notes = parse_midi(src)
        buf = render(notes)
        if len(buf) < SR:
            print("曲谱太短，跳过", name)
            continue
        tmp = os.path.join(OUT, "bgm", key + ".wav")
        write_wav(tmp, buf)
        ogg = os.path.join(OUT, "bgm", key + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp,
                        "-c:a", "libvorbis", "-q:a", "2", ogg], check=True)
        os.remove(tmp)
        made.append((key, name, round(len(buf) / SR, 1), os.path.getsize(ogg) // 1024))

    # 音效：短促的提示音
    SFX = {
        "select": beep([880], 0.05, "pulse"),
        "confirm": beep([660, 990], 0.06, "pulse"),
        "cancel": beep([440, 330], 0.06, "square"),
        "bump": noise(0.08, 0.35),
        "ball": noise(0.10, 0.5),
        "catch": beep([784, 988, 1175, 1568], 0.10, "pulse", 0.01),
        "heal": beep([523, 659, 784, 1047], 0.12, "tri"),
        "levelup": beep([659, 784, 988, 1319], 0.10, "pulse"),
        "item": beep([988, 1319], 0.09, "pulse"),
        "save": beep([523, 784], 0.12, "tri"),
        "badge": beep([523, 659, 784, 1047, 1319], 0.13, "pulse"),
        "hit": noise(0.12, 0.6),
        "faint": beep([392, 330, 262, 196], 0.14, "square"),
        "bike": beep([784, 1047], 0.07, "pulse"),
        "door": noise(0.10, 0.3),
        "water": noise(0.20, 0.25),
    }
    for key, buf in SFX.items():
        p = os.path.join(OUT, "sfx", key + ".wav")
        write_wav(p, buf.astype(np.float32))
        made.append((key, "sfx", round(len(buf) / SR, 2), os.path.getsize(p) // 1024))

    print("生成 %d 个音频" % len(made))
    for m in made:
        print("   ", m)


if __name__ == "__main__":
    main()
