import json, os, time, urllib.request

TOKEN = os.environ["GH_TOKEN"]
REPO = "guloi/PiliNara"

def call(method, path, data=None):
    req = urllib.request.Request("https://api.github.com" + path, method=method)
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", "pilinara-ci")
    body = None
    if data is not None:
        body = json.dumps(data).encode()
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, body, timeout=60) as r:
        raw = r.read()
        return r.status, (json.loads(raw) if raw else None)

try:
    s, d = call("POST", "/repos/%s/actions/workflows/build.yml/dispatches" % REPO,
                {"ref": "ds-ai-hdr", "inputs": {"build_android": "true"}})
    print("dispatch status", s)
except Exception as e:
    print("dispatch error", repr(e))
    raise

time.sleep(10)
s, runs = call("GET", "/repos/%s/actions/runs?per_page=5" % REPO)
for r in runs.get("workflow_runs", []):
    print(r["id"], "|", r["name"], "|", r["head_branch"], "|", r["status"], r["conclusion"], "|", r["html_url"])
