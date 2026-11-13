import os, urllib.parse, http.client, zipfile, io, time, sys
T = os.environ['GH_TOKEN']
URL = 'https://api.github.com/repos/guloi/PiliNara/actions/artifacts/13568698363/zip'
def open_stream(url, headers):
    for _ in range(8):
        p = urllib.parse.urlsplit(url)
        conn = http.client.HTTPSConnection(p.netloc, timeout=120)
        path = p.path + (('?' + p.query) if p.query else '')
        conn.request('GET', path, headers=headers)
        resp = conn.getresponse()
        if resp.status in (301, 302, 303, 307, 308):
            url = resp.getheader('Location')
            conn.close()
            headers = {'User-Agent': 'x'}
            continue
        return conn, resp
    raise RuntimeError('too many redirects')
data = None
for attempt in range(3):
    try:
        conn, resp = open_stream(URL, {'Authorization': 'Bearer ' + T, 'User-Agent': 'x'})
        print('status', resp.status, 'len', resp.getheader('Content-Length'), flush=True)
        buf = io.BytesIO()
        while True:
            chunk = resp.read(262144)
            if not chunk:
                break
            buf.write(chunk)
        data = buf.getvalue()
        conn.close()
        print('got', len(data), flush=True)
        break
    except Exception as ex:
        print('attempt', attempt, 'failed', type(ex).__name__, ex, flush=True)
        time.sleep(3)
if not data:
    sys.exit(1)
z = zipfile.ZipFile(io.BytesIO(data))
name = [n for n in z.namelist() if n.endswith('.apk')][0]
out = '.dsh-tmp/dist/' + os.path.basename(name)
open(out, 'wb').write(z.read(name))
print('saved', out, os.path.getsize(out), flush=True)