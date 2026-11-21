#!/usr/bin/env python3
"""Rebuild the historic ORAS plans using the shared collision/landmark compiler."""
import json
from collections import Counter
from field_layouts import ROOT, compile_map

def main():
    out={};counts=Counter()
    for p in sorted((ROOT/"content/regions").glob("*/maps/*.json")):
        m=json.loads(p.read_text());r=p.parents[1].name; key=r+"/"+p.stem
        plan=compile_map(p.stem,m,r)
        if plan is None:raise ValueError("Missing ground in "+str(p))
        out[key]=plan;counts[r]+=1
    (ROOT/"content/oras_fields.json").write_text(json.dumps(out,separators=(",",":"))+"\n")
    print("ORAS field plans",len(out),dict(counts))


if __name__=="__main__":main()
