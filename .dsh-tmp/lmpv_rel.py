import json,re,subprocess,urllib.request
root=r"C:\\Users\\fk\\PiliNara"
url=subprocess.check_output(["git","-C",root,"config","--local","remote.origin.url"],text=True).strip()
tok=re.search(r"guloi:([^@]+)@",url).group(1)
def get(u):
    req=urllib.request.Request(u,headers={"Authorization":"token "+tok,"Accept":"application/vnd.github+json","User-Agent":"dsh"})
    return json.load(urllib.request.urlopen(req,timeout=60))
r=get("https://api.github.com/repos/guloi/libmpv-android-video-build/releases/latest")
print("latest:", r["tag_name"], r["name"], r["published_at"], "prerelease", r["prerelease"], "draft", r["draft"])
for a in r["assets"]:
    print("  ", a["name"], a["size"], a["updated_at"], a["browser_download_url"].split("/")[-1])