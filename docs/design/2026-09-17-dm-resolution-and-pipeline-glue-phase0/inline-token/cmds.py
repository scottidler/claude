import json,os,re,collections
from concurrent.futures import ProcessPoolExecutor
RX=re.compile(r'<command-name>/([^<]+)</command-name>')
def scan(p):
    out=[]
    try: f=open(p,encoding='utf-8',errors='replace')
    except OSError: return out
    with f:
        for line in f:
            if '<command-name>' not in line: continue
            try: d=json.loads(line)
            except Exception: continue
            if d.get('type')!='user' or d.get('isSidechain'): continue
            c=d.get('message',{}).get('content')
            s=c if isinstance(c,str) else json.dumps(c)
            m=RX.search(s)
            if m: out.append((d.get('timestamp',''),m.group(1).strip(),d.get('uuid','')))
    return out
files=[os.path.join(r,fn) for r,_,fs in os.walk('.') for fn in fs if fn.endswith('.jsonl')]
res=[]
with ProcessPoolExecutor(max_workers=12) as ex:
    for ch in ex.map(scan,files,chunksize=8): res.extend(ch)
seen=set(); R=[]
for ts,name,u in res:
    if u in seen: continue
    seen.add(u); R.append((ts,name))
print('position-0 slash-command invocations (deduped by uuid):',len(R))
NAMES=set(json.load(open(os.environ['TMPDIR']+'/skillnames.json')))
c=collections.Counter(n for _,n in R)
print('distinct commands:',len(c))
skill=[(n,k) for n,k in c.most_common() if n in NAMES]
print('those matching an ON skill name:',sum(k for _,k in skill))
print(skill[:30])
print('by month:',dict(sorted(collections.Counter(ts[:7] for ts,_ in R).items())))
