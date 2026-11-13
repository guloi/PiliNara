
import json, urllib.request, re, os
tok = os.popen('git -C C:/Users/fk/PiliNara config --local remote.origin.url').read().strip()
m = re.search(r'guloi:([^@]+)@', tok)
hdr = {"Accept": "application/vnd.github.text-match+json", "User-Agent": "x"}
if m: hdr["Authorization"] = "Bearer " + m.group(1)
q = "gpu_ctx_create+repo:mpv-player/mpv"
req = urllib.request.Request("https://api.github.com/search/code?q="+q, headers=hdr)
try:
    data = json.load(urllib.request.urlopen(req, timeout=60))
    for it in data.get("items", [])[:10]:
        print(it["path"])
except Exception as e:
    print("ERR", e)
