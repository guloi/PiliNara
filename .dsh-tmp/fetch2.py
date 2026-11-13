
import os, json, urllib.request, base64, pathlib
TOKEN = os.environ['GH_TOKEN']
def call(p):
    r = urllib.request.Request('https://api.github.com' + p)
    r.add_header('Authorization', 'Bearer ' + TOKEN)
    r.add_header('User-Agent', 'x')
    return json.loads(urllib.request.urlopen(r, timeout=90).read())
out = pathlib.Path('.dsh-tmp/mpvsrc')
targets = [
    ('mpv-player/mpv', 'master', 'video/out/vo.c'),
    ('mpv-player/mpv', 'master', 'video/out/vo.h'),
    ('mpv-player/mpv', 'master', 'options/options.c'),
    ('mpv-player/mpv', 'master', 'player/command.c'),
    ('haasn/libplacebo', 'master', 'src/vulkan/swapchain.c'),
    ('haasn/libplacebo', 'master', 'src/vulkan/context.c'),
]
for repo, ref, f in targets:
    d = call('/repos/%s/contents/%s?ref=%s' % (repo, f, ref))
    txt = base64.b64decode(d['content']).decode('utf-8', 'replace')
    name = ('lp_' if repo.startswith('haasn') else '') + pathlib.Path(f).name
    (out / name).write_text(txt, encoding='utf-8')
    print(name, len(txt))

