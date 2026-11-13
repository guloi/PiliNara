import json, os, urllib.request
TOKEN = os.environ["GH_TOKEN"]
def call(path):
    req = urllib.request.Request("https://api.github.com" + path)
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "pilinara-ci")
    with urllib.request.urlopen(req, timeout=40) as r:
        return json.loads(r.read())
run = call("/repos/guloi/PiliNara/actions/runs/42355447157")
print(run["status"], run["conclusion"], run["updated_at"])
jobs = call("/repos/guloi/PiliNara/actions/runs/42355447157/jobs")
for j in jobs["jobs"]:
    print("JOB", j["name"], j["status"], j["conclusion"])
    for s in j["steps"]:
        print("   ", s["number"], s["name"], s["status"], s["conclusion"])
