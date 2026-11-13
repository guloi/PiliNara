
import os, re, urllib.request
tok = os.popen('git -C C:/Users/fk/PiliNara config --local remote.origin.url').read().strip()
m = re.search(r'guloi:([^@]+)@', tok)
hdr = {"Accept": "application/vnd.github.raw", "User-Agent": "x"}
if m: hdr["Authorization"] = "Bearer " + m.group(1)
url = "https://api.github.com/repos/mpv-player/mpv/contents/video/out/vo_gpu_next.c?ref=v0.41.0"
data = urllib.request.urlopen(urllib.request.Request(url, headers=hdr), timeout=90).read()
open(r"C:\Users\fk\PiliNara\.dsh-tmp\mpvsrc\vo_gpu_next.c","wb").write(data)
print(len(data))
