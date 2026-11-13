import json, os, ssl, sys, time, urllib.request

RUN = sys.argv[1] if len(sys.argv) > 1 else os.environ["RUN"]
TOKEN = os.environ["GH_TOKEN"]
ctx = ssl.create_default_context()

def api(path):
    req = urllib.request.Request("https://api.github.com" + path)
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Accept", "application/vnd.github+json")
    with urllib.request.urlopen(req, timeout=30, context=ctx) as r:
        return json.load(r)

while True:
    run = api("/repos/guloi/PiliNara/actions/runs/" + RUN)
    st = run["status"]
    print(time.strftime("%H:%M:%S"), st, run.get("conclusion"), flush=True)
    if st == "completed":
        break
    time.sleep(20)

print("LOGIN URL", run["html_url"])
for job in api("/repos/guloi/PiliNara/actions/runs/" + RUN + "/jobs")["jobs"]:
    print("JOB", job["name"], job["conclusion"])
    for s in job["steps"]:
        print("   ", s["number"], s["name"], s["conclusion"])

art = api("/repos/guloi/PiliNara/actions/runs/" + RUN + "/artifacts")
for a in art["artifacts"]:
    print("ART", a["id"], a["name"], round(a["size_in_bytes"]/1048576, 2), "MB")
