import json,re,subprocess,urllib.request
root=r"C:\Users\fk\PiliNara"
url=subprocess.check_output(["git","-C",root,"config","--local","remote.origin.url"],text=True).strip()
tok=re.search(r"guloi:([^@]+)@",url).group(1)
def get(u):
    req=urllib.request.Request(u,headers={"Authorization":"token "+tok,"Accept":"application/vnd.github+json","User-Agent":"dsh"})
    return json.load(urllib.request.urlopen(req,timeout=60))
runs=get("https://api.github.com/repos/guloi/libmpv-android-video-build/actions/runs?per_page=5")
for r in runs["workflow_runs"]:
    print(r["id"], r["event"], r["status"], r["conclusion"], r["head_branch"], r["head_sha"][:9], r["created_at"])
