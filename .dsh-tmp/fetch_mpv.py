import os, json, urllib.request, base64, pathlib
TOKEN = os.environ['GH_TOKEN']
def call(p):
    r = urllib.request.Request('https://api.github.com' + p)
    r.add_header('Authorization', 'Bearer ' + TOKEN)
    r.add_header('User-Agent', 'x')
    return json.loads(urllib.request.urlopen(r, timeout=60).read())
out = pathlib.Path('.dsh-tmp/mpvsrc'); out.mkdir(parents=True, exist_ok=True)
files = ['video/out/vo_gpu_next.c', 'video/out/android_common.c', 'video/out/gpu/context.c',
         'video/out/vulkan/context.c', 'video/out/vulkan/context_android.c',
         'video/out/vo_gpu.c', 'video/out/gpu/video.c']
for f in files:
    d = call('/repos/mpv-player/mpv/contents/' + f + '?ref=master')
    txt = base64.b64decode(d['content']).decode('utf-8', 'replace')
    (out / pathlib.Path(f).name).write_text(txt, encoding='utf-8')
    print(f, len(txt))
