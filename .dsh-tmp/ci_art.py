import json, os, urllib.request
TOKEN = os.environ["GH_TOKEN"]
def call(path):
    req = urllib.request.Request("https://api.github.com" + path)
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "pilinara-ci")
    with urllib.request.urlopen(req, timeout=40) as r:
        return json.loads(r.read())
arts = call("/repos/guloi/PiliNara/actions/runs/42355447157/artifacts")
for a in arts["artifacts"]:
    print(a["name"], "|", round(a["size_in_bytes"]/1048576, 1), "MB |", a["expired"])
run = call("/repos/guloi/PiliNara/actions/runs/42355447157")
print("sha", run["head_sha"])
