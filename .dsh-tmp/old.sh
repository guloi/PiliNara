#!/bin/bash
cd /c/Users/fk/PiliNara
export GH_TOKEN=$(git config --local remote.origin.url | sed -E "s#.*guloi:([^@]+)@.*#\1#")
python.exe - <<PY
import json,os,ssl,urllib.request
t=os.environ["GH_TOKEN"]
def api(p):
    r=urllib.request.Request("https://api.github.com"+p)
    r.add_header("Authorization","Bearer "+t)
    with urllib.request.urlopen(r,timeout=30,context=ssl.create_default_context()) as f: return json.load(f)
for rid in ("42384534821",):
    run=api("/repos/guloi/PiliNara/actions/runs/"+rid)
    print(rid, run["head_sha"][:9], run["status"], run["conclusion"])
PY
