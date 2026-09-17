import json,os,re,sys,collections
from concurrent.futures import ProcessPoolExecutor

NAMES=set(json.load(open(os.environ['TMPDIR']+'/skillnames.json')))
TOK=re.compile(r'/([A-Za-z0-9][A-Za-z0-9_.:-]*)')
SKIP_PREFIX=('<command-name>','<local-command','<bash-','Caveat:','<user-memory','<system-reminder','[Request interrupted','<command-message>','API Error','<ide_','<attachment')

def text_of(d):
    m=d.get('message') or {}
    c=m.get('content')
    if isinstance(c,str): return c
    if isinstance(c,list):
        parts=[]
        for b in c:
            if isinstance(b,dict):
                if b.get('type')=='tool_result': return None
                if b.get('type')=='text': parts.append(b.get('text') or '')
            elif isinstance(b,str): parts.append(b)
        return '\n'.join(parts) if parts else None
    return None

def scan(path):
    out=[]
    try:
        f=open(path,encoding='utf-8',errors='replace')
    except OSError:
        return out
    with f:
        for line in f:
            if '"type":"user"' not in line and '"type": "user"' not in line: continue
            try: d=json.loads(line)
            except Exception: continue
            if d.get('type')!='user': continue
            if d.get('isSidechain'): continue
            if d.get('isMeta'): continue
            if d.get('userType') not in (None,'external'): continue
            ps=d.get('promptSource')
            if ps not in (None,'typed','suggestion_accepted'): continue
            t=text_of(d)
            if not t: continue
            ts=d.get('timestamp') or ''
            s=t.lstrip()
            if s.startswith(SKIP_PREFIX): continue
            if '/' not in t: 
                out.append((ts,None,t))
                continue
            out.append((ts,True,t))
    return out

if __name__=='__main__':
    files=[]
    for r,_,fs in os.walk('.'):
        for fn in fs:
            if fn.endswith('.jsonl'): files.append(os.path.join(r,fn))
    res=[]
    with ProcessPoolExecutor(max_workers=12) as ex:
        for chunk in ex.map(scan,files,chunksize=8):
            res.extend(chunk)
    json.dump(res,open(os.environ['TMPDIR']+'/prompts.json','w'))
    print('typed prompt records:',len(res))
    from collections import Counter
    c=Counter(t[:7] for t,_,_ in res if t)
    for k in sorted(c):
        print(k,c[k])
