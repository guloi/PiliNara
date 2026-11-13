import os, time, json, urllib.request, urllib.error
T = os.environ["GH_TOKEN"]
def call(m, p, d=None):
    req = urllib.request.Request("https://api.github.com" + p, method=m)
    req.add_header("Authorization", "Bearer " + T)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "x")
    body = json.dumps(d).encode() if d is not None else None
    if body:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, body, timeout=60) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:200]

for i in range(10):
    s, d = call("POST", "/repos/guloi/PiliNara/actions/workflows/build.yml/dispatches",
                {"ref": "ds-ai-hdr", "inputs": {"build_android": "true"}})
    print("try", i, s, d if s >= 300 else "")
    if s == 204:
        break
    time.sleep(8)
time.sleep(15)
s, runs = call("GET", "/repos/guloi/PiliNara/actions/runs?per_page=3")
for r in runs.get("workflow_runs", []):
    print(r["id"], r["head_sha"][:9], r["status"], r["conclusion"], r["created_at"])
