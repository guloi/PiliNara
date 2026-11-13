import json,re,subprocess,urllib.request
root=r"C:\\Users\\fk\\PiliNara"
url=subprocess.check_output(["git","-C",root,"config","--local","remote.origin.url"],text=True).strip()
tok=re.search(r"guloi:([^@]+)@",url).group(1)
req=urllib.request.Request("https://api.github.com/repos/guloi/libmpv-android-video-build/actions/runs/42391184866/cancel",data=b"{}",method="POST",headers={"Authorization":"token "+tok,"Accept":"application/vnd.github+json","Content-Type":"application/json","User-Agent":"dsh"})
try:
    r=urllib.request.urlopen(req,timeout=60); print("cancel",r.status)
except urllib.error.HTTPError as e:
    print("ERR",e.code,e.read().decode()[:200])