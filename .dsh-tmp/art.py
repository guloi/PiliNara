import json,os,urllib.request
T=os.environ['GH_TOKEN']
def call(p):
    req=urllib.request.Request('https://api.github.com'+p)
    req.add_header('Authorization','Bearer '+T); req.add_header('User-Agent','x')
    return json.load(urllib.request.urlopen(req,timeout=60))
for run in ['42364537475','42360659341']:
    d=call('/repos/guloi/PiliNara/actions/runs/%s/artifacts?per_page=100'%run)
    print(run,'count',d['total_count'])
    for a in d['artifacts']:
        print('  ',a['id'],a['name'],round(a['size_in_bytes']/1048576,1),'MB',a['expired'])
