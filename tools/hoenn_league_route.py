"""Prepare and heal the Emerald League team using the League nurse, mart, inventory and party controls."""

LEADS = {"h_sidney": 291, "h_phoebe": 262, "h_glacia": 260, "h_drake": 351, "h_wallace": 64}


def count(p, name):
    return int(p.state["bag"].get(name, 0))


def supplies(p):
    p.use_at("hoenn_league", (3, 2))
    p.use_at("hoenn_league", (16, 2))
    for name, target, price in (("活力碎片", 9, 1500), ("厉害伤药", 10, 1200), ("全复药", 1, 3000)):
        amount = min(target - count(p, name), int(p.state["money"]) // price)
        if amount > 0:
            p.do("shop", item=name, amount=amount)
    p.do("back")
    print("LEAGUE supplies", {k: count(p, k) for k in ("活力块", "活力碎片", "全复药", "厉害伤药")}, flush=True)


def heal(p):
    # Spend scarce revives on the most effective members first.
    priorities = [260, 64, 351, 262, 291, 300]
    slots = sorted(range(len(p.state["party"])), key=lambda i: priorities.index(int(p.state["party"][i][1]))
                   if int(p.state["party"][i][1]) in priorities else len(priorities))
    for slot in slots:
        mon = p.state["party"][slot]
        if not mon[3]:
            revive = next((name for name in ("活力块", "活力碎片") if count(p, name)), None)
            if not revive:
                continue
            p.do("use", item=revive, slot=slot)
        for _ in range(7):
            mon = p.state["party"][slot]
            damage = mon[4] - mon[3]
            if damage < mon[4] * .2:
                break
            order = ("全复药", "厉害伤药", "好伤药", "伤药") if damage >= 100 else ("好伤药", "伤药", "厉害伤药", "全复药")
            medicine = next((name for name in order if count(p, name)), None)
            if not medicine:
                break
            before = mon[3]
            p.do("use", item=medicine, slot=slot)
            if p.state["party"][slot][3] <= before:
                raise AssertionError(("field medicine failed", medicine, mon[0]))


def prepare(p, event):
    key = event["id"]
    if key not in LEADS:
        return
    if key == "h_sidney":
        supplies(p)
    heal(p)
    lead = next((i for i, m in enumerate(p.state["party"]) if int(m[1]) == LEADS[key] and m[3] > 0), None)
    if lead:
        p.do("lead", slot=lead)
    print("LEAGUE party", key, [(mon[0], mon[3]) for mon in p.state["party"]], flush=True)
