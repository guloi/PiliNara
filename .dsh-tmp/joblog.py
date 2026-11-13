import os,sys,urllib.request
T=os.environ['GH_TOKEN']
jid=sys.argv[1]
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None
op=urllib.request.build_opener(NoRedirect)
req=urllib.request.Request('https://api.github.com/repos/guloi/PiliNara/actions/jobs/%s/logs'%jid)
req.add_header('Authorization','Bearer '+T);req.add_header('User-Agent','x')
try:
    op.open(req,timeout=60)
    print('no redirect?!');sys.exit(1)
except urllib.error.HTTPError as e:
    loc=e.headers.get('Location')
print('loc',loc[:80])
data=urllib.request.urlopen(urllib.request.Request(loc,headers={'User-Agent':'x'}),timeout=180).read()
open('.dsh-tmp/run.log','wb').write(data)
print(len(data))
