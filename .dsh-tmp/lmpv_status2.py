import json,re,subprocess,sys,urllib.request
root=r"C:\\Users\\fk\\PiliNara"
RUN=sys.argv[1]
url=subprocess.check_output(["git","-C",root,"config","--local","remote.origin.url"],text=True).strip()
tok=re.search(r"guloi:([^@]+)@",url).group(1)
def get(u):
    req=urllib.request.Request(u,headers={"Authorization":"token "+tok,"Accept":"application/vnd.github+json","User-Agent":"dsh"})
    return json.load(urllib.request.urlopen(req,timeout=60))
r=get("https://api.github.com/repos/guloi/libmpv-android-video-build/actions/runs/"+RUN)
print(r["status"], r["conclusion"], r["head_sha"][:9], r["updated_at"])
if r["status"]=="completed":
    for j in get("https://api.github.com/repos/guloi/libmpv-android-video-build/actions/runs/"+RUN+"/jobs")["jobs"]:
        print("JOB",j["name"],j["conclusion"])
        for s in j["steps"]:
            print("   ",s["number"],s["name"],s["conclusion"])