
import os, json, urllib.request, base64, pathlib
TOKEN = os.environ['GH_TOKEN']
def call(p):
    r = urllib.request.Request('https://api.github.com' + p)
    r.add_header('Authorization', 'Bearer ' + TOKEN)
    r.add_header('User-Agent', 'x')
    return json.loads(urllib.request.urlopen(r, timeout=90).read())
p='/repos/guloi/libmpv-android-video-build/contents/buildscripts/patches/mpv/android-vulkan-hdr.patch?ref=main'
d=call(p)
txt=base64.b64decode(d['content']).decode()
pathlib.Path('.dsh-tmp/mpvsrc/android-vulkan-hdr.patch').write_text(txt,encoding='utf-8')
print(len(txt))
print(txt)
