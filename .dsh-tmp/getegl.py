import json,re,subprocess,urllib.request,base64
root=r"C:\\Users\\fk\\PiliNara"
url=subprocess.check_output(["git","-C",root,"config","--local","remote.origin.url"],text=True).strip()
tok=re.search(r"guloi:([^@]+)@",url).group(1)
req=urllib.request.Request("https://api.github.com/repos/KhronosGroup/EGL-Registry/contents/api/EGL/eglext.h",headers={"Authorization":"token "+tok,"Accept":"application/vnd.github+json","User-Agent":"dsh"})
d=json.load(urllib.request.urlopen(req,timeout=60))
txt=base64.b64decode(d["content"]).decode("utf-8","replace")
open(root+r"\\.dsh-tmp\\eglext.h","w",encoding="utf-8").write(txt)
for line in txt.splitlines():
    if "GL_COLORSPACE" in line and "#define" in line:
        print(line.strip())