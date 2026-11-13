import json, os, sys, time, urllib.request

TOKEN = os.environ["GH_TOKEN"]
REPO = "guloi/PiliNara"
RUN_ID = sys.argv[1]
DEADLINE = time.time() + float(sys.argv[2] if len(sys.argv) > 2 else 1500)

def call(path):
    req = urllib.request.Request("https://api.github.com" + path)
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", "pilinara-ci")
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())

last = None
while time.time() < DEADLINE:
    run = call("/repos/%s/actions/runs/%s" % (REPO, RUN_ID))
    state = (run["status"], run["conclusion"])
    if state != last:
        print(time.strftime("%H:%M:%S"), "run", state, flush=True)
        last = state
    if run["status"] == "completed":
        jobs = call("/repos/%s/actions/runs/%s/jobs" % (REPO, RUN_ID))
        for j in jobs["jobs"]:
            print("JOB", j["name"], j["status"], j["conclusion"], flush=True)
            for s in j["steps"]:
                if s["conclusion"] not in ("success", "skipped", None):
                    print("  STEP FAILED:", s["name"], s["conclusion"], flush=True)
        break
    time.sleep(40)
else:
    print("timeout waiting", flush=True)
