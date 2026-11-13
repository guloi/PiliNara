import json,re,subprocess,urllib.request
root=r"C:\Users\fk\PiliNara"
url=subprocess.check_output(["git","-C",root,"config","--local","remote.origin.url"],text=True).strip()
tok=re.search(r"guloi:([^@]+)@",url).group(1)
def get(u):
    req=urllib.request.Request(u,headers={"Authorization":"token "+tok,"Accept":"application/vnd.github+json","User-Agent":"dsh"})
    return json.load(urllib.request.urlopen(req,timeout=60))
r=get("https://api.github.com/repos/guloi/libmpv-android-video-build/actions/runs/42388026088")
print(r["status"], r["conclusion"], r["created_at"], r["updated_at"])
jobs=get("https://api.github.com/repos/guloi/libmpv-android-video-build/actions/runs/42388026088/jobs")
for j in jobs["jobs"]:
    print("JOB", j["name"], j["status"], j["conclusion"])
    for s in j["steps"]:
        print("  ", s["number"], s["name"], s["status"], s["conclusion"])
